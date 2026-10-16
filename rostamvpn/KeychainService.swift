// Copyright 2026 Internet Mastering & Company, Inc.
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Security

enum KeychainError: Error {
    case unexpectedStatus(OSStatus)
}

/// Thin wrapper around Keychain Services, so the cid survives a reinstall.
enum KeychainService {
    /// Device-bound: never restored from a backup onto another device.
    private static let accessible = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

    static func setString(_ value: String, for key: String) throws {
        let data = Data(value.utf8)
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)

        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = accessible
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    /// Reading moves an item written under the earlier, backed-up class to
    /// `accessible`.
    static func getString(for key: String) -> String? {
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        var query = item
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        SecItemUpdate(item as CFDictionary, [kSecAttrAccessible as String: accessible] as CFDictionary)
        return String(data: data, encoding: .utf8)
    }

}
