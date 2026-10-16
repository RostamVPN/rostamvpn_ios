// Copyright 2026 Internet Mastering & Company, Inc.
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Security

/// The device's cashier identity.
enum CashierIdentity {
    private static let key = "com.rostamvpn.cid"

    /// Computed once per process. The app and the extension each call this
    /// independently; whichever runs second finds the value already there.
    static let current: String = {
        if let existing = KeychainService.getString(for: key), !existing.isEmpty {
            NSLog("[cid] loaded from keychain (survives reinstall)")
            return existing
        }
        let generated = generate()
        do {
            try KeychainService.setString(generated, for: key)
            NSLog("[cid] generated and stored")
        } catch {
            NSLog("[cid] COULD NOT PERSIST (\(error)) — entitlement will not survive relaunch")
        }
        return generated
    }()

    private static func generate() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            let u = UUID().uuid
            bytes = [u.0, u.1, u.2, u.3, u.4, u.5, u.6, u.7,
                     u.8, u.9, u.10, u.11, u.12, u.13, u.14, u.15]
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
