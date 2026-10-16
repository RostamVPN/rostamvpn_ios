// Copyright 2026 Internet Mastering & Company, Inc.
// SPDX-License-Identifier: Apache-2.0

import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Decides whether this device may serve as a SOCKS exit for other users, and
/// switches the relay on only when it may.
public enum PeerActivation {
    /// Shared with the tunnel process. The app writes consent and device signals;
    /// the extension reads them.
    private static let suiteName = BrandRuntime.appGroup
    private static var defaults: UserDefaults? { BrandRuntime.defaults }

    /// The user's explicit opt-in. Default FALSE, and read with a `false` fallback
    /// everywhere, so an absent value can never mean "on".
    private static let optInKey = "peerRelayOptIn"
    /// The sticky sample roll (0...99). Written once per install.
    private static let rollKey = "peerRelaySampleRoll"
    /// Device signals the extension process cannot read for itself; the app caches
    /// them here. See `captureDeviceSignals()`.
    private static let keyboardLangsKey = "peerRelayKeyboardLangs"
    private static let deviceTypeKey = "peerRelayDeviceType"
    /// Written by the app; the same value the core is given as its client id.
    private static let cidKey = "cid"
    private static let configKey = "config"

    /// The user's opt-in. FALSE until they turn it on themselves.
    public static var userOptIn: Bool {
        get {
            guard let d = defaults, d.object(forKey: optInKey) != nil else { return false }
            return d.bool(forKey: optInKey)
        }
        set {
            defaults?.set(newValue, forKey: optInKey)
            if !newValue { deactivate() }
        }
    }

    #if canImport(UIKit)
    /// Cache the signals the tunnel process cannot read for itself, only once
    /// the user has opted in; without consent they are cleared.
    public static func captureDeviceSignals() {
        guard userOptIn else {
            defaults?.removeObject(forKey: keyboardLangsKey)
            defaults?.removeObject(forKey: deviceTypeKey)
            return
        }
        let langs = UITextInputMode.activeInputModes
            .compactMap { $0.primaryLanguage?.lowercased() }

            .map { String($0.prefix(while: { $0 != "-" && $0 != "_" })) }
        let idiom = UIDevice.current.userInterfaceIdiom
        let type: String
        switch idiom {
        case .pad: type = "tablet"
        case .phone: type = "phone"
        default: type = "other"
        }
        defaults?.set(Array(Set(langs)), forKey: keyboardLangsKey)
        defaults?.set(type, forKey: deviceTypeKey)
    }
    #endif

    private static var cachedKeyboardLangs: [String] {
        (defaults?.stringArray(forKey: keyboardLangsKey) ?? []).map { $0.lowercased() }
    }

    private static var cachedDeviceType: String? {
        defaults?.string(forKey: deviceTypeKey)?.lowercased()
    }

    /// True on the Simulator. A compile-time check rather than a fingerprint
    /// heuristic — iOS has no analogue of Android's Build.FINGERPRINT, and it does
    /// not need one: there is exactly one way to run a non-device build.
    private static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    /// The `probe` block of the config: the server's half of the consent.
    private struct Policy {
        let enabled: Bool
        let gatewayHost: String
        let gatewayPort: UInt16
        let minTunBytes: UInt64
        let regions: [String]
        let keyboardLangs: [String]
        let deviceTypes: [String]
        let excludeEmulator: Bool
        let samplePct: Int

        /// Returns nil when the config carries no `probe` block, is missing, or does
        /// not parse — all of which mean OFF.
        init?(config: [String: Any]?) {
            guard let p = config?["probe"] as? [String: Any] else { return nil }
            enabled = (p["enabled"] as? Bool) ?? false
            gatewayHost = (p["gateway_host"] as? String) ?? ""
            let port = (p["gateway_port"] as? Int) ?? 9080
            gatewayPort = (port > 0 && port <= 65535) ? UInt16(port) : 9080
            minTunBytes = UInt64(max(0, (p["min_tun_bytes"] as? Int) ?? 512_000))
            regions = ((p["regions"] as? [String]) ?? []).map { $0.lowercased() }
            keyboardLangs = ((p["keyboard_langs"] as? [String]) ?? []).map { $0.lowercased() }
            deviceTypes = ((p["device_types"] as? [String]) ?? []).map { $0.lowercased() }
            excludeEmulator = (p["exclude_emulator"] as? Bool) ?? true
            samplePct = (p["sample_pct"] as? Int) ?? 100
        }
    }

    /// The config the tunnel is using.
    private static func configObject() -> [String: Any]? {
        func parse(_ json: String?) -> [String: Any]? {
            guard
                let data = json?.data(using: .utf8),
                let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return nil }
            return obj
        }
        if let stored = parse(defaults?.string(forKey: configKey)) { return stored }

