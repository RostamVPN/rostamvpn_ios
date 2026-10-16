// Copyright 2026 Internet Mastering & Company, Inc.
// SPDX-License-Identifier: Apache-2.0

import Foundation
import StoreKit
import NetworkExtension
import RostamKit
import os.log

/// Purchase state, private in the unified log.
private func payLog(_ msg: String) {
    os_log("%{private}@", msg)
}

extension Notification.Name {
    /// Premium turned on (or off). The screen must react without a relaunch.
    static let entitlementDidChange = Notification.Name("rostam.entitlementDidChange")
}

/// Subscriptions, via StoreKit 2.
@MainActor
final class Store: ObservableObject {
    static let shared = Store()

    @Published private(set) var products: [Product] = []
    nonisolated static let entitlementDefaults: UserDefaults = {
        let g = BrandRuntime.defaults ?? .standard
        EntitlementMigration.migrate(standard: .standard, group: g)
        return g
    }()

    @Published private(set) var isPaid = Store.entitlementDefaults.bool(forKey: "isPaid")

    /// Re-read the shared copy.
    func reloadFromGroup() {
        let g = Self.entitlementDefaults
        let paid = g.bool(forKey: "isPaid")
        let t = g.double(forKey: "paidUntil")
        paidUntil = t > 0 ? Date(timeIntervalSince1970: t) : nil
        if paid != isPaid {
            isPaid = paid
            NotificationCenter.default.post(name: .entitlementDidChange, object: nil)
        }
    }

    /// The cashier's `paid_until`, kept from the last answer it gave.
    private(set) var paidUntil: Date? = {
        let t = Store.entitlementDefaults.double(forKey: "paidUntil")
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }()

    private func notePaidUntil(_ reg: CashierApi.Registration) {
        setPaidUntil(reg.isPaid ? Self.parseISO(reg.paidUntil) : nil)
    }

    /// Written to the app group too: the extension refuses a paid-only start on the
    /// same rule (`lapsedBeyondGrace`) when the app is not running.
    private func setPaidUntil(_ d: Date?) {
        paidUntil = d
        Self.entitlementDefaults.set(d?.timeIntervalSince1970 ?? 0, forKey: "paidUntil")
    }

    @Published private(set) var storeKitHeld = UserDefaults.standard.bool(forKey: "storeKitHeld")

    private func setStoreKitHeld(_ held: Bool) {
        storeKitHeld = held
        UserDefaults.standard.set(held, forKey: "storeKitHeld")
        BrandRuntime.defaults?.set(held, forKey: "storeKitHeld")

        BrandRuntime.defaults?.set(Date().timeIntervalSince1970, forKey: "storeKitHeldAt")
    }

    static let lapseGrace: TimeInterval = 3 * 24 * 60 * 60

    /// The cashier's /usage just said paid but the local grant has not caught up
    /// (a grant made on the server, a purchase on another device).
    func adoptServerPaid() {
        BrandRuntime.defaults?.removeObject(forKey: GuardianMessage.lastRefusalKey)
        if let u = paidUntil, u.addingTimeInterval(Self.lapseGrace) < Date() { setPaidUntil(nil) }
        guard !isPaid else {
            Self.entitlementDefaults.set(true, forKey: "isPaid")
            return
        }
        payLog("[PAY] server says paid; adopting the grant before connect")
        isPaid = true
        Self.applyEntitlement(true)
    }
    var lapsedBeyondGrace: Bool {
        answeredThisProcess && dateBeyondGrace
    }

    /// The persisted paid_until is past the grace, StoreKit holds nothing, and
    /// nobody has answered yet in this process: ask the cashier (directly, on a
    /// paid-only build) before deciding.
    var staleUnanswered: Bool {
        !answeredThisProcess && dateBeyondGrace
    }

    private var dateBeyondGrace: Bool {
        guard let until = paidUntil, !storeKitHeld else { return false }
        return until.addingTimeInterval(Self.lapseGrace) < Date()
    }

    /// The cashier (register) or an exit entitlement note has answered since
    /// launch.
    private(set) var answeredThisProcess = false
    /// The last reconcile could not reach the cashier. The tabs paywall shows a
    /// retry for it.
    @Published private(set) var cashierUnreachable = false

