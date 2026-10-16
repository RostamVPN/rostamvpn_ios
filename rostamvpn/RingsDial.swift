// Copyright 2026 Internet Mastering & Company, Inc.
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import UIKit
import RostamKit

private let DIAL_BASE: CGFloat = 260

private let DIAL_BASE_WIDTH: CGFloat = 393

/// Fraction of the screen the dial occupies — derived from the measurement
/// above (260/393), not chosen, so a default-width phone renders byte-
/// identically to what shipped.
private let DIAL_WIDTH_FRACTION: CGFloat = DIAL_BASE / DIAL_BASE_WIDTH

private let DIAL_MIN: CGFloat = 248
private let DIAL_MAX: CGFloat = 320

private let CORE_FRACTION: CGFloat = 0.535
private let BAND_FRACTION: CGFloat = 0.116
private let BAND_COUNT = 4

/// Inner -> outer.
private let BAND_ALPHA: [Double] = [1.00, 0.91, 0.69, 0.40]

private let REST_ALPHA_LIGHT: [Double]   = [1.00, 0.85, 0.70, 0.55]

private let BAND_ALPHA_LIGHT: [Double]   = [1.00, 0.89, 0.73, 0.58]

private let FAILED_ALPHA_LIGHT: [Double] = [1.00, 1.00, 1.00, 1.00]

/// The OFF outlines.
private let REST_ALPHA: [Double] = [0.46, 0.37, 0.28, 0.19]

private let OUTLINE_STROKE: CGFloat = 2
private let FAILED_STROKE: CGFloat = 2.5

/// The power glyph, for a `rings` brand with no mark of its own.
private let GLYPH_SIZE: CGFloat = 64

struct RingsDial: View {
    let state: VpnState
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    @State private var chargeStart: Date?
    @State private var settleStart: Date?
    /// Where the settle animation came FROM, so it can ease between any pair.
    @State private var settleFrom: Double = 0
    @State private var pressed = false
    @State private var arrival: CGFloat = 1

    /// Android's `tween(700)` for the band fill and `tween(1500)` for the charge
    /// cycle. Same numbers, so the two platforms settle at the same rate.
    private static let SETTLE: Double = 0.7
    private static let CYCLE: Double = 1.5

    private var isConnecting: Bool { if case .connecting = state { return true }; return false }
    private var isConnected: Bool { if case .connected = state { return true }; return false }
    private var isFailed: Bool { if case .error = state { return true }; return false }

    private var bandColor: Color { BrandTheme.accentOnLight }

    /// The core's ground, and what the ramp is composited against. See the header:
    /// this is WHITE in both schemes and that is load-bearing.
    private let coreGround = Color.white

    private var bandFill: [Color] {
        (0..<BAND_COUNT).map {
            Color.mix(coreGround, bandColor,
                      (scheme == .dark ? BAND_ALPHA : BAND_ALPHA_LIGHT)[$0])
        }
    }

    /// The OUTLINES are the opposite case: they are strokes ON the page, so they
    /// must contrast with the PAGE rather than with the core. #BB0008 at 0.46 over
    /// a dark page is ~1.4:1 and simply is not there.
    private var outlineInk: Color {
        Color.liftOnto(scheme == .dark ? Surface.bgDark : Surface.bgLight,
                       bandColor, min: 3, toward: scheme == .dark ? .white : .black)
    }

    /// The fill this state RESTS at, with no motion involved.
    private var restingFill: Double {
        if isConnected { return Double(BAND_COUNT) }
        if isConnecting { return 2 }
        return 0
    }

    /// How many bands are lit at [now]. Pure, so the Canvas can be driven from the
    /// timeline's clock instead of from animatable state it cannot read.
    private func fill(at now: Date) -> Double {
        guard !reduceMotion else { return restingFill }

        if isConnecting, let start = chargeStart {
            let t = now.timeIntervalSince(start).truncatingRemainder(dividingBy: Self.CYCLE)
            return t / Self.CYCLE * Double(BAND_COUNT)
        }

        if let start = settleStart {
            let t = min(max(now.timeIntervalSince(start) / Self.SETTLE, 0), 1)

            let e = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
            return settleFrom + (restingFill - settleFrom) * e
        }
        return restingFill
    }

    /// Is anything moving? The timeline is PAUSED whenever this is false, so a
    /// tunnel that has been up for eight hours costs no frames.
    private func moving(at now: Date) -> Bool {
        guard !reduceMotion else { return false }
        if isConnecting { return true }
        if let start = settleStart { return now.timeIntervalSince(start) < Self.SETTLE }
        return false
    }

