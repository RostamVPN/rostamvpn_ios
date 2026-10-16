// Copyright 2026 Internet Mastering & Company, Inc.
// SPDX-License-Identifier: Apache-2.0

import Foundation
import RedSocketCore

/// The transport, as Swift sees it.
public final class RedSocketClient {
    public static let shared = RedSocketClient()
    private init() {}

    /// Take ownership of a Rust-allocated C string and release it correctly.
    private func takeString(_ p: UnsafeMutablePointer<CChar>?) -> String {
        guard let p else { return "" }
        defer { rs_free_string(p) }
        return String(cString: p)
    }

    /// Install the config JSON.
    public func loadConfig(_ json: String) {
        json.withCString { rs_load_config($0) }
    }

    /// Open a sealed config, or return `err:<reason>` if it does not verify.
    public func unsealConfig(_ sealedBase64: String, certSHA256Hex: String) -> String {
        sealedBase64.withCString { s in
            certSHA256Hex.withCString { c in
                takeString(rs_unseal_config(s, c))
            }
        }
    }

    /// Pick a server region ("fra", "lax", …). Empty string clears it.
    public func setRegion(_ region: String) {
        region.withCString { rs_set_region($0) }
    }

    /// Tell the core whether this install is premium; endpoint tiers depend on it.
    public func setPremium(_ premium: Bool) {
        rs_set_premium(premium ? 1 : 0)
    }

    /// Inject the app-owned client id. MUST be called before `start`.
    public func setClientId(_ cid: String) {
        cid.withCString { rs_set_client_id($0) }
    }

    /// Free-tier speed limit in kbps; 0 = unlimited. Paid users and freedom regions
    /// are never limited — the app decides, the core enforces.
    public func setRateLimitKbps(_ kbps: Int32) {
        rs_set_rate_limit_kbps(kbps)
    }

    /// Allow or deny the CDN fallback tier. Denied for free users by policy.
    public func setCdnAllowed(_ allowed: Bool) {
        rs_set_cdn_allowed(allowed ? 1 : 0)
    }

    /// Start the tunnel, serving SOCKS5 on `socksPort`.
    @discardableResult
    public func start(socksPort: UInt16 = 1080) -> String {
        takeString(rs_start(socksPort))
    }

    public func stop() {
        rs_stop()
    }

    public var isRunning: Bool {
        rs_is_running()
    }

    /// The SOCKS port the core ACTUALLY bound, or 0 when it is not running.
    public var socksPort: UInt16 {
        rs_socks_port()
    }

    /// Identity the relay presents to the gateway. Defaults to the client id when
    /// left unset; empty clears the override.
    public func setPeerTag(_ tag: String) {
        tag.withCString { rs_set_peer_tag($0) }
    }

    /// The gateway the relay reports to, from the config. Empty host clears it, and
    /// there is no address baked into the binary — no route, no relay.
    public func setPeerRoute(host: String, port: UInt16) {
        host.withCString { rs_set_peer_route($0, port) }
    }

    /// Device timezone, sent in the relay handshake.
    public func setPeerZone(_ tz: String) {
        tz.withCString { rs_set_peer_zone($0) }
    }

    /// Arm the relay. Necessary before `startPeer`, and never sufficient on its
    /// own: only call it once every consent gate has passed.
    public func enablePeer() {
        rs_enable_peer()
    }

    /// Disarm the relay. Takes effect on the running session, so a user turning
    /// their opt-in off stops relaying now rather than at the next connect.
    public func disablePeer() {
        rs_disable_peer()
    }

    /// Start the relay, reaching the tunnel through the local SOCKS5 port so its
    /// own traffic is tunnelled like everything else. No-op unless `enablePeer()`
    /// ran first; returns immediately (the relay is a thread).
    public func startPeer(socksPort: UInt16) {
        rs_start_peer(socksPort)
    }
}
