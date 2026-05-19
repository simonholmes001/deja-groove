import Foundation
import XCTest
import DejaGrooveAuth
@testable import DejaGrooveApp

final class AuthenticatedApiClientTests: XCTestCase {
    func testClientSendsBearerTokenFromAuthenticatedManager() async throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let session = AuthSession(
            accessToken: "session-at",
            refreshToken: "rt",
            expiresAt: now.addingTimeInterval(3600),
            userID: "user-1")
        let manager = await AuthSessionManager(
            tokenProvider: BridgeStubProvider(session: session),
            store: BridgeInMemoryStore(),
            dateProvider: BridgeFixedDate(now: now))
        _ = await manager.signIn(username: "u", password: "p")

        let transport = RecordingTransport(responseData: Self.scanJson)
        let client = AuthenticatedApiClientFactory.make(
            baseUrl: URL(string: "https://api.example.com/")!,
            authManager: manager,
            transport: transport)

        _ = try await client.scan(imageData: Data([0xFF, 0xD8]), clientScanId: UUID(), capturedAtIso: nil)

        let request = await transport.lastRequest
        XCTAssertEqual("Bearer session-at", request?.value(forHTTPHeaderField: "Authorization"))
    }

    func testClientOmitsAuthorizationWhenUnauthenticated() async throws {
        let manager = await AuthSessionManager(
            tokenProvider: BridgeStubProvider(session: nil),
            store: BridgeInMemoryStore(),
            dateProvider: BridgeFixedDate(now: Date()))

        let transport = RecordingTransport(responseData: Self.scanJson)
        let client = AuthenticatedApiClientFactory.make(
            baseUrl: URL(string: "https://api.example.com/")!,
            authManager: manager,
            transport: transport)

        _ = try await client.scan(imageData: Data([0xFF, 0xD8]), clientScanId: UUID(), capturedAtIso: nil)

        let request = await transport.lastRequest
        XCTAssertNil(request?.value(forHTTPHeaderField: "Authorization"))
    }

    private static let scanJson = """
    {"status":"no_match","confidence":0.0,"album":null,"candidates":[],"request_id":"00000000-0000-0000-0000-000000000001"}
    """.data(using: .utf8)!
}

final class BridgeStubProvider: AuthTokenProvider, @unchecked Sendable {
    private let session: AuthSession?
    init(session: AuthSession?) { self.session = session }

    func signIn(username: String, password: String) async throws -> AuthSession {
        guard let session else { throw AuthOnboardingError.invalidCredentials }
        return session
    }
    func refresh(using refreshToken: String) async throws -> AuthSession {
        guard let session else { throw AuthOnboardingError.invalidCredentials }
        return session
    }
}

final class BridgeInMemoryStore: SecureSessionStore, @unchecked Sendable {
    private var session: AuthSession?
    func load() throws -> AuthSession? { session }
    func save(_ session: AuthSession) throws { self.session = session }
    func clear() throws { session = nil }
}

struct BridgeFixedDate: DateProvider {
    let now: Date
}
