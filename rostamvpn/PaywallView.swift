// Copyright 2026 Internet Mastering & Company, Inc.
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import StoreKit
import RostamKit

/// The upgrade screen — a port of Android's PaywallScreen.kt, not a new design.
struct PaywallView: View {
    @StateObject private var store = Store.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var busy = false
    @State private var message: String?
    @State private var selected: String = ""
    @State private var showTerms = false
    @State private var showPrivacy = false
    /// The price hero's size. `@ScaledMetric` rather than a bare
    /// `.font(.system(size.
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 44
    /// The perk body. 13 sits between `.footnote` (13) and `.caption` (12) and
    /// there is no text style at exactly the weight wanted — but a bare
    /// `.system(size.
    @ScaledMetric(relativeTo: .footnote) private var perkBodySize: CGFloat = 13

    private let ground = Deep.ground
    private let top    = Deep.top
    private let card   = Deep.card
    private let ink    = Deep.ink
    private let muted  = Deep.muted
    private let gold   = Deep.gold
    private let goldLite = Deep.goldLite
    private let ctaTop = Deep.ctaLite
    private let ctaBottom = Deep.cta
    private let ctaInk = Deep.ctaInk
    private let line   = Deep.line
    /// The chosen plan's edge. A role of its own rather than `gold`: on the `rings`
    /// treatment the accent is rationed to the CTA and to THIS, so the row the user
    /// picked and the button that acts on it read as one decision.
    private let selectedEdge = Deep.selectedEdge

    var body: some View {
        ZStack {
            if BrandRuntime.style == .tabs {
                IPTheme.bg.ignoresSafeArea()
            } else {
            LinearGradient(stops: [.init(color: top, location: 0),
                                   .init(color: ground, location: 0.28),
                                   .init(color: ground, location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            }

            ScrollView {
                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.body.weight(.semibold))
                                .foregroundColor(BrandRuntime.style == .tabs ? IPTheme.muted : muted)
                                .frame(width: 44, height: 44)
                        }
                    }

                    if RegionPolicy.isFreedomRegion {
                        freeRegionNotice
                    } else if store.isPaid {
                        alreadyPaid
                    } else if BrandRuntime.style == .tabs {
                        tabsOffer
                    } else if BrandRuntime.style == .value {
                        valueOffer
                    } else {
                        offer
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 36)
            }
        }

        .preferredColorScheme(BrandRuntime.style == .tabs ? nil : .dark)
        .sheet(isPresented: $showTerms) { NavigationView { TermsOfUseView() } }
        .sheet(isPresented: $showPrivacy) { NavigationView { PrivacyPolicyView() } }

        .task { if !RegionPolicy.isFreedomRegion { await store.load(); anchorSelection() } }
        .onChange(of: store.products.map(\.id)) { _ in anchorSelection() }
    }

    private var offer: some View {
        VStack(spacing: 0) {
            Text("\(BrandRuntime.displayName.uppercased()) PREMIUM")
                .font(.caption2.weight(.semibold))
                .tracking(3)
                .foregroundColor(gold)
                .padding(.top, 6)

            Text("The fast lane out.")
                .font(.system(.title, design: .serif).weight(.semibold))
                .foregroundColor(ink)
                .multilineTextAlignment(.center)
                .padding(.top, 10)

            Text("Nothing in your way.")
                .font(.subheadline)
                .foregroundColor(muted)
                .multilineTextAlignment(.center)
                .padding(.top, 12)

            VStack(spacing: 14) {
                perk("\u{25C9}", "Every region", "Connect anywhere, switch anytime.")
                perk("\u{26A1}", "Full speed, always", "No cap, and never slowed down.")

                perk("\u{25A4}", "Our own hardware",
                     "Most VPNs rent cheap virtual servers. Ours sits inside the internet exchanges where the world's major networks meet — a shorter path, and a faster app.")
            }
            .padding(.top, 24)

            plans.padding(.top, 20)

            if let message {
                Text(message)
                    .font(.footnote).foregroundColor(muted)
                    .multilineTextAlignment(.center).padding(.top, 12)
            }

            Button { Task { await restore() } } label: {
                Text("Restore purchases").font(.subheadline).foregroundColor(muted)
            }
            .disabled(busy)
            .padding(.top, 18)

            renewalNote
                .padding(.top, 14)

            HStack(spacing: 14) {
                Button("Terms of Use") { showTerms = true }
                Text("\u{00B7}").foregroundColor(muted.opacity(0.5))
                Button("Privacy Policy") { showPrivacy = true }
            }
            .font(.caption)
            .foregroundColor(muted)
            .padding(.top, 10)
        }
    }

