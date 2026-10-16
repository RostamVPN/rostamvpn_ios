// Copyright 2026 Internet Mastering & Company, Inc.
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import RostamKit

/// The ring's three states. Named apart from the app's `ConnectPhase`, which is
/// the connect-progress helper used by the other treatments.
enum IPRingPhase { case off, connecting, on }

/// Connect, as the locked design draws it: the 186 pt ring, ONE status line
/// under it that is always true, throughput only when it is real, and a read-
/// only route card.
struct IPConnectTab: View {
    let phase: IPRingPhase
    let errorText: String?
    let isPro: Bool
    let connectedSince: Date?
    let downRate: String
    let upRate: String
    let routeLabel: String
    let blockedToday: Int?
    /// The exit acknowledged protection on this session (GuardianCenter).
    var protectionAcknowledged = false
    /// An operator notice from the control stream: one quiet row, never a push.
    var notice: GuardianCenter.Notice?
    var onDismissNotice: () -> Void = {}
    let onToggle: () -> Void
    let onGoPro: () -> Void
    let onStatusTap: () -> Void

    var body: some View {
        ZStack {
            background.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar.padding(.horizontal, 20).padding(.top, 8)
                if let notice { noticeRow(notice).padding(.horizontal, 20).padding(.top, 10) }
                ScrollView {
                    VStack(spacing: 22) {
                        IPRingDial(phase: phase, action: onToggle).padding(.top, 26)
                        statusLine
                        if phase == .on, !downRate.isEmpty, !upRate.isEmpty { statsRow }
                        routeCard
                        if phase == .on {
                            Button("Disconnect", action: onToggle).buttonStyle(IPOutlineButtonStyle())
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 24)
                }
            }
        }
    }

    private var topBar: some View {
        HStack {
            HStack(spacing: 8) {
                IPLogoTile(size: 22)
                Text(BrandRuntime.displayName)
                    .font(.system(size: 16, weight: .heavy))
                    .tracking(-0.2)
                    .foregroundColor(IPTheme.text)
            }
            Spacer()
            planChip
        }
    }

    /// PRO when entitled; otherwise "Go Pro", which opens the one plan. The fork's
    /// "Free" chip is gone: this product has no free tier.
    @ViewBuilder private var planChip: some View {
        if isPro {
            Text(verbatim: "PRO")
                .font(.system(size: 11.5, weight: .bold))
                .foregroundColor(IPTheme.accentStrong)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(IPTheme.accent.opacity(0.14))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(IPTheme.accent.opacity(0.34), lineWidth: 1))
        } else {
            Button(action: onGoPro) {
                Text("Go Pro")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(IPTheme.onAccent)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(IPTheme.accent)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private func noticeRow(_ n: GuardianCenter.Notice) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                if !n.title.isEmpty {
                    Text(n.title).font(.system(size: 13.5, weight: .bold)).foregroundColor(IPTheme.text)
                }
                if !n.body.isEmpty {
                    Text(n.body).font(.system(size: 12.5)).foregroundColor(IPTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let url = n.url, url.scheme?.lowercased() == "https" {
                    Link("Open", destination: url).font(.system(size: 12.5, weight: .semibold)).foregroundColor(IPTheme.accent)
                }
            }
            Spacer(minLength: 6)
            Button(action: onDismissNotice) {
                Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundColor(IPTheme.dim)
                    .frame(width: 28, height: 28)
            }
            .accessibilityLabel(Text("Dismiss"))
        }
        .ipCard(padding: 12)
    }

    private var background: some View {
        ZStack {
            IPTheme.bg
            if phase != .off {
                RadialGradient(colors: [IPTheme.glow, .clear], center: .top, startRadius: 10, endRadius: 320)
            }
        }
    }

    /// "Protected · N blocked today" only when the tunnel is up AND the exit has
    /// acknowledged protection on this session; "Connected" otherwise while up;
    /// "Off" when down. Never a claim the app cannot back.
    private var statusText: String {
        switch phase {
        case .connecting: return String(localized: "Connecting…")
        case .off: return errorText ?? String(localized: "Off")
        case .on:

            if protectionAcknowledged, let n = blockedToday {
                return String(format: String(localized: "status_protected_blocked",
                                             defaultValue: "Protected · %lld blocked today"), n)
            }
            return String(localized: "Connected")
        }
    }

    private var statusLine: some View {
        Button(action: onStatusTap) {
            HStack(spacing: 6) {
                Text(statusText)
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundColor(phase == .off && errorText != nil ? .red : IPTheme.text)
                    .multilineTextAlignment(.center)
                if phase == .on {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(IPTheme.dim)
                }
            }
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .disabled(phase != .on)
        .accessibilityHint(phase == .on ? Text("Shows what was blocked") : Text(""))
    }

    private var statsRow: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            HStack(spacing: 9) {
                IPStatCard(title: "Elapsed", value: elapsed(at: ctx.date), valueColor: IPTheme.text, mono: true)
                IPStatCard(title: "Download", value: downRate, valueColor: IPTheme.accent)
                IPStatCard(title: "Upload", value: upRate, valueColor: IPTheme.text)
            }
        }
    }

