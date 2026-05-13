import Foundation

public protocol AuthTokenProvider: Sendable {
    func signIn(username: String, password: String) async throws -> AuthSession
    func refresh(using refreshToken: String) async throws -> AuthSession
}

public protocol SecureSessionStore: Sendable {
    func load() throws -> AuthSession?
    func save(_ session: AuthSession) throws
    func clear() throws
}

public protocol DateProvider: Sendable {
    var now: Date { get }
}

public struct SystemDateProvider: DateProvider {
    public init() {}
    public var now: Date { Date() }
}
