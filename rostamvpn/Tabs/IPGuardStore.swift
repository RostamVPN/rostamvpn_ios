// Copyright 2026 Internet Mastering & Company, Inc.
// SPDX-License-Identifier: Apache-2.0

import Foundation
import UserNotifications
import RostamKit

/// Refused and noticed connections, kept on this device so the Guardian
/// timeline survives restarts and Connect can say "N blocked today".
final class GuardStore {
    struct Row: Codable, Hashable, Identifiable {
        let host: String
        let port: Int
        let bits: Int
        let reason: String
        let ts: Date
        let refused: Bool
        var id: String { "\(host):\(port):\(refused):\(ts.timeIntervalSince1970)" }
        /// Event identity without the time: what the 2 s window is checked within.
        var key: String { "\(host)\u{1F}\(port)\u{1F}\(refused)" }
    }

    static let shared = GuardStore()
    static let maxRows = 2000
    static let maxAge: TimeInterval = 30 * 24 * 60 * 60

    private let queue = DispatchQueue(label: "guard.store", qos: .utility)
    private let url: URL

    private var loaded = false
    private var rows: [Row] = []
    private var index: [String: [Date]] = [:]

    init(url: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("guard-events.json")) {
        self.url = url
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        rows = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([Row].self, from: $0) } ?? []
        rebuildIndex()
    }

    private func rebuildIndex() {
        index = [:]
        for r in rows { index[r.key, default: []].append(r.ts) }
    }

    /// Insert ring entries not already stored, prune, and report today's refused
    /// count. Completion on the main queue.
    func addAll(_ new: [Row], now: Date = Date(), completion: @escaping (Int) -> Void) {
        queue.async {
            self.loadIfNeeded()
            var inserted = false
            for r in new {
                if let seen = self.index[r.key], seen.contains(where: { abs($0.timeIntervalSince(r.ts)) <= 2 }) { continue }
                self.rows.append(r)
                self.index[r.key, default: []].append(r.ts)
                inserted = true
            }
            if inserted {
                self.rows.sort { $0.ts > $1.ts }
                self.rows.removeAll { now.timeIntervalSince($0.ts) > Self.maxAge }
                if self.rows.count > Self.maxRows { self.rows.removeLast(self.rows.count - Self.maxRows) }
                self.rebuildIndex()
                self.save()
            }
            let n = self.refusedTodayLocked(now: now)
            DispatchQueue.main.async { completion(n) }
        }
    }

    func recent(limit: Int = 200, completion: @escaping ([Row]) -> Void) {
        queue.async {
            self.loadIfNeeded()
            let out = Array(self.rows.prefix(limit))
            DispatchQueue.main.async { completion(out) }
        }
    }

    func refusedToday(now: Date = Date(), completion: @escaping (Int) -> Void) {
        queue.async {
            self.loadIfNeeded()
            let n = self.refusedTodayLocked(now: now)
            DispatchQueue.main.async { completion(n) }
        }
    }

    /// Refused since local midnight.
    private func refusedTodayLocked(now: Date) -> Int {
        let midnight = Calendar.current.startOfDay(for: now)
        return rows.lazy.filter { $0.refused && $0.ts >= midnight }.count
    }

    /// Excluded from backups, set on every write so that a file kept by an
    /// earlier build is covered too.
    private func save() {
        guard let d = try? JSONEncoder().encode(rows) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? d.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        var excluded = URLResourceValues()
        excluded.isExcludedFromBackup = true
        var file = url
        try? file.setResourceValues(excluded)
    }
}

/// While connected: copy the core's ring into GuardStore, read the extension's
/// per-session acknowledgements, and show the notes the extension set aside for
/// the app.
@MainActor
final class GuardianCenter: ObservableObject {
    static let shared = GuardianCenter()

    struct Notice: Equatable { let title: String; let body: String; let url: URL? }
    struct ProtectionInfo: Equatable { let enabled: Bool; let listVersion: String; let feedDate: String }

