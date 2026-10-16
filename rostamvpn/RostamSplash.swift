// Copyright 2026 Internet Mastering & Company, Inc.
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import RostamKit

/// The animated splash.
struct RostamSplash: View {
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection

    @State private var sheenX: CGFloat = -210
    @State private var stillLift: Double = 0
    @State private var lockupScale: CGFloat = 1
    @State private var rootOpacity: Double = 1

    /// The metal catching the light, at 15% inside a specular that is mostly white
    /// — so this tints the glint rather than colouring the artwork.
    private static let gold = BrandTheme.warning

    private typealias G = LaunchGeometry
    /// .offset(x:) is NOT mirrored by SwiftUI. A sweep must run the direction the
    /// eye reads, or in Persian it looks like something being undone.
    private var dir: CGFloat { layoutDirection == .rightToLeft ? -1 : 1 }

    var body: some View {
        ZStack {
            Color.adaptiveBg.ignoresSafeArea()
            Image("LaunchGradient").resizable().scaledToFill().ignoresSafeArea()

            logo
                .scaledToFit()
                .frame(width: G.boxW, height: G.boxH)
                .offset(y: G.lockupOffsetY)
                .scaleEffect(lockupScale)
        }
        .opacity(rootOpacity)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task { await run() }
    }

    /// Does this brand's mark need a light field under it?
    private var markNeedsLightField: Bool { !BrandRuntime.discFillsOnConnect }

    private var logo: some View {
        Image("LaunchLogo")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
                .frame(width: G.boxW, height: G.boxH)
            .background(

                Circle()
                    .fill(Color.white)
                    .frame(
                        width: G.boxW * BrandRuntime.launchDiscScale,
                        height: G.boxW * BrandRuntime.launchDiscScale,
                    )
                    .offset(y: G.boxH * BrandRuntime.launchDiscOffsetY)
                    .opacity(markNeedsLightField ? 1 : 0)
            )
            .overlay(light)

            .compositingGroup()
    }

    /// A narrow, fast SPECULAR pass, not a key light.
    @ViewBuilder private var light: some View {
        if reduceMotion {
            RadialGradient(colors: [.white.opacity(0.9), .white.opacity(0)],
                           center: .center, startRadius: 0, endRadius: G.boxW * 0.62)
                .mask(Image("LaunchLogo").resizable().scaledToFit()
                .frame(width: G.boxW, height: G.boxH))
                .blendMode(.plusLighter)
                .opacity(stillLift)
        } else {
            LinearGradient(stops: [
                .init(color: .clear, location: 0.00),
                .init(color: .clear, location: 0.42),
                .init(color: Self.gold.opacity(0.15), location: 0.46),
                .init(color: .white.opacity(0.45), location: 0.50),
                .init(color: Self.gold.opacity(0.15), location: 0.54),
                .init(color: .clear, location: 0.58),
                .init(color: .clear, location: 1.00)
            ], startPoint: .leading, endPoint: .trailing)
                .frame(width: G.boxW * 1.55, height: G.boxH * 1.70)
                .rotationEffect(.degrees(18 * Double(dir)))
                .offset(x: sheenX * dir)
                .mask(Image("LaunchLogo").resizable().scaledToFit()
                .frame(width: G.boxW, height: G.boxH))
                .blendMode(.plusLighter)
        }
    }

    private func run() async {
        if reduceMotion {
            await hold(60)
            withAnimation(.easeInOut(duration: 0.14)) { stillLift = 0.18 }
            await hold(150)
            withAnimation(.easeInOut(duration: 0.14)) { stillLift = 0 }
            await hold(140)
            withAnimation(.linear(duration: 0.14)) { rootOpacity = 0 }
            await hold(150)
        } else {
            await hold(220)
            withAnimation(.easeInOut(duration: 0.75)) { sheenX = 210 }
            await hold(750)
            await hold(600)
            withAnimation(.easeIn(duration: 0.45)) {
                lockupScale = 1.035
                rootOpacity = 0
            }
            await hold(450)
        }
        onFinish()
    }

    private func hold(_ ms: UInt64) async {
        try? await Task.sleep(nanoseconds: ms * 1_000_000)
    }
}
