// Copyright 2026 Internet Mastering & Company, Inc.
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import UIKit
import RostamKit

extension Color {
    struct RGB { let r: Double, g: Double, b: Double, a: Double }

    var rgbComponents: RGB {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return RGB(r: Double(r), g: Double(g), b: Double(b), a: Double(a))
    }

    /// [self]'s hue in degrees, 0 when it has none (any grey).
    var hueDegrees: Double {
        let c = rgbComponents
        let mx = max(c.r, c.g, c.b), mn = min(c.r, c.g, c.b)
        let d = mx - mn
        guard d > 0 else { return 0 }
        let h: Double
        if mx == c.r { h = ((c.g - c.b) / d).truncatingRemainder(dividingBy: 6) }
        else if mx == c.g { h = (c.b - c.r) / d + 2 }
        else { h = (c.r - c.g) / d + 4 }
        return (h * 60 + 360).truncatingRemainder(dividingBy: 360)
    }

    /// [c]'s HUE, re-lit at [s] saturation and [l] lightness.
    static func tone(_ c: Color, _ s: Double, _ l: Double) -> Color {
        hsl(c.hueDegrees, s, l)
    }

    /// HSL → sRGB, by hand. There is no `Color.init(hue:saturation:lightness:)`.
    static func hsl(_ hDeg: Double, _ s: Double, _ l: Double) -> Color {
        let h = hDeg / 360
        func hue2rgb(_ p: Double, _ q: Double, _ t0: Double) -> Double {
            var t = t0
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1.0 / 6 { return p + (q - p) * 6 * t }
            if t < 1.0 / 2 { return q }
            if t < 2.0 / 3 { return p + (q - p) * (2.0 / 3 - t) * 6 }
            return p
        }
        guard s > 0 else { return Color(red: l, green: l, blue: l) }
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s
        let p = 2 * l - q
        return Color(red: hue2rgb(p, q, h + 1.0 / 3),
                     green: hue2rgb(p, q, h),
                     blue: hue2rgb(p, q, h - 1.0 / 3))
    }

    /// [a] blended toward [b] by [t]. Opaque; this is a mix, not a composite.
    static func mix(_ a: Color, _ b: Color, _ t: Double) -> Color {
        let x = a.rgbComponents, y = b.rgbComponents
        return Color(red: x.r + (y.r - x.r) * t,
                     green: x.g + (y.g - x.g) * t,
                     blue: x.b + (y.b - x.b) * t)
    }

    /// WCAG 2.1 relative luminance.
    var relativeLuminance: Double {
        func lin(_ v: Double) -> Double {
            v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        let c = rgbComponents
        return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)
    }

    /// WCAG 2.1 contrast ratio, 1.0 (identical) to 21.0 (black on white).
    static func contrastRatio(_ a: Color, _ b: Color) -> Double {
        let la = a.relativeLuminance + 0.05, lb = b.relativeLuminance + 0.05
        return la > lb ? la / lb : lb / la
    }

    /// The more legible of two candidates on [bg].
    static func mostLegibleOn(_ bg: Color, _ a: Color, _ b: Color) -> Color {
        contrastRatio(a, bg) >= contrastRatio(b, bg) ? a : b
    }

    /// [c] blended toward [toward] by the SMALLEST amount that clears [min] against
    /// [bg]. Returns [c] untouched when it already clears.
    static func liftOnto(_ bg: Color, _ c: Color,
                         min: Double = 4.5, toward: Color = .white) -> Color {
        if contrastRatio(c, bg) >= min { return c }
        for i in 1...20 {
            let blended = mix(c, toward, Double(i) / 20)
            if contrastRatio(blended, bg) >= min { return blended }
        }
        return toward
    }
}

enum Surface {
    /// The neutral near-black every CLASSIC brand runs on.
    private static let neutralBgDark   = Color(red: 0x12 / 255, green: 0x12 / 255, blue: 0x12 / 255)
    private static let neutralCardDark = Color(red: 0x2C / 255, green: 0x2C / 255, blue: 0x2C / 255)

    /// ── THE DARK PAGE, PER TREATMENT ──.
    static var bgDark: Color {
        BrandRuntime.style == .rings ? BrandTheme.groundDark : neutralBgDark
    }
    static var cardDark: Color {
        BrandRuntime.style == .rings ? BrandTheme.cardDark : neutralCardDark
    }
    static var bgLight: Color {
        BrandRuntime.style == .rings ? BrandTheme.groundLight : neutralBgLight
    }
    private static let neutralBgLight = Color(red: 0xF8 / 255, green: 0xF9 / 255, blue: 0xFA / 255)
    static let cardLight   = Color.white
    /// One step below the card. On a `rings` brand it is the ground itself lifted a
    /// little, so the three dark surfaces are one ramp rather than a brand ground
    /// with two neutral greys sitting on it.
    static var surfaceDark: Color {
        BrandRuntime.style == .rings
            ? Color.mix(BrandTheme.groundDark, .white, 0.035)
            : Color(red: 0x1E / 255, green: 0x1E / 255, blue: 0x1E / 255)
    }

