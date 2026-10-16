// Copyright 2026 Internet Mastering & Company, Inc.
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import StoreKit
import RostamKit

/// The main-screen upgrade offer and free-tier data bar.
struct PremiumBanner: View {
    let reducedSpeed: Bool
    let onUpgrade: () -> Void

    /// Prices come from StoreKit, so this shows a real number or none at all --
    /// never a hardcoded one that could disagree with what the sheet charges.
    @ObservedObject private var store = Store.shared

    /// THE VALUE ANCHOR: the LONGEST billing period, which is what `PaywallView`
    /// already picks.
    private var anchor: Product? {
        store.products.max(by: { months($0) < months($1) })
    }

    /// Months in a plan's period. Same derivation as the paywall's, because a
    /// banner that disagreed with the sheet it opens is worse than no banner.
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

    /// Headline. While throttled it NAMES THE STATE rather than pitching: the user
    /// is feeling the slowdown right now and the first thing they need is to know
    /// it is a plan limit, not the app failing.
    private var title: String {
        reducedSpeed
            ? NSLocalizedString("premium_title_throttled", value: "Speed reduced",
                                comment: "Banner headline while throttled")
            : NSLocalizedString("premium_title", value: "Go Premium",
                                comment: "Banner headline")
    }

    private var subtitle: String {
        let benefit = reducedSpeed
            ? NSLocalizedString("premium_sub_throttled",
                                value: "Upgrade for full speed \u{00B7} no data limit",
                                comment: "Shown while throttled")
            : NSLocalizedString("premium_sub_default",
                                value: "Full speed always \u{00B7} choose any region",
                                comment: "Premium benefits")
        guard let p = anchor else { return benefit }
        let m = months(p)
        guard m > 0 else { return benefit }

        let period = m >= 12
            ? NSLocalizedString("premium_per_year", value: "per year",
                                comment: "Billing period, annual plan")
            : NSLocalizedString("premium_per_month", value: "per month",
                                comment: "Billing period, monthly plan")
        var out = String(format: NSLocalizedString("premium_sub_priced",
                                                   value: "%1$@ \u{00B7} just %2$@ %3$@",
                                                   comment: "%1$@ benefit, %2$@ price, %3$@ period"),
                         benefit, p.displayPrice, period)

        if m >= 12, p.price / Decimal(m) < 1 {
            let oneUnit = Decimal(1).formatted(p.priceFormatStyle)
            out += " " + String(format: NSLocalizedString("premium_under_per_month",
                                                          value: "Less than %1$@/month.",
                                                          comment: "%1$@ one unit of currency"),
                                oneUnit)
        }
        return out
    }

    private let tealDark = Deep.ground
    private let tealLight = Deep.top
    private let muted = Deep.muted
    private let gold = Deep.gold
    private let goldLight = Deep.goldLite
    private let goldPillText = Deep.goldInk

    var body: some View {
        if BrandRuntime.style == .rings {
            upgradePill
        } else {
            classicBanner
        }
    }

    /// THE UPGRADE PILL -- the design's own, and the loudest thing on the screen
    /// after the dial.
    private var upgradePill: some View {
        Button(action: onUpgrade) {
            HStack(spacing: 10) {
                Image(systemName: reducedSpeed ? "tortoise.fill" : "star.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.22))
                    .clipShape(Circle())
                    .accessibilityHidden(true)

                Text(reducedSpeed ? "Restore" : "Upgrade")
                    .font(.title3.weight(.bold))
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                LinearGradient(colors: [BrandTheme.accent, BrandTheme.primary],
                               startPoint: .leading, endPoint: .trailing)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var classicBanner: some View {
        Button(action: onUpgrade) {
            HStack(spacing: 12) {
                Text(reducedSpeed ? "\u{1F422}" : "\u{2605}")
                    .font(.title3.weight(.bold))
                    .foregroundColor(goldLight)
                    .frame(width: 40, height: 40)
                    .background(gold.opacity(0.16))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.callout.weight(.bold))
                        .foregroundColor(goldLight)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)

                Text(reducedSpeed ? "Restore" : "Upgrade")
                    .font(.footnote.weight(.bold))
                    .foregroundColor(goldPillText)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(
                        LinearGradient(colors: [goldLight, gold],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                LinearGradient(colors: [tealDark, tealLight],
                               startPoint: .leading, endPoint: .trailing)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

/// Free-tier allowance, as a bar that can be watched draining.
struct DataUsageBar: View {
    let usedMB: Int64
    let quotaMB: Int64
    let overQuota: Bool
    let reducedSpeed: Bool
    let onUpgrade: () -> Void

    private var fraction: Double {
        guard quotaMB > 0 else { return 0 }
        return min(max(Double(usedMB) / Double(quotaMB), 0), 1)
    }
    private var remainingMB: Int64 { max(quotaMB - usedMB, 0) }
    /// "Low" is where the bar becomes a call to action rather than a readout.
    private var low: Bool { overQuota || fraction >= 0.8 }
    /// Fill colour.
    private var accent: Color {
        low ? .warningOnCard : .brandOnCard
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                HStack(spacing: 4) {
                    if reducedSpeed {
                        Image(systemName: "tortoise.fill")
                            .font(.caption2)
                            .foregroundColor(accent)
                    }
                    Text(reducedSpeed ? "Reduced speed" : "Free data")
                        .font(.caption2)
                        .foregroundColor(reducedSpeed ? accent : .secondary)
                }
                Spacer()

                Text(overQuota
                     ? "Free data used"
                     : "\(UsageStatsView.fmtBytes(remainingMB * 1_000_000)) of \(UsageStatsView.fmtBytes(quotaMB * 1_000_000))")
                    .font(.caption2)
                    .foregroundColor(accent)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.32))
                    Capsule().fill(accent)

                        .frame(width: max(geo.size.width * fraction,
                                          fraction > 0 ? 6 : 0))
                }
            }
            .frame(height: 4)

            Group {
                if overQuota && ConfigPolicy.quotaHardStop {
                    Text("Free data used up — upgrade for more")
                } else if overQuota {
                    Text("Still free at up to \(ConfigPolicy.freeSpeedLabel). Upgrade for full speed.")
                } else if low {
                    Text("Upgrade to stay at full speed.")
                } else if !ConfigPolicy.freeSpeedLabel.isEmpty {
                    Text("After that, a reduced speed of up to \(ConfigPolicy.freeSpeedLabel). Still free.")
                }
            }
            .font(.caption2)
            .foregroundColor(low ? accent : .secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .contentShape(Rectangle())
        .onTapGesture { if low { onUpgrade() } }
    }
}
