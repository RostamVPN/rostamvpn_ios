// Copyright 2026 Internet Mastering & Company, Inc.
// SPDX-License-Identifier: Apache-2.0

import Foundation
import RostamKit

/// The app is the meter.
@MainActor
final class UsageReporter {
    static let shared = UsageReporter()
    private init() {}

    private let suite = BrandRuntime.appGroup
    private var timer: Timer?
    /// Reported total, so a report that fails is retried rather than lost.
    private var lastReportedMB: Int64 = 0

    /// Lifetime bytes, accumulated from deltas by the traffic monitor.
    private var lifetimeBytes: Int64 {
        Int64(UserDefaults(suiteName: suite)?.string(forKey: "lifetimeBytes") ?? "0") ?? 0
    }

    private var shouldMeter: Bool {
        !RegionPolicy.isFreedomRegion
            && !Store.entitlementDefaults.bool(forKey: "isPaid")
    }

    /// Begin reporting. Safe to call repeatedly.
    func start() {
        refreshVerdict()
        guard shouldMeter, timer == nil else { return }

        let t = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.report() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        report()
    }

    func stop() {
        timer?.invalidate()
        timer = nil

        report()
    }

    /// Report the cumulative total and read back the server's verdict.
    func report() {
        guard shouldMeter else {
            refreshVerdict()
            return
        }
        let mb = lifetimeBytes / 1_000_000

        guard mb > lastReportedMB || lastReportedMB == 0 else {
            refreshVerdict()
            return
        }

        CashierApi.reportUsage(usedMB: mb) { [weak self] status in
            Task { @MainActor in
                guard let status else { return }
                self?.lastReportedMB = mb
                Self.applyVerdict(status)
            }
        }
    }

    /// Pull `over_quota` back. The SERVER decides, never this device: a client that
    /// decided its own quota state would be trivially reset by a reinstall.
    private func refreshVerdict() {
        CashierApi.usage { u in
            guard let u else { return }
            Self.applyVerdict(u)
        }
    }

    /// Apply a verdict however it arrived -- from the POST that reported usage, or
    /// from a standalone GET. Split out so the reporting path can use the response
    /// it already has instead of paying a second round trip for the identical
    /// object.
    fileprivate static func applyVerdict(_ u: CashierApi.UsageStatus) {
        if u.direct { return }
        do {
            let d = BrandRuntime.defaults
            d?.set(u.overQuota, forKey: "overQuota")

            d?.set(ConfigPolicy.freeKbps, forKey: "freeKbps")

            Store.applyEntitlement(u.paid)
            RegionGate.remember(u)
            NotificationCenter.default.post(name: .usageDidChange, object: nil)
        }
    }
}

extension Notification.Name {
    static let usageDidChange = Notification.Name("rostam.usageDidChange")
}

/// May this user choose a region?
enum RegionGate {
    private static let key = "mayPickRegion"

    /// Store the last server answer, so a view with no `usage` in scope still gets
    /// the server's verdict rather than a hardcoded guess.
    static func remember(_ u: CashierApi.UsageStatus) {
        UserDefaults.standard.set(u.canSelectRegion && !u.overQuota, forKey: key)
    }

    /// Pass the live `usage` where there is one; pass nil to read the last
    /// remembered answer.
    static func allows(_ u: CashierApi.UsageStatus?) -> Bool {
        if Store.entitlementDefaults.bool(forKey: "isPaid") { return true }
        if RegionPolicy.isFreedomRegion { return true }
        guard let u else { return UserDefaults.standard.bool(forKey: key) }
        return u.canSelectRegion && !u.overQuota
    }
}
