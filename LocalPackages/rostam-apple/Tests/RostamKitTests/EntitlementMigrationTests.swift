// Copyright 2026 Internet Mastering & Company, Inc.
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import RostamKit

final class EntitlementMigrationTests: XCTestCase {
    private var s: UserDefaults!
    private var g: UserDefaults!
    private var names: [String] = []

    override func setUp() {
        let a = "test.std.\(UUID().uuidString)", b = "test.grp.\(UUID().uuidString)"
        names = [a, b]
        s = UserDefaults(suiteName: a)
        g = UserDefaults(suiteName: b)
    }

    override func tearDown() {
        names.forEach { UserDefaults().removePersistentDomain(forName: $0) }
    }

    func testGroupEmptyCopiesStandardPaid() {
        s.set(true, forKey: "isPaid"); s.set(1_800_000_000.0, forKey: "paidUntil")
        EntitlementMigration.migrate(standard: s, group: g)
        XCTAssertTrue(g.bool(forKey: "isPaid"))
        XCTAssertEqual(g.double(forKey: "paidUntil"), 1_800_000_000)
    }

    func testGroupEmptyCopiesStandardUnpaid() {
        s.set(false, forKey: "isPaid")
        EntitlementMigration.migrate(standard: s, group: g)
        XCTAssertNotNil(g.object(forKey: "isPaid"))
        XCTAssertFalse(g.bool(forKey: "isPaid"))
    }

    func testStandardPaidBeatsStaleGroupFalse() {
        s.set(true, forKey: "isPaid"); g.set(false, forKey: "isPaid")
        EntitlementMigration.migrate(standard: s, group: g)
        XCTAssertTrue(g.bool(forKey: "isPaid"), "a paying user must never read false after the upgrade")
    }

    func testGroupPaidKeptOverStandardFalse() {
        s.set(false, forKey: "isPaid"); g.set(true, forKey: "isPaid")
        EntitlementMigration.migrate(standard: s, group: g)
        XCTAssertTrue(g.bool(forKey: "isPaid"))
    }

    func testLaterPaidUntilWins() {
        s.set(1_700_000_000.0, forKey: "paidUntil"); g.set(1_800_000_000.0, forKey: "paidUntil")
        EntitlementMigration.migrate(standard: s, group: g)
        XCTAssertEqual(g.double(forKey: "paidUntil"), 1_800_000_000)
    }

    func testRunsOnce() {
        s.set(true, forKey: "isPaid")
        EntitlementMigration.migrate(standard: s, group: g)
        g.set(false, forKey: "isPaid")
        EntitlementMigration.migrate(standard: s, group: g)
        XCTAssertFalse(g.bool(forKey: "isPaid"), "must not re-run and undo a later revoke")
    }

    func testNothingInStandardLeavesGroupAlone() {
        g.set(false, forKey: "isPaid")
        EntitlementMigration.migrate(standard: s, group: g)
        XCTAssertFalse(g.bool(forKey: "isPaid"))
        XCTAssertTrue(g.bool(forKey: EntitlementMigration.doneKey))
    }
}
