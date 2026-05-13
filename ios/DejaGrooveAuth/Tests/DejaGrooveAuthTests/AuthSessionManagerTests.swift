import Foundation
import Testing
@testable import DejaGrooveAuth

@Suite("Auth Session Manager")
struct AuthSessionManagerTests {
    @Test("Sign in stores session and transitions to authenticated")
    @MainActor
    func signInSuccess() async {
        let now = Date(timeIntervalSince1970: 1_000)
        let session = AuthSession(
            accessToken: "access-1",
            refreshToken: "refresh-1",
            expiresAt: now.addingTimeInterval(3600),
            userID: "user-1"
        )
        let provider = StubTokenProvider(signInResult: .success(session), refreshResult: .success(session))
        let store = InMemoryStore()
        let manager = AuthSessionManager(tokenProvider: provider, store: store, dateProvider: FixedDateProvider(now: now))

        let result = await manager.signIn(username: "u", password: "p")

        #expect(result == .success(session))
        #expect(manager.state == .authenticated(AuthSessionView(expiresAt: session.expiresAt, userID: session.userID)))
        #expect(store.saved == session)
    }

    @Test("Sign in fails when store save throws")
    @MainActor
    func signInStoreSaveFailure() async {
        let now = Date(timeIntervalSince1970: 1_000)
        let session = AuthSession(
            accessToken: "access-1",
            refreshToken: "refresh-1",
            expiresAt: now.addingTimeInterval(3600),
            userID: "user-1"
        )
        let provider = StubTokenProvider(signInResult: .success(session), refreshResult: .success(session))
        let store = InMemoryStore(shouldThrowOnSave: true)
        let manager = AuthSessionManager(tokenProvider: provider, store: store, dateProvider: FixedDateProvider(now: now))

        let result = await manager.signIn(username: "u", password: "p")

        #expect(result == .failure(.unknown))
        #expect(manager.state == .unauthenticated)
    }

    @Test("Sign in fails when provider returns invalid session")
    @MainActor
    func signInInvalidSession() async {
        let now = Date(timeIntervalSince1970: 1_000)
        let invalid = AuthSession(
            accessToken: "",
            refreshToken: "refresh-1",
            expiresAt: now.addingTimeInterval(3600),
            userID: "user-1"
        )
        let provider = StubTokenProvider(signInResult: .success(invalid), refreshResult: .success(invalid))
        let store = InMemoryStore()
        let manager = AuthSessionManager(tokenProvider: provider, store: store, dateProvider: FixedDateProvider(now: now))

        let result = await manager.signIn(username: "u", password: "p")

        #expect(result == .failure(.providerConfiguration))
        #expect(manager.state == .unauthenticated)
        #expect(store.saved == nil)
    }

    @Test("Sign in failure maps to onboarding recovery state")
    @MainActor
    func signInFailure() async {
        let now = Date(timeIntervalSince1970: 1_000)
        let provider = StubTokenProvider(
            signInResult: .failure(.invalidCredentials),
            refreshResult: .failure(.unknown)
        )
        let manager = AuthSessionManager(tokenProvider: provider, store: InMemoryStore(), dateProvider: FixedDateProvider(now: now))

        let result = await manager.signIn(username: "u", password: "bad")

        #expect(result == .failure(.invalidCredentials))
        #expect(manager.state == .unauthenticated)
        let recovery = manager.recovery(for: .invalidCredentials)
        #expect(recovery.actionLabel == "Retry Sign-In")
    }

    @Test("Sign in failure with clear error surfaces cleanup failure state")
    @MainActor
    func signInFailureCleanupError() async {
        let now = Date(timeIntervalSince1970: 1_000)
        let provider = StubTokenProvider(
            signInResult: .failure(.networkUnavailable),
            refreshResult: .failure(.unknown)
        )
        let store = InMemoryStore(shouldThrowOnClear: true)
        let manager = AuthSessionManager(tokenProvider: provider, store: store, dateProvider: FixedDateProvider(now: now))

        let result = await manager.signIn(username: "u", password: "p")

        #expect(result == .failure(.networkUnavailable))
        #expect(manager.state == .reauthenticationRequired(.credentialCleanupFailed))
    }

