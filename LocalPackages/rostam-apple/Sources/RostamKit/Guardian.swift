// Copyright 2026 Internet Mastering & Company, Inc.
// SPDX-License-Identifier: Apache-2.0

import Foundation
import RedSocketCore

/// One refused (or noticed) connection from the core's recent-blocks ring.
public struct GuardianEvent: Codable, Hashable, Identifiable, Sendable {
    public let host: String
    public let port: Int
    public let category: String
    public let secsAgo: Int
    /// The feed's own one-sentence explanation, carried by the exit's verdict.
    /// Empty for a local (on-device list) refusal; the sheet falls back to the
    /// category then.
    public let reason: String?
    /// The verdict's category bits (the pipeline's meta.json bit table, also
    /// published as OTA `protection.categories`). 0 for a local refusal.
    public let bits: Int
    /// true = refused (BLOCK tier); false = noticed only (NOTIFY tier).
    public let refused: Bool

    public var id: String { "\(host):\(port):\(secsAgo):\(refused)" }

    public init(host: String, port: Int, category: String, secsAgo: Int, reason: String? = nil,
                bits: Int = 0, refused: Bool = true) {
        self.host = host; self.port = port; self.category = category
        self.secsAgo = secsAgo; self.reason = reason; self.bits = bits; self.refused = refused
    }

    enum CodingKeys: String, CodingKey {
        case host, port, category, reason, bits, refused
        case secsAgo = "secs_ago"
    }

    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        host = try c.decode(String.self, forKey: .host)
        port = try c.decodeIfPresent(Int.self, forKey: .port) ?? 0
        category = try c.decodeIfPresent(String.self, forKey: .category) ?? ""
        secsAgo = try c.decodeIfPresent(Int.self, forKey: .secsAgo) ?? 0
        reason = try c.decodeIfPresent(String.self, forKey: .reason)
        bits = try c.decodeIfPresent(Int.self, forKey: .bits) ?? 0
        refused = try c.decodeIfPresent(Bool.self, forKey: .refused) ?? true
    }
}

/// Everything the Guardian sheet shows, in one reply.
public struct GuardianSnapshot: Codable, Hashable, Sendable {
    public var enabled: Bool
    /// Enabled AND a list is loaded, i.e. actually filtering.
    public var armed: Bool
    /// The core's per-process total. "Blocked today" is NOT this: it is counted
    /// from the app's own store, which survives reconnects.
    public var sessionTotal: Int
    public var byCategory: [String: Int]
    public var recent: [GuardianEvent]
    public var allow: [String]
    public var deny: [String]

    /// The exit sent `caps`: it acknowledged the capabilities on this session.
    public var capsAcknowledged: Bool?
    /// The most recent `protection` note on this session, if any. The exit sends
    /// enabled:false while it has no bundle loaded.
    public var protectionEnabled: Bool?
    public var protectionListVersion: String?
    public var protectionFeedDate: String?
    /// The most recent `entitlement` note on this session (`state`, `paid_until`).
    public var entitlementState: String?
    public var entitlementPaidUntil: String?

    public var isProtected: Bool { capsAcknowledged == true && protectionEnabled == true }

    public init(enabled: Bool, armed: Bool, sessionTotal: Int, byCategory: [String: Int],
                recent: [GuardianEvent], allow: [String], deny: [String]) {
        self.enabled = enabled; self.armed = armed; self.sessionTotal = sessionTotal
        self.byCategory = byCategory; self.recent = recent; self.allow = allow; self.deny = deny
    }

    public static let empty = GuardianSnapshot(enabled: false, armed: false, sessionTotal: 0,
                                               byCategory: [:], recent: [], allow: [], deny: [])
}

/// The provider-message vocabulary. Plain strings, like `get-stats` and
/// `refresh-entitlement`, so the extension's dispatcher stays one switch.
public enum GuardianMessage {
    public static let get = "guardian-get"
    /// `guardian-rule:<allow|deny|clear>:<host>`.
    public static func rule(_ verdict: String, host: String) -> String { "guardian-rule:\(verdict):\(host)" }
    /// `guardian-enabled:1` / `guardian-enabled:0`.
    public static func enabled(_ on: Bool) -> String { "guardian-enabled:\(on ? 1 : 0)" }
    /// `guardian-categories:<u16>`: categories the user switched off, sent upstream
    /// as `categories_off` with the current lists.
    public static func categoriesOff(_ mask: Int) -> String { "guardian-categories:\(mask & 0xFFFF)" }
    /// `guardian-rules:<json>`: replace both lists (a {rules} echo from another
    /// device). Applied only when it differs.
    public static func rules(_ json: String) -> String { "guardian-rules:\(json)" }
    /// `guardian-notes` -> the raw JSON array from rs_drain_notes (drains).
    public static let notes = "guardian-notes"

