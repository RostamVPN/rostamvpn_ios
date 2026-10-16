// Copyright 2026 Internet Mastering & Company, Inc.
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import NetworkExtension
import RostamKit

/// Where the data comes from. One live source; a fixture in Debug so the screen
/// can be drawn on a simulator, which cannot run the tunnel.
protocol GuardianSource {
    func send(_ message: String) async -> GuardianSnapshot?
    /// The control-stream notes queued since the last call (drains), as JSON.
    func drainNotes() async -> String?
}

extension GuardianSource {
    func snapshot() async -> GuardianSnapshot? { await send(GuardianMessage.get) }
}

/// The running tunnel, via `sendProviderMessage`. nil when it is not up.
struct LiveGuardianSource: GuardianSource {
    func send(_ message: String) async -> GuardianSnapshot? {
        await raw(message).flatMap { try? JSONDecoder().decode(GuardianSnapshot.self, from: $0) }
    }

    func drainNotes() async -> String? {
        await raw(GuardianMessage.notes).flatMap { String(data: $0, encoding: .utf8) }
    }

    private func raw(_ message: String) async -> Data? {
        await withCheckedContinuation { c in
            NETunnelProviderManager.loadAllFromPreferences { managers, _ in
                guard let s = managers?.first(where: TunnelProfile.isOurs)?.connection as? NETunnelProviderSession,
                      s.status == .connected else { c.resume(returning: nil); return }
                do { try s.sendProviderMessage(Data(message.utf8)) { c.resume(returning: $0) } }
                catch { c.resume(returning: nil) }
            }
        }
    }
}

#if DEBUG
/// Sample data for drawing on a simulator. Only selected when the app-group key
/// `guardianFixture` is set; never in a Release build.
final class FixtureGuardianSource: GuardianSource {
    static let categories = ["malware": 0, "phishing": 1, "controller": 2, "scanner": 4, "rating_malicious": 5]

    /// Events at FIXED wall-clock times (minutes after local midnight), so secs_ago
    /// grows like the real ring's and the store does not take the same event twice
    /// across launches.
    private static func ago(_ minutesAfterMidnight: Double) -> Int {
        let at = Calendar.current.startOfDay(for: Date()).addingTimeInterval(minutesAfterMidnight * 60)
        return max(0, Int(Date().timeIntervalSince(at)))
    }

    private var snap = GuardianSnapshot(
        enabled: true, armed: true, sessionTotal: 3,
        byCategory: ["malware": 1, "phishing": 1, "controller": 1],
        recent: [
            GuardianEvent(host: "cdn-update.secure-login.top", port: 443, category: "phishing", secsAgo: ago(9),
                          reason: "Hosts a page imitating a bank login.", bits: 1 << 1, refused: true),
            GuardianEvent(host: "203.0.113.47", port: 8080, category: "controller", secsAgo: ago(7),
                          reason: "Controls infected devices that report to it.", bits: 1 << 2, refused: true),
            GuardianEvent(host: "198.51.100.23", port: 22, category: "scanner", secsAgo: ago(5),
                          reason: "Scans the internet for open ports.", bits: 1 << 4, refused: false),
            GuardianEvent(host: "files.dl-free-apk.icu", port: 443, category: "malware", secsAgo: ago(3),
                          reason: "Serves an installer that carries malware.", bits: 1 << 0, refused: true),
            GuardianEvent(host: "login-verify.example-bank.top", port: 443, category: "", secsAgo: ago(1),
                          reason: "domain", bits: 1 << 0, refused: true),
        ],
        allow: [], deny: ["ads.tracker.example"])
    private var notesSent = false
    /// Polls before the simulated exit acknowledges: the first snapshot is
    /// "Connected", later ones "Protected", as on a real session.
    private var polls = 0

    /// (event, minutes after local midnight): ages are computed when READ, as the
    /// real ring's are, so the same event lands on the same timestamp.
    private static let anchors: [(String, Double)] = [
        ("cdn-update.secure-login.top", 9), ("203.0.113.47", 7), ("198.51.100.23", 5),
        ("files.dl-free-apk.icu", 3), ("login-verify.example-bank.top", 1),
    ]

