import Foundation
import DejaGrooveAuth

enum AppConfiguration {
    static func load(bundle: Bundle = .main) -> LoadedAppConfiguration {
        guard let baseURL = bundle.object(forInfoDictionaryKey: "DEJA_GROOVE_API_BASE_URL") as? String,
              let apiBaseURL = URL(string: baseURL),
              let authorityRaw = bundle.object(forInfoDictionaryKey: "DEJA_GROOVE_ENTRA_AUTHORITY") as? String,
              let authority = URL(string: authorityRaw),
              let clientID = bundle.object(forInfoDictionaryKey: "DEJA_GROOVE_ENTRA_CLIENT_ID") as? String,
              let redirectRaw = bundle.object(forInfoDictionaryKey: "DEJA_GROOVE_ENTRA_REDIRECT_URI") as? String,
              let redirectURI = URL(string: redirectRaw),
              let scopesRaw = bundle.object(forInfoDictionaryKey: "DEJA_GROOVE_ENTRA_SCOPES") as? String else {
            preconditionFailure("Missing required app configuration in Info.plist")
        }

        let scopes = scopesRaw
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }
        precondition(apiBaseURL.scheme?.lowercased() == "https", "DEJA_GROOVE_API_BASE_URL must be https")
        precondition(authority.scheme?.lowercased() == "https", "DEJA_GROOVE_ENTRA_AUTHORITY must be https")
        precondition(!clientID.hasPrefix("REPLACE_"), "DEJA_GROOVE_ENTRA_CLIENT_ID must be configured")
        precondition(redirectURI.scheme == "msauth.com.dejagroove.app", "DEJA_GROOVE_ENTRA_REDIRECT_URI scheme mismatch")
        precondition(!scopes.isEmpty, "DEJA_GROOVE_ENTRA_SCOPES must not be empty")

        return LoadedAppConfiguration(
            apiBaseURL: apiBaseURL,
            entra: EntraConfig(
                authority: authority,
                clientID: clientID,
                redirectURI: redirectURI,
                scopes: scopes))
    }
}

struct LoadedAppConfiguration {
    let apiBaseURL: URL
    let entra: EntraConfig
}
