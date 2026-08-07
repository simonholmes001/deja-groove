import SwiftUI
import DejaGrooveApp
import DejaGrooveAuth

@main
struct DejaGrooveMobileApp: App {
    @StateObject private var coordinator: AppAuthCoordinator
    private let apiClient: ApiClient
    private let runtimeMode: DejaGrooveRuntimeMode
    private let startupError: String?

    init() {
        switch AppConfiguration.load() {
        case .success(let config):
            let authManager: AuthSessionManager
            switch config.runtimeMode {
            case .hosted:
                guard let entra = config.entra, let apiBaseURL = config.apiBaseURL else {
                    authManager = Self.disabledAuthManager()
                    _coordinator = StateObject(wrappedValue: AppAuthCoordinator(authManager: authManager))
                    apiClient = DisabledApiClient()
                    runtimeMode = .hosted
                    startupError = AppConfigurationError.missingRequiredKeys.errorDescription
                    return
                }
                let tokenProvider = EntraTokenProvider(
                    config: entra,
                    transport: URLSessionTokenTransport(),
                    authorizer: DeferredWebAuthenticationAuthorizer())
                authManager = AuthSessionManager(
                    tokenProvider: tokenProvider,
                    store: KeychainSessionStore())
                _coordinator = StateObject(wrappedValue: AppAuthCoordinator(authManager: authManager))
                apiClient = AuthenticatedApiClientFactory.make(baseUrl: apiBaseURL, authManager: authManager)
            case .localProxy:
                authManager = Self.disabledAuthManager()
                _coordinator = StateObject(wrappedValue: AppAuthCoordinator(authManager: authManager))
                apiClient = LocalProxyApiClientFactory.make(
                    recognitionProxyBaseURL: config.recognitionProxyBaseURL,
                    recognitionProxyKey: config.recognitionProxyKey)
            }
            runtimeMode = config.runtimeMode
            startupError = nil
        case .failure(let error):
            let authManager = Self.disabledAuthManager()
            _coordinator = StateObject(wrappedValue: AppAuthCoordinator(authManager: authManager))
            apiClient = DisabledApiClient()
            runtimeMode = .hosted
            startupError = error.errorDescription
        }
    }

    var body: some Scene {
        WindowGroup {
            if let startupError {
                StartupConfigurationErrorView(message: startupError)
            } else if runtimeMode == .hosted {
                AuthGateView(coordinator: coordinator) {
                    DejaGrooveRootView(
                        api: apiClient,
                        onAuthenticationRequired: {
                            await MainActor.run {
                                coordinator.invalidateSession()
                            }
                        })
                }
            } else {
                DejaGrooveRootView(api: apiClient)
            }
        }
    }

    private static func disabledAuthManager() -> AuthSessionManager {
        AuthSessionManager(
            tokenProvider: DisabledInteractiveTokenProvider(),
            store: KeychainSessionStore())
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

    func deleteCollectionRecord(id: UUID) async throws {
        throw ApiClientError.encodingFailure
    }

    func fetchCrateCollections(search: String?) async throws -> [CrateCollection] {
        throw ApiClientError.encodingFailure
    }

    func createCrateCollection(name: String) async throws -> CrateCollection {
        throw ApiClientError.encodingFailure
    }

    func renameCrateCollection(id: UUID, name: String) async throws -> CrateCollection {
        throw ApiClientError.encodingFailure
    }

    func deleteCrateCollection(id: UUID) async throws {
        throw ApiClientError.encodingFailure
    }

    func addRecord(_ recordId: UUID, toCrateCollection collectionId: UUID) async throws -> CrateCollection {
        throw ApiClientError.encodingFailure
    }

    func removeRecord(_ recordId: UUID, fromCrateCollection collectionId: UUID) async throws -> CrateCollection {
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
