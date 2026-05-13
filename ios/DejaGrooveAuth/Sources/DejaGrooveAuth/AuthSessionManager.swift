import Foundation

@MainActor
public final class AuthSessionManager {
    public private(set) var state: AuthState = .unauthenticated

    private let tokenProvider: AuthTokenProvider
    private let store: SecureSessionStore
    private let dateProvider: DateProvider

    public init(tokenProvider: AuthTokenProvider, store: SecureSessionStore, dateProvider: DateProvider = SystemDateProvider()) {
        self.tokenProvider = tokenProvider
        self.store = store
        self.dateProvider = dateProvider
    }

    public func signIn(username: String, password: String) async -> Result<AuthSession, AuthOnboardingError> {
        state = .authenticating
        do {
            let session = try await tokenProvider.signIn(username: username, password: password)
            guard isValid(session) else {
                state = .unauthenticated
                return .failure(.providerConfiguration)
            }
            try store.save(session)
            state = .authenticated(session)
            return .success(session)
        } catch let error as AuthOnboardingError {
            state = .unauthenticated
            return .failure(error)
        } catch {
            state = .unauthenticated
            return .failure(.unknown)
        }
    }

    public func restoreSession() {
        let loaded: AuthSession?
        do {
            loaded = try store.load()
        } catch {
            state = .reauthenticationRequired(.missingSession)
            return
        }
        guard let session = loaded else {
            state = .reauthenticationRequired(.missingSession)
            return
        }
        state = .authenticated(session)
    }

    public func refreshIfNeeded() async {
        guard case let .authenticated(session) = state else { return }
        guard session.expiresAt <= dateProvider.now else { return }

        state = .refreshing(session)
        do {
            let refreshed = try await tokenProvider.refresh(using: session.refreshToken)
            guard isValid(refreshed) else {
                try? store.clear()
                state = .reauthenticationRequired(.refreshFailed)
                return
            }
            try store.save(refreshed)
            state = .authenticated(refreshed)
        } catch {
            try? store.clear()
            state = .reauthenticationRequired(.refreshFailed)
        }
    }

    public func signOut() {
        do {
            try store.clear()
            state = .reauthenticationRequired(.signedOut)
        } catch {
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

    private func isValid(_ session: AuthSession) -> Bool {
        !session.accessToken.isEmpty &&
        !session.refreshToken.isEmpty &&
        !session.userID.isEmpty &&
        session.expiresAt > dateProvider.now
    }
}