    func send(_ message: String) async -> GuardianSnapshot? {
        snap.recent = snap.recent.map { e in
            let m = Self.anchors.first { $0.0 == e.host }?.1 ?? 0
            return GuardianEvent(host: e.host, port: e.port, category: e.category, secsAgo: Self.ago(m),
                                 reason: e.reason, bits: e.bits, refused: e.refused)
        }
        if message.hasPrefix("guardian-rule:") {
            let p = message.split(separator: ":", maxSplits: 2).map(String.init)
            if p.count == 3 {
                snap.allow.removeAll { $0 == p[2] }; snap.deny.removeAll { $0 == p[2] }
                if p[1] == "allow" { snap.allow.append(p[2]) }
                if p[1] == "deny" { snap.deny.append(p[2]) }
            }
        } else if message.hasPrefix("guardian-enabled:") {
            snap.enabled = message.hasSuffix(":1"); snap.armed = snap.enabled
        }

        polls += 1
        if polls >= 2 {
            snap.capsAcknowledged = true
            snap.protectionEnabled = true
            snap.protectionListVersion = "20261012"
            snap.protectionFeedDate = "2026-10-12"
        }
        return snap
    }

    func drainNotes() async -> String? {
        guard !notesSent else { return "[]" }
        notesSent = true
        return """
        [{"seq":2,"ts":1791830001,"type":"notice","payload":{"title":"Faster route to Frankfurt","body":"A new exit is live. Nothing to do on your side."}}]
        """
    }
}
#endif

enum GuardianSources {
    static var current: GuardianSource {
        #if DEBUG
        if isFixture { return fixture }
        #endif
        return LiveGuardianSource()
    }
    #if DEBUG
    static var isFixture: Bool { BrandRuntime.defaults?.bool(forKey: "guardianFixture") == true }
    private static let fixture = FixtureGuardianSource()
    #endif

    /// OTA `protection.categories` (name -> bit). A Debug fixture run with no table
    /// published gets the sample one, so the toggles can be drawn.
    static var categories: [String: Int] {
        let t = ConfigPolicy.protectionCategories
        #if DEBUG
        if t.isEmpty, isFixture { return FixtureGuardianSource.categories }
        #endif
        return t
    }

    /// Categories the user switched off, as verdict bits. Kept in the app group so
    /// the extension re-sends it on every connect.
    static var categoriesOff: Int {
        get { BrandRuntime.defaults?.integer(forKey: GuardianMessage.categoriesOffKey) ?? 0 }
        set { BrandRuntime.defaults?.set(newValue & 0xFFFF, forKey: GuardianMessage.categoriesOffKey) }
    }
}

/// The user's rules as the extension persists them (app group), so an edit made
/// while disconnected is kept and replayed.
enum GuardianLocalRules {
    static func load() -> (allow: [String], deny: [String]) {
        guard let s = BrandRuntime.defaults?.string(forKey: GuardianMessage.rulesKey),
              let o = (try? JSONSerialization.jsonObject(with: Data(s.utf8))) as? [String: Any]
        else { return ([], []) }
        return (o["allow"] as? [String] ?? [], o["deny"] as? [String] ?? [])
    }

    /// Same normalisation as the core's set_user_rule.
    static func normalise(_ host: String) -> String {
        var h = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while h.hasPrefix("*.") { h.removeFirst(2) }
        return h.trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    static func apply(_ verdict: String, host: String) {
        let h = normalise(host)
        guard !h.isEmpty else { return }
        var (allow, deny) = load()
        allow.removeAll { $0 == h }
        deny.removeAll { $0 == h }
        if verdict == "allow" { allow.append(h) }
        if verdict == "deny" { deny.append(h) }
        let o: [String: Any] = ["allow": allow, "deny": deny]
        if let d = try? JSONSerialization.data(withJSONObject: o), let s = String(data: d, encoding: .utf8) {
            BrandRuntime.defaults?.set(s, forKey: GuardianMessage.rulesKey)

            BrandRuntime.defaults?.set(Date().timeIntervalSince1970, forKey: GuardianMessage.rulesUpdatedKey)
        }
    }

    static var enabled: Bool? {
        get { BrandRuntime.defaults?.object(forKey: GuardianMessage.enabledKey) as? Bool }
        set { BrandRuntime.defaults?.set(newValue, forKey: GuardianMessage.enabledKey) }
    }

    /// Persist first, then tell the running tunnel. nil when it is not up; the edit
    /// is kept either way.
    static func send(_ source: GuardianSource, verdict: String, host: String) async -> GuardianSnapshot? {
        apply(verdict, host: host)
        return await source.send(GuardianMessage.rule(verdict, host: normalise(host)))
    }
}

/// Category words: the OTA bit table first, the feed's tag ids second.
enum GuardianCategory {
    static func label(bits: Int, fallback id: String) -> String {
        if bits != 0, let name = GuardianSources.categories
            .sorted(by: { $0.value < $1.value })
            .first(where: { bits & (1 << $0.value) != 0 })?.key {
            return label(name)
        }
        return label(id)
    }

