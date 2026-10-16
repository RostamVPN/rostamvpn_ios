// Copyright 2026 Internet Mastering & Company, Inc.
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

enum BrandTheme {
    private static func hex(_ v: UInt32) -> Color {
        Color(
            red:   Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8) & 0xFF) / 255,
            blue:  Double(v & 0xFF) / 255
        )
    }

    static let primary       = hex(0x3D6B6F)
    static let primaryDeep   = hex(0x0E1E25)
    static let secondary     = hex(0x4A9BA3)
    static let accent        = hex(0xEFA638)
    static let accentOnLight = hex(0xDB4645)
    static let success       = hex(0x45988A)
    static let danger        = hex(0xD32F2F)
    static let warning       = hex(0xD7A23E)
    static let background    = hex(0xF5F5F5)
    static let ink           = hex(0x2D3436)

    /// The connect ring, when a brand wants it off-primary: a mark whose colour has
    /// nothing to do with `primary` should not sit inside a ring of it.
    static let ring          = hex(0x3D6B6F)

    /// Opacity of the ring's socket track when DISCONNECTED. 0.15 is tuned for teal
    /// on an off-white ground; gold on cream disappears entirely at that.
    static let ringRestAlpha = 0.15

    /// 10% of the brand's own accent mixed into a near-black -- the hue is what
    /// stops a dark app reading as "the OS dark theme" instead of as itself.
    static let groundDark    = hex(0xFF261F18)
    /// One step lighter: the card fill on that ground. 7% white.
    static let cardDark      = hex(0xFF352F28)
    /// 6% of the brand's own accent mixed into WHITE -- the inverse of
    /// `groundDark`, from the same `gen-branding.py` so the platforms cannot drift.
    static let groundLight   = hex(0xFFFEFAF3)

    /// `branding.themeDark`, by design token name. Empty for brands without one;
    /// IPTheme uses its transcribed value for any missing key.
    static let themeDark: [String: String] = [:]
    /// `branding.themeLight`, same contract.
    static let themeLight: [String: String] = [:]
}
