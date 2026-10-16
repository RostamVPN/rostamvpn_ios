// Copyright 2026 Internet Mastering & Company, Inc.
// SPDX-License-Identifier: Apache-2.0

import Foundation
import WgtcpCore

/// WGTCP — WireGuard over a TCP carrier, the second transport.
public final class WgtcpClient {
    public static let shared = WgtcpClient()
    private init() {}

    private func takeString(_ p: UnsafeMutablePointer<CChar>?) -> String {
        guard let p else { return "" }
        defer { wgtcp_free_string(p) }
        return String(cString: p)
    }

    /// Start the tunnel, serving SOCKS5 on `socksPort`.
    @discardableResult
    public func start(configJSON: String, socksPort: UInt16) -> String {
        configJSON.withCString { takeString(wgtcp_start($0, socksPort)) }
    }

    public func stop() {
        wgtcp_stop()
    }

    public var isRunning: Bool {
        wgtcp_is_running() != 0
    }

    /// "connected", "reconnecting" (no completed WireGuard handshake on the
    /// current carrier), "stopped", or "failed: <reason>".
    public var status: String {
        takeString(wgtcp_status())
    }

    /// Running, with a completed WireGuard handshake on the current carrier.
    public var isConnected: Bool {
        isRunning && status == "connected"
    }

    /// Blocks until `isConnected`, checking every 200 ms for up to 15 s.
    public func waitUntilConnected() -> Bool {
        Self.poll(retries: 75, every: 0.2) { isConnected }
    }

    /// Asks `ready` once, then again after each `interval` up to `retries` times.
    static func poll(retries: Int, every interval: TimeInterval, until ready: () -> Bool) -> Bool {
        for _ in 0..<retries {
            if ready() { return true }
            Thread.sleep(forTimeInterval: interval)
        }
        return ready()
    }

    /// Generate a WireGuard keypair as `(privateKey, publicKey)`, both base64.
    public func generateKeypair() -> (privateKey: String, publicKey: String)? {
        let s = takeString(wgtcp_generate_keypair())
        guard !s.hasPrefix("err:") else { return nil }
        let parts = s.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        return (parts[0], parts[1])
    }
}