    /// A category id from the feed or the OTA table, in words. Unknown ids are
    /// humanised (underscores to spaces) rather than shown raw.
    static func label(_ id: String) -> String {
        switch id.lowercased() {
        case "rating_malicious": return String(localized: "Rated malicious")
        case "domain": return String(localized: "Known bad site")
        case "malware": return String(localized: "Malware")
        case "phishing": return String(localized: "Phishing")
        case "controller": return String(localized: "Controls infected devices")
        case "orb": return String(localized: "Hijacked relay network")
        case "scanner": return String(localized: "Scanner")
        case "proxy": return String(localized: "Open proxy")
        case "": return String(localized: "Blocked")
        default:
            let words = id.replacingOccurrences(of: "_", with: " ")
            return words.prefix(1).uppercased() + words.dropFirst()
        }
    }
}

struct IPGuardianSheet: View {
    let source: GuardianSource
    @ObservedObject private var center = GuardianCenter.shared
    @Environment(\.dismiss) private var dismiss
    @State private var snap: GuardianSnapshot?
    @State private var rows: [GuardStore.Row] = []
    /// Bumped after an edit made while disconnected, to re-read local rules.
    @State private var localTick = 0
    @State private var openRules = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    summary
                    if !rows.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                                if i > 0 { Divider().background(IPTheme.border) }
                                row(r)
                            }
                        }
                        .ipCard(radius: IPTheme.Radius.cardLarge, padding: 0)
                    } else {
                        IPEmptyState(title: "Nothing blocked yet",
                                     systemImage: "checkmark.circle",
                                     message: "Refused connections appear here, newest first. They stay on this phone for 30 days and are never sent anywhere.")
                            .ipCard(radius: IPTheme.Radius.cardLarge)
                    }
                    NavigationLink(isActive: $openRules) {
                        IPGuardianRules(source: source, snap: $snap)
                    } label: {
                        HStack {
                            Text("Rules").font(.system(size: 14.5, weight: .bold)).foregroundColor(IPTheme.text)
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundColor(IPTheme.dim)
                        }
                        .ipCard()
                    }
                    .buttonStyle(.plain)
                }
                .padding(20)
            }
            .background(IPTheme.bg.ignoresSafeArea())
            .navigationTitle("Guardian")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
        .navigationViewStyle(.stack)
        .tint(IPTheme.accent)
        .task {
            center.loadToday()
            await center.poll(source)
            snap = await source.snapshot()
            #if DEBUG

            if BrandRuntime.defaults?.bool(forKey: "debugRules") == true {
                BrandRuntime.defaults?.removeObject(forKey: "debugRules")
                openRules = true
            }
            #endif
        }
        .refreshable { await center.poll(source); snap = await source.snapshot() }
        .onReceive(center.$revision) { _ in GuardStore.shared.recent { rows = $0 } }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(format: String(localized: "guardian_blocked_today", defaultValue: "%lld blocked today"),
                        center.blockedToday))
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundColor(IPTheme.text)
            Text(snap?.armed == false
                 ? "Protection is off. Turn it on in Rules."
                 : "Known malware, phishing and hijacked hosts are refused before they reach your phone.")
                .font(.system(size: 13.5))
                .foregroundColor(IPTheme.muted)
            if let p = center.protection, !p.feedDate.isEmpty {
                Text(String(format: String(localized: "guardian_list_date", defaultValue: "Protection list from %@"),
                            Self.feedDate(p.feedDate)))
                    .font(.system(size: 12))
                    .foregroundColor(IPTheme.dim)
            }
        }
    }

    private static func feedDate(_ s: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: s) else { return s }
        return d.formatted(date: .abbreviated, time: .omitted)
    }

    private func row(_ r: GuardStore.Row) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(r.host).font(.system(size: 14.5, weight: .bold)).foregroundColor(IPTheme.text)
                        .lineLimit(1).truncationMode(.middle)
                    if !r.refused {
                        Text("Noticed")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundColor(IPTheme.muted)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(IPTheme.surface2)
                            .clipShape(Capsule())
                    }
                }
                Text("\(GuardianCategory.label(bits: r.bits, fallback: r.reason)) · \(String(r.port)) · \(relative(r.ts))")
                    .font(.system(size: 12)).foregroundColor(IPTheme.dim)
                if !r.reason.isEmpty, r.reason.contains(" ") {
                    Text(r.reason).font(.system(size: 12.5)).foregroundColor(IPTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if allowSet.contains(r.host) {
                Text("Allowed").font(.system(size: 12.5, weight: .semibold)).foregroundColor(IPTheme.dim)
            } else {
                Button("Allow") {
                    Task {
                        if let s = await GuardianLocalRules.send(source, verdict: "allow", host: r.host) { snap = s }
                        localTick += 1
                    }
                }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(IPTheme.accent)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .overlay(Capsule().stroke(IPTheme.border, lineWidth: 1))
                    .accessibilityLabel(Text("Allow \(r.host)"))
            }
        }
        .padding(14)
    }

    /// Live lists when connected, the persisted ones otherwise.
    private var allowSet: Set<String> {
        _ = localTick
        return Set(snap?.allow ?? GuardianLocalRules.load().allow)
    }

    private func relative(_ at: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: at, relativeTo: Date())
    }

    private func send(_ m: String) async {
        if let s = await source.send(m) { snap = s }
    }
}