    /// Starts at 0 and is filled from the store when a session starts, so
    /// constructing this object (every brand's ContentView does) reads nothing.
    @Published private(set) var blockedToday = 0
    @Published var notice: Notice?
    @Published private(set) var protection: ProtectionInfo?
    /// "Protected" is allowed: the exit sent `caps` on THIS session AND its latest
    /// `protection` note says enabled.
    @Published private(set) var acknowledged = false
    /// Bumped on every store change, so an open sheet can re-read it.
    @Published private(set) var revision = 0
    private var lastEntitlement: String?

    /// One poll loop per connection; returns when `stillConnected` goes false.
    func run(source: GuardianSource, stillConnected: @escaping () -> Bool) async {
        resetSession()
        GuardStore.shared.refusedToday { [weak self] n in self?.blockedToday = n }
        while stillConnected(), !Task.isCancelled {
            await poll(source)
            try? await Task.sleep(nanoseconds: 5_000_000_000)
        }
        resetSession()
    }

    func loadToday() {
        GuardStore.shared.refusedToday { [weak self] n in self?.blockedToday = n }
    }

    /// A new tunnel session must earn the acknowledgement again.
    func resetSession() {
        acknowledged = false
        protection = nil
        lastEntitlement = nil
    }

    func poll(_ source: GuardianSource) async {
        if let snap = await source.snapshot() { apply(snap) }
        if let notes = await source.drainNotes() { handle(notes) }
    }

    func apply(_ snap: GuardianSnapshot, now: Date = Date()) {
        acknowledged = snap.isProtected
        if let enabled = snap.protectionEnabled {
            protection = ProtectionInfo(enabled: enabled, listVersion: snap.protectionListVersion ?? "",
                                        feedDate: snap.protectionFeedDate ?? "")
        } else {
            protection = nil
        }

        if let state = snap.entitlementState, !state.isEmpty {
            let key = "\(state)|\(snap.entitlementPaidUntil ?? "")"
            if key != lastEntitlement {
                lastEntitlement = key
                Store.shared.applyServerEntitlement(state: state, paidUntilISO: snap.entitlementPaidUntil)
            }
        }
        let rows = snap.recent.map {
            GuardStore.Row(host: $0.host, port: $0.port, bits: $0.bits,
                           reason: $0.reason ?? $0.category,
                           ts: now.addingTimeInterval(-Double($0.secsAgo)), refused: $0.refused)
        }
        guard !rows.isEmpty else { return }
        GuardStore.shared.addAll(rows, now: now) { [weak self] n in
            guard let self else { return }
            if n != self.blockedToday { self.blockedToday = n }
            self.revision += 1
        }
    }

    /// Notes the extension set aside for the app: `[{seq, ts, type, payload}]`.
    /// Entitlement, caps, protection and rules are handled in the extension.
    func handle(_ json: String) {
        guard let arr = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [[String: Any]] else { return }
        for m in arr where m["type"] as? String == "notice" {
            let p = m["payload"] as? [String: Any] ?? [:]
            let n = Notice(title: p["title"] as? String ?? "", body: p["body"] as? String ?? "",
                           url: (p["url"] as? String).flatMap(Self.httpsURL))
            guard !n.title.isEmpty || !n.body.isEmpty else { continue }
            notice = n
            Self.postIfAllowed(n)
        }
    }

    static func httpsURL(_ s: String) -> URL? {
        guard let u = URL(string: s), u.scheme?.lowercased() == "https", u.host != nil else { return nil }
        return u
    }

    /// A system notification only where the user has ALREADY allowed them. Never
    /// asks: the quiet row on Connect shows the notice regardless.
    private static func postIfAllowed(_ n: Notice) {
        let c = UNUserNotificationCenter.current()
        c.getNotificationSettings { s in
            guard s.authorizationStatus == .authorized || s.authorizationStatus == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = n.title
            content.body = n.body
            c.add(UNNotificationRequest(identifier: "notice-\(n.title.hashValue)-\(n.body.hashValue)",
                                        content: content, trigger: nil))
        }
    }
}
