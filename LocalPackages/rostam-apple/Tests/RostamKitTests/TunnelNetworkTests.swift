// Copyright 2026 Internet Mastering & Company, Inc.
// SPDX-License-Identifier: Apache-2.0

import NetworkExtension
import RostamKit
import XCTest

final class TunnelNetworkTests: XCTestCase {
    func testBothFamiliesRouteIntoTheTunnelAndItsResolverAnswersEverything() {
        let s = TunnelNetwork.settings()
        let v4 = s.ipv4Settings?.includedRoutes?.first
        XCTAssertEqual(v4?.destinationAddress, "0.0.0.0")
        XCTAssertEqual(v4?.destinationSubnetMask, "0.0.0.0")
        let v6 = s.ipv6Settings?.includedRoutes?.first
        XCTAssertEqual(v6?.destinationAddress, "::")
        XCTAssertEqual(v6?.destinationNetworkPrefixLength.intValue, 0)
        XCTAssertEqual(s.dnsSettings?.matchDomains, [""])
    }
}
