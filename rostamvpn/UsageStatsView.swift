// Copyright 2026 Internet Mastering & Company, Inc.
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// Data usage. Mirrors Android's DataUsageScreen card for card.
struct UsageStatsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var usage: CashierApi.UsageStatus?

    let sessionRx: String
    let sessionTx: String
    let lifetimeBytes: Int64

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                statCard("Total data used", Self.fmtBytes(lifetimeBytes))

                statCard("This session",
                         "\u{2193} \(sessionRx.isEmpty ? "0 B" : sessionRx)   "
                         + "\u{2191} \(sessionTx.isEmpty ? "0 B" : sessionTx)",
                         sub: sessionRx.isEmpty && sessionTx.isEmpty
                              ? "Not connected" : nil)

                if let u = usage, u.paid || u.unlimited {
                    statCard("Plan", u.paid ? "Premium" : "Unlimited",
                             sub: "No data limit")
                } else if let u = usage, !ConfigPolicy.paidOnly {
                    let used = max(u.usedMB, 0) * 1_000_000
                    let quota = max(u.freeQuotaMB, 0) * 1_000_000
                    statCard("Free allowance",
                             "\(Self.fmtBytes(used)) / \(Self.fmtBytes(quota))",
                             sub: u.overQuota
                                ? "Free data used up — upgrade for more"
                                : "\(Self.fmtBytes(max(quota - used, 0))) left",
                             alert: u.overQuota)
                }

                Text("Total is measured on this device across all sessions.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
            .padding(24)
        }
        .navigationTitle("Usage stats")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            CashierApi.usage { u in
                DispatchQueue.main.async { usage = u }
            }
        }
    }

    private func statCard(_ label: String, _ value: String,
                          sub: String? = nil, alert: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundColor(alert ? .dangerRed : .primary)
            if let sub {
                Text(sub)
                    .font(.caption)
                    .foregroundColor(alert ? .dangerRed : .secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.adaptiveCard)
        .cornerRadius(16)
    }

    /// Decimal units, matching the server's MB (1e6), not MiB. Mixing the two is
    /// how a 1024 MB cap once rendered as "1 GB" while actually being 1.07.
    static func fmtBytes(_ b: Int64) -> String {
        let d = Double(b)
        if d >= 1e9 { return String(format: "%.2f GB", d / 1e9) }
        if d >= 1e6 { return String(format: "%.1f MB", d / 1e6) }
        if d >= 1e3 { return String(format: "%.0f KB", d / 1e3) }
        return "\(b) B"
    }
}
