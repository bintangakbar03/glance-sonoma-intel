//
//  KeychainManager.swift
//  glance
//
//  Thin, password-agnostic wrapper around Keychain Services. The Sonoma
//  Intel build is intentionally ad-hoc signed, so it uses the legacy/login
//  Keychain explicitly instead of the Data Protection Keychain. The latter
//  requires an application identity / Keychain entitlement that an ad-hoc
//  build does not have.
//

import Foundation
import Security

enum KeychainError: LocalizedError {
    case itemNotFound
    case unexpectedData
    case authenticationFailed
    case osStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .itemNotFound:
            return "Keychain item not found."
        case .unexpectedData:
            return "Keychain item had an unexpected format."
        case .authenticationFailed:
            return "Authentication was cancelled or failed."
        case .osStatus(let status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
            return "Keychain error: \(message)"
        }
    }
}

enum KeychainManager {
    nonisolated static let service = "com.jonathan.glance"

    /// Every operation opts out of the Data Protection Keychain. That keeps
    /// this private, ad-hoc-signed Intel build on the user's login Keychain
    /// and avoids `errSecMissingEntitlement` (-34018).
    nonisolated private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: false
        ]
    }

    /// Existence check against the same legacy Keychain used for reads and
    /// writes. Only a real success counts as an existing item; entitlement,
    /// interaction, and other errors must never be mistaken for existence.
    nonisolated static func exists(account: String) -> Bool {
        var query = baseQuery(account: account)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// Reads raw data from the legacy/login Keychain. Session authentication
    /// is handled separately by `SecureCredentialManager` with
    /// LocalAuthentication, so this layer never requests a Keychain ACL.
    nonisolated static func read(account: String) throws -> Data {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { throw KeychainError.unexpectedData }
            return data
        case errSecItemNotFound:
            throw KeychainError.itemNotFound
        case errSecUserCanceled, errSecAuthFailed:
            throw KeychainError.authenticationFailed
        default:
            throw KeychainError.osStatus(status)
        }
    }

    /// Saves `data` to the legacy/login Keychain, replacing any existing
    /// value. Do not add `kSecAttrAccessible` or `kSecAttrAccessControl` here:
    /// those select the Data Protection Keychain path on macOS and bring the
    /// missing-entitlement failure back for an ad-hoc build.
    nonisolated static func save(account: String, data: Data) throws {
        let deleteQuery = baseQuery(account: account)
        SecItemDelete(deleteQuery as CFDictionary)

        var addQuery = baseQuery(account: account)
        addQuery[kSecValueData as String] = data

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.osStatus(status) }
    }

    nonisolated static func delete(account: String) throws {
        let query = baseQuery(account: account)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.osStatus(status)
        }
    }
}
