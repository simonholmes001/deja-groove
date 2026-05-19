import Foundation
import Testing
@testable import DejaGrooveAuth

@Suite("Auth Token Access")
struct AuthTokenAccessTests {
    @Test("Returns the access token when authenticated and unexpired")
    @MainActor
    func tokenWhenAuthenticated() async {
        let now = Date(timeIntervalSince1970: 1_000)
        let session = AuthSession(accessToken: "live-at", refreshToken: "rt",
                                  expiresAt: now.addingTimeInterval(3600), userID: "u")
        let manager = AuthSessionManager(
            tokenProvider: TokenAccessStubProvider(refresh: .success(session)),
            store: TokenAccessInMemoryStore(),
            dateProvider: TokenAccessFixedDate(now: now))
        _ = await manager.signIn(username: "u", password: "p")

        #expect(await manager.currentAccessToken() == "live-at")
    }

    @Test("Refreshes an expired token and returns the new one")
    @MainActor
    func refreshesExpiredToken() async {
        let now = Date(timeIntervalSince1970: 1_000)
        let expired = AuthSession(accessToken: "old-at", refreshToken: "rt-1",
                                  expiresAt: now.addingTimeInterval(-1), userID: "u")
        let fresh = AuthSession(accessToken: "new-at", refreshToken: "rt-2",
                                expiresAt: now.addingTimeInterval(3600), userID: "u")
        let store = TokenAccessInMemoryStore()
        try? store.save(expired)
        let manager = AuthSessionManager(
            tokenProvider: TokenAccessStubProvider(refresh: .success(fresh)),
            store: store,
            dateProvider: TokenAccessFixedDate(now: now))
        manager.restoreSession()

        #expect(await manager.currentAccessToken() == "new-at")
    }

    @Test("Returns nil when unauthenticated")
    @MainActor
    func nilWhenUnauthenticated() async {
        let manager = AuthSessionManager(
            tokenProvider: TokenAccessStubProvider(refresh: .failure(.unknown)),
            store: TokenAccessInMemoryStore(),
            dateProvider: TokenAccessFixedDate(now: Date()))

        #expect(await manager.currentAccessToken() == nil)
    }
}

final class TokenAccessStubProvider: AuthTokenProvider, @unchecked Sendable {
    private let refreshResult: Result<AuthSession, AuthOnboardingError>
    init(refresh: Result<AuthSession, AuthOnboardingError>) { self.refreshResult = refresh }

    func signIn(username: String, password: String) async throws -> AuthSession {
        switch refreshResult {
        case let .success(s): return s
        case let .failure(e): throw e
        }
    }
    func refresh(using refreshToken: String) async throws -> AuthSession {
        switch refreshResult {
        case let .success(s): return s
        case let .failure(e): throw e
        }
    }
}

final class TokenAccessInMemoryStore: SecureSessionStore, @unchecked Sendable {
    private var session: AuthSession?
    func load() throws -> AuthSession? { session }
    func save(_ session: AuthSession) throws { self.session = session }
    func clear() throws { session = nil }
}

struct TokenAccessFixedDate: DateProvider {
    let now: Date
}
