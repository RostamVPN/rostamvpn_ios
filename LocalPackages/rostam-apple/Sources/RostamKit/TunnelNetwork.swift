// Copyright 2026 Internet Mastering & Company, Inc.
// SPDX-License-Identifier: Apache-2.0

import NetworkExtension

/// The packet tunnel's network settings. Both address families take the default
/// route and the in-tunnel resolver answers for every domain, so on a dual-stack
/// network no flow leaves beside the tunnel.
public enum TunnelNetwork {
    public static func settings() -> NEPacketTunnelNetworkSettings {
        let s = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "198.18.0.2")
        s.ipv4Settings = NEIPv4Settings(addresses: ["198.18.0.1"], subnetMasks: ["255.254.0.0"])
        s.ipv4Settings?.includedRoutes = [NEIPv4Route.default()]
        s.ipv6Settings = NEIPv6Settings(addresses: ["fd00:7a11:4::1"], networkPrefixLengths: [64])
        s.ipv6Settings?.includedRoutes = [NEIPv6Route.default()]
        s.dnsSettings = NEDNSSettings(servers: ["198.18.0.2"])
        s.dnsSettings?.matchDomains = [""]
        s.mtu = 1500
        return s
    }
}