    private func perk(_ glyph: String, _ title: String, _ sub: String) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Text(glyph).font(.subheadline).foregroundColor(gold).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundColor(ink)
                Text(sub).font(.caption).foregroundColor(muted)
            }
            Spacer()
        }
    }

    /// The one product the hero can speak for: a SOLE annual plan.
    private var heroProduct: Product? {
        guard store.products.count == 1, let p = store.products.first,
              months(p) == 12 else { return nil }
        return p
    }

    private var valueOffer: some View {
        VStack(spacing: 0) {
            Text("Unlimited data, always full speed")
                .font(.title3.weight(.semibold))
                .foregroundColor(ink)
                .multilineTextAlignment(.center)
                .padding(.top, 4)

            if let hero = heroProduct, let perMonth = perMonthDisplay(hero) {
                priceHero(perMonth: perMonth, product: hero).padding(.top, 26)
                if let message { messageLine(message) }
                valueCta(hero).padding(.top, 28)
            } else {
                plans.padding(.top, 20)
                if let message { messageLine(message) }
            }

            Text("No account or email needed.")
                .font(.footnote)
                .foregroundColor(muted)
                .multilineTextAlignment(.center)
                .padding(.top, 12)

            renewalNote
                .padding(.top, 8)

            valuePerks.padding(.top, 26)

            Button { Task { await restore() } } label: {
                Text("Restore purchases")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(muted)
            }
            .disabled(busy)
            .padding(.top, 26)

            HStack(spacing: 14) {
                Button("Terms of Use") { showTerms = true }
                Text("\u{00B7}").foregroundColor(muted.opacity(0.5))
                Button("Privacy Policy") { showPrivacy = true }
            }
            .font(.caption)
            .foregroundColor(muted)
            .padding(.top, 12)
        }
    }

    /// One plan, stated once, in the design's type. No eyebrow, no "Premium", no
    /// comparison with a free tier the product does not have.
    private var tabsOffer: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Go Pro")
                .font(.system(size: 30, weight: .heavy))
                .tracking(-0.4)
                .foregroundColor(IPTheme.text)
            VStack(alignment: .leading, spacing: 10) {
                tabsCheck("Unlimited data, never slowed down")
                tabsCheck("Every region, switch anytime")
                tabsCheck("Our own hardware inside the internet exchanges")
            }
            if let p = store.products.first(where: { $0.id == selected }) ?? store.products.first {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.subscription?.subscriptionPeriod.unit == .year ? "Yearly" : "Monthly")
                            .font(.system(size: 15, weight: .bold)).foregroundColor(IPTheme.text)
                        Text(p.subscription?.subscriptionPeriod.unit == .year ? "per year" : "per month")
                            .font(.system(size: 12.5)).foregroundColor(IPTheme.muted)
                    }
                    Spacer()
                    Text(bidi(p.displayPrice)).font(.system(size: 22, weight: .heavy)).foregroundColor(IPTheme.text)
                }
                .padding(16)
                .background(ZStack {
                    IPTheme.surface
                    RadialGradient(colors: [IPTheme.glow, .clear], center: .topTrailing, startRadius: 4, endRadius: 200)
                })
                .clipShape(RoundedRectangle(cornerRadius: IPTheme.Radius.cardLarge, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: IPTheme.Radius.cardLarge, style: .continuous)
                    .stroke(IPTheme.accent.opacity(0.55), lineWidth: 1.5))
            } else if let why = store.unavailable {
                Text(why).font(.system(size: 13.5)).foregroundColor(IPTheme.muted)
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
            if let message {
                Text(message).font(.system(size: 13)).foregroundColor(IPTheme.muted)
            }

            if store.cashierUnreachable, !store.isPaid {
                HStack(spacing: 10) {
                    Text("Couldn't check your subscription.")
                        .font(.system(size: 13)).foregroundColor(IPTheme.muted)
                    Spacer(minLength: 6)
                    Button {
                        busy = true
                        Task {
                            await store.reconcileEntitlementAtLaunch()
                            busy = false
                            if store.isPaid { dismiss() }
                        }
                    } label: {
                        Text("Check again").font(.system(size: 13.5, weight: .semibold)).foregroundColor(IPTheme.accent)
                    }
                    .disabled(busy)
                }
            }
            Button { Task { await buySelected() } } label: {
                Text(busy ? "\u{2026}" : "Continue")
            }
            .buttonStyle(IPPrimaryButtonStyle())
            .disabled(busy || store.products.isEmpty)

            VStack(spacing: 10) {
                Text("Auto-renews until cancelled. Cancel anytime in Settings \u{203A} Apple ID \u{203A} Subscriptions.")
                    .font(.system(size: 11.5)).foregroundColor(IPTheme.dim).multilineTextAlignment(.center)
                Button { Task { await restore() } } label: {
                    Text("Restore purchases").font(.system(size: 13.5, weight: .semibold)).foregroundColor(IPTheme.accent)
                }
                .disabled(busy)
                HStack(spacing: 14) {
                    Button("Terms of Use") { showTerms = true }
                    Text("\u{00B7}").foregroundColor(IPTheme.dim)
                    Button("Privacy Policy") { showPrivacy = true }
                }
                .font(.system(size: 12))
                .foregroundColor(IPTheme.muted)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
        }
        .padding(.top, 8)
    }

    private func tabsCheck(_ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundColor(IPTheme.accent)
                .padding(.top, 2)
            Text(text).font(.system(size: 14.5)).foregroundColor(IPTheme.text)
        }
    }

    private func messageLine(_ text: String) -> some View {
        Text(text)
            .font(.footnote).foregroundColor(muted)
            .multilineTextAlignment(.center).padding(.top, 12)
    }

    /// The single-plan price lockup.
    private func priceHero(perMonth: String, product p: Product) -> some View {
        VStack(spacing: 0) {
            Text(bidi(perMonth))
                .font(.system(size: heroSize, weight: .black))
                .foregroundColor(ink)
                .lineLimit(1)

                .minimumScaleFactor(0.65)
                .multilineTextAlignment(.center)

            Text("per month")
                .font(.body.weight(.medium))
                .foregroundColor(muted)
                .padding(.top, 6)

            Text("\(bidi(p.displayPrice)) billed once a year")
                .font(.body.weight(.semibold))
                .foregroundColor(ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
        }
        .frame(maxWidth: .infinity)
    }

    /// The button, with the real charge appended.
    private func valueCta(_ p: Product) -> some View {
        Button { Task { await buySelected() } } label: {
            Group {
                if busy {
                    Text("\u{2026}")
                } else {
                    HStack(spacing: 7) {
                        Text("Go Premium")
                        Text("\u{00B7}")
                        Text(bidi(p.displayPrice))
                    }
                }
            }
            .font(.callout.weight(.bold))
            .foregroundColor(ctaInk)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)

            .background(LinearGradient(colors: [ctaTop, ctaBottom],
                                       startPoint: .top, endPoint: .bottom))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(busy)
    }

    /// Android's order, and Android's sentences.
    private var valuePerks: some View {
        VStack(spacing: 16) {
            valuePerk("infinity", "Unlimited data",

                      ConfigPolicy.paidOnly
                      ? "No cap and no allowance to count down."
                      : ConfigPolicy.quotaHardStop

                      ? "Your free data is a one-time allowance. Premium never runs out."
                      : "The free allowance renews every month. Premium has no cap.")
            valuePerk("bolt.fill", "Full speed, always",
                      "No cap, and never slowed down.")
            valuePerk("globe", "Every region",
                      "Connect anywhere, switch anytime.")
            valuePerk("square.stack.3d.up.fill", "Our own hardware",
                      "Most VPNs rent cheap virtual servers. Ours sits inside the internet exchanges where the world's major networks meet — a shorter path, and a faster app.")
        }
    }

    private func valuePerk(_ symbol: String,
                           _ title: LocalizedStringKey,
                           _ body: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(gold)
                .frame(width: 34, height: 34)
                .background(gold.opacity(0.16))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(ink)
                Text(body)
                    .font(.system(size: perkBodySize))

                    .lineSpacing(3)
                    .foregroundColor(muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    /// FIRST STRONG ISOLATE … POP DIRECTIONAL ISOLATE.
    private func bidi(_ s: String) -> String { "\u{2068}\(s)\u{2069}" }

    /// This plan's price expressed PER MONTH, in the store's own currency.
    private func perMonthDisplay(_ p: Product) -> String? {
        let m = months(p)
        guard m > 1 else { return nil }

        let nf = NumberFormatter()
        nf.numberStyle = .currency
        nf.currencyCode = p.priceFormatStyle.currencyCode
        let digits = max(0, nf.maximumFractionDigits)

        var raw = p.price / Decimal(m)
        var floored = Decimal()
        NSDecimalRound(&floored, &raw, digits, .down)
        guard floored > 0 else { return nil }
        return floored.formatted(p.priceFormatStyle)
    }

    private var plans: some View {
        VStack(spacing: 0) {
            if store.loading {
                ProgressView().tint(goldLite).padding(.vertical, 30)
            } else if let reason = store.unavailable {
                Text(reason).font(.subheadline).foregroundColor(muted)
                    .multilineTextAlignment(.center).padding(.vertical, 24)
            }

            ForEach(store.products.sorted { months($0) > months($1) }, id: \.id) { p in
                planRow(p)
            }

            if !store.products.isEmpty {
                Button { Task { await buySelected() } } label: {
                    Text(busy ? "\u{2026}" : "Continue")
                        .font(.callout.weight(.bold))

                        .foregroundColor(ctaInk)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(LinearGradient(colors: [ctaTop, ctaBottom],
                                                   startPoint: .top, endPoint: .bottom))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(busy || selected.isEmpty)
                .padding(.top, 16)
            }
        }
    }

    private func planRow(_ p: Product) -> some View {
        let isSel = p.id == selected
        return Button { selected = p.id } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.periodLabel)
                        .font(.subheadline.weight(.semibold)).foregroundColor(ink)
                    Text(periodCaption(p)).font(.caption).foregroundColor(muted)
                }
                Spacer()
                Text(p.displayPrice)
                    .font(.body.weight(.bold)).foregroundColor(ink)
            }
            .padding(16)
            .background(card)
            .overlay(RoundedRectangle(cornerRadius: 16)
                .stroke(isSel ? selectedEdge : line, lineWidth: isSel ? 2 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(alignment: .topTrailing) {
                if let b = savingsBadge(p) {
                    Text(b)
                        .font(.caption2.weight(.bold))
                        .foregroundColor(Deep.goldInk)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(goldLite).clipShape(Capsule())
                        .offset(x: layoutDirection == .rightToLeft ? 12 : -6, y: -6)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 6)
    }

    private var freeRegionNotice: some View {
        VStack(spacing: 14) {
            Image(systemName: "gift").font(.system(size: 44)).foregroundColor(goldLite)
            Text("\(BrandRuntime.displayName) is free in your region")
                .font(.title3.weight(.semibold)).foregroundColor(ink)
                .multilineTextAlignment(.center)
            Text("There is nothing to buy. Full speed, every region, no limits.")
                .font(.subheadline).foregroundColor(muted).multilineTextAlignment(.center)
        }
        .padding(.top, 70)
    }

    /// The one sentence a subscriber actually came here for: where to cancel or
    /// change plan.
    private var renewalNote: some View {
        Text("Auto-renews until cancelled. Cancel anytime in Settings \u{203A} Apple ID \u{203A} Subscriptions.")
            .font(.caption2)
            .foregroundColor(muted)
            .multilineTextAlignment(.center)
    }

    private var alreadyPaid: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44)).foregroundColor(goldLite)
            Text("Premium is active").font(.title3.weight(.semibold)).foregroundColor(ink)
            Text("Thank you for supporting an open internet.")
                .font(.subheadline).foregroundColor(muted)
            renewalNote.padding(.top, 10)
        }
        .padding(.top, 70)
    }

    private func months(_ p: Product) -> Int {
        guard let per = p.subscription?.subscriptionPeriod else { return 0 }
        switch per.unit {
        case .day:   return per.value >= 28 ? per.value / 30 : 0
        case .week:  return per.value >= 4 ? per.value / 4 : 0
        case .month: return per.value
        case .year:  return per.value * 12
        @unknown default: return 0
        }
    }

    private func periodCaption(_ p: Product) -> String {
        switch months(p) {
        case 1: return "per month"
        case 2: return "per 2 months"
        case 3: return "per 3 months"
        case 6: return "per 6 months"
        case 12: return "per year"
        default: return ""
        }
    }

    /// The value anchor: longest billing period, usually annual.
    private var anchorID: String {
        (store.products.max(by: { months($0) < months($1) }) ?? store.products.first)?.id ?? ""
    }

    /// Longest billing period is the value anchor, usually annual.
    private func anchorSelection() {
        guard !store.products.isEmpty else { return }

        if store.products.contains(where: { $0.id == selected }) { return }
        selected = (store.products.max(by: { months($0) < months($1) })
                    ?? store.products[0]).id
    }

    private func monthlyRate(_ p: Product) -> Decimal? {
        let m = months(p)
        return m > 0 ? p.price / Decimal(m) : nil
    }

    private func savingsBadge(_ p: Product) -> String? {
        guard p.id == anchorID,
              let mine = monthlyRate(p),
              let worst = store.products.compactMap(monthlyRate).max(),
              worst > 0, mine < worst else { return nil }
        let pct = ((worst - mine) / worst * 100 as NSDecimalNumber).intValue
        return pct >= 5 ? "SAVE \(pct)%" : nil
    }

    private func buySelected() async {
        guard let p = store.products.first(where: { $0.id == selected }) else { return }
        busy = true; message = nil
        defer { busy = false }
        switch await store.purchase(p) {
        case .entitled: dismiss()
        case .cancelled: break
        case .pending:
            message = "Waiting for approval. This will unlock automatically once approved."
        case .failed(let why): message = why
        }
    }

    private func restore() async {
        busy = true; message = nil
        defer { busy = false }
        message = await store.restore() ? nil : "No active subscription found for this account."
        if store.isPaid { dismiss() }
    }
}