    /// SCREEN width, deliberately, not the container's.
    private var screenWidth: CGFloat {
        (UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.screen.bounds.width) ?? DIAL_BASE_WIDTH
    }

    private var dialSize: CGFloat {
        min(DIAL_MAX, max(DIAL_MIN, screenWidth * DIAL_WIDTH_FRACTION))
    }

    private var coreSize: CGFloat { dialSize * CORE_FRACTION }
    /// Per BRAND, from the manifest. Rostam's mark has a circular aperture its
    /// horns escape (1.18); a full-bleed raster mark sits inside the disc at well
    /// under 1. A shared constant is one brand's geometry on everyone.
    private var markSize: CGFloat { coreSize * BrandRuntime.markScale }

    private var accessibilityLabel: LocalizedStringKey {
        if isConnected { return "Tap to disconnect" }
        if isConnecting { return "Tap to cancel" }
        return "Tap to connect"
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0,
                                        paused: !moving(at: Date()))) { timeline in
                let fill = self.fill(at: timeline.date)
                Canvas { ctx, size in
                    let r = min(size.width, size.height) / 2
                    let core = r * CORE_FRACTION
                    let band = r * BAND_FRACTION
                    let c = CGPoint(x: size.width / 2, y: size.height / 2)

                    func circlePath(_ radius: CGFloat) -> Path {
                        Path(ellipseIn: CGRect(x: c.x - radius, y: c.y - radius,
                                               width: radius * 2, height: radius * 2))
                    }

                    for i in stride(from: BAND_COUNT - 1, through: 0, by: -1) {
                        let outer = core + band * CGFloat(i + 1)
                        let strokeR = outer - band / 2

                        if isFailed {
                            ctx.stroke(circlePath(strokeR),
                                       with: .color(Color.dangerRed.opacity(
                                           scheme == .dark ? REST_ALPHA[i] * 2.2
                                                           : FAILED_ALPHA_LIGHT[i])),
                                       lineWidth: FAILED_STROKE)
                        } else if fill > Double(i) {
                            let lit = Swift.min(Swift.max(fill - Double(i), 0), 1)
                            ctx.fill(circlePath(outer),
                                     with: .color(bandFill[i].opacity(lit)))

                            if lit < 1 {
                                ctx.stroke(circlePath(strokeR),
                                           with: .color(outlineInk.opacity(
                                           (scheme == .dark ? REST_ALPHA : REST_ALPHA_LIGHT)[i])),
                                           lineWidth: OUTLINE_STROKE)
                            }
                        } else {
                            ctx.stroke(circlePath(strokeR),
                                       with: .color(outlineInk.opacity(
                                           (scheme == .dark ? REST_ALPHA : REST_ALPHA_LIGHT)[i])),
                                       lineWidth: OUTLINE_STROKE)
                        }
                    }
                }
                .frame(width: dialSize, height: dialSize)
                }

                Circle()
                    .fill(coreGround)
                    .frame(width: coreSize, height: coreSize)
                    .shadow(color: .black.opacity(0.28),
                            radius: isConnected ? 10 : 6, y: isConnected ? 0 : 3)

                if BrandRuntime.hasMascot {
                    Image("BrandDialMark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: markSize, height: markSize)
                } else {
                    Image(systemName: "power")
                        .font(.system(size: GLYPH_SIZE * 0.5, weight: .semibold))
                        .foregroundColor(isFailed ? .dangerRed : .brand1)
                        .frame(width: GLYPH_SIZE, height: GLYPH_SIZE)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: dialSize, height: dialSize)
            .scaleEffect((pressed ? 0.955 : 1) * arrival)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)

        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !pressed else { return }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { pressed = true }
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { pressed = false }
                }
        )

        .onAppear { retarget(animated: false) }
        .onChange(of: stateKey) { _ in retarget(animated: true) }
    }

    /// Collapses `VpnState` to something Equatable. `.error(String)` carries a
    /// payload, so the enum itself cannot be compared without conforming it.
    private var stateKey: Int {
        if isConnected { return 1 }
        if isConnecting { return 2 }
        if isFailed { return 3 }
        return 0
    }

    /// Point both clocks at the state the dial is now in.
    private func retarget(animated: Bool) {
        let now = Date()

        let current = fill(at: now)

        if isConnecting && !reduceMotion {
            chargeStart = now
            settleStart = nil
        } else {
            chargeStart = nil
            if animated && !reduceMotion && current != restingFill {
                settleFrom = current
                settleStart = now
            } else {
                settleStart = nil
            }
        }

        guard animated, isConnected, !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 0.16)) { arrival = 1.06 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) { arrival = 1 }
        }
    }
}
