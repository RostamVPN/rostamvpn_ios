// Copyright 2026 Internet Mastering & Company, Inc.
// SPDX-License-Identifier: Apache-2.0

import RostamKit
import XCTest

final class ControlPlaneTests: XCTestCase {
    func testNothingLeavesBeforeTheTunnelStateIsKnown() {
        XCTAssertTrue(ControlPlane.mustDefer(profileExists: nil, tunnelConnected: false, paidOnly: false))
        XCTAssertTrue(ControlPlane.mustDefer(profileExists: nil, tunnelConnected: false, paidOnly: true))
        XCTAssertFalse(ControlPlane.mustDefer(profileExists: false, tunnelConnected: false, paidOnly: false))
        XCTAssertTrue(ControlPlane.mustDefer(profileExists: true, tunnelConnected: false, paidOnly: false))
        XCTAssertFalse(ControlPlane.mustDefer(profileExists: true, tunnelConnected: false, paidOnly: true))
        XCTAssertFalse(ControlPlane.mustDefer(profileExists: true, tunnelConnected: true, paidOnly: false))
    }
}