    @Test("Restore session requires reauth when missing")
    @MainActor
    func restoreMissingSession() {
        let manager = AuthSessionManager(
            tokenProvider: StubTokenProvider(signInResult: .failure(.unknown), refreshResult: .failure(.unknown)),
            store: InMemoryStore(),
            dateProvider: FixedDateProvider(now: Date(timeIntervalSince1970: 1_000))
        )

        manager.restoreSession()

        #expect(manager.state == .reauthenticationRequired(.missingSession))
    }

    @Test("Restore session load failure requires store failure reauth")
    @MainActor
    func restoreStoreFailure() {
        let manager = AuthSessionManager(
            tokenProvider: StubTokenProvider(signInResult: .failure(.unknown), refreshResult: .failure(.unknown)),
            store: InMemoryStore(shouldThrowOnLoad: true),
            dateProvider: FixedDateProvider(now: Date(timeIntervalSince1970: 1_000))
        )

        manager.restoreSession()

        #expect(manager.state == .reauthenticationRequired(.sessionStoreFailure))
    }

    @Test("Restore expired session requires reauth")
    @MainActor
    func restoreExpiredSession() {
        let now = Date(timeIntervalSince1970: 2_000)
        let expired = AuthSession(
            accessToken: "access",
            refreshToken: "refresh",
            expiresAt: now.addingTimeInterval(-1),
            userID: "user"
        )
        let store = InMemoryStore(saved: expired)
        let manager = AuthSessionManager(
            tokenProvider: StubTokenProvider(signInResult: .success(expired), refreshResult: .success(expired)),
            store: store,
            dateProvider: FixedDateProvider(now: now)
        )

        manager.restoreSession()

        #expect(manager.state == .reauthenticationRequired(.tokenExpired))
    }

    @Test("Restore valid session transitions to authenticated")
    @MainActor
    func restoreValidSession() {
        let now = Date(timeIntervalSince1970: 2_000)
        let valid = AuthSession(
            accessToken: "access",
            refreshToken: "refresh",
            expiresAt: now.addingTimeInterval(120),
            userID: "user"
        )
        let store = InMemoryStore(saved: valid)
        let manager = AuthSessionManager(
            tokenProvider: StubTokenProvider(signInResult: .success(valid), refreshResult: .success(valid)),
            store: store,
            dateProvider: FixedDateProvider(now: now)
        )

        manager.restoreSession()

        #expect(manager.state == .authenticated(AuthSessionView(expiresAt: valid.expiresAt, userID: valid.userID)))
    }

    @Test("Restore invalid stored session triggers invalid stored session reauth")
    @MainActor
    func restoreInvalidStoredSession() {
        let now = Date(timeIntervalSince1970: 2_000)
        let invalid = AuthSession(
            accessToken: "",
            refreshToken: "refresh",
            expiresAt: now.addingTimeInterval(120),
            userID: "user"
        )
        let store = InMemoryStore(saved: invalid)
        let manager = AuthSessionManager(
            tokenProvider: StubTokenProvider(signInResult: .success(invalid), refreshResult: .success(invalid)),
            store: store,
            dateProvider: FixedDateProvider(now: now)
        )

        manager.restoreSession()

        #expect(manager.state == .reauthenticationRequired(.invalidStoredSession))
        #expect(store.saved == nil)
    }

