import Foundation
import DejaGrooveAuth

enum DejaGrooveRuntimeMode: String, Equatable {
    case hosted
    case localProxy = "local_proxy"

    init?(configurationValue: String) {
        let normalized = configurationValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")

        switch normalized {
        case "hosted":
            self = .hosted
        case "local_proxy", "localproxy":
            self = .localProxy
        default:
            return nil
        }
    }
}

enum AppConfiguration {
    static func load(bundle: Bundle = .main) -> Result<LoadedAppConfiguration, AppConfigurationError> {
        let runtimeModeRaw = bundle.object(forInfoDictionaryKey: "DEJA_GROOVE_RUNTIME_MODE") as? String ?? "hosted"
        guard let runtimeMode = DejaGrooveRuntimeMode(configurationValue: runtimeModeRaw) else {
            return .failure(.invalidRuntimeMode)
        }

        switch runtimeMode {
        case .hosted:
            return loadHosted(bundle: bundle)
        case .localProxy:
            return loadLocalProxy(bundle: bundle)
        }
    }

    private static func loadHosted(bundle: Bundle) -> Result<LoadedAppConfiguration, AppConfigurationError> {
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
            runtimeMode: .hosted,
            apiBaseURL: apiBaseURL,
            recognitionProxyBaseURL: nil,
            recognitionProxyKey: nil,
            entra: EntraConfig(
                authority: authority,
                clientID: clientID,
                redirectURI: redirectURI,
                scopes: scopes)))
    }

    private static func loadLocalProxy(bundle: Bundle) -> Result<LoadedAppConfiguration, AppConfigurationError> {
        guard let proxyURLRaw = bundle.object(forInfoDictionaryKey: "DEJA_GROOVE_RECOGNITION_PROXY_BASE_URL") as? String,
              let recognitionProxyBaseURL = URL(string: proxyURLRaw),
              let recognitionProxyKey = bundle.object(forInfoDictionaryKey: "DEJA_GROOVE_RECOGNITION_PROXY_KEY") as? String else {
            return .failure(.missingRequiredKeys)
        }
        guard recognitionProxyBaseURL.scheme?.lowercased() == "https" else {
            return .failure(.recognitionProxyBaseUrlMustUseHttps)
        }
        guard !recognitionProxyKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !recognitionProxyKey.hasPrefix("REPLACE_") else {
            return .failure(.placeholderRecognitionProxyKey)
        }

        return .success(LoadedAppConfiguration(
            runtimeMode: .localProxy,
            apiBaseURL: nil,
            recognitionProxyBaseURL: recognitionProxyBaseURL,
            recognitionProxyKey: recognitionProxyKey,
            entra: nil))
    }
}

struct LoadedAppConfiguration {
    let runtimeMode: DejaGrooveRuntimeMode
    let apiBaseURL: URL?
    let recognitionProxyBaseURL: URL?
    let recognitionProxyKey: String?
    let entra: EntraConfig?
}

enum AppConfigurationError: Error, LocalizedError {
    case missingRequiredKeys
    case invalidRuntimeMode
    case apiBaseUrlMustUseHttps
    case recognitionProxyBaseUrlMustUseHttps
    case authorityMustUseHttps
    case placeholderClientId
    case placeholderRecognitionProxyKey
    case redirectUriSchemeMismatch
    case emptyScopes

    var errorDescription: String? {
        switch self {
        case .missingRequiredKeys:
            return "Missing required app configuration values."
        case .invalidRuntimeMode:
            return "Runtime mode must be hosted or local_proxy."
        case .apiBaseUrlMustUseHttps:
            return "API base URL must use HTTPS."
        case .recognitionProxyBaseUrlMustUseHttps:
            return "Recognition proxy base URL must use HTTPS."
        case .authorityMustUseHttps:
            return "Entra authority must use HTTPS."
        case .placeholderClientId:
            return "Entra client ID is not configured for this build."
        case .placeholderRecognitionProxyKey:
            return "Recognition proxy function key is not configured for this build."
        case .redirectUriSchemeMismatch:
            return "Redirect URI scheme does not match app URL scheme."
        case .emptyScopes:
            return "Entra scopes are empty."
        }
    }
}
