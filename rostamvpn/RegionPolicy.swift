// Copyright 2026 Internet Mastering & Company, Inc.
// SPDX-License-Identifier: Apache-2.0

import Foundation
import UIKit

/// Where the user is, for the purposes of policy.
enum RegionPolicy {
    /// ISO country the user appears to be in, uppercased. "" when unknown. Honours
    /// the Dev Tools region override — see `ConfigPolicy`.
    static var country: String { ConfigPolicy.country }

    /// Freedom-region country codes, from the config.
    static var freedomRegions: [String] {
        ConfigPolicy.freedomRegionCodes.sorted()
    }

    /// Whether this device gets the product free by policy.
    static var isFreedomRegion: Bool { ConfigPolicy.isFreedomRegion }

    /// Logged because this decision SILENTLY removes the Premium entry, the paywall
    /// and all purchase UI. When it is wrong the symptom is "the upgrade option is
    /// missing" with nothing to point at.
    static func describe() -> String {
        "keyboard=\(keyboardRegion ?? "nil") " + ConfigPolicy.describe()
    }

    /// Installed keyboards -> the language the user reads.
    static var keyboardRegion: String? {
        let langs = UITextInputMode.activeInputModes
            .compactMap { $0.primaryLanguage?.lowercased() }
        if langs.contains(where: { $0.hasPrefix("fa") || $0.hasPrefix("ckb") }) { return "IR" }
        if langs.contains(where: { $0.hasPrefix("ru") }) { return "RU" }
        return nil
    }

}
