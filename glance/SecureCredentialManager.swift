//
//  SecureCredentialManager.swift
//  glance
//
//  Two-tier password storage on top of KeychainManager:
//    1. A random 256-bit AES session key is stored in the user's legacy/login
//       Keychain. For an existing session key, Glance performs device-owner
//       authentication (Touch ID or the Mac login password) before loading
//       the key into memory.
//    2. The Mac password is AES-GCM encrypted under that session key and the
//       ciphertext is stored separately in the same legacy/login Keychain.
//
//  The upstream app can bind the session key directly to a Keychain ACL
//  because it has a signed application identity. This Sonoma Intel port is
//  ad-hoc signed, so doing that selects the Data Protection Keychain and
//  fails with errSecMissingEntitlement (-34018). Authentication is therefore
//  performed explicitly with LocalAuthentication before the existing key is
//  released into the app session.
//

import Foundation
import CryptoKit
import LocalAuthentication

enum SecureCredentialError: LocalizedError {
    case emptyPassword
    case sessionLocked
    case authenticationRequired
    case encryptionFailed
    case decryptionFailed
    case sessionKeyUnavailable

    var errorDescription: String? {
        switch self {
        case .emptyPassword:
            return "Password cannot be empty."
        case .sessionLocked:
            return "Session is locked. Authenticate before storing or using the password."
        case .authenticationRequired:
            return "Session is locked. Authenticate from Password settings before continuing."
        case .encryptionFailed:
            return "Encryption failed."
        case .decryptionFailed:
            return "Decryption failed. The stored credential may be corrupted."
        case .sessionKeyUnavailable:
            return "The session key is missing, but encrypted data still exists that only it could read. Nothing has been deleted. Remove the stored password on the Password tab to clear both and start fresh."
        }
    }
}

extension Notification.Name {
    /// Fires whenever the cached session key changes — unlocked, locked, or
    /// wiped by `deletePassword()`. Stores encrypted under that key observe
    /// this instead of relying on individual callers to remember to reload.
    nonisolated static let secureCredentialSessionDidChange = Notification.Name("SecureCredentialManager.sessionDidChange")
}

enum SecureCredentialManager {
    nonisolated private static let sessionKeyAccount = "sessionKey"
    nonisolated private static let passwordBlobAccount = "encryptedPassword"

    // MARK: - Session state (thread-safe via NSLock)

    nonisolated private static let sessionLock = NSLock()
    nonisolated(unsafe) private static var _cachedKey: SymmetricKey?
    nonisolated(unsafe) private static var _lastActivityAt: Date?

    nonisolated static var isSessionUnlocked: Bool {
        sessionLock.lock(); defer { sessionLock.unlock() }
        return _cachedKey != nil
    }

    /// `nil` whenever the session is locked — there is no activity to age.
    nonisolated static var lastActivityAt: Date? {
        sessionLock.lock(); defer { sessionLock.unlock() }
        return _lastActivityAt
    }

    nonisolated private static func cachedKey() -> SymmetricKey? {
        sessionLock.lock(); defer { sessionLock.unlock() }
        return _cachedKey
    }

    nonisolated private static func setCachedKey(_ key: SymmetricKey?) {
        sessionLock.lock()
        let changed = (key != nil) != (_cachedKey != nil)
        _cachedKey = key
        _lastActivityAt = key == nil ? nil : Date()
        sessionLock.unlock()

        guard changed else { return }
        NotificationCenter.default.post(name: .secureCredentialSessionDidChange, object: nil)
    }

    /// Resets the idle countdown after a successful use of the stored
    /// password, so an actively used session does not auto-lock.
    nonisolated private static func recordActivity() {
        sessionLock.lock()
        if _cachedKey != nil { _lastActivityAt = Date() }
        sessionLock.unlock()
    }

    // MARK: - Generic session-key crypto

    nonisolated static func encrypt(_ plaintext: Data) throws -> Data {
        guard let key = cachedKey() else { throw SecureCredentialError.sessionLocked }
        do {
            let sealed = try AES.GCM.seal(plaintext, using: key)
            guard let combined = sealed.combined else { throw SecureCredentialError.encryptionFailed }
            return combined
        } catch {
            throw SecureCredentialError.encryptionFailed
        }
    }

