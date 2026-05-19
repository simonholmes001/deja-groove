import XCTest
import DejaGrooveAuth
@testable import DejaGrooveApp

@MainActor
final class AppAuthCoordinatorTests: XCTestCase {
    func testBootstrapWithoutStoredSessionRequiresSignIn() {
        let manager = AuthSessionManager(
            tokenProvider: InteractiveStubProvider(result: .failure(.providerConfiguration)),
            store: CoordinatorInMemoryStore(),
            dateProvider: BridgeFixedDate(now: Date()))
        let sut = AppAuthCoordinator(authManager: manager)

        sut.bootstrap()

        XCTAssertTrue(sut.requiresSignIn)
        XCTAssertNil(sut.lastError)
    }

    func testSignInSuccessTransitionsToAuthenticated() async {
        let now = Date(timeIntervalSince1970: 1000)
        let session = AuthSession(
            accessToken: "at",
            refreshToken: "rt",
            expiresAt: now.addingTimeInterval(3600),
            userID: "user-1")
        let manager = AuthSessionManager(
            tokenProvider: InteractiveStubProvider(result: .success(session)),
            store: CoordinatorInMemoryStore(),
            dateProvider: BridgeFixedDate(now: now))
        let sut = AppAuthCoordinator(authManager: manager)

        await sut.signInInteractively()

        XCTAssertFalse(sut.requiresSignIn)
        XCTAssertNil(sut.lastError)
    }

    func testSignInFailureExposesRecoveryError() async {
        let manager = AuthSessionManager(
            tokenProvider: InteractiveStubProvider(result: .failure(.networkUnavailable)),
            store: CoordinatorInMemoryStore(),
            dateProvider: BridgeFixedDate(now: Date()))
        let sut = AppAuthCoordinator(authManager: manager)

        await sut.signInInteractively()

        XCTAssertTrue(sut.requiresSignIn)
        XCTAssertEqual("No Connection", sut.lastError?.title)
    }
}

final class InteractiveStubProvider: InteractiveAuthTokenProvider, @unchecked Sendable {
    private let result: Result<AuthSession, AuthOnboardingError>

    init(result: Result<AuthSession, AuthOnboardingError>) {
        self.result = result
    }

    func signIn(username: String, password: String) async throws -> AuthSession {
        throw AuthOnboardingError.providerConfiguration
    }

    func signInInteractively() async throws -> AuthSession {
        try result.get()
    }

    func refresh(using refreshToken: String) async throws -> AuthSession {
        try result.get()
    }
}

final class CoordinatorInMemoryStore: SecureSessionStore, @unchecked Sendable {
    private var session: AuthSession?
    func load() throws -> AuthSession? { session }
    func save(_ session: AuthSession) throws { self.session = session }
    func clear() throws { session = nil }
}