    /// The CONNECTED wash: the brand's own primary laid over the resting page.
    static func connectedWash(_ amount: Double, dark: Bool) -> Color {
        let ground = dark ? bgDark : bgLight

        guard BrandRuntime.style != .rings else { return ground }
        return Color.mix(ground, BrandTheme.primary, dark ? amount * 2.2 : amount)
    }
    /// The strongest tint of that wash, i.e. the WORST ground a brand-coloured
    /// foreground has to survive.
    static var washDark: Color { connectedWash(0.105, dark: true) }
    static var washLight: Color { connectedWash(0.105, dark: false) }

    /// The SETTINGS SHEET's field, which is dark in both schemes because the sheet
    /// paints its own ground.
    static var sheetTop: Color {
        BrandRuntime.style == .rings ? BrandTheme.cardDark : Color.tone(BrandTheme.primary, 0.26, 0.28)
    }
    static var sheetBottom: Color {
        BrandRuntime.style == .rings ? BrandTheme.cardDark : Color.tone(BrandTheme.primary, 0.125, 0.20)
    }

    /// A dynamic colour that resolves [make] against the light or dark member of a
    /// surface pair.
    static func adaptive(light: Color, dark: Color,
                         _ make: (_ ground: Color, _ toward: Color) -> Color) -> Color {
        let l = UIColor(make(light, .black))
        let d = UIColor(make(dark, .white))
        return Color(UIColor { $0.userInterfaceStyle == .dark ? d : l })
    }
}

extension Color {
    /// `primary`, made legible as TEXT on the app background in both schemes.
    static let brandOnBg = Surface.adaptive(light: Surface.washLight, dark: Surface.washDark) {
        liftOnto($0, BrandTheme.primary, min: 4.5, toward: $1)
    }

    /// `primary`, made legible as TEXT on a card.
    static let brandOnCard = Surface.adaptive(light: Surface.cardLight, dark: Surface.cardDark) {
        liftOnto($0, BrandTheme.primary, min: 4.5, toward: $1)
    }

    /// `primary` as a non-text GRAPHIC on the app background — a glyph, a rule, a
    /// meter fill. 3:1 per SC 1.4.11, not 4.5.
    static let brandGraphicOnBg = Surface.adaptive(light: Surface.washLight, dark: Surface.washDark) {
        liftOnto($0, BrandTheme.primary, min: 3, toward: $1)
    }

    /// `primary` as a non-text graphic on a card.
    static let brandGraphicOnCard = Surface.adaptive(light: Surface.cardLight, dark: Surface.cardDark) {
        liftOnto($0, BrandTheme.primary, min: 3, toward: $1)
    }

    /// `secondary` as TEXT on the app background. The CONNECTING state, which is
    /// the only thing that draws it.
    static let accentOnBg = Surface.adaptive(light: Surface.washLight, dark: Surface.washDark) {
        liftOnto($0, BrandTheme.secondary, min: 4.5, toward: $1)
    }

    /// `secondary` as a control on that field -- the probe switch's ON track.
    /// A secondary close to the sheet colour can sit at 1.03:1, which leaves the
    /// switch exactly one visible state.
    static var accentOnSheet: Color {
        liftOnto(Surface.sheetTop, BrandTheme.secondary, min: 3)
    }

    /// The `warning` role — "running low", never "used up" — as a meter fill AND
    /// the caption beside it. 4.5, not 3, because the same value draws both and the
    /// caption is small text.
    static let warningOnCard = Surface.adaptive(light: Surface.cardLight, dark: Surface.cardDark) {
        liftOnto($0, BrandTheme.warning, min: 4.5, toward: $1)
    }

    /// The cool end, LIFTED for the page it sits on. Text, so 4.5.
    static let statusGradientTop = Surface.adaptive(light: Surface.bgLight, dark: Surface.bgDark) {
        liftOnto($0, BrandTheme.accent, min: 4.5, toward: $1)
    }
    /// The warm end, same treatment.
    static let statusGradientBottom = Surface.adaptive(light: Surface.bgLight, dark: Surface.bgDark) {
        liftOnto($0, BrandTheme.primary, min: 4.5, toward: $1)
    }
}

enum Deep {
    private static var field: Color { BrandTheme.primary }
    private static var metal: Color { BrandTheme.warning }
    private static var isRings: Bool { BrandRuntime.style == .rings }
    private static var isValue: Bool { BrandRuntime.style == .value }

