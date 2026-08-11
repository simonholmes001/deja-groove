import Foundation

enum DejaGrooveRuntimeMode: String, Equatable {
    case localProxy = "local_proxy"

    init?(configurationValue: String) {
        let normalized = configurationValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")

        switch normalized {
        case "local_proxy", "localproxy":
            self = .localProxy
        default:
            return nil
        }
    }
}

enum AppConfiguration {
    static func load(bundle: Bundle = .main) -> Result<LoadedAppConfiguration, AppConfigurationError> {
        let runtimeModeRaw = bundle.object(forInfoDictionaryKey: "DEJA_GROOVE_RUNTIME_MODE") as? String ?? DejaGrooveRuntimeMode.localProxy.rawValue
        guard DejaGrooveRuntimeMode(configurationValue: runtimeModeRaw) == .localProxy else {
            return .failure(.invalidRuntimeMode)
        }

        return loadLocalProxy(bundle: bundle)
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
            recognitionProxyBaseURL: recognitionProxyBaseURL,
            recognitionProxyKey: recognitionProxyKey))
    }
}

struct LoadedAppConfiguration {
    let recognitionProxyBaseURL: URL?
    let recognitionProxyKey: String?
}

enum AppConfigurationError: Error, LocalizedError {
    case missingRequiredKeys
    case invalidRuntimeMode
    case recognitionProxyBaseUrlMustUseHttps
    case placeholderRecognitionProxyKey

    var errorDescription: String? {
        switch self {
        case .missingRequiredKeys:
            return "Missing required app configuration values."
        case .invalidRuntimeMode:
            return "Runtime mode must be local_proxy."
        case .recognitionProxyBaseUrlMustUseHttps:
            return "Recognition proxy base URL must use HTTPS."
        case .placeholderRecognitionProxyKey:
            return "Recognition proxy function key is not configured for this build."
        }
    }
}