struct IPGuardianRules: View {
    let source: GuardianSource
    @Binding var snap: GuardianSnapshot?
    @State private var newDeny = ""
    /// Bumped after an edit made while disconnected, to re-read local rules.
    @State private var localTick = 0
    private var lists: (allow: [String], deny: [String]) {
        _ = localTick
        if let snap { return (snap.allow, snap.deny) }
        return GuardianLocalRules.load()
    }
    @State private var offMask = GuardianSources.categoriesOff

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Toggle(isOn: Binding(
                    get: { _ = localTick; return snap?.enabled ?? GuardianLocalRules.enabled ?? true },
                    set: { on in
                        GuardianLocalRules.enabled = on
                        localTick += 1
                        Task { await send(GuardianMessage.enabled(on)) }
                    })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Protection").font(.system(size: 15, weight: .bold)).foregroundColor(IPTheme.text)
                        Text("Refuse known malware, phishing and hijacked hosts.")
                            .font(.system(size: 12.5)).foregroundColor(IPTheme.muted)
                    }
                }
                .tint(IPTheme.accent)
                .ipCard()

                let table = GuardianSources.categories
                if !table.isEmpty {
                    section("Categories") {
                        ForEach(table.sorted { $0.key < $1.key }, id: \.key) { name, bit in
                            Toggle(GuardianCategory.label(name), isOn: Binding(
                                get: { offMask & (1 << bit) == 0 },
                                set: { on in
                                    offMask = on ? offMask & ~(1 << bit) : offMask | (1 << bit)
                                    GuardianSources.categoriesOff = offMask
                                    Task { _ = await source.send(GuardianMessage.categoriesOff(offMask)) }
                                }))
                            .font(.system(size: 14))
                            .foregroundColor(IPTheme.text)
                            .tint(IPTheme.accent)
                        }
                    }
                }

                section("Always allow") {
                    if lists.allow.isEmpty {
                        Text("Sites you allow from the timeline appear here.")
                            .font(.system(size: 13)).foregroundColor(IPTheme.dim)
                    }
                    ForEach(lists.allow, id: \.self) { host in ruleRow(host) }
                }

                section("Always block") {
                    ForEach(lists.deny, id: \.self) { host in ruleRow(host) }
                    HStack(spacing: 8) {
                        TextField("example.com", text: $newDeny)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .font(.system(size: 14))
                            .foregroundColor(IPTheme.text)
                        Button("Add") {
                            let h = newDeny.trimmingCharacters(in: .whitespaces)
                            newDeny = ""
                            guard !h.isEmpty else { return }
                            Task { await rule("deny", h) }
                        }
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundColor(IPTheme.accent)
                    }
                }

                if snap == nil {
                    Text("Changes apply the next time you connect.")
                        .font(.system(size: 12.5)).foregroundColor(IPTheme.dim)
                }
            }
            .padding(20)
        }
        .background(IPTheme.bg.ignoresSafeArea())
        .navigationTitle("Rules")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func section<C: View>(_ title: LocalizedStringKey, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 12.5, weight: .bold)).foregroundColor(IPTheme.muted)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ipCard()
    }

    private func ruleRow(_ host: String) -> some View {
        HStack {
            Text(host).font(.system(size: 14)).foregroundColor(IPTheme.text).lineLimit(1).truncationMode(.middle)
            Spacer()
            Button { Task { await rule("clear", host) } } label: {
                Image(systemName: "xmark.circle.fill").foregroundColor(IPTheme.dim)
            }
            .accessibilityLabel(Text("Remove \(host)"))
        }
    }

    private func send(_ m: String) async {
        if let s = await source.send(m) { snap = s }
    }

    private func rule(_ verdict: String, _ host: String) async {
        if let s = await GuardianLocalRules.send(source, verdict: verdict, host: host) { snap = s }
        localTick += 1
    }
}
