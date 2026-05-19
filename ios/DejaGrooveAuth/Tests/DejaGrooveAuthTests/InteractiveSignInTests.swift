import Foundation
import Testing
@testable import DejaGrooveAuth

@Suite("Interactive Sign-In")
struct InteractiveSignInTests {
    @Test("Interactive sign-in authenticates and persists the session")
    @MainActor
    func interactiveSuccess() async {
        let now = Date(timeIntervalSince1970: 2_000)
        let session = AuthSession(accessToken: "iat", refreshToken: "irt",
                                  expiresAt: now.addingTimeInterval(3600), userID: "iu")
        let store = InteractiveInMemoryStore()
        let manager = AuthSessionManager(
            tokenProvider: InteractiveStubProvider(result: .success(session)),
            store: store,
            dateProvider: InteractiveFixedDate(now: now))

        let result = await manager.signInInteractively()

        #expect(result == .success(session))
        #expect(manager.state == .authenticated(AuthSessionView(expiresAt: session.expiresAt, userID: session.userID)))
        #expect(store.saved == session)
    }

    @Test("Interactive sign-in failure maps to onboarding error and cleans up")
    @MainActor
    func interactiveFailure() async {
        let manager = AuthSessionManager(
            tokenProvider: InteractiveStubProvider(result: .failure(.cancelledByUser)),
            store: InteractiveInMemoryStore(),
            dateProvider: InteractiveFixedDate(now: Date()))

        let result = await manager.signInInteractively()

        #expect(result == .failure(.cancelledByUser))
        #expect(manager.state == .unauthenticated)
    }

    @Test("Non-interactive provider yields provider-configuration failure")
    @MainActor
    func nonInteractiveProvider() async {
        // A plain AuthTokenProvider that does not support interactive sign-in.
        let manager = AuthSessionManager(
            tokenProvider: PlainOnlyProvider(),
            store: InteractiveInMemoryStore(),
            dateProvider: InteractiveFixedDate(now: Date()))

        let result = await manager.signInInteractively()

        #expect(result == .failure(.providerConfiguration))
    }
}

final class InteractiveStubProvider: InteractiveAuthTokenProvider, @unchecked Sendable {
    private let result: Result<AuthSession, AuthOnboardingError>
    init(result: Result<AuthSession, AuthOnboardingError>) { self.result = result }

    func signIn(username: String, password: String) async throws -> AuthSession {
        throw AuthOnboardingError.providerConfiguration
    }
    func refresh(using refreshToken: String) async throws -> AuthSession {
        try result.get()
    }
    func signInInteractively() async throws -> AuthSession {
        try result.get()
    }
}

final class PlainOnlyProvider: AuthTokenProvider, @unchecked Sendable {
    func signIn(username: String, password: String) async throws -> AuthSession {
        throw AuthOnboardingError.providerConfiguration
    }
    func refresh(using refreshToken: String) async throws -> AuthSession {
        throw AuthOnboardingError.providerConfiguration
    }
}

final class InteractiveInMemoryStore: SecureSessionStore, @unchecked Sendable {
    private(set) var saved: AuthSession?
    func load() throws -> AuthSession? { saved }
    func save(_ session: AuthSession) throws { saved = session }
    func clear() throws { saved = nil }
}

struct InteractiveFixedDate: DateProvider {
    let now: Date
}
