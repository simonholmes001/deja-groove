import Foundation
import Testing
@testable import DejaGrooveAuth

@Suite("Keychain Session Store")
struct KeychainSessionStoreTests {
    private func makeSession() -> AuthSession {
        AuthSession(
            accessToken: "at",
            refreshToken: "rt",
            expiresAt: Date(timeIntervalSince1970: 1_700_000_000),
            userID: "user-7")
    }

    @Test("Save then load round-trips the session")
    func roundTrip() throws {
        let keychain = InMemoryKeychain()
        let store = KeychainSessionStore(keychain: keychain)
        let session = makeSession()

        try store.save(session)

        #expect(try store.load() == session)
    }

    @Test("Load returns nil when nothing is stored")
    func loadEmpty() throws {
        let store = KeychainSessionStore(keychain: InMemoryKeychain())
        #expect(try store.load() == nil)
    }

    @Test("Clear removes the stored session")
    func clearRemoves() throws {
        let store = KeychainSessionStore(keychain: InMemoryKeychain())
        try store.save(makeSession())

        try store.clear()

        #expect(try store.load() == nil)
    }

    @Test("Save surfaces keychain write failures")
    func saveFailure() {
        let store = KeychainSessionStore(keychain: InMemoryKeychain(failWrites: true))
        #expect(throws: (any Error).self) {
            try store.save(makeSession())
        }
    }

    @Test("Corrupt stored payload is treated as no session, not a crash")
    func corruptPayload() throws {
        let keychain = InMemoryKeychain()
        try keychain.set(Data("not-json".utf8), account: KeychainSessionStore.account)
        let store = KeychainSessionStore(keychain: keychain)

        #expect(try store.load() == nil)
    }
}

final class InMemoryKeychain: KeychainAccessing, @unchecked Sendable {
    private var storage: [String: Data] = [:]
    private let failWrites: Bool

    init(failWrites: Bool = false) { self.failWrites = failWrites }

    func set(_ data: Data, account: String) throws {
        if failWrites { throw KeychainError.unhandled(status: -25299) }
        storage[account] = data
    }

    func get(account: String) throws -> Data? { storage[account] }

    func delete(account: String) throws { storage[account] = nil }
}