    /// The exit's `entitlement` note over the control stream: the server's own
    /// verdict, delivered while connected. Active = `state == "paid"` (the core's
    /// contract); `paid_until` is kept for display and the timer.
    func applyServerEntitlement(state: String, paidUntilISO: String?) {
        guard !state.isEmpty else { return }
        let until = Self.parseISO(paidUntilISO)
        let active = state.lowercased() == "paid"
        answeredThisProcess = true
        payLog("[PAY] entitlement note: state=\(state) until=\(paidUntilISO ?? "-") active=\(active)")

        if !active && storeKitHeld {
            payLog("[PAY] entitlement note says unpaid but StoreKit holds a current subscription — not revoking")
            return
        }
        setPaidUntil(active ? until : nil)
        guard active != isPaid else { return }
        isPaid = active
        Self.applyEntitlement(active)
    }

    static func parseISO(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
    @Published private(set) var loading = false
    /// Non-nil when the paywall cannot be shown at all, with the reason.
    @Published private(set) var unavailable: String?

    @Published var justPurchased = false

    private var updatesTask: Task<Void, Never>?

    private init() {
        updatesTask = Task.detached { [weak self] in
            for await update in Transaction.updates {
                guard case .verified(let txn) = update else { continue }

                await self?.refreshStoreKitHeld()
                await self?.redeem(productID: txn.productID, finishing: txn,
                                   signed: update.jwsRepresentation)
            }
        }
    }

    deinit { updatesTask?.cancel() }

    func load() async {
        let ids = BrandRuntime.storeKitProductIDs
        guard !ids.isEmpty else {
            unavailable = "Plans aren't available right now"
            return
        }
        loading = true
        defer { loading = false }
        do {
            products = try await Product.products(for: ids).sorted { $0.price < $1.price }
            unavailable = products.isEmpty ? "Plans aren't available right now" : nil
        } catch {
            unavailable = "Couldn't reach the App Store"
            payLog("[store] product load failed: \(error)")
        }
    }

    enum PurchaseOutcome { case entitled, cancelled, pending, failed(String) }

    /// Entitlement must land in THREE places or the app lies to the user.
    static func applyEntitlement(_ paid: Bool) {
        entitlementDefaults.set(paid, forKey: "isPaid")
        NotificationCenter.default.post(name: .entitlementDidChange, object: nil)

        NETunnelProviderManager.loadAllFromPreferences { managers, _ in

            guard let s = managers?.first(where: TunnelProfile.isOurs)?
                    .connection as? NETunnelProviderSession,
                  s.status == .connected else { return }
            try? s.sendProviderMessage(Data("refresh-entitlement".utf8))
        }
    }

    func purchase(_ product: Product) async -> PurchaseOutcome {
        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let txn) = verification else {
                    return .failed("This purchase could not be verified")
                }

                return await redeem(productID: txn.productID, finishing: txn,
                                    signed: verification.jwsRepresentation,
                                    userInitiated: true)
                    ? .entitled
                    : .failed("Purchase couldn't be confirmed with our server")

            case .userCancelled:
                return .cancelled

            case .pending:

                return .pending

            @unknown default:
                return .failed("Unexpected App Store response")
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Hand the receipt to the cashier and, only if it accepts, finish the
    /// transaction.
    @discardableResult
    private func redeem(productID: String, finishing txn: Transaction,
                        signed: String, userInitiated: Bool = false) async -> Bool {
        let ok = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            CashierApi.verifyIAP(signedTransaction: signed, productId: productID) { c.resume(returning: $0) }
        }
        if ok {
            await txn.finish()

            if let exp = txn.expirationDate { setPaidUntil(exp) }
            isPaid = true
            Self.applyEntitlement(true)

            if userInitiated { justPurchased = true }
            payLog("[store] verified and entitled: \(productID)"
                   + (userInitiated ? "" : " (replayed; no connect)"))
        } else {
            payLog("[store] cashier did not confirm \(productID); transaction left unfinished for retry")
        }
        return ok
    }

