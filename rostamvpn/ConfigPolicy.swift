// Copyright 2026 Internet Mastering & Company, Inc.
// SPDX-License-Identifier: Apache-2.0

import Foundation
import StoreKit
import RostamKit

enum ConfigPolicy {
    /// Shared with the Network Extension. Same suite `RemoteConfig` writes to.
    static let suiteName = BrandRuntime.appGroup

    static var devRegionOverride: String? {
        let raw = UserDefaults(suiteName: suiteName)?
            .string(forKey: "devRegionOverride")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard let raw, !raw.isEmpty else { return nil }
        return raw
    }

    /// ISO country for a freedom-region timezone, else nil.
    static func freedomRegion(forTimezone tz: String,
                              in map: [String: [String]]) -> String? {
        let t = tz.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        for (region, zones) in map {
            for z in zones where !z.isEmpty {
                if t.compare(z, options: .caseInsensitive) == .orderedSame { return region }
                if t.lowercased().hasPrefix(z.lowercased()) { return region }
            }
        }
        return nil
    }

    /// Everything the config says, parsed exactly once.
    struct Snapshot {
        let version: String

        let freedomRegions: [String: [String]]
        /// Does this BRAND grant the free tier at all? See `isFreedomRegion`.
        let freedomTier: Bool

        let serverRegions: [(id: String, label: String)]

        let throttleEnabled: Bool
        let freeKbps: Int
        /// STOP instead of slowing down once the allowance is gone. A brand with this
        /// on has no free tier past the quota at all.
        let quotaHardStop: Bool
        /// No free tier AT ALL: no allowance, no slow lane, no trial. Top-level
        /// `paid_only`, absent = false, so every brand that predates the key is
        /// untouched.
        private(set) var remotePaidOnly = false
        /// `protection.enabled`: the malware-protection kill switch (OTA). Only the
        /// `tabs` status line reads it; false when absent.
        private(set) var protectionEnabled = false
        /// OTA `protection.categories`: category name -> verdict bit (0...15), the
        /// pipeline's meta.json bit table. Empty (the default) hides the Rules toggles:
        /// the client never invents category names.
        private(set) var protectionCategories: [String: Int] = [:]

        let probe: ProbeSettings

        let transportOrder: [String]

        /// The DEFAULTS. The LAST of three steps (see `snapshot`): used when no config
        /// has been fetched, this build bundles no boot config, and whichever of those
        /// exists will not parse.
        static let fallback = Snapshot(
            version: "",
            freedomTier: true,
            freedomRegions: ["IR": ["Asia/Tehran", "Iran"],
                             "RU": ["Europe/Moscow", "W-SU"]],
            serverRegions: [],
            throttleEnabled: false,
            freeKbps: 0,
            quotaHardStop: false,
            probe: .disabled,

            transportOrder: ["redsocket"]
        )

        init(version: String,
             freedomTier: Bool,
             freedomRegions: [String: [String]],
             serverRegions: [(id: String, label: String)],
             throttleEnabled: Bool,
             freeKbps: Int,
             quotaHardStop: Bool,
             probe: ProbeSettings,
             transportOrder: [String]) {
            self.version = version
            self.freedomTier = freedomTier
            self.freedomRegions = freedomRegions
            self.serverRegions = serverRegions
            self.quotaHardStop = quotaHardStop
            self.throttleEnabled = throttleEnabled
            self.freeKbps = freeKbps
            self.probe = probe
            self.transportOrder = transportOrder
        }

        /// Parse a decoded config object. Pure — no I/O, no side effects.
        init(json o: [String: Any]) {
            let fb = Snapshot.fallback

            version = (o["version"] as? String) ?? ""

            var freedom: [String: [String]] = [:]
            if let fr = o["freedom_regions"] as? [String: Any] {
                for (k, v) in fr {
                    freedom[k.uppercased()] = (v as? [String])?.filter { !$0.isEmpty } ?? []
                }
            }
            freedomRegions = freedom.isEmpty ? fb.freedomRegions : freedom
            freedomTier = (o["freedom_tier"] as? Bool) ?? true

            if let regions = o["regions"] as? [String: Any] {
                serverRegions = regions.keys.sorted().map { id in
                    let label = (regions[id] as? [String: Any])?["label"] as? String
                    return (id: id, label: label?.isEmpty == false ? label! : id.uppercased())
                }
            } else {
                serverRegions = []
            }

            if let th = o["throttle"] as? [String: Any] {
                throttleEnabled = (th["enabled"] as? Bool) ?? false
                quotaHardStop = (th["hard_stop"] as? Bool) ?? false
                let raw = (th["free_kbps"] as? Int) ?? 0

                freeKbps = raw <= 0 ? 0 : (raw < 256 ? 256 : raw)
            } else {
                throttleEnabled = fb.throttleEnabled
                freeKbps = fb.freeKbps
                quotaHardStop = fb.quotaHardStop
            }

            remotePaidOnly = (o["paid_only"] as? Bool) ?? false
            protectionEnabled = ((o["protection"] as? [String: Any])?["enabled"] as? Bool) ?? false
            protectionCategories = (((o["protection"] as? [String: Any])?["categories"] as? [String: Any]) ?? [:])
                .compactMapValues { ($0 as? Int).flatMap { (0...15).contains($0) ? $0 : nil } }

            probe = ProbeSettings(json: o["probe"] as? [String: Any])

            let order = (o["transport_order"] as? [String] ?? [])
                .map { $0.lowercased() }
                .filter { !$0.isEmpty }
            transportOrder = order.isEmpty ? fb.transportOrder : order
        }
    }

