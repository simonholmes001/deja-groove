import SwiftUI
import DejaGrooveApp
import DejaGrooveAuth

@main
struct DejaGrooveMobileApp: App {
    @StateObject private var coordinator: AppAuthCoordinator
    private let apiClient: ApiClient

    init() {
        let config = AppConfiguration.load()
        let tokenProvider = EntraTokenProvider(
            config: config.entra,
            transport: URLSessionTokenTransport(),
            authorizer: DeferredWebAuthenticationAuthorizer())
        let authManager = AuthSessionManager(
            tokenProvider: tokenProvider,
            store: KeychainSessionStore())
        _coordinator = StateObject(wrappedValue: AppAuthCoordinator(authManager: authManager))
        apiClient = AuthenticatedApiClientFactory.make(baseUrl: config.apiBaseURL, authManager: authManager)
    }

    var body: some Scene {
        WindowGroup {
            AuthGateView(coordinator: coordinator) {
                DejaGrooveRootView(api: apiClient)
            }
        }
    }
}
