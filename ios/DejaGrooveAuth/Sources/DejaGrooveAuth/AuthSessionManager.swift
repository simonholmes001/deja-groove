import Foundation

@MainActor
public final class AuthSessionManager {
    public private(set) var state: AuthState = .unauthenticated

    private let tokenProvider: AuthTokenProvider
    private let store: SecureSessionStore
    private let dateProvider: DateProvider
    private var currentSession: AuthSession?
    private var restoreBlockedBySignOutFailure = false

    public init(tokenProvider: AuthTokenProvider, store: SecureSessionStore, dateProvider: DateProvider = SystemDateProvider()) {
        self.tokenProvider = tokenProvider
        self.store = store
        self.dateProvider = dateProvider
    }

    public func signIn(username: String, password: String) async -> Result<AuthSession, AuthOnboardingError> {
        state = .authenticating
        do {
            let session = try await tokenProvider.signIn(username: username, password: password)
            guard isStructurallyValid(session), !isExpired(session) else {
                state = .unauthenticated
                return .failure(.providerConfiguration)
            }
            try store.save(session)
            transitionToAuthenticated(session)
            return .success(session)
        } catch let error as AuthOnboardingError {
            handleSignInFailureCleanup(defaultState: .unauthenticated)
            return .failure(error)
        } catch {
            handleSignInFailureCleanup(defaultState: .unauthenticated)
            return .failure(.unknown)
        }
    }

    public func restoreSession() {
        if restoreBlockedBySignOutFailure {
            currentSession = nil
            state = .reauthenticationRequired(.signOutFailed)
            return
        }

        let loaded: AuthSession?
        do {
            loaded = try store.load()
        } catch {
            state = .reauthenticationRequired(.sessionStoreFailure)
            return
        }
        guard let session = loaded else {
            state = .reauthenticationRequired(.missingSession)
            return
        }
        guard isStructurallyValid(session) else {
            transitionAfterCredentialCleanup(defaultReason: .invalidStoredSession)
            return
        }
        guard !isExpired(session) else {
            currentSession = session
            state = .reauthenticationRequired(.tokenExpired)
            return
        }
        transitionToAuthenticated(session)
    }

    public func refreshIfNeeded() async {
        switch state {
        case .authenticated, .reauthenticationRequired(.tokenExpired):
            break
        default:
            return
        }
        guard let session = currentSession else { return }
        guard isExpired(session) else { return }

        state = .refreshing(AuthSessionView(expiresAt: session.expiresAt, userID: session.userID))
        do {
            let refreshed = try await tokenProvider.refresh(using: session.refreshToken)
            guard isStructurallyValid(refreshed), !isExpired(refreshed) else {
                transitionAfterCredentialCleanup(defaultReason: .refreshFailed)
                return
            }
            try store.save(refreshed)
            transitionToAuthenticated(refreshed)
        } catch {
            transitionAfterCredentialCleanup(defaultReason: .refreshFailed)
        }
    }

    public func signOut() {
        do {
            try store.clear()
            restoreBlockedBySignOutFailure = false
            currentSession = nil
            state = .reauthenticationRequired(.signedOut)
        } catch {
            restoreBlockedBySignOutFailure = true
            currentSession = nil
            state = .reauthenticationRequired(.signOutFailed)
        }
    }

    public func recovery(for error: AuthOnboardingError) -> AuthOnboardingRecovery {
        switch error {
        case .invalidCredentials:
            return AuthOnboardingRecovery(
                title: "Invalid Credentials",
                message: "Your email or password is incorrect. Please try again.",
                actionLabel: "Retry Sign-In"
            )
        case .networkUnavailable:
            return AuthOnboardingRecovery(
                title: "No Connection",
                message: "Please check your network connection and retry.",
                actionLabel: "Retry"
            )
        case .cancelledByUser:
            return AuthOnboardingRecovery(
                title: "Sign-In Cancelled",
                message: "You can resume onboarding whenever you are ready.",
                actionLabel: "Continue"
            )
        case .providerConfiguration:
            return AuthOnboardingRecovery(
                title: "Authentication Unavailable",
                message: "Sign-in is temporarily unavailable. Please try again later.",
                actionLabel: "Try Later"
            )
        case .unknown:
            return AuthOnboardingRecovery(
                title: "Unexpected Error",
                message: "An unexpected error occurred. Please try again.",
                actionLabel: "Retry"
            )
        }
    }

    private func transitionToAuthenticated(_ session: AuthSession) {
        restoreBlockedBySignOutFailure = false
        currentSession = session
        state = .authenticated(AuthSessionView(expiresAt: session.expiresAt, userID: session.userID))
    }

    private func transitionAfterCredentialCleanup(defaultReason: ReauthReason) {
        currentSession = nil
        do {
            try store.clear()
            state = .reauthenticationRequired(defaultReason)
        } catch {
            state = .reauthenticationRequired(.credentialCleanupFailed)
        }
    }

    private func handleSignInFailureCleanup(defaultState: AuthState) {
        currentSession = nil
        do {
            try store.clear()
            state = defaultState
        } catch {
            state = .reauthenticationRequired(.credentialCleanupFailed)
        }
    }

    private func isStructurallyValid(_ session: AuthSession) -> Bool {
        !session.accessToken.isEmpty &&
        !session.refreshToken.isEmpty &&
        !session.userID.isEmpty
    }

    private func isExpired(_ session: AuthSession) -> Bool {
        session.expiresAt <= dateProvider.now
    }
}