    /// Smart-probe policy. A client only becomes an exit when it opts in AND every
    /// configured gate passes AND the sample roll succeeds.
    struct ProbeSettings {
        let enabled: Bool
        let gatewayHost: String
        let gatewayPort: Int
        /// Inclusive random wait before the FIRST gateway dial, seconds. Without it
        /// every client whose tunnel comes up in the same window dials the gateway
        /// simultaneously — a self-inflicted DDoS.
        let startDelay: (lo: Int, hi: Int)
        /// Bytes of tun traffic required before enrolling, proving a real session
        /// rather than an install that opened the app once.
        let minTunBytes: Int64
        /// All four are EMPTY MEANS NO RESTRICTION.
        let regions: Set<String>
        let keyboardLangs: Set<String>
        let deviceTypes: Set<String>
        let excludeEmulator: Bool
        /// Ramp knob, 0…100. Sticky per install on Android: lowering it does NOT retire
        /// devices that already rolled in.
        let samplePct: Int

        static let disabled = ProbeSettings(
            enabled: false, gatewayHost: "", gatewayPort: 9080,
            startDelay: (5, 15), minTunBytes: 512_000,
            regions: [], keyboardLangs: [], deviceTypes: [],
            excludeEmulator: true, samplePct: 0
        )

        init(enabled: Bool, gatewayHost: String, gatewayPort: Int,
             startDelay: (lo: Int, hi: Int), minTunBytes: Int64,
             regions: Set<String>, keyboardLangs: Set<String>,
             deviceTypes: Set<String>, excludeEmulator: Bool, samplePct: Int) {
            self.enabled = enabled
            self.gatewayHost = gatewayHost
            self.gatewayPort = gatewayPort
            self.startDelay = startDelay
            self.minTunBytes = minTunBytes
            self.regions = regions
            self.keyboardLangs = keyboardLangs
            self.deviceTypes = deviceTypes
            self.excludeEmulator = excludeEmulator
            self.samplePct = samplePct
        }

        /// Pure. `nil` (no `probe` block) yields the disabled settings.
        init(json p: [String: Any]?) {
            guard let p else { self = .disabled; return }
            let d = ProbeSettings.disabled

            enabled = (p["enabled"] as? Bool) ?? false
            gatewayHost = ((p["gateway_host"] as? String) ?? "")
                .trimmingCharacters(in: .whitespaces)
            let port = (p["gateway_port"] as? Int) ?? d.gatewayPort
            gatewayPort = (1...65535).contains(port) ? port : d.gatewayPort

            let raw = (p["start_delay_secs"] as? [Int]) ?? []
            if raw.count >= 2 {
                let a = max(0, raw[0]), b = max(0, raw[1])
                startDelay = a <= b ? (a, b) : (b, a)
            } else {
                startDelay = d.startDelay
            }

            let mtb = (p["min_tun_bytes"] as? NSNumber)?.int64Value ?? d.minTunBytes
            minTunBytes = max(0, mtb)

            func set(_ k: String) -> Set<String> {
                Set((p[k] as? [String] ?? [])
                    .map { $0.uppercased() }
                    .filter { !$0.isEmpty })
            }
            regions = set("regions")
            keyboardLangs = set("keyboard_langs")
            deviceTypes = set("device_types")
            excludeEmulator = (p["exclude_emulator"] as? Bool) ?? true
            samplePct = min(100, max(0, (p["sample_pct"] as? Int) ?? 100))
        }
    }

    private static let lock = NSLock()
    private static var cachedRaw: String?
    private static var cachedSnapshot: Snapshot?

    /// The BOOT config bundled into this build, or nil when the brand ships none.
    /// Read once; a resource cannot change under a running process.
    private static let bundledRaw: String? = {
        guard let url = Bundle.main.url(forResource: "default-config", withExtension: "json"),
              let text = try? String(contentsOf: url, encoding: .utf8),
              !text.isEmpty
        else { return nil }
        return text
    }()

