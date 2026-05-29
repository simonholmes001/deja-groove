import Foundation
import DejaGrooveAuth

@MainActor
public final class AppAuthCoordinator: ObservableObject {
    @Published public private(set) var requiresSignIn = true
    @Published public private(set) var lastError: AuthOnboardingRecovery?
    @Published public private(set) var isSigningIn = false

    private let authManager: AuthSessionManager

    public init(authManager: AuthSessionManager) {
        self.authManager = authManager
    }

    public func bootstrap() {
        authManager.restoreSession()
        syncFromAuthState()
    }

    public func signInInteractively() async {
        guard !isSigningIn else { return }
        isSigningIn = true
        defer { isSigningIn = false }

        let result = await authManager.signInInteractively()
        switch result {
        case .success:
            lastError = nil
        case .failure(let error):
            lastError = authManager.recovery(for: error)
        }
        syncFromAuthState()
    }

    public func signOut() {
        authManager.signOut()
        syncFromAuthState()
    }

    public func refreshAuthenticationState() async {
        _ = await authManager.currentAccessToken()
        syncFromAuthState()
    }

    private func syncFromAuthState() {
        switch authManager.state {
        case .authenticated:
            requiresSignIn = false
        default:
            requiresSignIn = true
        }
    }
}
