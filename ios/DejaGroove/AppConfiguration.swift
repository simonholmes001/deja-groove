import Foundation
import DejaGrooveAuth

enum AppConfiguration {
    static func load(bundle: Bundle = .main) -> Result<LoadedAppConfiguration, AppConfigurationError> {
        guard let baseURL = bundle.object(forInfoDictionaryKey: "DEJA_GROOVE_API_BASE_URL") as? String,
              let apiBaseURL = URL(string: baseURL),
              let authorityRaw = bundle.object(forInfoDictionaryKey: "DEJA_GROOVE_ENTRA_AUTHORITY") as? String,
              let authority = URL(string: authorityRaw),
              let clientID = bundle.object(forInfoDictionaryKey: "DEJA_GROOVE_ENTRA_CLIENT_ID") as? String,
              let redirectRaw = bundle.object(forInfoDictionaryKey: "DEJA_GROOVE_ENTRA_REDIRECT_URI") as? String,
              let redirectURI = URL(string: redirectRaw),
              let scopesRaw = bundle.object(forInfoDictionaryKey: "DEJA_GROOVE_ENTRA_SCOPES") as? String else {
            return .failure(.missingRequiredKeys)
        }

        let scopes = scopesRaw
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }
        guard apiBaseURL.scheme?.lowercased() == "https" else {
            return .failure(.apiBaseUrlMustUseHttps)
        }
        guard authority.scheme?.lowercased() == "https" else {
            return .failure(.authorityMustUseHttps)
        }
        guard !clientID.hasPrefix("REPLACE_"), !clientID.isEmpty else {
            return .failure(.placeholderClientId)
        }
        guard redirectURI.scheme == "msauth.com.dejagroove.app" else {
            return .failure(.redirectUriSchemeMismatch)
        }
        guard !scopes.isEmpty else {
            return .failure(.emptyScopes)
        }

        return .success(LoadedAppConfiguration(
            apiBaseURL: apiBaseURL,
            entra: EntraConfig(
                authority: authority,
                clientID: clientID,
                redirectURI: redirectURI,
                scopes: scopes)))
    }
}

struct LoadedAppConfiguration {
    let apiBaseURL: URL
    let entra: EntraConfig
}

enum AppConfigurationError: Error, LocalizedError {
    case missingRequiredKeys
    case apiBaseUrlMustUseHttps
    case authorityMustUseHttps
    case placeholderClientId
    case redirectUriSchemeMismatch
    case emptyScopes

    var errorDescription: String? {
        switch self {
        case .missingRequiredKeys:
            return "Missing required app configuration values."
        case .apiBaseUrlMustUseHttps:
            return "API base URL must use HTTPS."
        case .authorityMustUseHttps:
            return "Entra authority must use HTTPS."
        case .placeholderClientId:
            return "Entra client ID is not configured for this build."
        case .redirectUriSchemeMismatch:
            return "Redirect URI scheme does not match app URL scheme."
        case .emptyScopes:
            return "Entra scopes are empty."
        }
    }
}
