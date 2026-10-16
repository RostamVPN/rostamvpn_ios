// Copyright 2026 Internet Mastering & Company, Inc.
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import RostamKit

/// THE CONNECT DIAL — the one thing this app is for. Direct SwiftUI port of
/// Android's `ui/components/PowerButton.kt`; read that file's header for the
/// full rationale. Short version.
struct ConnectDial: View {
    let state: VpnState
    /// Which line of the connect narrative is showing (`ConnectPhase`). Also drives
    /// the sweep's size and spin speed, so the ring visibly matches the same budget
    /// the status text narrates.
    let connectPhase: Int
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var spin: Double = 0
    @State private var haloBreath = false

    private let dialSize: CGFloat = 248
    private let ringStroke: CGFloat = 14
    private let ringInset: CGFloat = 10
    private let ringGap: CGFloat = 8
    private var ringDiameter: CGFloat { dialSize - ringInset * 2 - ringStroke }
    private var discSize: CGFloat { dialSize - (ringInset + ringStroke + ringGap) * 2 }
    private let glyphSize: CGFloat = 76
    /// Derived, not a literal, so it cannot drift from the mark's own 1040/880
    /// aperture ratio — see BrandDialMark.svg for why.
    private var markSize: CGFloat { discSize * (1040.0 / 880.0) }

    private var isConnecting: Bool { if case .connecting = state { return true }; return false }
    private var isDisconnecting: Bool { if case .disconnecting = state { return true }; return false }
    private var isConnected: Bool { if case .connected = state { return true }; return false }
    private var isFailed: Bool { if case .error = state { return true }; return false }
    private var isBusy: Bool { isConnecting || isDisconnecting }

    /// BrandTheme.ring, not .brand1.
    private var ringColor: Color { isFailed ? .dangerRed : BrandTheme.ring }

    private var sweepFraction: CGFloat {
        switch state {
        case .connected, .error: return 1.0
        case .connecting, .disconnecting: return ConnectPhase.trim(connectPhase)
        case .disconnected: return 0.0
        }
    }

    /// 0 on the white disc, a hint of the destination colour while connecting,
    /// fully opaque once connected.
    private var discBrandOpacity: Double {
        guard BrandRuntime.discFillsOnConnect else { return 0.0 }
        switch state {
        case .connected: return 1.0
        case .connecting, .disconnecting: return 0.10
        case .disconnected, .error: return 0.0
        }
    }

    private var glyphTint: Color {
        switch state {
        case .connected: return .white
        case .error: return .dangerRed
        default: return .brand1
        }
    }

    private var mascotAlpha: Double { isConnected ? 1.0 : 0.95 }
    private var mascotSaturation: Double { isConnected ? 1.0 : 0.80 }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(RadialGradient(
                        colors: [ringColor.opacity(0.22), ringColor.opacity(0.10), .clear],
                        center: .center, startRadius: 0, endRadius: dialSize / 2))
                    .frame(width: dialSize, height: dialSize)
                    .scaleEffect(haloBreath ? 1.06 : 0.94)
                    .opacity(isConnected ? (reduceMotion ? 0.85 : (haloBreath ? 1.0 : 0.7)) : 0)
                    .allowsHitTesting(false)
                    .animation(.easeInOut(duration: 0.5), value: isConnected)

                ZStack {
                    Circle().fill(Color.adaptiveSurface)
                    Circle().fill(Color.brand1).opacity(discBrandOpacity)
                }
                .frame(width: discSize, height: discSize)
                .shadow(color: Color.brand1.opacity(isConnected ? 0.30 : 0.20),
                        radius: isConnected ? 14 : 10, y: isConnected ? 0 : 3)
                .animation(.easeInOut(duration: 0.2), value: discBrandOpacity)

                ZStack {
                    Circle().stroke(ringColor.opacity(BrandTheme.ringRestAlpha), lineWidth: ringStroke)
                    if sweepFraction > 0.001 {
                        Circle()
                            .trim(from: 0, to: sweepFraction)
                            .stroke(ringColor, style: StrokeStyle(lineWidth: ringStroke, lineCap: .round))
                            .rotationEffect(.degrees(-90 + (isBusy && !reduceMotion ? spin : 0)))
                    }
                }
                .frame(width: ringDiameter, height: ringDiameter)
                .animation(.easeInOut(duration: 0.5), value: sweepFraction)

                Group {
                    if BrandRuntime.hasMascot {
                        Image("BrandDialMark")
                            .resizable()
                            .frame(width: markSize, height: markSize)
                            .saturation(mascotSaturation)
                            .opacity(mascotAlpha)
                    } else {
                        Image(systemName: "power")
                            .font(.system(size: glyphSize * 0.42, weight: .semibold))
                            .frame(width: glyphSize, height: glyphSize)
                            .foregroundColor(glyphTint)
                            .accessibilityHidden(true)
                    }
                }
                .animation(.easeInOut(duration: 0.35), value: isConnected)
            }
            .frame(width: dialSize, height: dialSize)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onAppear { restartSpinIfBusy(); restartHaloIfConnected() }
        .onChange(of: isBusy) { _ in restartSpinIfBusy() }
        .onChange(of: connectPhase) { _ in restartSpinIfBusy() }
        .onChange(of: isConnected) { connected in
            haloBreath = false
            guard connected else { return }
            restartHaloIfConnected()
        }
    }

    private func restartSpinIfBusy() {
        guard isBusy, !reduceMotion else { return }
        spin = 0
        withAnimation(.linear(duration: ConnectPhase.period(connectPhase)).repeatForever(autoreverses: false)) {
            spin = 360
        }
    }

    private func restartHaloIfConnected() {
        guard isConnected, !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
            haloBreath = true
        }
    }
}
