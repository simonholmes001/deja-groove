import Foundation
import Security

/// Errors raised by the Keychain layer.
public enum KeychainError: Error, Equatable, Sendable {
    case unhandled(status: OSStatus)
}

/// Narrow seam over the Keychain so the store can be unit-tested without
/// touching the real system keychain.
public protocol KeychainAccessing: Sendable {
    func set(_ data: Data, account: String) throws
    func get(account: String) throws -> Data?
    func delete(account: String) throws
}

/// `SecureSessionStore` backed by the iOS Keychain. The session (access token
/// plus the long-lived ~90-day refresh token) is stored as a single encrypted
/// item with `WhenUnlockedThisDeviceOnly` accessibility so it never syncs off
/// the device and is unreadable while locked. Corrupt payloads are treated as
/// "no session" so a bad item degrades to re-authentication, never a crash.
public struct KeychainSessionStore: SecureSessionStore {
    public static let account = "com.dejagroove.auth.session"

    private let keychain: KeychainAccessing

    public init(keychain: KeychainAccessing = SystemKeychain()) {
        self.keychain = keychain
    }

    public func load() throws -> AuthSession? {
        guard let data = try keychain.get(account: Self.account) else { return nil }
        return try? JSONDecoder().decode(AuthSession.self, from: data)
    }

    public func save(_ session: AuthSession) throws {
        let data = try JSONEncoder().encode(session)
        try keychain.set(data, account: Self.account)
    }

    public func clear() throws {
        try keychain.delete(account: Self.account)
    }
}

/// Production `KeychainAccessing` using the Security framework. `set` is
/// upsert: delete-then-add keeps the call idempotent across token refreshes.
public struct SystemKeychain: KeychainAccessing {
    private let service = "DejaGroove"

    public init() {}

    public func set(_ data: Data, account: String) throws {
        try delete(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unhandled(status: status)
        }
    }

    public func get(account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw KeychainError.unhandled(status: status)
        }
        return item as? Data
    }

    public func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandled(status: status)
        }
    }
}
