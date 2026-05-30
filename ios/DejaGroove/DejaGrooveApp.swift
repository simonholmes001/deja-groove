import SwiftUI
import DejaGrooveApp
import DejaGrooveAuth

@main
struct DejaGrooveMobileApp: App {
    @StateObject private var coordinator: AppAuthCoordinator
    private let apiClient: ApiClient
    private let startupError: String?

    init() {
        switch AppConfiguration.load() {
        case .success(let config):
            let tokenProvider = EntraTokenProvider(
                config: config.entra,
                transport: URLSessionTokenTransport(),
                authorizer: DeferredWebAuthenticationAuthorizer())
            let authManager = AuthSessionManager(
                tokenProvider: tokenProvider,
                store: KeychainSessionStore())
            _coordinator = StateObject(wrappedValue: AppAuthCoordinator(authManager: authManager))
            apiClient = AuthenticatedApiClientFactory.make(baseUrl: config.apiBaseURL, authManager: authManager)
            startupError = nil
        case .failure(let error):
            let authManager = AuthSessionManager(
                tokenProvider: DisabledInteractiveTokenProvider(),
                store: KeychainSessionStore())
            _coordinator = StateObject(wrappedValue: AppAuthCoordinator(authManager: authManager))
            apiClient = DisabledApiClient()
            startupError = error.errorDescription
        }
    }

    var body: some Scene {
        WindowGroup {
            if let startupError {
                StartupConfigurationErrorView(message: startupError)
            } else {
                AuthGateView(coordinator: coordinator) {
                    DejaGrooveRootView(
                        api: apiClient,
                        onAuthenticationRequired: {
                            await coordinator.refreshAuthenticationState()
                        })
                }
            }
        }
    }
}

private struct StartupConfigurationErrorView: View {
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Text("Configuration Error")
                .font(.title2.bold())
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Text("Update build configuration values and relaunch.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(24)
    }
}

private struct DisabledApiClient: ApiClient {
    func scan(imageData: Data, clientScanId: UUID, capturedAtIso: String?) async throws -> ScanResponse {
        throw ApiClientError.encodingFailure
    }

    func resolve(requestId: UUID, selectedMbid: String?, selectedDiscogsReleaseId: String?) async throws -> ScanResponse {
        throw ApiClientError.encodingFailure
    }

    func addToCollection(album: Album, notes: String?, addAnyway: Bool) async throws -> CollectionItemResponse {
        throw ApiClientError.encodingFailure
    }

    func fetchCollection(search: String?) async throws -> CollectionListResponse {
        throw ApiClientError.encodingFailure
    }

    func patchCollection(id: UUID, format: String?, notes: String?) async throws -> CollectionItemResponse {
        throw ApiClientError.encodingFailure
    }
}

private final class DisabledInteractiveTokenProvider: InteractiveAuthTokenProvider, @unchecked Sendable {
    func signIn(username: String, password: String) async throws -> AuthSession {
        throw AuthOnboardingError.providerConfiguration
    }

    func signInInteractively() async throws -> AuthSession {
        throw AuthOnboardingError.providerConfiguration
    }

    func refresh(using refreshToken: String) async throws -> AuthSession {
        throw AuthOnboardingError.providerConfiguration
    }
}
