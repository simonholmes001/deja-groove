#if canImport(AuthenticationServices) && os(iOS)
import Foundation
import AuthenticationServices

/// Production `AuthorizationCodeRequesting` backed by
/// `ASWebAuthenticationSession`. This is the deliberately thin, untestable UI
/// boundary: it only presents the system browser and parses `code`/`state`
/// from the redirect — all flow logic lives in the unit-tested
/// `EntraTokenProvider`. Mirrors the `SystemKeychain` humble-object pattern.
@MainActor
public final class WebAuthenticationAuthorizer: NSObject, AuthorizationCodeRequesting,
    ASWebAuthenticationPresentationContextProviding {

    private let anchor: ASPresentationAnchor

    public init(presentationAnchor: ASPresentationAnchor) {
        self.anchor = presentationAnchor
    }

    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor
    }

    public func requestCode(
        authorizationURL: URL,
        redirectURI: URL,
        expectedState: String
    ) async throws -> AuthorizationCodeResult {
        let callbackScheme = redirectURI.scheme
        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authorizationURL,
                callbackURLScheme: callbackScheme
            ) { url, error in
                if let error {
                    let cancelled = (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin
                    continuation.resume(
                        throwing: cancelled
                            ? AuthOnboardingError.cancelledByUser
                            : AuthOnboardingError.unknown)
                    return
                }
                guard let url else {
                    continuation.resume(throwing: AuthOnboardingError.unknown)
                    return
                }
                continuation.resume(returning: url)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            if !session.start() {
                continuation.resume(throwing: AuthOnboardingError.providerConfiguration)
            }
        }

        let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard let code = items.first(where: { $0.name == "code" })?.value,
              let state = items.first(where: { $0.name == "state" })?.value else {
            throw AuthOnboardingError.providerConfiguration
        }
        return AuthorizationCodeResult(code: code, state: state)
    }
}
#endif