    /// App-group keys the extension persists across launches. The core forgets the
    /// user's rules when the process dies; these are what restore them.
    public static let rulesKey = "guardianUserRules"
    public static let enabledKey = "guardianEnabled"
    public static let categoriesOffKey = "guardianCategoriesOff"
    /// When this device's lists last changed (seconds): a local edit, online or
    /// offline, or an applied echo's `updated`.
    public static let rulesUpdatedKey = "guardianRulesUpdated"

    /// An echo's `updated` in seconds (milliseconds accepted, as the cursor's
    /// `since` uses them), never later than now; nil when absent.
    public static func updatedSeconds(_ v: Any?) -> Double? {
        guard let n = (v as? NSNumber)?.doubleValue, n > 0 else { return nil }
        return min(n > 1e12 ? n / 1000 : n, Date().timeIntervalSince1970)
    }

    /// Two rule documents hold the same lists, whatever the key order, spacing or
    /// extra fields (`updated`, `categories_off`).
    public static func sameLists(_ a: [String: Any], _ b: [String: Any]) -> Bool {
        Set(a["allow"] as? [String] ?? []) == Set(b["allow"] as? [String] ?? [])
            && Set(a["deny"] as? [String] ?? []) == Set(b["deny"] as? [String] ?? [])
    }
    public static let lastRefusalKey = "lastRefusal"
}

extension RedSocketClient {
    private func take(_ p: UnsafeMutablePointer<CChar>?) -> String {
        guard let p else { return "" }
        defer { rs_free_string(p) }
        return String(cString: p)
    }

    /// Master gate for on-device filtering. Off by default in the core.
    public func setBlockingEnabled(_ on: Bool) { rs_set_blocking_enabled(on ? 1 : 0) }

    /// Counts and the recent-blocks ring, as the core's JSON.
    public func blockStatsJSON() -> String { take(rs_get_block_stats()) }

    /// One user rule; `verdict` is `allow`, `deny` or `clear`. Effective on the
    /// next connection.
    public func setUserRule(host: String, verdict: String) -> String { take(rs_set_user_rule(host, verdict)) }

    /// Replace both lists: `{"allow":[…],"deny":[…]}`.
    public func setUserRules(json: String) -> String { take(rs_set_user_rules(json)) }

    /// The user's rules as authored. Persist this; restore with `setUserRules`.
    public func userRulesJSON() -> String { take(rs_get_user_rules()) }

    /// Brand id for the MUX2 `app` field (sent only when a capability is on) and
    /// the probe tag prefix. Before `start`.
    public func setApp(_ app: String) { rs_set_app(app) }

    /// Queued control-stream messages as a JSON array, oldest first; drains.
    public func drainNotesJSON() -> String {
        let s = take(rs_drain_notes())
        return s.isEmpty ? "[]" : s
    }

    /// Stats + rules folded into one snapshot.
    public func guardianSnapshot() -> GuardianSnapshot {
        let stats = (try? JSONSerialization.jsonObject(with: Data(blockStatsJSON().utf8))) as? [String: Any] ?? [:]
        let rules = (try? JSONSerialization.jsonObject(with: Data(userRulesJSON().utf8))) as? [String: Any] ?? [:]
        let recent: [GuardianEvent] = (stats["recent"] as? [[String: Any]] ?? []).compactMap { e in
            guard let host = e["host"] as? String else { return nil }
            return GuardianEvent(host: host,
                                 port: e["port"] as? Int ?? 0,
                                 category: e["category"] as? String ?? "",
                                 secsAgo: e["secs_ago"] as? Int ?? 0,
                                 reason: (e["reason"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                                 bits: e["bits"] as? Int ?? 0,
                                 refused: e["refused"] as? Bool ?? true)
        }
        let byCat = (stats["by_category"] as? [String: Any] ?? [:]).compactMapValues { ($0 as? NSNumber)?.intValue }
        return GuardianSnapshot(enabled: stats["enabled"] as? Bool ?? false,
                                    armed: stats["armed"] as? Bool ?? false,
                                    sessionTotal: (stats["blocked_total"] as? NSNumber)?.intValue ?? 0,
                                    byCategory: byCat,
                                    recent: recent,
                                    allow: rules["allow"] as? [String] ?? [],
                                    deny: rules["deny"] as? [String] ?? [])
    }

    /// The current lists with `categories_off` added, handed back to the core.
    public func setCategoriesOff(_ mask: Int) -> String {
        var o = (try? JSONSerialization.jsonObject(with: Data(userRulesJSON().utf8))) as? [String: Any] ?? [:]
        o["categories_off"] = mask & 0xFFFF
        guard let d = try? JSONSerialization.data(withJSONObject: o),
              let json = String(data: d, encoding: .utf8) else { return "err:encode" }
        return setUserRules(json: json)
    }
}