    @Test("Refresh expired token updates state to authenticated")
    @MainActor
    func refreshSuccess() async {
        let now = Date(timeIntervalSince1970: 3_000)
        let clock = MutableDateProvider(now: now)
        let initial = AuthSession(
            accessToken: "access-old",
            refreshToken: "refresh-old",
            expiresAt: now.addingTimeInterval(60),
            userID: "user"
        )
        let refreshed = AuthSession(
            accessToken: "access-new",
            refreshToken: "refresh-new",
            expiresAt: now.addingTimeInterval(3600),
            userID: "user"
        )

        let provider = StubTokenProvider(signInResult: .success(initial), refreshResult: .success(refreshed))
        let store = InMemoryStore()
        let manager = AuthSessionManager(tokenProvider: provider, store: store, dateProvider: clock)
        _ = await manager.signIn(username: "u", password: "p")
        clock.now = now.addingTimeInterval(120)

        await manager.refreshIfNeeded()

        #expect(manager.state == .authenticated(AuthSessionView(expiresAt: refreshed.expiresAt, userID: refreshed.userID)))
        #expect(store.saved == refreshed)
        #expect(provider.lastRefreshToken == "refresh-old")
        #expect(provider.refreshCallCount == 1)
    }

    @Test("Refresh from token-expired restore state can recover authenticated session")
    @MainActor
    func refreshFromTokenExpiredState() async {
        let now = Date(timeIntervalSince1970: 3_000)
        let expired = AuthSession(
            accessToken: "access-old",
            refreshToken: "refresh-old",
            expiresAt: now.addingTimeInterval(-1),
            userID: "user"
        )
        let refreshed = AuthSession(
            accessToken: "access-new",
            refreshToken: "refresh-new",
            expiresAt: now.addingTimeInterval(3600),
            userID: "user"
        )
        let provider = StubTokenProvider(signInResult: .success(expired), refreshResult: .success(refreshed))
        let store = InMemoryStore(saved: expired)
        let manager = AuthSessionManager(tokenProvider: provider, store: store, dateProvider: FixedDateProvider(now: now))

        manager.restoreSession()
        #expect(manager.state == .reauthenticationRequired(.tokenExpired))

        await manager.refreshIfNeeded()

        #expect(manager.state == .authenticated(AuthSessionView(expiresAt: refreshed.expiresAt, userID: refreshed.userID)))
        #expect(store.saved == refreshed)
    }

    @Test("Refresh failure transitions to reauth required")
    @MainActor
    func refreshFailure() async {
        let now = Date(timeIntervalSince1970: 4_000)
        let clock = MutableDateProvider(now: now)
        let initial = AuthSession(
            accessToken: "access-old",
            refreshToken: "refresh-old",
            expiresAt: now.addingTimeInterval(60),
            userID: "user"
        )
        let provider = StubTokenProvider(signInResult: .success(initial), refreshResult: .failure(.networkUnavailable))
        let store = InMemoryStore()
        let manager = AuthSessionManager(tokenProvider: provider, store: store, dateProvider: clock)
        _ = await manager.signIn(username: "u", password: "p")
        clock.now = now.addingTimeInterval(120)

        await manager.refreshIfNeeded()

        #expect(manager.state == .reauthenticationRequired(.refreshFailed))
        #expect(store.saved == nil)
    }

    @Test("Refresh does not run when unauthenticated")
    @MainActor
    func refreshNoOpWhenUnauthenticated() async {
        let provider = StubTokenProvider(signInResult: .failure(.unknown), refreshResult: .failure(.unknown))
        let manager = AuthSessionManager(
            tokenProvider: provider,
            store: InMemoryStore(),
            dateProvider: FixedDateProvider(now: Date(timeIntervalSince1970: 10_000))
        )

        await manager.refreshIfNeeded()

        #expect(provider.refreshCallCount == 0)
        #expect(manager.state == .unauthenticated)
    }

    @Test("Refresh does not run when token has not expired")
    @MainActor
    func refreshNoOpWhenNotExpired() async {
        let now = Date(timeIntervalSince1970: 4_000)
        let valid = AuthSession(
            accessToken: "access",
            refreshToken: "refresh",
            expiresAt: now.addingTimeInterval(300),
            userID: "user"
        )
        let provider = StubTokenProvider(signInResult: .success(valid), refreshResult: .failure(.unknown))
        let manager = AuthSessionManager(
            tokenProvider: provider,
            store: InMemoryStore(saved: valid),
            dateProvider: FixedDateProvider(now: now)
        )
        manager.restoreSession()

        await manager.refreshIfNeeded()

        #expect(provider.refreshCallCount == 0)
        #expect(manager.state == .authenticated(AuthSessionView(expiresAt: valid.expiresAt, userID: valid.userID)))
    }

