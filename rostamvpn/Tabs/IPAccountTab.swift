// Copyright 2026 Internet Mastering & Company, Inc.
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import StoreKit
import RostamKit

/// Account, per the approved direction: ONE card (Pro, the price, active until
/// a date or "Not active", Go Pro), restore, and a single Legal link that holds
/// About, open source, privacy and terms.
struct IPAccountTab: View {
    @ObservedObject private var store = Store.shared
    let isPro: Bool
    let onGoPro: () -> Void
    @Binding var probeEnabled: Bool
    let onProbeToggle: (Bool) -> Void
    @Binding var themeSetting: String

    @State private var restoring = false
    @State private var restoreNote: String?
    @State private var showLegal = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 10) {
                        IPLogoTile(size: 28)
                        IPTitle(text: "Account")
                    }
                    proCard
                    Button { showLegal = true } label: {
                        row("Legal & settings", icon: "doc.text")
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .background(IPTheme.bg.ignoresSafeArea())
            .navigationBarHidden(true)
        }
        .navigationViewStyle(.stack)
        .task { if store.products.isEmpty { await store.load() } }
        .sheet(isPresented: $showLegal) {
            IPLegalSheet(probeEnabled: $probeEnabled, onProbeToggle: onProbeToggle, themeSetting: $themeSetting)
        }
    }

    private var priceLine: String {
        guard let p = store.products.first else { return "" }
        let per = p.subscription?.subscriptionPeriod.unit == .year
            ? String(localized: "per year") : String(localized: "per month")
        return "\(p.displayPrice) \(per)"
    }

    private var statusLine: String {
        guard isPro else { return String(localized: "Not active") }
        if let d = store.paidUntil {
            return String(format: String(localized: "pro_active_until", defaultValue: "Active until %@"),
                          d.formatted(date: .abbreviated, time: .omitted))
        }
        return String(localized: "Active")
    }

    private var proCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Pro").font(.system(size: 20, weight: .heavy)).tracking(-0.3).foregroundColor(IPTheme.text)
                Spacer()
                if !priceLine.isEmpty {
                    Text(priceLine).font(.system(size: 13.5, weight: .bold)).foregroundColor(IPTheme.muted)
                }
            }
            HStack(spacing: 6) {
                Circle().fill(isPro ? IPTheme.accent : IPTheme.dim).frame(width: 7, height: 7)
                Text(statusLine).font(.system(size: 13.5, weight: .semibold))
                    .foregroundColor(isPro ? IPTheme.accentStrong : IPTheme.muted)
            }
            if !isPro {
                Button("Go Pro", action: onGoPro).buttonStyle(IPPrimaryButtonStyle())
                Text("Renews automatically · cancel anytime")
                    .font(.system(size: 11))
                    .foregroundColor(IPTheme.dim)
                    .frame(maxWidth: .infinity)
            }
            Button {
                restoring = true
                Task {
                    let ok = await store.restore()
                    restoring = false
                    restoreNote = ok ? String(localized: "Restored.") : String(localized: "Nothing to restore on this Apple ID.")
                }
            } label: {
                HStack(spacing: 6) {
                    Text("Restore purchase")
                    if restoring { ProgressView().scaleEffect(0.7) }
                }
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(IPTheme.accent)
            }
            .disabled(restoring)
            if let restoreNote {
                Text(restoreNote).font(.system(size: 12)).foregroundColor(IPTheme.muted)
            }
        }
        .padding(17)
        .background(ZStack {
            IPTheme.surface
            RadialGradient(colors: [IPTheme.glow, .clear], center: .topTrailing, startRadius: 4, endRadius: 220)
        })
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .stroke(IPTheme.accent.opacity(0.45), lineWidth: 1.5))
    }

    private func row(_ title: LocalizedStringKey, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundColor(IPTheme.muted).frame(width: 22)
            Text(title).font(.system(size: 14.5, weight: .semibold)).foregroundColor(IPTheme.text)
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundColor(IPTheme.dim)
        }
        .ipCard()
    }
}

private struct IPLegalSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var probeEnabled: Bool
    let onProbeToggle: (Bool) -> Void
    @Binding var themeSetting: String

    var body: some View {
        NavigationView {
            List {
                Section {
                    NavigationLink("About \(BrandRuntime.displayName)") { AboutView() }
                    NavigationLink("Privacy Policy") { PrivacyPolicyView() }
                    NavigationLink("Terms of Use") { TermsOfUseView() }
                }
                Section {
                    Picker("Appearance", selection: Binding(
                        get: { themeSetting == "light" ? "light" : "auto" },
                        set: { themeSetting = $0 })) {
                        Text("Dark").tag("auto")
                        Text("Light").tag("light")
                    }
                    Toggle("Help Improve", isOn: Binding(get: { probeEnabled }, set: { onProbeToggle($0) }))
                        .tint(IPTheme.accent)
                } footer: {
                    Text("Help Improve sends anonymous connection diagnostics. Nothing about the sites you visit.")
                }
            }
            .navigationTitle("Legal & settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
        .navigationViewStyle(.stack)
        .tint(IPTheme.accent)
    }
}
