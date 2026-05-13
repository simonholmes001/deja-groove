import Foundation

public enum AuthState: Equatable, Sendable {
    case unauthenticated
    case authenticating
    case authenticated(AuthSession)
    case refreshing(AuthSession)
    case reauthenticationRequired(ReauthReason)
}

public struct AuthSession: Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Date
    public let userID: String

    public init(accessToken: String, refreshToken: String, expiresAt: Date, userID: String) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.userID = userID
    }
}

public enum ReauthReason: String, Equatable, Sendable {
    case refreshFailed
    case missingSession
    case signedOut
    case signOutFailed
    case tokenExpired
}

public enum AuthOnboardingError: Error, Equatable, Sendable {
    case invalidCredentials
    case networkUnavailable
    case cancelledByUser
    case providerConfiguration
    case unknown
}

public struct AuthOnboardingRecovery: Equatable, Sendable {
    public let title: String
    public let message: String
    public let actionLabel: String

    public init(title: String, message: String, actionLabel: String) {
        self.title = title
        self.message = message
        self.actionLabel = actionLabel
    }
}