    /// Hand Apple's current entitlements to the cashier, one by one, and stop at
    /// the first the cashier accepts.
    private func redeemCurrentEntitlements() async -> (held: Bool, confirmed: Bool) {
        var held = false
        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let txn) = entitlement, Self.isCurrent(txn) else { continue }
            held = true
            if await redeem(productID: txn.productID, finishing: txn,
                            signed: entitlement.jwsRepresentation) {
                setStoreKitHeld(true)
                return (true, true)
            }
        }
        setStoreKitHeld(held)
        return (held, false)
    }

    /// Scan only: no redeem, no network. For the updates listener.
    func refreshStoreKitHeld() async {
        var held = false
        for await e in Transaction.currentEntitlements {
            if case .verified(let txn) = e, Self.isCurrent(txn) { held = true; break }
        }
        setStoreKitHeld(held)
    }

    private static func isCurrent(_ txn: Transaction) -> Bool {
        txn.revocationDate == nil && (txn.expirationDate.map { $0 > Date() } ?? true)
    }

    /// Launch-time entitlement reconcile. Call this instead of a bare `registerCid`
    /// + `applyEntitlement`.
    func reconcileEntitlementAtLaunch() async {
        async let storeKit = redeemCurrentEntitlements()
        async let registration: CashierApi.Registration? =
            withCheckedContinuation { (c: CheckedContinuation<CashierApi.Registration?, Never>) in
                CashierApi.registerCid { c.resume(returning: $0) }
            }

        let apple = await storeKit
        let reg = await registration

        cashierUnreachable = (reg == nil)

        let usableReg: CashierApi.Registration? = (reg?.direct == true && reg?.isPaid != true) ? nil : reg
        if let reg, reg.direct, !reg.isPaid {
            payLog("[PAY] direct cashier answered \(reg.tier) — upgrade-only path, not applied")
        }
        if let reg = usableReg {
            answeredThisProcess = true
            notePaidUntil(reg)
            if reg.direct { BrandRuntime.defaults?.removeObject(forKey: GuardianMessage.lastRefusalKey) }
            payLog("[PAY] tier=\(reg.tier) product=\(reg.product ?? "-") until=\(reg.paidUntil ?? "-")")
        } else {
            payLog("[PAY] cashier unreachable")
        }
        payLog("[PAY] apple held=\(apple.held) confirmed=\(apple.confirmed)")

        if apple.confirmed || reg?.isPaid == true {
            isPaid = true
            Self.applyEntitlement(true)
            payLog("[PAY] entitled")
            return
        }

        guard let reg = usableReg, !reg.isPaid, !apple.held else {
            if apple.held { payLog("[PAY] apple holds an unconfirmed entitlement — not revoking") }
            return
        }
        isPaid = false
        Self.applyEntitlement(false)
    }

    /// Restore: re-verify whatever Apple still considers current.
    func restore() async -> Bool {
        if await redeemCurrentEntitlements().confirmed { return true }

        return await withCheckedContinuation { c in
            CashierApi.registerCid { reg in

                guard let reg else { c.resume(returning: false); return }

                if reg.direct && !reg.isPaid { c.resume(returning: false); return }
                Task { @MainActor in
                    self.answeredThisProcess = true
                    self.cashierUnreachable = false
                    self.notePaidUntil(reg)
                    self.isPaid = reg.isPaid
                    Self.applyEntitlement(reg.isPaid)
                    if reg.direct { BrandRuntime.defaults?.removeObject(forKey: GuardianMessage.lastRefusalKey) }
                }
                c.resume(returning: reg.isPaid)
            }
        }
    }
}

extension Product {
    /// Human label derived from the SUBSCRIPTION PERIOD, never the product id.
    var periodLabel: String {
        guard let p = subscription?.subscriptionPeriod else { return displayName }
        let n = p.value
        switch p.unit {
        case .day:   return n == 7 ? "Weekly" : "\(n) days"
        case .week:  return n == 1 ? "Weekly" : "\(n) weeks"
        case .month: return n == 1 ? "Monthly" : "\(n) months"
        case .year:  return n == 1 ? "Yearly" : "\(n) years"
        @unknown default: return displayName
        }
    }
}
