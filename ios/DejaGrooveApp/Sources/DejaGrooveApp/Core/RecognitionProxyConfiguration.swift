import Foundation

public enum RecognitionProxyConfiguration {
    public static func validate(baseURL: URL, functionKey: String) -> RecognitionProxyConfigurationError? {
        guard baseURL.scheme?.lowercased() == "https" else {
            return .baseURLMustUseHttps
        }
        guard !isPlaceholderBaseURL(baseURL) else {
            return .placeholderBaseURL
        }
        let trimmedKey = functionKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty, !trimmedKey.hasPrefix("REPLACE_") else {
            return .placeholderFunctionKey
        }
        return nil
    }

    private static func isPlaceholderBaseURL(_ url: URL) -> Bool {
        guard let host = url.host()?.lowercased() else { return true }
        return host.hasSuffix(".example") || host == "example.com"
    }
}

public enum RecognitionProxyConfigurationError: Equatable, Sendable {
    case baseURLMustUseHttps
    case placeholderBaseURL
    case placeholderFunctionKey
}
