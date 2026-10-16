// Copyright 2026 Internet Mastering & Company, Inc.
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Moving isPaid / paidUntil from standard defaults (the app's copy until
/// 86310b1) to the App Group (the single copy since). Run ONCE per install,
/// before anything reads the group copy, for EVERY brand.
public enum EntitlementMigration {
    public static let doneKey = "entitlementInGroup"

    public static func migrate(standard s: UserDefaults, group g: UserDefaults) {
        guard g !== s, !g.bool(forKey: doneKey) else { return }
        if let sv = s.object(forKey: "isPaid") as? Bool {
            if g.object(forKey: "isPaid") == nil || (sv && !g.bool(forKey: "isPaid")) {
                g.set(sv, forKey: "isPaid")
            }
        }
        let su = s.double(forKey: "paidUntil")
        if su > g.double(forKey: "paidUntil") { g.set(su, forKey: "paidUntil") }
        g.set(true, forKey: doneKey)
    }
}
