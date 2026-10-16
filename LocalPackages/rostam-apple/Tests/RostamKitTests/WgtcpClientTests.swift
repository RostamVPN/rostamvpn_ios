// Copyright 2026 Internet Mastering & Company, Inc.
// SPDX-License-Identifier: Apache-2.0

@testable import RostamKit
import XCTest

final class WgtcpClientTests: XCTestCase {
    func testTheReadinessWaitEndsAtTheFirstConnectedReadingAndIsBounded() {
        var asks = 0
        let connectedOnThird = WgtcpClient.poll(retries: 75, every: 0) { asks += 1; return asks == 3 }
        XCTAssertTrue(connectedOnThird)
        XCTAssertEqual(asks, 3)

        asks = 0
        let neverConnected = WgtcpClient.poll(retries: 75, every: 0) { asks += 1; return false }
        XCTAssertFalse(neverConnected)
        XCTAssertEqual(asks, 76)

        XCTAssertFalse(WgtcpClient.shared.isConnected)
    }
}