    private func elapsed(at now: Date) -> String {
        guard let since = connectedSince else { return "00:00:00" }
        let s = max(0, Int(now.timeIntervalSince(since)))
        return String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }

    /// Read-only, per the approved direction, until the server has a region
    /// contract for this brand.
    private var routeCard: some View {
        HStack {
            Label("Route", systemImage: "location.fill")
                .font(.system(size: 13.5))
                .foregroundColor(IPTheme.muted)
            Spacer()
            Text(routeLabel)
                .font(.system(size: 13.5, weight: .bold))
                .foregroundColor(IPTheme.text)
        }
        .padding(.horizontal, 0)
        .ipCard()
        .accessibilityElement(children: .combine)
    }
}

/// 186 pt, exactly as the July fork draws it (ConnectView.swift @43f3415).
struct IPRingDial: View {
    let phase: IPRingPhase
    let action: () -> Void

    private let diameter: CGFloat = 186
    private let lineWidth: CGFloat = 10
    private let spinPeriod: TimeInterval = 1.4

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().stroke(IPTheme.border, lineWidth: lineWidth)
                switch phase {
                case .off:
                    EmptyView()
                case .connecting:

                    TimelineView(.animation) { ctx in
                        let p = ctx.date.timeIntervalSinceReferenceDate
                            .truncatingRemainder(dividingBy: spinPeriod) / spinPeriod
                        Circle()
                            .trim(from: 0, to: 0.3)
                            .stroke(IPTheme.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                            .rotationEffect(.degrees(p * 360))
                    }
                case .on:
                    Circle()
                        .stroke(IPTheme.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .shadow(color: IPTheme.glow, radius: 22)
                }
                core
            }
            .frame(width: diameter, height: diameter)
        }
        .buttonStyle(.plain)

        .accessibilityLabel(phase == .off ? Text("Connect") : Text("Disconnect"))
    }

    private var core: some View {
        Circle()
            .fill(phase == .on
                  ? AnyShapeStyle(RadialGradient(colors: [IPTheme.accent.opacity(0.22), IPTheme.surface],
                                                 center: .center, startRadius: 4, endRadius: 66))
                  : AnyShapeStyle(IPTheme.surface))
            .overlay(Circle().stroke(phase == .on ? IPTheme.accent.opacity(0.4) : IPTheme.border, lineWidth: 1))
            .frame(width: 132, height: 132)
            .overlay(glyph)
            .shadow(color: phase == .on ? IPTheme.glow : .clear, radius: 24)
    }

    @ViewBuilder private var glyph: some View {
        switch phase {
        case .off:
            Image(systemName: "power").font(.system(size: 44, weight: .semibold)).foregroundColor(IPTheme.dim)
        case .connecting:
            Image(systemName: "power").font(.system(size: 44, weight: .semibold)).foregroundColor(IPTheme.accent)
        case .on:
            Image(systemName: "checkmark").font(.system(size: 44, weight: .bold)).foregroundColor(IPTheme.accent)
        }
    }
}

struct IPStatCard: View {
    let title: LocalizedStringKey
    let value: String
    let valueColor: Color
    var mono = false

    var body: some View {
        VStack(spacing: 3) {
            Text(title).font(.system(size: 11)).foregroundColor(IPTheme.dim)
            Text(value)
                .font(mono ? .system(size: 15, weight: .heavy).monospacedDigit() : .system(size: 15, weight: .heavy))
                .foregroundColor(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
        .background(IPTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: IPTheme.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: IPTheme.Radius.card, style: .continuous).stroke(IPTheme.border, lineWidth: 1))
    }
}
