// Copyright 2026 Internet Mastering & Company, Inc.
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import RostamKit

/// First run, and the only screen between a fresh install and a working tunnel.
struct WelcomeView: View {
    /// Invoked once, on the primary tap, AFTER `hasSeenWelcome` is persisted. The
    /// host is expected to dismiss this view and run its normal connect path -- the
    /// system VPN prompt is the next thing the user sees.
    let onContinue: () -> Void

    private static let seenKey = "hasSeenWelcome"

    /// The host's gate. `true` until the user has tapped through once.
    static var shouldShow: Bool {
        !(BrandRuntime.defaults?.bool(forKey: seenKey) ?? false)
    }

    /// Written on the tap, never on appear: an install killed while this screen is
    /// on-screen has not been onboarded, and should see it again.
    private static func markSeen() {
        BrandRuntime.defaults?.set(true, forKey: seenKey)
    }

    private let gold = Color.warningOnCard

    var body: some View {
        ZStack {
            Color.adaptiveBg.ignoresSafeArea()

            VStack {
                LinearGradient(
                    colors: [Color.brand2.opacity(0.18), Color.brand2.opacity(0.0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 320)
                Spacer()
            }
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    hero
                        .padding(.top, 24)

                    Text("Welcome to \(BrandRuntime.displayName)")
                        .font(.title.weight(.bold))
                        .multilineTextAlignment(.center)
                        .foregroundColor(.primary)
                        .padding(.top, 20)

                    Text("A private, faster connection on any network.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                        .padding(.horizontal, 8)

                    ornament
                        .padding(.top, 20)

                    valueSection(
                        "Our own hardware",
                        "Most VPNs rent cheap virtual servers. Ours sits inside the internet exchanges where the world's major networks meet — a shorter path, and a faster app.")
                        .padding(.top, 22)

                    if !RegionPolicy.isFreedomRegion, !ConfigPolicy.paidOnly {
                        valueSection(
                            "Free, or Premium",
                            "Free gives you a monthly allowance at full speed. Premium removes the cap.")
                            .padding(.top, 18)
                    }

                    explainer
                        .padding(.top, 22)

                    Text("iOS shows that same wording for every VPN app.")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .padding(.top, 14)
                        .padding(.horizontal, 8)

                    connectButton
                        .padding(.top, 24)

                    Text("You can disconnect at any time.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .padding(.top, 12)
                        .padding(.bottom, 28)
                }
                .frame(maxWidth: 480)
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity)
            }
        }
    }

    /// The mascot on a disc. Decorative, so it is hidden from VoiceOver rather than
    /// given a label a screen reader would have to sit through first.
    private var hero: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.brand2.opacity(0.20), Color.brand1.opacity(0.08)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            Image("BrandMascot")
                .resizable()
                .scaledToFit()
                .padding(24)
        }
        .frame(width: 148, height: 148)
        .accessibilityHidden(true)
    }

    /// The brand divider: a rule with a node at its centre. Symmetric, so it needs
    /// no mirroring under RTL.
    private var ornament: some View {
        HStack(spacing: 8) {
            Capsule().fill(gold.opacity(0.45)).frame(width: 44, height: 1)
            RoundedRectangle(cornerRadius: 1).fill(gold).frame(width: 4, height: 4)
            Capsule().fill(gold.opacity(0.45)).frame(width: 44, height: 1)
        }
        .accessibilityHidden(true)
    }

    /// What iOS is about to ask, in the order the user will meet it.
    private var explainer: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What happens next")
                .font(.headline)
                .foregroundColor(.primary)

            row(
                symbol: "lock.shield.fill",
                title: Text("Your iPhone asks to add a VPN configuration"),
                body: Text("That is how iOS lets an app carry your traffic through a secure tunnel. Every VPN needs it.")
            )

            row(
                symbol: "faceid",
                title: Text("Then Face ID, Touch ID, or your passcode"),
                body: Text("iOS asks so that only you can change the VPN settings on this iPhone.")
            )

            row(
                symbol: "power",
                title: Text("You stay in control"),
                body: Text("Turn the connection off in the app, or in Settings, whenever you want.")
            )
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.adaptiveCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    /// One explainer line. `leading`/`trailing` throughout and no `offset(x:)`, so
    /// the icon sits on the correct side in Persian and Arabic.
    private func row(symbol: String, title: Text, body: Text) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.body)

                .foregroundColor(.brandGraphicOnCard)
                .frame(width: 26, alignment: .center)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                title
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                body
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// One value section: a title and a paragraph, centred like everything else on
    /// this screen. No icon — the explainer below uses numbered rows, and a second
    /// icon language above it would read as two designs on one screen.
    private func valueSection(_ title: String, _ body: String) -> some View {
        VStack(spacing: 6) {
            Text(LocalizedStringKey(title))
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundColor(.primary)
            Text(LocalizedStringKey(body))
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
    }

    private var connectButton: some View {
        Button {
            WelcomeView.markSeen()
            onContinue()
        } label: {
            Text("Connect")
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [Color.brand2, Color.brand1],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}
