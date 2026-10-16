// Copyright 2026 Internet Mastering & Company, Inc.
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// Region selection, on the MAIN screen — a port of Android's
/// RegionSelectionCard.kt and the locked card beside it in MainScreen.kt.
struct RegionCard: View {
    @Binding var selectedRegion: String
    let regions: [(String, String)]
    let mayPick: Bool
    let usage: CashierApi.UsageStatus?
    let reducedSpeed: Bool
    let onUpgrade: () -> Void
    /// Region is only read when the tunnel STARTS, so selecting one while connected
    /// changed nothing and said nothing. The caller reconnects.
    let onPicked: (String) -> Void

    @State private var showSheet = false

    private var selectedLabel: String {
        selectedRegion == "auto"
            ? String(localized: "Automatic")
            : regions.first { $0.0 == selectedRegion }?.1 ?? selectedRegion.uppercased()
    }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: { mayPick ? (showSheet = true) : onUpgrade() }) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Region")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if mayPick {
                            Text(selectedLabel)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.brandOnCard)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(selectedRegion == "auto"
                                 ? "Picks the fastest working region"
                                 : "Connect via this location")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text("Automatic — choose a region with Premium")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer()
                    if mayPick {
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .accessibilityHidden(true)
                    } else {
                        Text("\u{1F512}").font(.title3).accessibilityHidden(true)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(mayPick ? Text("Region, \(selectedLabel)")
                                        : Text("Region locked, Premium required"))
            .accessibilityHint(mayPick ? Text("Choose a server region")
                                       : Text("Opens Premium"))

            if !mayPick, !ConfigPolicy.paidOnly, let u = usage, !u.unlimited, !u.paid, u.freeQuotaMB > 0 {
                Divider().background(Color.secondary.opacity(0.12))
                DataUsageBar(usedMB: u.usedMB,
                             quotaMB: u.freeQuotaMB,
                             overQuota: u.overQuota,
                             reducedSpeed: reducedSpeed,
                             onUpgrade: onUpgrade)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
        }
        .background(Color.adaptiveCard)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.06), radius: 8, y: 2)
        .sheet(isPresented: $showSheet) { regionSheet }
    }

    private var regionSheet: some View {
        NavigationView {
            List {
                row("auto", String(localized: "Automatic"),
                    String(localized: "Picks the fastest working region"))
                ForEach(regions, id: \.0) { id, label in
                    row(id, label, String(localized: "Connect via this location"))
                }
            }
            .navigationTitle("Region")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { showSheet = false }
                }
            }
        }
    }

    private func row(_ id: String, _ label: String, _ hint: String) -> some View {
        Button {
            let changed = selectedRegion != id
            selectedRegion = id
            showSheet = false
            if changed { onPicked(id) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).foregroundColor(.primary)
                    Text(hint).font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                if selectedRegion == id {
                    Image(systemName: "checkmark")
                        .foregroundColor(.brandGraphicOnCard)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selectedRegion == id ? [.isButton, .isSelected] : .isButton)
    }
}