    /// The parsed config. Never nil — falls back to `Snapshot.fallback`, whose
    /// every default errs in the safe direction (see its doc comment).
    static var snapshot: Snapshot {
        let raw = RemoteConfig.current ?? bundledRaw
        lock.lock()
        defer { lock.unlock() }
        if let cachedSnapshot, cachedRaw == raw { return cachedSnapshot }

        let parsed: Snapshot
        if let raw,
           let data = raw.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            parsed = Snapshot(json: obj)
        } else {
            parsed = .fallback
        }
        cachedRaw = raw
        cachedSnapshot = parsed
        return parsed
    }

    /// Drop the cache. For tests and for anyone who mutates the stored config
    /// directly; the normal refresh path does not need it.
    static func invalidate() {
        lock.lock()
        cachedRaw = nil
        cachedSnapshot = nil
        lock.unlock()
    }

    /// App Store storefront country, or nil.
    static var storefrontCountry: String? {
        guard let c = SKPaymentQueue.default().storefront?.countryCode, !c.isEmpty
        else { return nil }
        return c.uppercased()
    }

    /// ISO country the device appears to be in, uppercased. "" when unknown.
    static var country: String {
        if let dev = devRegionOverride { return dev }
        if let store = storefrontCountry { return store }
        if let region = Locale.current.regionCode, !region.isEmpty {
            return region.uppercased()
        }
        return ""
    }

    /// The device timezone resolved to a freedom region, or nil.
    static var timezoneRegion: String? {
        freedomRegion(forTimezone: TimeZone.current.identifier, in: freedomRegions)
    }

    /// ISO -> timezones that also count.
    static var freedomRegions: [String: [String]] { snapshot.freedomRegions }
    static var freedomTier: Bool { snapshot.freedomTier }
    static var quotaHardStop: Bool { snapshot.quotaHardStop }
    /// See `Snapshot.paidOnly`. Every free-allowance surface and the connect gate
    /// read this; nothing reads the brand id.
    static var paidOnly: Bool { BrandRuntime.paidOnly }
    static var protectionEnabled: Bool { snapshot.protectionEnabled }
    static var protectionCategories: [String: Int] { snapshot.protectionCategories }

    /// Just the country codes.
    static var freedomRegionCodes: Set<String> { Set(snapshot.freedomRegions.keys) }

    /// Whether this device gets the product free by policy: no paywall, no usage
    /// metering, no purchase UI.
    static var isFreedomRegion: Bool {
        guard freedomTier, !paidOnly else { return false }
        let list = freedomRegionCodes

        if let dev = devRegionOverride { return list.contains(dev) }
        if let tz = timezoneRegion, list.contains(tz) { return true }
        if let r = Locale.current.regionCode?.uppercased(), list.contains(r) { return true }
        if let s = storefrontCountry, list.contains(s) { return true }
        return false
    }

    /// The server region picker: `(id, label)` sorted by id, labels from the config
    /// so a region added over the air shows its own name. Falls back to the
    /// uppercased id, never to a hardcoded name.
    static func serverRegions() -> [(String, String)] {
        snapshot.serverRegions.map { ($0.id, $0.label) }
    }

    /// Free-tier speed limit in kbps. 0 = unlimited (also when throttling is off,
    /// so callers need only read this one number).
    static var freeKbps: Int {
        let s = snapshot
        return s.throttleEnabled ? s.freeKbps : 0
    }

    static var throttleEnabled: Bool { snapshot.throttleEnabled }

    /// The free tier's speed as a display string, e.g. "2 Mbps".
    static var freeSpeedLabel: String {
        if quotaHardStop { return "" }
        let kbps = freeKbps
        guard kbps > 0 else { return "" }
        let n = NumberFormatter()
        n.numberStyle = .decimal
        n.maximumFractionDigits = kbps % 1000 == 0 ? 0 : 1
        if kbps >= 1000 {
            let v = n.string(from: NSNumber(value: Double(kbps) / 1000.0)) ?? "\(kbps / 1000)"
            return String(format: NSLocalizedString("speed_mbps", value: "%@ Mbps",
                                                    comment: "%@ is a number"), v)
        }
        let v = n.string(from: NSNumber(value: kbps)) ?? "\(kbps)"
        return String(format: NSLocalizedString("speed_kbps", value: "%@ kbps",
                                                comment: "%@ is a number"), v)
    }

    static var probe: ProbeSettings { snapshot.probe }

    /// Protocol priority: listed order is try order; omitting one skips it.
    static var transportOrder: [String] { snapshot.transportOrder }

    /// Publish version.
    static var configVersion: String {
        let header = RemoteConfig.stamp.version
        return header.isEmpty ? snapshot.version : header
    }

    /// When the server PUBLISHED the config, not when this device fetched it. A
    /// device-side date would read "just now" for a config published months ago,
    /// which is the opposite of what the display is for.
    static var publishedAt: Date? { RemoteConfig.stamp.publishedAt }

    /// One line describing every input to the region decision.
    static func describe() -> String {
        "override=\(devRegionOverride ?? "nil") "
        + "storefront=\(storefrontCountry ?? "nil") "
        + "locale=\(Locale.current.regionCode ?? "nil") "
        + "tz=\(TimeZone.current.identifier) "
        + "-> country=\(country) freedom=\(isFreedomRegion) "
        + "list=\(freedomRegionCodes.sorted().joined(separator: ",")) "
        + "cfg=\(configVersion.isEmpty ? "-" : configVersion)"
        + (snapshot.remotePaidOnly != paidOnly ? " paid_only:build=\(paidOnly)/remote=\(snapshot.remotePaidOnly)" : "")
    }
}