    @Test("Refresh failure when saving refreshed token clears state")
    @MainActor
    func refreshSaveFailure() async {
        let now = Date(timeIntervalSince1970: 4_000)
        let clock = MutableDateProvider(now: now)
        let initial = AuthSession(
            accessToken: "access-old",
            refreshToken: "refresh-old",
            expiresAt: now.addingTimeInterval(60),
            userID: "user"
        )
        let refreshed = AuthSession(
            accessToken: "access-new",
            refreshToken: "refresh-new",
            expiresAt: now.addingTimeInterval(300),
            userID: "user"
        )
        let provider = StubTokenProvider(signInResult: .success(initial), refreshResult: .success(refreshed))
        let store = InMemoryStore()
        let manager = AuthSessionManager(tokenProvider: provider, store: store, dateProvider: clock)
        _ = await manager.signIn(username: "u", password: "p")
        store.shouldThrowOnSave = true
        clock.now = now.addingTimeInterval(120)

        await manager.refreshIfNeeded()

        #expect(manager.state == .reauthenticationRequired(.refreshFailed))
        #expect(store.saved == nil)
    }

    @Test("Refresh cleanup failure surfaces explicit cleanup reason")
    @MainActor
    func refreshCleanupFailure() async {
        let now = Date(timeIntervalSince1970: 4_000)
        let providerNow = MutableDateProvider(now: now)
        let initial = AuthSession(
            accessToken: "access-old",
            refreshToken: "refresh-old",
            expiresAt: now.addingTimeInterval(120),
            userID: "user"
        )
        let provider = StubTokenProvider(signInResult: .success(initial), refreshResult: .failure(.networkUnavailable))
        let store = InMemoryStore(shouldThrowOnClear: true)
        let manager = AuthSessionManager(tokenProvider: provider, store: store, dateProvider: providerNow)
        _ = await manager.signIn(username: "u", password: "p")
        providerNow.now = now.addingTimeInterval(180)

        await manager.refreshIfNeeded()

        #expect(manager.state == .reauthenticationRequired(.credentialCleanupFailed))
    }

    @Test("Sign out clears secure store and sets signed-out reauth reason")
    @MainActor
    func signOutFlow() {
        let now = Date(timeIntervalSince1970: 5_000)
        let valid = AuthSession(
            accessToken: "access",
            refreshToken: "refresh",
            expiresAt: now.addingTimeInterval(100),
            userID: "user"
        )
        let store = InMemoryStore(saved: valid)
        let manager = AuthSessionManager(
            tokenProvider: StubTokenProvider(signInResult: .success(valid), refreshResult: .success(valid)),
            store: store,
            dateProvider: FixedDateProvider(now: now)
        )
        manager.restoreSession()

        manager.signOut()

        #expect(store.saved == nil)
        #expect(manager.state == .reauthenticationRequired(.signedOut))
    }

    @Test("Sign out failure keeps explicit failure state")
    @MainActor
    func signOutFailure() {
        let now = Date(timeIntervalSince1970: 5_000)
        let valid = AuthSession(
            accessToken: "access",
            refreshToken: "refresh",
            expiresAt: now.addingTimeInterval(100),
            userID: "user"
        )
        let store = InMemoryStore(saved: valid, shouldThrowOnClear: true)
        let manager = AuthSessionManager(
            tokenProvider: StubTokenProvider(signInResult: .success(valid), refreshResult: .success(valid)),
            store: store,
            dateProvider: FixedDateProvider(now: now)
        )
        manager.restoreSession()

        manager.signOut()

        #expect(manager.state == .reauthenticationRequired(.signOutFailed))
    }

