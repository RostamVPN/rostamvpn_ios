// Copyright 2026 Internet Mastering & Company, Inc.
// SPDX-License-Identifier: Apache-2.0

import NetworkExtension
import RostamKit
import HevSocks5TunnelWrapper
import os.log

class RedSocketPacketTunnelProvider: NEPacketTunnelProvider {
    private let extensionLog = OSLog(subsystem: "com.rostamvpn.redsocket", category: "RostamTunnel")
    /// PREFERRED SOCKS port, not a guarantee. Random per session: a fixed port
    /// names the product to every app on the device and can be taken before
    /// the tunnel starts.
    private let preferredSocksPort = UInt16.random(in: 20000...49151)

    /// The port to dial right now: what the core bound, or the preference when
    /// nothing is running yet.
    private var activeSocksPort: UInt16 {
        let p = RedSocketClient.shared.socksPort
        return p > 0 ? p : preferredSocksPort
    }

    /// Periodic health check timer — tears down VPN if SOCKS5 proxy dies.
    private var healthTimer: DispatchSourceTimer?
    private var peerRelayTimer: DispatchSourceTimer?

    override init() {
        super.init()

        if let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: BrandRuntime.appGroup) {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent("extension.log"))
        }
        extLog("Extension init()")
    }

    /// Unified log only, as private data: endpoints and verdicts stay out of
    /// sysdiagnose and the shared container.
    private func extLog(_ msg: String) {
        os_log("%{private}@", log: extensionLog, type: .default, msg)
    }

    override func startTunnel(
        options: [String: NSObject]?,
        completionHandler: @escaping (Error?) -> Void
    ) {
        extLog("startTunnel() called")

        guard FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: BrandRuntime.appGroup) != nil else {
            extLog("FATAL: app group \(BrandRuntime.appGroup) unavailable — refusing to start")

            completionHandler(Self.refusalError("App Group \(BrandRuntime.appGroup) is not available to the tunnel"))
            return
        }

        if let r = accessRefusal() {
            extLog("refusing to start: \(r.reason)")
            recordRefusal(r)
            completionHandler(Self.refusalError("Open \(BrandRuntime.displayName) to continue: \(r.reason)"))
            return
        }
        resetGuardianSession()

        let config = (protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration
        let probeEnabled = (config?["probeEnabled"] as? String) == "true"

        let group = BrandRuntime.defaults
        let choice = (config?["protocol"] as? String)
            ?? group?.string(forKey: "selectedProtocol")
            ?? "auto"
        let wgtcpConfig = group?.string(forKey: "wgtcpConfig")
        extLog("SOCKS port: \(preferredSocksPort), probe: \(probeEnabled), protocol: \(choice), "
               + "wgtcp provisioned: \(wgtcpConfig != nil)")

        let wgtcpAllowed = (group?.object(forKey: "wgtcpAllowed") as? Bool) ?? false
        if !wgtcpAllowed, wgtcpConfig != nil {
            extLog("wgtcp profile present but policy disallows it; RedSocket only")
        }
        if choice != "redsocket", wgtcpAllowed, let wg = wgtcpConfig {
            startWgtcp(config: wg, probeEnabled: probeEnabled) { [weak self] ok in
                guard let self = self else { return }
                if ok { return }
                if choice == "wgtcp" {
                    self.extLog("WGTCP failed and was explicitly selected; not falling back")
                    completionHandler(NSError(
                        domain: "com.rostamvpn.wgtcp", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "WGTCP could not connect"]))
                    return
                }
                self.extLog("WGTCP failed; falling through to RedSocket")
                self.startRedSocket(probeEnabled: probeEnabled, completionHandler: completionHandler)
            } completionHandler: { err in
                completionHandler(err)
            }
            return
        }

        startRedSocket(probeEnabled: probeEnabled, completionHandler: completionHandler)
    }

    /// Tear down whichever transport is up.
    override func handleAppMessage(_ messageData: Data,
                                   completionHandler: ((Data?) -> Void)?) {
        let msg = String(data: messageData, encoding: .utf8)

        if msg == "get-stats" {
            let s = Tun2SocksWrapper.shared.getStats()
            accumulateStats()
            completionHandler?(try? JSONSerialization.data(
                withJSONObject: ["tx": s.txBytes, "rx": s.rxBytes]))
            return
        }

        if let msg, msg.hasPrefix("guardian-") {
            completionHandler?(handleGuardian(msg))
            return
        }

        guard msg == "refresh-entitlement" else {
            completionHandler?(nil); return
        }
        if let r = accessRefusal() {
            extLog("entitlement refreshed: \(r.reason) — ending the session")
            recordRefusal(r)
            completionHandler?(nil)
            cancelTunnelWithError(Self.refusalError(r.reason))
            return
        }
        let g = BrandRuntime.defaults
        let paid = g?.bool(forKey: "isPaid") ?? false
        let entitled = paid || (!BrandRuntime.paidOnly && (g?.bool(forKey: "isFreedomRegion") ?? false))
        RedSocketClient.shared.setPremium(paid)

        let overQuota = g?.bool(forKey: "overQuota") ?? false
        let limitKbps: Int32 = (entitled || !overQuota) ? 0 : freeTierKbps(g)
        RedSocketClient.shared.setRateLimitKbps(limitKbps)
        RedSocketClient.shared.setCdnAllowed(entitled)
        extLog("entitlement refreshed: paid=\(paid) over=\(overQuota) kbps=\(limitKbps)")
        completionHandler?(nil)
    }

    /// `guardian-get` -> snapshot; `guardian-rule:<verdict>:<host>`, `guardian-
    /// rules:<json>`, `guardian-enabled:<0|1>` and `guardian-categories:<mask>`
    /// apply, persist to the app group (the core forgets on process death) and
    /// reply with the fresh snapshot; `guardian-notes` drains the control-stream
    /// queue and replies with it raw.
    private func handleGuardian(_ msg: String) -> Data? {
        let g = BrandRuntime.defaults
        let core = RedSocketClient.shared
        if msg == GuardianMessage.notes {
            return guardianQueue.sync {
                drainNotesLocked()
                let out = (try? JSONSerialization.data(withJSONObject: pendingNotes)) ?? Data("[]".utf8)
                pendingNotes = []
                return out
            }
        }
        if msg.hasPrefix("guardian-rule:") {
            let parts = msg.split(separator: ":", maxSplits: 2).map(String.init)
            if parts.count == 3 {
                let mask = g?.integer(forKey: GuardianMessage.categoriesOffKey) ?? 0
                let r: String
                if mask == 0 {
                    r = core.setUserRule(host: parts[2], verdict: parts[1])
                } else {
                    r = core.setUserRules(json: Self.rulesJSON(core.userRulesJSON(),
                                                               verdict: parts[1], host: parts[2], mask: mask))
                }
                extLog("guardian rule \(parts[1]): \(r.hasPrefix("err") ? r : "ok")")
                g?.set(core.userRulesJSON(), forKey: GuardianMessage.rulesKey)
                g?.set(Date().timeIntervalSince1970, forKey: GuardianMessage.rulesUpdatedKey)
            }
        } else if msg.hasPrefix("guardian-rules:") {
            let json = String(msg.dropFirst("guardian-rules:".count))
            if let p = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] {
                guardianQueue.sync { applyRulesEchoLocked(p) }
            }
        } else if msg.hasPrefix("guardian-enabled:") {
            let on = msg.hasSuffix(":1")
            core.setBlockingEnabled(on)
            g?.set(on, forKey: GuardianMessage.enabledKey)
        } else if msg.hasPrefix("guardian-categories:") {
            let mask = Int(msg.dropFirst("guardian-categories:".count)) ?? 0
            g?.set(mask, forKey: GuardianMessage.categoriesOffKey)
            g?.set(Date().timeIntervalSince1970, forKey: GuardianMessage.rulesUpdatedKey)
            _ = core.setCategoriesOff(mask)
        }
        return guardianQueue.sync {
            drainNotesLocked()
            return try? JSONEncoder().encode(sessionSnapshotLocked())
        }
    }

    /// A {rules} echo (another device's lists, replayed by the exit).
    private func applyRulesEchoLocked(_ p: [String: Any]) {
        let g = BrandRuntime.defaults
        let core = RedSocketClient.shared
        let current = (try? JSONSerialization.jsonObject(with: Data(core.userRulesJSON().utf8))) as? [String: Any] ?? [:]
        let echoUpdated = GuardianMessage.updatedSeconds(p["updated"])
        let localUpdated = g?.double(forKey: GuardianMessage.rulesUpdatedKey) ?? 0
        if GuardianMessage.sameLists(p, current) {
            if let e = echoUpdated, e > localUpdated { g?.set(e, forKey: GuardianMessage.rulesUpdatedKey) }
            return
        }
        if let e = echoUpdated, e < localUpdated {
            extLog("guardian: rules echo is older than this device's lists — kept ours")
            return
        }
        var doc: [String: Any] = ["allow": p["allow"] as? [String] ?? [], "deny": p["deny"] as? [String] ?? []]
        let mask = g?.integer(forKey: GuardianMessage.categoriesOffKey) ?? 0
        if mask != 0 { doc["categories_off"] = mask & 0xFFFF }
        guard let d = try? JSONSerialization.data(withJSONObject: doc),
              let json = String(data: d, encoding: .utf8) else { return }
        _ = core.setUserRules(json: json)
        g?.set(core.userRulesJSON(), forKey: GuardianMessage.rulesKey)
        g?.set(echoUpdated ?? Date().timeIntervalSince1970, forKey: GuardianMessage.rulesUpdatedKey)
    }

    /// The core keeps `categories_off` in memory only and a rules write replaces
    /// it, so the stored mask rides along with every lists change.
    private func reapplyCategoriesOff() {
        let mask = BrandRuntime.defaults?.integer(forKey: GuardianMessage.categoriesOffKey) ?? 0
        if mask != 0 { _ = RedSocketClient.shared.setCategoriesOff(mask) }
    }

    /// Re-apply what the user set, before the first connection is made, so the
    /// first {rules} frame carries the lists and the category mask.
    private func restoreGuardian() {
        let g = BrandRuntime.defaults
        if let rules = g?.string(forKey: GuardianMessage.rulesKey), !rules.isEmpty {
            _ = RedSocketClient.shared.setUserRules(json: rules)
        }
        reapplyCategoriesOff()
        if g?.object(forKey: GuardianMessage.enabledKey) != nil {
            RedSocketClient.shared.setBlockingEnabled(g?.bool(forKey: GuardianMessage.enabledKey) ?? false)
        }
    }

    /// nil = this session may run; otherwise why not. Read from the app group,
    /// which the app keeps current; the same rules as the app's own gates.
    private func storeKitHeldFresh(_ g: UserDefaults?) -> Bool {
        guard let g, g.bool(forKey: "storeKitHeld") else { return false }
        let at = g.double(forKey: "storeKitHeldAt")
        return at > 0 && Date().timeIntervalSince1970 - at < 24 * 60 * 60
    }

    struct Refusal { let kind: String; let reason: String }

    /// Recorded for the app (GuardianMessage.lastRefusalKey); see there.
    private func recordRefusal(_ r: Refusal) {
        BrandRuntime.defaults?.set(["kind": r.kind, "reason": r.reason, "at": Date().timeIntervalSince1970],
                                   forKey: GuardianMessage.lastRefusalKey)
    }

    private static func refusalError(_ text: String) -> NSError {
        NSError(domain: NEVPNErrorDomain, code: NEVPNError.Code.connectionFailed.rawValue,
                userInfo: [NSLocalizedDescriptionKey: text])
    }

    private func accessRefusal() -> Refusal? {
        guard let g = BrandRuntime.defaults else { return Refusal(kind: "app_group", reason: "app group unavailable") }
        let paid = g.bool(forKey: "isPaid")
        if BrandRuntime.paidOnly {
            return paid ? nil : Refusal(kind: "entitlement", reason: "no active subscription")
        }
        let entitled = paid || g.bool(forKey: "isFreedomRegion")
        if g.bool(forKey: "quotaHardStop"), g.bool(forKey: "overQuota"), !entitled {
            return Refusal(kind: "allowance", reason: "allowance used")
        }
        return nil
    }

    /// Per tunnel session; touched only on `guardianQueue`.
    private var gSession = GuardianSnapshot.empty
    /// Notes for the app (notice, and anything this process does not act on).
    private var pendingNotes: [Any] = []
    private let guardianQueue = DispatchQueue(label: "rostam.guardian")
    private var notesTimer: DispatchSourceTimer?

    private func resetGuardianSession() {
        guardianQueue.sync {
            discardQueuedNotesLocked()
            gSession = .empty
            pendingNotes = []
        }
    }

    private func discardQueuedNotesLocked() {
        let json = RedSocketClient.shared.drainNotesJSON()
        guard json != "[]",
              let arr = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [[String: Any]]
        else { return }
        for m in arr where m["type"] as? String == "cursor" {
            if let p = m["payload"] as? [String: Any],
               let d = try? JSONSerialization.data(withJSONObject: p),
               let s = String(data: d, encoding: .utf8) {
                BrandRuntime.defaults?.set(s, forKey: Self.ctlCursorKey)
            }
        }
        extLog("guardian: discarded \(arr.count) note(s) from the previous session")
    }

    /// The EXTENSION drains rs_drain_notes on its own clock, so an entitlement note
    /// ends a session even when the app has been swiped away, and the core's queue
    /// never backs up.
    private func startNotesDrain() {
        notesTimer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: guardianQueue)
        t.schedule(deadline: .now() + 2, repeating: 5)
        t.setEventHandler { [weak self] in self?.drainNotesLocked() }
        t.resume()
        notesTimer = t
    }

    private func drainNotesLocked() {
        let json = RedSocketClient.shared.drainNotesJSON()
        guard json != "[]",
              let arr = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [[String: Any]]
        else { return }
        let g = BrandRuntime.defaults
        for m in arr {
            let p = m["payload"] as? [String: Any] ?? [:]
            switch m["type"] as? String {
            case "caps":

                let acked = p["acked"] as? Bool ?? false
                gSession.capsAcknowledged = acked
                if !acked {
                    gSession.protectionEnabled = nil
                    gSession.protectionListVersion = nil
                    gSession.protectionFeedDate = nil
                }
            case "cursor":

                if let d = try? JSONSerialization.data(withJSONObject: p),
                   let json = String(data: d, encoding: .utf8) {
                    g?.set(json, forKey: Self.ctlCursorKey)
                }
            case "protection":

                gSession.protectionEnabled = p["enabled"] as? Bool ?? false
                gSession.protectionListVersion = (p["list_version"]).flatMap { $0 is NSNull ? nil : "\($0)" }
                gSession.protectionFeedDate = p["feed_date"] as? String
            case "entitlement":

                guard let state = p["state"] as? String, !state.isEmpty else { continue }
                gSession.entitlementState = state
                gSession.entitlementPaidUntil = p["paid_until"] as? String
                if state.lowercased() == "paid" {
                    g?.set(true, forKey: "isPaid")
                } else if BrandRuntime.paidOnly, !storeKitHeldFresh(g) {
                    g?.set(false, forKey: "isPaid")
                    extLog("[paid_only] exit says \(state) — ending the session")
                    recordRefusal(Refusal(kind: "entitlement", reason: "subscription not active (\(state))"))
                    cancelTunnelWithError(Self.refusalError("Subscription not active"))
                } else if BrandRuntime.paidOnly {
                    extLog("[paid_only] exit says \(state) but StoreKit holds a subscription — not ending")
                }
            case "rules":
                applyRulesEchoLocked(p)
            default:
                pendingNotes.append(m)
                if pendingNotes.count > 200 { pendingNotes.removeFirst(pendingNotes.count - 200) }
            }
        }
    }

    /// The core's current lists with one rule applied (same normalisation as its
    /// set_user_rule) and categories_off attached, for a single rs_set_user_rules
    /// call.
    private static func rulesJSON(_ current: String, verdict: String, host: String, mask: Int) -> String {
        let o = (try? JSONSerialization.jsonObject(with: Data(current.utf8))) as? [String: Any] ?? [:]
        var allow = o["allow"] as? [String] ?? []
        var deny = o["deny"] as? [String] ?? []
        var h = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while h.hasPrefix("*.") { h.removeFirst(2) }
        h = h.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        allow.removeAll { $0 == h }
        deny.removeAll { $0 == h }
        if verdict == "allow" { allow.append(h) }
        if verdict == "deny" { deny.append(h) }
        let out: [String: Any] = ["allow": allow, "deny": deny, "categories_off": mask & 0xFFFF]
        guard let d = try? JSONSerialization.data(withJSONObject: out),
              let s = String(data: d, encoding: .utf8) else { return current }
        return s
    }

    /// App-group key for the control-stream mailbox cursor.
    private static let ctlCursorKey = "ctlCursor"

    /// The config with the persisted cursor added as `ctl_cursor`. Unchanged when
    /// there is no cursor (no control stream has ever opened) or either side does
    /// not parse.
    private static func withCursor(_ config: String, _ g: UserDefaults?) -> String {
        guard let c = g?.string(forKey: ctlCursorKey),
              let cursor = (try? JSONSerialization.jsonObject(with: Data(c.utf8))) as? [String: Any],
              var o = (try? JSONSerialization.jsonObject(with: Data(config.utf8))) as? [String: Any]
        else { return config }
        o["ctl_cursor"] = cursor
        guard let d = try? JSONSerialization.data(withJSONObject: o),
              let out = String(data: d, encoding: .utf8) else { return config }
        return out
    }

    /// The core's stats and rules plus this session's acknowledgements.
    private func sessionSnapshotLocked() -> GuardianSnapshot {
        var s = RedSocketClient.shared.guardianSnapshot()
        s.capsAcknowledged = gSession.capsAcknowledged
        s.protectionEnabled = gSession.protectionEnabled
        s.protectionListVersion = gSession.protectionListVersion
        s.protectionFeedDate = gSession.protectionFeedDate
        s.entitlementState = gSession.entitlementState
        s.entitlementPaidUntil = gSession.entitlementPaidUntil
        return s
    }

    /// The free tier's cap, refusing to read a missing value as "unlimited".
    private static let fallbackFreeKbps: Int32 = 2000
    private func freeTierKbps(_ g: UserDefaults?) -> Int32 {
        let v = Int32(g?.integer(forKey: "freeKbps") ?? 0)
        if v > 0 { return v }
        extLog("freeKbps missing or 0 while metering applies — using \(Self.fallbackFreeKbps)")
        return Self.fallbackFreeKbps
    }

    private var statsLast: (tx: UInt64, rx: UInt64) = (0, 0)
    private var statsTimer: DispatchSourceTimer?
    /// statsLast is now touched from the timer queue AND the message queue.
    private let statsQueue = DispatchQueue(label: "rostam.stats")

    /// Fold the counters on the EXTENSION's own clock, not the app's poll.
    private func startStatsAccumulator() {
        statsTimer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: statsQueue)
        t.schedule(deadline: .now() + 15, repeating: 15)
        t.setEventHandler { [weak self] in self?.accumulateStatsLocked() }
        t.resume()
        statsTimer = t
    }

    /// Fold the tun counters into durable totals. Deltas, not absolutes: the
    /// counters reset whenever the extension restarts, so anything derived from
    /// their absolute value loses the history at every reconnect.
    private func accumulateStats() {
        statsQueue.sync {
            accumulateStatsLocked()
        }
    }

    private func accumulateStatsLocked() {
        let s = Tun2SocksWrapper.shared.getStats()
        let tx = UInt64(s.txBytes), rx = UInt64(s.rxBytes)
        let d = (tx >= statsLast.tx ? tx - statsLast.tx : tx)
              + (rx >= statsLast.rx ? rx - statsLast.rx : rx)
        statsLast = (tx, rx)
        guard d > 0, let g = BrandRuntime.defaults else { return }
        g.set(String((UInt64(g.string(forKey: "lifetimeBytes") ?? "0") ?? 0) + d),
              forKey: "lifetimeBytes")

        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        let k = f.string(from: Date())
        var m = g.dictionary(forKey: "dailyBytes") as? [String: NSNumber] ?? [:]
        m[k] = NSNumber(value: (m[k]?.uint64Value ?? 0) + d)
        for old in m.keys.sorted().dropLast(14) { m.removeValue(forKey: old) }
        g.set(m, forKey: "dailyBytes")
    }

    override func stopTunnel(with reason: NEProviderStopReason,
                             completionHandler: @escaping () -> Void) {
        extLog("stopTunnel(reason: \(reason.rawValue))")

        healthTimer?.cancel()
        healthTimer = nil
        accumulateStats()
        statsTimer?.cancel()
        statsTimer = nil
        notesTimer?.cancel()
        notesTimer = nil
        guardianQueue.sync { discardQueuedNotesLocked() }
        peerRelayTimer?.cancel()
        peerRelayTimer = nil
        PeerActivation.deactivate()
        Tun2SocksWrapper.shared.stop()
        WgtcpClient.shared.stop()
        RedSocketClient.shared.stop()
        completionHandler()
    }

    /// Bring up WGTCP, which serves SOCKS5 on the same port RedSocket would.
    private func startWgtcp(config: String,
                            probeEnabled: Bool,
                            onFinished: @escaping (Bool) -> Void,
                            completionHandler: @escaping (Error?) -> Void) {
        extLog("WGTCP: starting")
        let bgThread = Thread { [weak self] in
            guard let self = self else { return }
            let result = WgtcpClient.shared.start(configJSON: config, socksPort: self.preferredSocksPort)
            let connected = result == "ok" && WgtcpClient.shared.waitUntilConnected()
            self.extLog("WGTCP result: \(result), connected: \(connected)")

            DispatchQueue.main.async {
                guard connected else {
                    WgtcpClient.shared.stop()
                    onFinished(false)
                    return
                }
                self.setActiveTransport("wgtcp")
                self.configureSocksProxy(probeEnabled: probeEnabled,
                                         completionHandler: completionHandler)
                onFinished(true)
            }
        }
        bgThread.qualityOfService = .userInitiated
        bgThread.start()
    }

    private func startRedSocket(probeEnabled: Bool, completionHandler: @escaping (Error?) -> Void) {
        extLog("RedSocket v2: starting carrier race")

        let bgThread = Thread { [weak self] in
            guard let self = self else { return }

            let g = BrandRuntime.defaults
            let paid = g?.bool(forKey: "isPaid") ?? false

            let freeRegion = !BrandRuntime.paidOnly && (g?.bool(forKey: "isFreedomRegion") ?? false)

            RedSocketClient.shared.setClientId(g?.string(forKey: "cid") ?? "")
            RedSocketClient.shared.setPremium(paid)
            RedSocketClient.shared.setRegion(g?.string(forKey: "entitledRegion") ?? "")

            let entitled = paid || freeRegion

            let overQuota = g?.bool(forKey: "overQuota") ?? false
            RedSocketClient.shared.setRateLimitKbps(
                (entitled || !overQuota) ? 0 : freeTierKbps(g))
            RedSocketClient.shared.setCdnAllowed(entitled)

            if let config = g?.string(forKey: "config") {
                RedSocketClient.shared.loadConfig(Self.withCursor(config, g))
                self.extLog("config loaded (\(config.count) chars)")
            } else {
                self.extLog("no config in the app group; using built-in endpoints")
            }

            RedSocketClient.shared.setApp(BrandRuntime.id)
            self.restoreGuardian()

            let result = RedSocketClient.shared.start(socksPort: self.preferredSocksPort)
            self.extLog("RedSocket result: \(result)")

            if result.hasPrefix("ok:") {
                let carrier = String(result.dropFirst(3))
                self.extLog("RedSocket: connected via \(carrier)")
                self.setActiveTransport("redsocket")

                DispatchQueue.main.async {
                    self.configureSocksProxy(probeEnabled: probeEnabled, completionHandler: completionHandler)
                }
            } else {
                let error = String(result.dropFirst(4))
                self.extLog("RedSocket FAILED: \(error)")
                DispatchQueue.main.async {
                    completionHandler(NSError(domain: "com.rostamvpn.redsocket", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: error]))
                }
            }
        }
        bgThread.qualityOfService = .userInitiated
        bgThread.start()
    }

    /// Which core is actually serving SOCKS5. The health monitor MUST consult this:
    /// asking the wrong core whether it is running returns false forever and the
    /// watchdog tears down a perfectly healthy tunnel.
    private var activeTransport = "redsocket"

    private func setActiveTransport(_ transport: String) {
        activeTransport = transport
        BrandRuntime.defaults?.set(transport, forKey: "activeTransport")
    }

    /// Find the TUN (utun) file descriptor after setTunnelNetworkSettings
    /// completes. Network Extension creates a utun device; we scan open fds to find
    /// it.
    private var tunnelFileDescriptor: Int32? {
        var buf = [CChar](repeating: 0, count: Int(IFNAMSIZ))
        for fd: Int32 in 0...1024 {
            var len = socklen_t(buf.count)
            if getsockopt(fd, 2, 2, &buf, &len) == 0 {
                let name = String(cString: buf)
                if name.hasPrefix("utun") {
                    return fd
                }
            }
        }
        return nil
    }

    private func configureSocksProxy(probeEnabled: Bool, completionHandler: @escaping (Error?) -> Void) {
        let socksPort = activeSocksPort
        setTunnelNetworkSettings(TunnelNetwork.settings()) { [weak self] error in
            if let error = error {
                self?.extLog("setTunnelNetworkSettings error: \(error.localizedDescription)")
                completionHandler(error)
                return
            }
            self?.extLog("TUN interface configured")

            guard let tunFD = self?.tunnelFileDescriptor else {
                self?.extLog("ERROR: Could not find TUN file descriptor")
                completionHandler(NSError(domain: "com.rostamvpn.redsocket", code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "TUN fd not found"]))
                return
            }
            self?.extLog("[Tun2Socks] Found TUN fd: \(tunFD)")

            do {
                try Tun2SocksWrapper.shared.initialize(
                    socksAddress: "127.0.0.1:\(socksPort)",
                    tunMTU: 1500,
                    enableMapDNS: true
                )
                self?.extLog("[Tun2Socks] Config: TUN=198.18.0.1, DNS=198.18.0.2, mapdns=ON, MTU=1500")
                Tun2SocksWrapper.shared.setTunnelFD(tunFD)
                try Tun2SocksWrapper.shared.start()
                self?.extLog("[Tun2Socks] Started successfully")
            } catch {
                self?.extLog("[Tun2Socks] Start FAILED: \(error.localizedDescription)")
                completionHandler(error)
                return
            }

            completionHandler(nil)

            self?.startHealthMonitor()
            self?.startStatsAccumulator()
            self?.startNotesDrain()

            PeerActivation.tunByteSource = {
                let s = Tun2SocksWrapper.shared.getStats()
                return UInt64(s.rxBytes) + UInt64(s.txBytes)
            }
            let relayTimer = DispatchSource.makeTimerSource(
                queue: DispatchQueue.global(qos: .utility))
            relayTimer.schedule(deadline: .now() + 5, repeating: 5)
            relayTimer.setEventHandler {
                PeerActivation.maybeActivate(socksPort: socksPort)
            }
            relayTimer.resume()
            self?.peerRelayTimer = relayTimer

            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5.0) {
                let stats = Tun2SocksWrapper.shared.getStats()
                self?.extLog("[Tun2Socks] Stats after 5s: TX=\(stats.txPackets)pkts/\(stats.txBytes)B, RX=\(stats.rxPackets)pkts/\(stats.rxBytes)B")
            }

            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2.0) {
                self?.testConnectivityViaSocks()
            }
        }
    }

    /// Periodic check that SOCKS5 proxy is alive. If the Rust proxy thread dies
    /// (front-selector failure, TLS error, panic), tear down the VPN instead of
    /// showing a fake "connected" state with no traffic.
    private func startHealthMonitor() {
        healthTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + 10, repeating: 10)
        var consecutiveFailures = 0
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }

            let proxyAlive = activeTransport == "wgtcp"
                ? WgtcpClient.shared.isConnected
                : RedSocketClient.shared.isRunning
            let portOpen = self.testSocksLiveness(port: self.activeSocksPort)

            if proxyAlive && portOpen {
                consecutiveFailures = 0
                return
            }

            consecutiveFailures += 1
            self.extLog("[HealthCheck] \(self.activeTransport) proxy dead (alive=\(proxyAlive), port=\(portOpen), failures=\(consecutiveFailures)/2)")

            if consecutiveFailures >= 2 {
                self.extLog("[HealthCheck] Tearing down VPN — proxy unrecoverable after \(consecutiveFailures) checks")
                self.cancelTunnelWithError(NSError(
                    domain: "com.rostamvpn.redsocket", code: -10,
                    userInfo: [NSLocalizedDescriptionKey: "VPN proxy stopped unexpectedly"]
                ))
            }
        }
        timer.resume()
        healthTimer = timer
        extLog("[HealthCheck] Started (10s interval, 2-strike teardown)")
    }

    /// Quick TCP liveness check on the local SOCKS5 port.
    private func testSocksLiveness(port: UInt16) -> Bool {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }
        defer { close(sock) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        var tv = timeval(tv_sec: 3, tv_usec: 0)
        setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }

    private func testConnectivityViaSocks() {
        extLog("Testing SOCKS5 connectivity on port \(activeSocksPort)...")

        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [
            kCFStreamPropertySOCKSProxyHost as String: "127.0.0.1",
            kCFStreamPropertySOCKSProxyPort as String: activeSocksPort,
            kCFStreamPropertySOCKSVersion as String: kCFStreamSocketSOCKSVersion5,
        ]
        config.timeoutIntervalForRequest = 15
        let session = URLSession(configuration: config)

        let url = URL(string: "https://ip-geo.example.com/")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        request.setValue(FleetConstants.wireUserAgent, forHTTPHeaderField: "User-Agent")

        let task = session.dataTask(with: request) { [weak self] _, _, error in
            self?.extLog(error.map { "SOCKS5 test FAILED: \($0.localizedDescription)" } ?? "SOCKS5 test OK")
        }
        task.resume()
    }
}
