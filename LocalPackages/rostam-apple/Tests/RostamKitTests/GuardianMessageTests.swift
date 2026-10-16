// Copyright 2026 Internet Mastering & Company, Inc.
// SPDX-License-Identifier: Apache-2.0

import RostamKit
import XCTest

final class GuardianMessageTests: XCTestCase {
    func testAnEchoCannotDateItsListsIntoTheFuture() {
        let future = Date().timeIntervalSince1970 + 365 * 24 * 60 * 60
        let clamped = GuardianMessage.updatedSeconds(NSNumber(value: future))
        XCTAssertNotNil(clamped)
        XCTAssertLessThanOrEqual(clamped ?? .infinity, Date().timeIntervalSince1970)
        XCTAssertEqual(GuardianMessage.updatedSeconds(NSNumber(value: 1_700_000_000_000.0)), 1_700_000_000)
        XCTAssertNil(GuardianMessage.updatedSeconds(nil))
    }
}