    @Test("Sign out failure blocks restore from persisted session")
    @MainActor
    func signOutFailureBlocksRestore() {
        let now = Date(timeIntervalSince1970: 5_000)
        let valid = AuthSession(
            accessToken: "access",
            refreshToken: "refresh",
            expiresAt: now.addingTimeInterval(100),
            userID: "user"
        )
        let store = InMemoryStore(saved: valid, shouldThrowOnClear: true)
        let manager = AuthSessionManager(
            tokenProvider: StubTokenProvider(signInResult: .success(valid), refreshResult: .success(valid)),
            store: store,
            dateProvider: FixedDateProvider(now: now)
        )
        manager.restoreSession()
        #expect(manager.state == .authenticated(AuthSessionView(expiresAt: valid.expiresAt, userID: valid.userID)))

        manager.signOut()
        #expect(manager.state == .reauthenticationRequired(.signOutFailed))

        manager.restoreSession()
        #expect(manager.state == .reauthenticationRequired(.signOutFailed))
    }

    @Test("Recovery mappings cover all onboarding errors")
    @MainActor
    func recoveryMappings() {
        let manager = AuthSessionManager(
            tokenProvider: StubTokenProvider(signInResult: .failure(.unknown), refreshResult: .failure(.unknown)),
            store: InMemoryStore(),
            dateProvider: FixedDateProvider(now: Date(timeIntervalSince1970: 1))
        )

        #expect(manager.recovery(for: .invalidCredentials).actionLabel == "Retry Sign-In")
        #expect(manager.recovery(for: .networkUnavailable).actionLabel == "Retry")
        #expect(manager.recovery(for: .cancelledByUser).actionLabel == "Continue")
        #expect(manager.recovery(for: .providerConfiguration).actionLabel == "Try Later")
        #expect(manager.recovery(for: .unknown).actionLabel == "Retry")
    }
}

private struct FixedDateProvider: DateProvider {
    let now: Date
}

private final class MutableDateProvider: DateProvider, @unchecked Sendable {
    var now: Date

    init(now: Date) {
        self.now = now
    }
}

private final class InMemoryStore: SecureSessionStore, @unchecked Sendable {
    var saved: AuthSession?
    var shouldThrowOnLoad: Bool
    var shouldThrowOnSave: Bool
    var shouldThrowOnClear: Bool

    init(saved: AuthSession? = nil, shouldThrowOnLoad: Bool = false, shouldThrowOnSave: Bool = false, shouldThrowOnClear: Bool = false) {
        self.saved = saved
        self.shouldThrowOnLoad = shouldThrowOnLoad
        self.shouldThrowOnSave = shouldThrowOnSave
        self.shouldThrowOnClear = shouldThrowOnClear
    }

    func load() throws -> AuthSession? {
        if shouldThrowOnLoad {
            throw TestError.intentional
        }
        return saved
    }

    func save(_ session: AuthSession) throws {
        if shouldThrowOnSave {
            throw TestError.intentional
        }
        saved = session
    }

    func clear() throws {
        if shouldThrowOnClear {
            throw TestError.intentional
        }
        saved = nil
    }
}

private final class StubTokenProvider: AuthTokenProvider, @unchecked Sendable {
    let signInResult: Result<AuthSession, AuthOnboardingError>
    let refreshResult: Result<AuthSession, AuthOnboardingError>
    private(set) var refreshCallCount: Int = 0
    private(set) var lastRefreshToken: String?

    init(signInResult: Result<AuthSession, AuthOnboardingError>, refreshResult: Result<AuthSession, AuthOnboardingError>) {
        self.signInResult = signInResult
        self.refreshResult = refreshResult
    }

    func signIn(username: String, password: String) async throws -> AuthSession {
        switch signInResult {
        case let .success(session):
            return session
        case let .failure(error):
            throw error
        }
    }

    func refresh(using refreshToken: String) async throws -> AuthSession {
        refreshCallCount += 1
        lastRefreshToken = refreshToken
        switch refreshResult {
        case let .success(session):
            return session
        case let .failure(error):
            throw error
        }
    }
}

private enum TestError: Error {
    case intentional
}
