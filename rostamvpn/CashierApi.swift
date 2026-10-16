// Copyright 2026 Internet Mastering & Company, Inc.
// SPDX-License-Identifier: Apache-2.0

import Foundation
import RostamKit

/// The cashier: entitlement, usage, and pay rails.
enum CashierApi {
    struct Registration {
        let tier: String
        let product: String?
        /// Server's paid-through date, ISO-8601. NOT a promise of renewal.
        let paidUntil: String?
        /// Answered over the DIRECT path (paid-only build, tunnel down): an unpinned
        /// connection, so the answer is UPGRADE-ONLY. See `directNow`.
        var direct = false
        var isPaid: Bool { tier.lowercased() == "paid" }
    }

    private static var base: String { BrandRuntime.cashierBase }

    private static func request(_ path: String, body: [String: Any]) -> URLRequest {
        var r = URLRequest(url: URL(string: base + path)!)
        r.httpMethod = "POST"
        r.timeoutInterval = 15
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue(BrandRuntime.cashierKey, forHTTPHeaderField: "X-App-Key")
        r.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return r
    }

    /// Set from `loadStatus()` and `handleVPNStatusChange`, which are the two
    /// places that already know. Mirrors Android's `CashierApi.hasTunnelProfile` /
    /// `tunnelUp` pair, and exists for the same reason. Nil until `loadStatus()`
    /// has read the saved profiles.
    static var tunnelProfileExists: Bool?
    static var tunnelConnected = false

    /// See `ControlPlane.mustDefer`.
    private static var deferUntilTunnel: Bool {
        ControlPlane.mustDefer(profileExists: tunnelProfileExists, tunnelConnected: tunnelConnected,
                               paidOnly: BrandRuntime.paidOnly)
    }

    /// A call made now goes DIRECT: a paid-only build with the tunnel down.
    static var directNow: Bool {
        BrandRuntime.paidOnly && tunnelProfileExists == true && !tunnelConnected
    }

    private static func post(_ path: String, _ body: [String: Any],
                             _ done: @escaping ([String: Any]?) -> Void) {
        if deferUntilTunnel { done(nil); return }
        URLSession.shared.dataTask(with: request(path, body: body)) { data, resp, _ in
            guard
                let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                let data,
                let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                done(nil)
                return
            }
            done(obj)
        }.resume()
    }

    /// Register this device and read back SERVER-TRUTH entitlement.
    static func registerCid(_ done: @escaping (Registration?) -> Void) {
        let direct = directNow
        post("/api/v1/cid/register", [
            "cid": CashierIdentity.current,
            "brand": BrandRuntime.cashierKey,
            "tz": TimeZone.current.identifier,
        ]) { obj in
            guard let obj else { done(nil); return }
            done(Registration(
                tier: obj["tier"] as? String ?? "free",
                product: obj["product"] as? String,
                paidUntil: obj["paid_until"] as? String,
                direct: direct
            ))
        }
    }

    /// Report cumulative usage. The APP is the meter; last write wins.
    static func reportUsage(usedMB: Int64, _ done: ((UsageStatus?) -> Void)? = nil) {
        let direct = directNow
        post("/api/v1/usage", ["cid": CashierIdentity.current, "used_mb": usedMB]) { obj in
            var u = parseUsage(obj)
            u?.direct = direct
            done?(u)
        }
    }

    /// ONE parse for the POST and the GET, because they are the same server-side
    /// object (`_status_counted`) and two copies would drift.
    private static func parseUsage(_ o: [String: Any]?) -> UsageStatus? {
        guard let o else { return nil }
        return UsageStatus(
            usedMB: (o["used_mb"] as? NSNumber)?.int64Value ?? 0,
            freeQuotaMB: (o["free_quota_mb"] as? NSNumber)?.int64Value ?? 0,
            remainingMB: (o["remaining_mb"] as? NSNumber)?.int64Value ?? 0,
            overQuota: o["over_quota"] as? Bool ?? false,
            unlimited: o["unlimited"] as? Bool ?? false,
            paid: o["paid"] as? Bool ?? false,
            regionSelect: o["region_select"] as? String ?? "on")
    }

    /// Verify an App Store purchase and grant the entitlement.
    static func verifyIAP(signedTransaction: String, productId: String,
                          _ done: @escaping (Bool) -> Void) {
        post("/api/v1/iap/verify", [
            "platform": "apple",
            "cid": CashierIdentity.current,
            "product_id": productId,

            "signed_transaction": signedTransaction,
            "bundle_id": BrandRuntime.appBundleID,
            "token": "",
            "brand": BrandRuntime.cashierKey,
        ]) { obj in
            done((obj?["ok"] as? Bool ?? false) && (obj?["entitled"] as? Bool ?? false))
        }
    }

    /// Free-data status for this cid. Mirrors Android's CashierApi.usage().
    struct UsageStatus {
        let usedMB: Int64
        let freeQuotaMB: Int64
        let remainingMB: Int64
        let overQuota: Bool
        let unlimited: Bool
        let paid: Bool
        /// Fetched over the direct path: upgrade-only (see directNow).
        var direct = false

        /// The cashier's `region_select` verdict: off / until_quota / pro_only / on.
        let regionSelect: String

        /// Byte-for-byte Android's `CashierApi.Usage.canSelectRegion`. The two
        /// platforms must agree on this or one of them sells a region picker the other
        /// hides.
        var canSelectRegion: Bool {
            paid || regionSelect == "on" || (regionSelect == "until_quota" && !overQuota)
        }
    }

    static func usage(_ done: @escaping (UsageStatus?) -> Void) {
        let cid = CashierIdentity.current
        guard !deferUntilTunnel, !cid.isEmpty,
              let url = URL(string: base + "/api/v1/usage?cid=" + cid)
        else { done(nil); return }
        var r = URLRequest(url: url)
        r.timeoutInterval = 15
        r.setValue(BrandRuntime.cashierKey, forHTTPHeaderField: "X-App-Key")
        let direct = directNow
        URLSession.shared.dataTask(with: r) { data, _, _ in
            var u = parseUsage(try? JSONSerialization.jsonObject(with: data ?? Data()) as? [String: Any])
            u?.direct = direct
            done(u)
        }.resume()
    }
}
