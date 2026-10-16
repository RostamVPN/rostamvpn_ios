// Copyright 2026 Internet Mastering & Company, Inc.
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

/// Numbers shared by LaunchScreen.storyboard and RostamSplash. Change one,
/// change the other -- if they disagree the logo visibly jumps at the hand-off,
/// which is the one thing a splash must never do.
enum LaunchGeometry {
    static let artW: CGFloat = 600
    static let artH: CGFloat = 728

    static let boxW: CGFloat = 200
    /// DERIVED, never typed.
    static let boxH: CGFloat = boxW * artH / artW
    static let lockupOffsetY: CGFloat = -30
}
