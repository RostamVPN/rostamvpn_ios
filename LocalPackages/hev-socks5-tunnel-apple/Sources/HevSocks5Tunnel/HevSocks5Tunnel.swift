// Copyright 2026 Internet Mastering & Company, Inc.
// SPDX-License-Identifier: Apache-2.0

import Foundation
import CHevSocks5Tunnel

/// Swift wrapper for hev-socks5-tunnel (tun2socks) Converts TUN interface
/// packets to SOCKS5 connections.
public class Tun2SocksWrapper {
    public enum TunnelError: LocalizedError {
        case initFailed
        case alreadyRunning
        case notRunning
        case invalidConfig

        public var errorDescription: String? {
            switch self {
            case .initFailed: return "Failed to initialize hev-socks5-tunnel"
            case .alreadyRunning: return "Tunnel is already running"
            case .notRunning: return "Tunnel is not running"
            case .invalidConfig: return "Invalid configuration"
            }
        }
    }

    /// Tunnel statistics.
    public struct Stats {
        public let txPackets: UInt64
        public let txBytes: UInt64
        public let rxPackets: UInt64
        public let rxBytes: UInt64
    }

    /// Singleton instance.
    public static let shared = Tun2SocksWrapper()

    private var isRunning = false
    private var tunnelThread: Thread?
    private var configString: String = ""
    private var tunFD: Int32 = -1

    private init() {}

    /// Initialize tunnel with SOCKS5 server address.
    public func initialize(
        socksAddress: String,
        tunMTU: Int = 1500,
        enableMapDNS: Bool = true
    ) throws {
        let components = socksAddress.components(separatedBy: ":")
        guard components.count == 2,
              let port = Int(components[1]) else {
            throw TunnelError.invalidConfig
        }

        let host = components[0]

        var config = """
        tunnel:
          mtu: \(tunMTU)
          ipv4: 198.18.0.1
          ipv6: 'fd00:7a11:4::1'

        socks5:
          address: '\(host)'
          port: \(port)
          udp: 'udp'
        """

        if enableMapDNS {
            config += """

            mapdns:
              address: 198.18.0.2
              port: 53
              network: 100.64.0.0
              netmask: 255.192.0.0
              cache-size: 10000
            """
        }

        config += """

        misc:
          log-level: 'info'
        """

        configString = config
    }

    /// Set the TUN file descriptor from NEPacketTunnelProvider.
    public func setTunnelFD(_ fd: Int32) {
        tunFD = fd
    }

    /// Start the tunnel (runs in background thread) This is a blocking function
    /// that runs until quit() is called.
    public func start() throws {
        guard !isRunning else {
            throw TunnelError.alreadyRunning
        }

        guard !configString.isEmpty else {
            throw TunnelError.invalidConfig
        }

        guard tunFD >= 0 else {
            NSLog("[Tun2Socks] ERROR: Invalid TUN FD: \(tunFD)")
            throw TunnelError.initFailed
        }

        NSLog("[Tun2Socks] Starting tunnel with TUN FD: \(tunFD)")
        NSLog("[Tun2Socks] Config:\n\(configString)")

        isRunning = true
        tunnelThread = Thread { [weak self] in
            guard let self = self else { return }

            NSLog("[Tun2Socks] Thread started, calling hev_socks5_tunnel_main_from_str...")
            let configData = self.configString.data(using: .utf8)!
            let result = configData.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) -> Int32 in
                let bytes = ptr.bindMemory(to: UInt8.self)
                return hev_socks5_tunnel_main_from_str(
                    bytes.baseAddress,
                    UInt32(configData.count),
                    self.tunFD
                )
            }

            if result != 0 {
                NSLog("[Tun2Socks] Tunnel exited with error code: \(result)")
            } else {
                NSLog("[Tun2Socks] Tunnel exited normally")
            }
            self.isRunning = false
        }
        tunnelThread?.name = "Tun2SocksWrapper"
        tunnelThread?.start()
    }

    /// Stop the tunnel.
    public func stop() {
        guard isRunning else { return }
        hev_socks5_tunnel_quit()
    }

    /// Get current tunnel statistics.
    public func getStats() -> Stats {
        var txPackets: size_t = 0
        var txBytes: size_t = 0
        var rxPackets: size_t = 0
        var rxBytes: size_t = 0

        hev_socks5_tunnel_stats(&txPackets, &txBytes, &rxPackets, &rxBytes)

        return Stats(
            txPackets: UInt64(txPackets),
            txBytes: UInt64(txBytes),
            rxPackets: UInt64(rxPackets),
            rxBytes: UInt64(rxBytes)
        )
    }

    /// Check if tunnel is currently running.
    public var running: Bool {
        return isRunning
    }
}

public typealias HevSocks5Tunnel = Tun2SocksWrapper