    nonisolated static func decrypt(_ ciphertext: Data) throws -> Data {
        guard let key = cachedKey() else { throw SecureCredentialError.sessionLocked }
        do {
            let sealed = try AES.GCM.SealedBox(combined: ciphertext)
            return try AES.GCM.open(sealed, using: key)
        } catch {
            throw SecureCredentialError.decryptionFailed
        }
    }

    // MARK: - Public API

    nonisolated static func hasStoredPassword() -> Bool {
        KeychainManager.exists(account: passwordBlobAccount)
    }

    /// Device-owner authentication for normal session unlocks. This is kept
    /// genuinely asynchronous; blocking an async Swift worker with a
    /// semaphore while waiting for LocalAuthentication can starve the
    /// cooperative thread pool.
    nonisolated private static func authenticateDeviceOwner(reason: String) async throws {
        let context = LAContext()
        var policyError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) else {
            if let policyError { throw policyError }
            throw KeychainError.authenticationFailed
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, error in
                if success {
                    continuation.resume(returning: ())
                } else if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(throwing: KeychainError.authenticationFailed)
                }
            }
        }
    }

    /// Normal unlock path used by Settings. Authentication happens first;
    /// only then is an existing session key read from the legacy/login
    /// Keychain and cached in memory. On a genuine empty first run it can
    /// also create the initial key after authentication.
    nonisolated static func authenticateAndUnlockSession(reason: String) async throws {
        if cachedKey() != nil { return }
        try await authenticateDeviceOwner(reason: reason)

        if KeychainManager.exists(account: sessionKeyAccount) {
            let data = try KeychainManager.read(account: sessionKeyAccount)
            setCachedKey(SymmetricKey(data: data))
            return
        }

        try createInitialSessionKey()
    }

    /// Bootstrap path retained for the first-run onboarding flow, whose
    /// existing call site is synchronous. It is deliberately allowed only
    /// when no session key exists yet. Once a key has been created, a locked
    /// session cannot be reopened through this method; callers must use
    /// `authenticateAndUnlockSession(reason:)` instead.
    ///
    /// This lets the first-run password screen create its encryption key
    /// without reintroducing the Data Protection Keychain entitlement error,
    /// while preventing later enrollment/debug paths from bypassing the
    /// session authentication gate.
    nonisolated static func unlockSession(reason: String) throws {
        if cachedKey() != nil { return }

        if KeychainManager.exists(account: sessionKeyAccount) {
            throw SecureCredentialError.authenticationRequired
        }

        try createInitialSessionKey()
    }

    /// Creates the first session key only when no encrypted payload survives
    /// from an older key. Refusing the orphaned state prevents silently
    /// replacing the only key capable of decrypting an existing password or
    /// enrolled face store.
    nonisolated private static func createInitialSessionKey() throws {
        guard !hasSessionEncryptedData else {
            throw SecureCredentialError.sessionKeyUnavailable
        }

        let key = SymmetricKey(size: .bits256)
        try KeychainManager.save(
            account: sessionKeyAccount,
            data: key.withUnsafeBytes { Data($0) }
        )
        setCachedKey(key)
    }

    /// Whether anything on this Mac is currently encrypted under the session
    /// key. This remains answerable while the session itself is locked.
    nonisolated static var hasSessionEncryptedData: Bool {
        KeychainManager.exists(account: passwordBlobAccount) || SecureFaceStore.exists
    }

    /// Clears the in-memory key. Reopening an existing session requires
    /// device-owner authentication again.
    nonisolated static func lockSession() {
        setCachedKey(nil)
    }

    /// Encrypts and stores `passwordBytes`. Requires an unlocked session.
    nonisolated static func savePassword(_ passwordBytes: Data) throws {
        guard !passwordBytes.isEmpty else { throw SecureCredentialError.emptyPassword }
        let combined = try encrypt(passwordBytes)
        try KeychainManager.save(account: passwordBlobAccount, data: combined)
    }

    /// Decrypts and returns the stored password. The caller must zero the
    /// returned buffer after use.
    nonisolated static func readPassword() throws -> Data {
        guard cachedKey() != nil else { throw SecureCredentialError.sessionLocked }
        let ciphertext = try KeychainManager.read(account: passwordBlobAccount)
        let plaintext = try decrypt(ciphertext)
        recordActivity()
        return plaintext
    }

    /// Deletes both Keychain items and clears the cached session key.
    nonisolated static func deletePassword() throws {
        try KeychainManager.delete(account: passwordBlobAccount)
        try KeychainManager.delete(account: sessionKeyAccount)
        setCachedKey(nil)
    }
}
