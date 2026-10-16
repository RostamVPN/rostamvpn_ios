// Copyright 2026 Internet Mastering & Company, Inc.
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// The connect narrative, keyed to the core's REAL budget: 8s per endpoint, 32s
/// of direct tiers, then the CDN fallback, 60s total (OPEN_TIMEOUT /
/// DIRECT_BUDGET / SELECT_BUDGET). Each line is true at the moment it appears.
enum ConnectPhase {
    static let marks: [Double] = [0, 8, 20, 32, 50]

    static func index(elapsed: Double) -> Int {
        var i = 0
        for (n, m) in marks.enumerated() where elapsed >= m { i = n }
        return i
    }

    static func helper(_ i: Int) -> LocalizedStringKey {
        switch i {
        case 0:  return "Finding the fastest route"
        case 1:  return "First route is slow — trying another"
        case 2:  return "This network is blocking directly. Working around it."
        case 3:  return "Switching to a backup route"
        default: return "Last route. Hold on."
        }
    }

    /// Same strings, resolved. LocalizedStringKey is for Text; VoiceOver's
    /// announcement API needs a real String.
    static func spoken(_ i: Int) -> String {
        switch i {
        case 0:  return String(localized: "Finding the fastest route")
        case 1:  return String(localized: "First route is slow — trying another")
        case 2:  return String(localized: "This network is blocking directly. Working around it.")
        case 3:  return String(localized: "Switching to a backup route")
        default: return String(localized: "Last route. Hold on.")
        }
    }

    /// Arc sweep as a fraction of the circle: grows with the phase.
    static func trim(_ i: Int) -> CGFloat { [0.16, 0.24, 0.34, 0.48, 0.62][min(i, 4)] }

    /// Seconds per revolution. SLOWS as phases advance -- deliberate search reads
    /// as competence; speeding up reads as panic.
    static func period(_ i: Int) -> Double { [1.1, 1.4, 1.8, 2.2, 2.6][min(i, 4)] }
}
