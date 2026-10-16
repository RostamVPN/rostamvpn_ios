// Copyright 2026 Internet Mastering & Company, Inc.
// SPDX-License-Identifier: Apache-2.0

/// When a cashier request may leave the device.
public enum ControlPlane {
    /// `profileExists` is nil until the saved profiles have been read, and an
    /// unknown state never sends. No profile -> allow, the first-run register.
    /// Profile and connected -> allow, tunnelled. Profile but down -> defer,
    /// except on a paid-only build, whose direct answer is upgrade-only.
    public static func mustDefer(profileExists: Bool?, tunnelConnected: Bool, paidOnly: Bool) -> Bool {
        guard let profileExists else { return true }
        return profileExists && !tunnelConnected && !paidOnly
    }
}
