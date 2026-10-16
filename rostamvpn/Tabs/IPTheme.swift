// Copyright 2026 Internet Mastering & Company, Inc.
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import UIKit

extension Color {
    /// `#RGB`, `#RRGGBB` or `#RRGGBBAA` (leading `#` optional).
    init(ipHex hex: String) {
        let s = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r, g, b, a: UInt64
        switch s.count {
        case 3: (r, g, b, a) = ((v >> 8) * 17, (v >> 4 & 0xF) * 17, (v & 0xF) * 17, 255)
        case 8: (r, g, b, a) = (v >> 24, v >> 16 & 0xFF, v >> 8 & 0xFF, v & 0xFF)
        default: (r, g, b, a) = (v >> 16, v >> 8 & 0xFF, v & 0xFF, 255)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255,
                  opacity: Double(a) / 255)
    }
}

enum IPTheme {
    /// Dark and light values for one design token, manifest first.
    private static func token(_ name: String, dark: String, light: String) -> Color {
        let d = BrandTheme.themeDark[name] ?? dark
        let l = BrandTheme.themeLight[name] ?? light
        return Color(uiColor: UIColor { traits in
            UIColor(Color(ipHex: traits.userInterfaceStyle == .dark ? d : l))
        })
    }

    static let bg = token("bg", dark: "#0a0f1a", light: "#f3f7fb")
    static let surface = token("surface", dark: "#111c2e", light: "#ffffff")
    static let surface2 = token("surface2", dark: "#152237", light: "#f4f8fc")

    /// `rgba(255,255,255,.09)` dark / `rgba(13,27,48,.12)` light.
    static let border = token("border", dark: "#ffffff17", light: "#0d1b301f")
    /// `rgba(255,255,255,.06)` dark / `rgba(13,27,48,.07)` light: the tab-bar
    /// hairline.
    static let hairline = token("hairline", dark: "#ffffff0f", light: "#0d1b3012")

    static let text = token("text", dark: "#e9eff7", light: "#0c1726")
    static let muted = token("muted", dark: "#a0b2c6", light: "#46586d")
    static let dim = token("dim", dark: "#6c7f96", light: "#6a7c91")

    static let accent = token("accent", dark: "#2dd4bf", light: "#0d9488")
    static let accentStrong = token("accentStrong", dark: "#5eead4", light: "#0f766e")
    /// Text and icons placed ON an accent fill.
    static let onAccent = token("onAccent", dark: "#04211d", light: "#ffffff")

    /// `rgba(45,212,191,.20)` dark / `rgba(13,148,136,.14)` light: the glow behind
    /// the connected ring and the Pro card.
    static let glow = token("glow", dark: "#2dd4bf33", light: "#0d948824")

    enum Radius {
        static let card: CGFloat = 16
        static let cardLarge: CGFloat = 18
        static let control: CGFloat = 12
    }
}

/// The design's bordered card: surface fill, hairline border, rounded.
struct IPCard: ViewModifier {
    var radius: CGFloat = IPTheme.Radius.card
    var stroke: Color = IPTheme.border
    var lineWidth: CGFloat = 1
    var padding: CGFloat? = 14
    func body(content: Content) -> some View {
        content
            .padding(padding ?? 0)
            .background(IPTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(stroke, lineWidth: lineWidth))
    }
}

extension View {
    func ipCard(radius: CGFloat = IPTheme.Radius.card, stroke: Color = IPTheme.border,
                lineWidth: CGFloat = 1, padding: CGFloat? = 14) -> some View {
        modifier(IPCard(radius: radius, stroke: stroke, lineWidth: lineWidth, padding: padding))
    }
}

/// Filled accent button, the design's primary action.
struct IPPrimaryButtonStyle: ButtonStyle {
    var radius: CGFloat = 13
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .foregroundColor(IPTheme.onAccent)
            .background(IPTheme.accent.opacity(configuration.isPressed ? 0.8 : 1))
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// Outlined button, the design's secondary action.
struct IPOutlineButtonStyle: ButtonStyle {
    var radius: CGFloat = IPTheme.Radius.control
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .bold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .foregroundColor(IPTheme.text)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(IPTheme.border, lineWidth: 1))
    }
}

/// The brand mark in its rounded tile (top bar, Account header).
struct IPLogoTile: View {
    var size: CGFloat = 22
    var body: some View {
        Image("BrandDialMark")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Plain empty state (ContentUnavailableView is iOS 17; target is 15.6).
struct IPEmptyState: View {
    let title: LocalizedStringKey
    let systemImage: String
    let message: LocalizedStringKey
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage).font(.system(size: 34)).foregroundColor(IPTheme.dim)
            Text(title).font(.system(size: 16, weight: .heavy)).foregroundColor(IPTheme.text)
            Text(message).font(.system(size: 13.5)).foregroundColor(IPTheme.muted).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

/// Section heading in the design's type: heavy, tight.
struct IPTitle: View {
    let text: LocalizedStringKey
    var size: CGFloat = 23
    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .heavy))
            .tracking(-0.3)
            .foregroundColor(IPTheme.text)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