    /// The room. Rostam lands on #0C2325 against the #0C2522 literal it replaces —
    /// three units of blue, which is the point.
    static var ground: Color {
        if isRings { return BrandTheme.groundDark }
        if isValue { return BrandTheme.primaryDeep }
        return Color.tone(field, 0.51, 0.096)
    }
    /// The top of the field, where the gradient starts. On `rings` it is a WHISPER,
    /// not a second field: 4% white, so the screen is not dead flat under the mark.
    /// Android's value exactly.
    static var top: Color {
        if isRings { return Color.mix(BrandTheme.groundDark, .white, 0.04) }
        if isValue { return BrandTheme.primary }
        return Color.tone(field, 0.53, 0.165)
    }
    /// A card on that ground. One step up, which is what gives a dark screen depth
    /// without spending any colour.
    static var card: Color {
        if isRings { return BrandTheme.cardDark }

        if isValue { return Color.mix(ground, .white, 0.09) }
        return Color.tone(field, 0.52, 0.130)
    }

    /// Body text. The metal at near-white — a warm off-white on a cold ground,
    /// which is what keeps the screen from reading as grey on grey. Not pure white,
    /// deliberately. 13.4:1 to 15.3:1 across the four brands.
    static var ink: Color {
        if isRings { return Self.ringsInk }
        if isValue { return BrandTheme.background }
        return Color.tone(metal, 0.48, 0.910)
    }
    /// Secondary text. The FIELD's hue held light, so captions belong to the room.
    /// 7.26:1 to 7.39:1. On `value` it is the INK's hue held down instead, so the
    /// caption is the same off-white dimmed rather than a second colour.
    static var muted: Color {
        if isRings { return Self.ringsMuted }
        if isValue { return Color.tone(BrandTheme.background, 0.13, 0.72) }
        return Color.tone(field, 0.13, 0.660)
    }
    /// A hairline on the ground: ink at 10%.
    static var line: Color { ink.opacity(0.10) }

    /// Android's own two values for the RINGS field. They are the SAME pair its
    /// `RingsDarkColorScheme` uses for `onBackground`/`onSurfaceVariant`, so the
    /// paywall and the home screen read as one room on both platforms.
    private static let ringsInk   = Color(red: 0xF4 / 255, green: 0xF1 / 255, blue: 0xF6 / 255)
    private static let ringsMuted = Color(red: 0xA9 / 255, green: 0xA2 / 255, blue: 0xB4 / 255)

    private static func schemed(light: Color, dark: Color) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light) })
    }

    /// The page's primary ink. Light: the brand's own `ink`, 14.72:1 on the tinted
    /// ground. Dark: unchanged.
    static var ringsPageInk: Color {
        schemed(light: BrandTheme.ink, dark: ringsInk)
    }

    /// The helper line under the status word. Light.
    static var ringsPageMuted: Color {
        schemed(light: Color.tone(BrandTheme.accent, 0.10, 0.42), dark: ringsMuted)
    }

    /// The RESTING status word, dimmed toward its own ground in both schemes.
    /// 8.85:1 light, and the dark arm keeps the exact literal it shipped with —
    /// blending toward `groundDark` instead differs by ~6 units.
    static var ringsStatusRest: Color {
        schemed(light: Color.mix(BrandTheme.ink, BrandTheme.groundLight, 0.17),
                dark:  Color.mix(ringsInk, .black, 0.25))
    }

    /// ── THE CALL TO ACTION ──.
    static var cta: Color {
        if isRings { return BrandTheme.primary }
        if isValue { return BrandTheme.accent }
        return Color.tone(field, 0.57, 0.427)
    }
    static var ctaLite: Color {
        if isRings { return BrandTheme.accent }
        if isValue { return BrandTheme.accent }
        return Color.tone(field, 0.57, 0.494)
    }
    static var ctaInk: Color {
        if isRings { return .white }
        if isValue { return Color.mostLegibleOn(cta, .white, BrandTheme.ink) }
        return Color.mostLegibleOn(cta, .white, Color.tone(field, 0.70, 0.070))
    }

    /// The metal at full strength. `liftOnto` is a floor, not a tint: it only moves
    /// for a brand whose gold is too dark for its own field.
    static var gold: Color {
        if isRings { return Self.ringsInk }
        if isValue { return Color.liftOnto(ground, BrandTheme.accent, min: 4.5) }
        return Color.liftOnto(ground, metal, min: 4.5)
    }
    /// The save badge's fill — and, on `value`, the banner title's colour.
    static var goldLite: Color {
        if isRings { return Self.ringsInk }
        if isValue { return Color.tone(BrandTheme.accent, 0.82, 0.660) }
        return Color.tone(metal, 0.82, 0.660)
    }
    static var goldInk: Color {
        let dark = Color.tone(isValue ? BrandTheme.accent : metal, 0.72, 0.090)
        return Color.mostLegibleOn(goldLite, dark, .white)
    }

    static var selectedEdge: Color { (isRings || isValue) ? cta : gold }
}
