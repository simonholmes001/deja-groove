import UIKit
import DejaGrooveAuth

enum PresentationAnchorResolver {
    @MainActor
    static func resolve() -> UIWindow? {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            if let key = windowScene.windows.first(where: \.isKeyWindow) {
                return key
            }
            if let first = windowScene.windows.first {
                return first
            }
        }
        return nil
    }
}

final class DeferredWebAuthenticationAuthorizer: AuthorizationCodeRequesting, @unchecked Sendable {
    @MainActor
    func requestCode(
        authorizationURL: URL,
        redirectURI: URL,
        expectedState: String
    ) async throws -> AuthorizationCodeResult {
        guard let anchor = PresentationAnchorResolver.resolve() else {
            throw AuthOnboardingError.providerConfiguration
        }
        let authorizer = WebAuthenticationAuthorizer(presentationAnchor: anchor)
        return try await authorizer.requestCode(
            authorizationURL: authorizationURL,
            redirectURI: redirectURI,
            expectedState: expectedState)
    }
}
