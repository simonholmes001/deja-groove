import Foundation
import DejaGrooveAuth

/// Builds a `LiveApiClient` whose bearer token is sourced from the
/// `AuthSessionManager`. This is the single seam that connects identity
/// (DejaGrooveAuth) to the API layer: the client asks the manager for a valid
/// access token per request, and the manager transparently refreshes an
/// expired one. When unauthenticated the token is `nil` and the client omits
/// the Authorization header, so the API responds 401 at the edge.
public enum AuthenticatedApiClientFactory {
    public static func make(
        baseUrl: URL,
        authManager: AuthSessionManager,
        transport: HttpTransport = URLSessionTransport(session: .shared)
    ) -> LiveApiClient {
        LiveApiClient(
            baseUrl: baseUrl,
            transport: transport,
            authTokenProvider: { await authManager.currentAccessToken() })
    }
}
