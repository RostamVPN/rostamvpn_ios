// Copyright 2026 Internet Mastering & Company, Inc.
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The ONE type that answers "which brand is this build?" at runtime.
public enum BrandRuntime {
    private static func string(_ key: String) -> String? {
        guard let v = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !v.isEmpty else { return nil }
        return v
    }

    /// Required key.
    private static func req(_ key: String) -> String {
        guard let v = string(key) else {
            preconditionFailure("brand key \(key) missing from Info.plist; Config/Brand.xcconfig was not applied")
        }
        return v
    }

    /// Info.plist values are substituted from build settings, and a build setting
    /// cannot be an array. List-valued brand data therefore travels as a comma-
    /// separated string and is split here.
    private static func csv(_ key: String) -> [String] {
        (string(key) ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static func flag(_ key: String) -> Bool {
        let v = (string(key) ?? "").uppercased()
        return v == "YES" || v == "TRUE" || v == "1"
    }

    /// Stable brand key. The cashier's `X-App-Key`, and the value it scopes every
    /// entitlement and quota decision by.
    public static let id = req("BrandID")

    /// The name a user sees. Deliberately a SEPARATE key from
    /// `CFBundleDisplayName`.
    public static let displayName = req("BrandDisplayName")

    /// The App Group both processes share. It carries the cid, the sealed config,
    /// entitledRegion, isPaid, freeKbps and selectedProtocol.
    public static let appGroup = req("BrandAppGroup")

    /// The Network Extension's bundle id. The app matches saved `NEVPNManager`
    /// profiles on it, and the extension target's `PRODUCT_BUNDLE_IDENTIFIER` is
    /// the SAME variable in the same generated file, so the two cannot drift.
    public static let tunnelBundleID = req("BrandTunnelBundleID")

    public static let legacyTunnelIDs = csv("BrandLegacyTunnelIDs")

    /// The App Group's `UserDefaults`. Nil only if the group is not entitled, which
    /// is a signing fault, never a runtime condition to design around.
    public static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    /// Read from the BUILD, never from the manifest, so it can never drift from
    /// what the binary actually is. Same rule as Android's `CashierApi.PKG =
    /// BuildConfig.APPLICATION_ID`.
    public static var appBundleID: String { Bundle.main.bundleIdentifier ?? "" }

    public static var cashierBase: String { string("BrandCashierBase") ?? "" }
    public static var cashierKey: String { string("BrandCashierKey") ?? id }
    public static var wgtcpAPIKey: String { string("BrandWGTCPAPIKey") ?? "" }
    public static var storeKitProductIDs: [String] { csv("BrandStoreKitIDs") }
    public static var appStoreID: String { string("BrandAppStoreID") ?? "" }

    public static var hasMascot: Bool { flag("BrandHasMascot") }

    /// Does the connect disc fill with the brand colour when connected?
    public static var discFillsOnConnect: Bool {
        guard let v = string("BrandDiscFillsOnConnect"), !v.isEmpty else { return true }
        return ["YES", "TRUE", "1"].contains(v.uppercased())
    }
    /// The splash light-field disc, as a fraction of the launch art's box WIDTH.
    public static var launchDiscScale: CGFloat {
        guard let v = string("BrandLaunchDiscScale"), let f = Double(v), f > 0 else { return 0.78 }
        return CGFloat(f)
    }

    public static var launchDiscOffsetY: CGFloat {
        guard let v = string("BrandLaunchDiscOffsetY"), let f = Double(v) else { return 0 }
        return CGFloat(f)
    }

    /// The line under the connect dial, e.g. "Your Digital Guardian".
    public static var tagline: String { string("BrandTagline") ?? "" }

    /// The provenance line below the tagline, e.g. "Made in USA". Same rules, same
    /// reason.
    public static var provenance: String { string("BrandProvenance") ?? "" }

    /// No free tier at all: every connect needs an entitlement.
    public static var paidOnly: Bool { flag("BrandPaidOnly") }
    public static var legalOperator: String { string("BrandLegalOperator") ?? displayName }
    public static var supportEmail: String { string("BrandSupportEmail") ?? "" }
    public static var siteURL: String { string("BrandSiteURL") ?? "" }

    /// `siteURL` without the scheme or trailing slash, for display.
    public static var siteHost: String {
        siteURL
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    /// The contact bullets for the privacy policy, omitting anything this brand has
    /// not recorded. EMPTY means the whole section is hidden: a dead support
    /// address inside a legal document is worse than no address.
    public static var contactLines: String {
        var out: [String] = []
        if !supportEmail.isEmpty { out.append("\u{2022} By email: \(supportEmail)") }
        if !siteURL.isEmpty { out.append("\u{2022} By visiting: \(siteURL)") }
        return out.joined(separator: "\n")
    }

    /// WHICH COMPOSITION THIS BRAND RENDERS.
    public enum Style: String {
        /// The default composition: the connect dial, the drawer and the welcome
        /// slides.
        case classic
        /// Concentric band dial, gradient status word, gradient upgrade pill,
        /// accent-tinted dark ground. See `RingsDial`.
        case rings
        /// The single-plan paywall composition; the home screen renders classic.
        case value
        /// Bottom tabs (Connect · Account), the 186 pt ring dial, its own token set
        /// (`IPTheme`, overridable per key from `branding.themeDark`), no drawer,
        /// no welcome slides. Dark-first.
        case tabs

        /// Is this treatment DARK-GROUNDED when nobody has asked for anything?
        public var forcesDark: Bool { self == .rings || self == .tabs }
    }

    /// Unknown or absent -> `.classic`, i.e. today's shipping layout.
    public static var style: Style {
        Style(rawValue: (string("BrandStyle") ?? "").lowercased()) ?? .classic
    }

    /// The mark's size as a fraction of the dial's core disc.
    public static var markScale: CGFloat {
        guard let v = string("BrandMarkScale"), let f = Double(v), f > 0 else { return 1.0 }
        return CGFloat(f)
    }
}

/// Fleet-wide constants. Deliberately NOT per brand.
public enum FleetConstants {
    /// The config seal certificate hash.
    public static let configSealCertSHA256 =
        "6432a955d40722a1fd604d6384d445198c551cd8905e889eb98d432688cec415"

    /// The User-Agent the tunnel sends on the wire.
    public static let wireUserAgent = "RostamVPN/2.0"
}
