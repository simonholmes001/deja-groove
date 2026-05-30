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

    func testSignInInteractivelyIgnoresConcurrentReentry() async {
        let now = Date(timeIntervalSince1970: 2000)
        let session = AuthSession(
            accessToken: "at",
            refreshToken: "rt",
            expiresAt: now.addingTimeInterval(3600),
            userID: "user-2")
        let provider = DelayedInteractiveProvider(session: session)
        let manager = AuthSessionManager(
            tokenProvider: provider,
            store: CoordinatorInMemoryStore(),
            dateProvider: BridgeFixedDate(now: now))
        let sut = AppAuthCoordinator(authManager: manager)

        async let first: Void = sut.signInInteractively()
        async let second: Void = sut.signInInteractively()
        _ = await (first, second)

        let calls = await provider.interactiveCalls
        XCTAssertEqual(1, calls)
        XCTAssertFalse(sut.isSigningIn)
    }

    func testInvalidateSessionRequiresSignIn() async {
        let now = Date(timeIntervalSince1970: 3000)
        let session = AuthSession(
            accessToken: "at",
            refreshToken: "rt",
            expiresAt: now.addingTimeInterval(3600),
            userID: "user-3")
        let store = CoordinatorInMemoryStore()
        try? store.save(session)
        let manager = AuthSessionManager(
            tokenProvider: InteractiveStubProvider(result: .success(session)),
            store: store,
            dateProvider: BridgeFixedDate(now: now))
        let sut = AppAuthCoordinator(authManager: manager)
        sut.bootstrap()

        sut.invalidateSession()

        XCTAssertTrue(sut.requiresSignIn)
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

actor DelayedInteractiveProvider: InteractiveAuthTokenProvider {
    private(set) var interactiveCalls = 0
    private let session: AuthSession

    init(session: AuthSession) {
        self.session = session
    }

    func signIn(username: String, password: String) async throws -> AuthSession {
        throw AuthOnboardingError.providerConfiguration
    }

    func signInInteractively() async throws -> AuthSession {
        interactiveCalls += 1
        try await Task.sleep(nanoseconds: 30_000_000)
        return session
    }

    func refresh(using refreshToken: String) async throws -> AuthSession {
        session
    }
}
