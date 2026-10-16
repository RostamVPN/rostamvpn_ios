// Copyright 2026 Internet Mastering & Company, Inc.
// SPDX-License-Identifier: Apache-2.0

import Foundation
import StoreKit
import SwiftUI
import UIKit
import RostamKit

/// Asks for an App Store review, but only at a moment the user is plausibly
/// happy.
enum ReviewPrompt {
    private static func reviewConfig() -> [String: Any]? {
        guard
            let raw = RemoteConfig.current,
            let d = raw.data(using: .utf8),
            let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any]
        else { return nil }
        return o["review"] as? [String: Any]
    }

    private static func cfgInt(_ key: String, _ fallback: Int, floor: Int) -> Int {
        let v = (reviewConfig()?[key] as? NSNumber)?.intValue ?? fallback

        return max(floor, v)
    }

    /// Master switch. Sessions are still COUNTED while off, so turning it back on
    /// finds users already qualified rather than restarting their clock.
    private static var enabled: Bool {
        (reviewConfig()?["enabled"] as? Bool) ?? true
    }

    /// How long a connection must hold before it counts as a real success.
    private static var minSustainedSeconds: TimeInterval {
        TimeInterval(cfgInt("min_sustained_secs", 30, floor: 10))
    }

    /// Sustained sessions required before we are willing to ask at all.
    private static var minGoodSessions: Int {
        cfgInt("min_good_sessions", 3, floor: 1)
    }

    /// Days since first use before we are willing to ask at all.
    private static var minDaysSinceFirstUse: Double {
        Double(cfgInt("min_days_since_first_use", 2, floor: 0))
    }

    /// Days between two asks. 45, deliberately BELOW Apple's own 3-per-year cap: a
    /// quota'd request is a silent no-op that costs nothing, so our brake should
    /// not be the binding one.
    private static var minDaysBetweenAsks: Double {
        Double(cfgInt("ask_cooldown_days", 45, floor: 30))
    }

    private static let suiteName = BrandRuntime.appGroup

    private enum Key {
        static let firstUse = "review.firstUseAt"
        static let goodSessions = "review.goodSessions"
        static let lastAsk = "review.lastAskAt"
        static let askCount = "review.askCount"
    }

    private static var store: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    /// When the current connection reached `.connected`. Nil when not connected.
    private static var connectedAt: Date?

    /// Sticky for the life of the process. A user who hit an error or saw the
    /// paywall this launch is not asked to rate us this launch, even if a later
    /// connection goes perfectly.
    private static var sessionPoisoned = false

    /// The tunnel reached `.connected`. Starts the sustained-connection clock. -
    /// Parameter since: when the tunnel ACTUALLY came up, if the caller knows. Pass
    /// `connection.connectedDate`; `nil` falls back to now.
    static func recordSuccessfulConnection(since: Date? = nil) {
        bootstrapFirstUse()
        connectedAt = since ?? Date()
    }

    /// A connect attempt failed, or the tunnel dropped unexpectedly. Poisons this
    /// launch: no rating ask until the app is relaunched.
    static func recordConnectionFailure() {
        connectedAt = nil
        sessionPoisoned = true
    }

    static func recordPaywallShown() {
        sessionPoisoned = true
    }

    /// Evaluate every gate and, if they all pass, show the system review prompt.
    static func maybeAsk() {
        guard enabled else { _ = consumeQualifyingSession(); return }
        guard consumeQualifyingSession() else { return }
        guard let scene = activeScene else { return }
        recordAsk()
        present(in: scene)
    }

    /// The user tapped Rate. Opens the App Store review sheet for this app; does
    /// NOT call `requestReview`.
    static func askNow() {
        let id = BrandRuntime.appStoreID
        guard !id.isEmpty,
              let url = URL(string: "https://apps.apple.com/app/id\(id)?action=write-review")
        else {
            NSLog("[review] no App Store id for this brand; cannot open the review page")
            return
        }
        DispatchQueue.main.async { UIApplication.shared.open(url) }
    }

    /// SwiftUI iOS 16+ variant, for callers that already hold
    /// `@Environment(\.requestReview)`. Identical gating; it just lets SwiftUI
    /// resolve the scene instead of us walking `connectedScenes`.
    @available(iOS 16.0, *)
    static func maybeAsk(using action: RequestReviewAction) {
        guard enabled else { _ = consumeQualifyingSession(); return }
        guard consumeQualifyingSession() else { return }
        recordAsk()
        DispatchQueue.main.async { action() }
    }

    /// Returns true when this disconnect is a genuinely good moment to ask. Always
    /// clears `connectedAt`, so one connection can qualify at most once.
    private static func consumeQualifyingSession() -> Bool {
        guard let start = connectedAt else { return false }
        connectedAt = nil

        let held = Date().timeIntervalSince(start)
        guard held >= minSustainedSeconds, held < 60 * 60 * 24 * 7 else { return false }

        let sessions = store.integer(forKey: Key.goodSessions) + 1
        store.set(sessions, forKey: Key.goodSessions)

        guard !sessionPoisoned else { return false }

        guard sessions >= minGoodSessions else { return false }
        let firstUse = bootstrapFirstUse()
        guard Date().timeIntervalSince(firstUse) >= minDaysSinceFirstUse * 86_400 else {
            return false
        }

        let last = store.double(forKey: Key.lastAsk)
        if last > 0 {
            let elapsed = Date().timeIntervalSince(Date(timeIntervalSince1970: last))

            if elapsed < 0 {
                store.removeObject(forKey: Key.lastAsk)
            } else {
                guard elapsed >= minDaysBetweenAsks * 86_400 else { return false }
            }
        }

        return true
    }

    private static func recordAsk() {
        store.set(Date().timeIntervalSince1970, forKey: Key.lastAsk)
        store.set(store.integer(forKey: Key.askCount) + 1, forKey: Key.askCount)
    }

    /// First-use timestamp, written once. Not the install date — we have no
    /// reliable one — but "first time the app got far enough to connect", which is
    /// the more meaningful clock for this decision anyway.
    @discardableResult
    private static func bootstrapFirstUse() -> Date {
        let existing = store.double(forKey: Key.firstUse)
        if existing > 0 { return Date(timeIntervalSince1970: existing) }
        let now = Date()
        store.set(now.timeIntervalSince1970, forKey: Key.firstUse)
        return now
    }

    private static var activeScene: UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
    }

    private static func present(in scene: UIWindowScene) {
        DispatchQueue.main.async {
            if #available(iOS 16.0, *) {
                AppStore.requestReview(in: scene)
            } else {
                legacyRequestReview(in: scene)
            }
        }
    }

    /// iOS 15 only. The `@available(iOS, deprecated: 18.0)` annotation is what
    /// keeps SKStoreReviewController's deprecation warning from firing at a call
    /// site that can only ever run on 15.x.
    @available(iOS, deprecated: 18.0)
    private static func legacyRequestReview(in scene: UIWindowScene) {
        SKStoreReviewController.requestReview(in: scene)
    }
}