        if let url = Bundle.main.url(forResource: "default-config", withExtension: "json"),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            return parse(text)
        }
        return nil
    }

    /// The device's own region, lowercased ISO, from the timezone.
    private static func regionFromTimezone(_ config: [String: Any]?) -> String {
        let tz = TimeZone.current.identifier.trimmingCharacters(in: .whitespaces)
        guard !tz.isEmpty, let map = config?["freedom_regions"] as? [String: Any] else { return "us" }
        for (iso, value) in map {
            guard let zones = value as? [String] else { continue }
            for z in zones where !z.isEmpty {
                if tz.compare(z, options: .caseInsensitive) == .orderedSame
                    || tz.lowercased().hasPrefix(z.lowercased()) {
                    return iso.lowercased()
                }
            }
        }
        return "us"
    }

    /// Sticky per-install sample roll: rolled ONCE, stored, reused forever.
    private static func samplePassed(_ pct: Int) -> Bool {
        if pct >= 100 { return true }
        if pct <= 0 { return false }
        guard let d = defaults else { return false }
        var roll = (d.object(forKey: rollKey) as? Int) ?? -1
        if roll < 0 || roll > 99 {
            roll = Int.random(in: 0..<100)
            d.set(roll, forKey: rollKey)
        }
        return roll < pct
    }

    private static let lock = NSLock()
    /// Set once the relay has been activated in THIS process, so a per-second
    /// caller does not re-evaluate or restart it.
    private static var activated = false

    /// A byte counter for gate 6, when the caller does not pass one.
    public static var tunByteSource: (() -> UInt64)?

    /// Evaluate every gate and, only if all of them pass, start the relay.
    @discardableResult
    public static func maybeActivate(socksPort: UInt16, tunBytes: UInt64? = nil) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        if activated {
            guard userOptIn else {
                RedSocketClient.shared.disablePeer()
                activated = false
                log("stopped (consent withdrawn)")
                return false
            }
            return true
        }

        guard RedSocketClient.shared.isRunning else { return deny("core-not-running") }

        let config = configObject()
        guard let policy = Policy(config: config) else { return deny("no-policy") }
        guard policy.enabled else { return deny("policy-disabled") }

        guard !policy.gatewayHost.isEmpty else { return deny("no-route") }

        guard userOptIn else { return deny("no-consent") }

        let region = regionFromTimezone(config)
        if !policy.regions.isEmpty, !policy.regions.contains(region) {
            return deny("region")
        }

        if !policy.keyboardLangs.isEmpty {
            let langs = Set(cachedKeyboardLangs)
            guard !langs.isEmpty else { return deny("keyboard-unknown") }
            guard !langs.isDisjoint(with: Set(policy.keyboardLangs)) else { return deny("keyboard") }
        }

        if policy.excludeEmulator, isSimulator { return deny("simulator") }
        if !policy.deviceTypes.isEmpty {
            guard let type = cachedDeviceType else { return deny("device-unknown") }
            guard policy.deviceTypes.contains(type) else { return deny("device-type") }
        }

        guard let bytes = tunBytes ?? tunByteSource?() else { return deny("bytes-unknown") }
        guard bytes >= policy.minTunBytes else { return deny("bytes") }

        guard samplePassed(policy.samplePct) else { return deny("sample") }

        let cid = defaults?.string(forKey: cidKey) ?? ""
        if !cid.isEmpty { RedSocketClient.shared.setPeerTag(cid) }
        RedSocketClient.shared.setPeerRoute(host: policy.gatewayHost, port: policy.gatewayPort)
        RedSocketClient.shared.setPeerZone(TimeZone.current.identifier)
        RedSocketClient.shared.enablePeer()

        RedSocketClient.shared.startPeer(socksPort: socksPort)
        activated = true
        log("activated")
        return true
    }

    /// Stop relaying now.
    public static func deactivate() {
        lock.lock()
        defer { lock.unlock() }
        RedSocketClient.shared.disablePeer()
        activated = false
        log("deactivated")
    }

    /// True when this process activated the relay.
    public static var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return activated
    }

    /// Records WHY the relay stayed off, never who or where.
    private static func deny(_ gate: String) -> Bool {
        log("not activated (\(gate))")
        return false
    }

    /// Debug builds only. Gate names carry no identity, no gateway address and no
    /// timezone — and in release nothing is written at all, so a shared debug log
    /// cannot reveal that this user relays.
    private static func log(_ message: String) {
        #if DEBUG
        NSLog("[peer] %@", message)
        #endif
    }
}
