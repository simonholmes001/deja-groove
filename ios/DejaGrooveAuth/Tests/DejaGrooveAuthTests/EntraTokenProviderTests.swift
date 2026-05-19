import Foundation
import Testing
@testable import DejaGrooveAuth

@Suite("Entra Token Provider")
struct EntraTokenProviderTests {
    private static let config = EntraConfig(
        authority: URL(string: "https://dejagroove.ciamlogin.com/dejagroove.onmicrosoft.com")!,
        clientID: "client-123",
        redirectURI: URL(string: "msauth.com.dejagroove.app://auth")!,
        scopes: ["openid", "offline_access", "api://deja-groove-api/scan"]
    )

    // Minimal unsigned JWT with sub=user-xyz (client only reads the subject;
    // the backend performs signature/issuer/audience validation).
    private static func idToken(sub: String) -> String {
        func b64(_ s: String) -> String {
            Data(s.utf8).base64URLEncodedString()
        }
        return "\(b64("{\"alg\":\"none\"}")).\(b64("{\"sub\":\"\(sub)\"}")).sig"
    }

    private static func tokenJSON(sub: String) -> Data {
        Data(#"""
        {"access_token":"at-1","refresh_token":"rt-1","expires_in":3600,"id_token":"\#(idToken(sub: sub))"}
        """#.utf8)
    }

    @Test("Refresh exchanges the refresh token for a new session")
    func refreshSuccess() async throws {
        let transport = FakeTokenTransport(
            response: (Self.tokenJSON(sub: "user-xyz"), 200))
        let now = Date(timeIntervalSince1970: 10_000)
        let provider = EntraTokenProvider(
            config: Self.config,
            transport: transport,
            authorizer: FakeAuthorizer(),
            now: { now })

        let session = try await provider.refresh(using: "old-rt")

        #expect(session.accessToken == "at-1")
        #expect(session.refreshToken == "rt-1")
        #expect(session.userID == "user-xyz")
        #expect(session.expiresAt == now.addingTimeInterval(3600))
        // Correct grant + endpoint.
        let body = transport.lastBodyParameters
        #expect(body["grant_type"] == "refresh_token")
        #expect(body["refresh_token"] == "old-rt")
        #expect(body["client_id"] == "client-123")
        #expect(transport.lastURL?.path.contains("/oauth2/v2.0/token") == true)
    }

    @Test("Refresh maps a non-2xx token response to a provider error")
    func refreshHttpError() async {
        let transport = FakeTokenTransport(
            response: (Data(#"{"error":"invalid_grant"}"#.utf8), 400))
        let provider = EntraTokenProvider(
            config: Self.config, transport: transport,
            authorizer: FakeAuthorizer(), now: { Date() })

        await #expect(throws: AuthOnboardingError.invalidCredentials) {
            _ = try await provider.refresh(using: "expired-rt")
        }
    }

    @Test("invalid_grant at 400 maps to credentials error (re-auth)")
    func errorBodyInvalidGrant() async {
        let transport = FakeTokenTransport(
            response: (Data(#"{"error":"invalid_grant","error_description":"expired"}"#.utf8), 400))
        let provider = EntraTokenProvider(
            config: Self.config, transport: transport,
            authorizer: FakeAuthorizer(), now: { Date() })

        await #expect(throws: AuthOnboardingError.invalidCredentials) {
            _ = try await provider.refresh(using: "rt")
        }
    }

    @Test("invalid_client at 400 maps to provider configuration (no re-auth loop)")
    func errorBodyInvalidClient() async {
        let transport = FakeTokenTransport(
            response: (Data(#"{"error":"invalid_client"}"#.utf8), 400))
        let provider = EntraTokenProvider(
            config: Self.config, transport: transport,
            authorizer: FakeAuthorizer(), now: { Date() })

        await #expect(throws: AuthOnboardingError.providerConfiguration) {
            _ = try await provider.refresh(using: "rt")
        }
    }

    @Test("Interactive sign-in runs PKCE and exchanges the authorization code")
    func interactiveSignIn() async throws {
        let transport = FakeTokenTransport(
            response: (Self.tokenJSON(sub: "abc"), 200))
        let authorizer = FakeAuthorizer(code: "auth-code-9")
        let now = Date(timeIntervalSince1970: 5_000)
        let provider = EntraTokenProvider(
            config: Self.config, transport: transport,
            authorizer: authorizer, now: { now })

        let session = try await provider.signInInteractively()

        #expect(session.accessToken == "at-1")
        #expect(session.userID == "abc")
        // Authorization URL carries PKCE challenge + S256 + state.
        let authComponents = URLComponents(url: authorizer.receivedURL!, resolvingAgainstBaseURL: false)!
        let q = Dictionary(uniqueKeysWithValues: authComponents.queryItems!.map { ($0.name, $0.value ?? "") })
        #expect(q["code_challenge_method"] == "S256")
        #expect(q["response_type"] == "code")
        #expect(q["client_id"] == "client-123")
        #expect(q["code_challenge"] != nil)
        #expect((q["state"] ?? "").isEmpty == false)
        // Token exchange sends the matching verifier + auth code.
        let body = transport.lastBodyParameters
        #expect(body["grant_type"] == "authorization_code")
        #expect(body["code"] == "auth-code-9")
        #expect(body["code_verifier"] != nil)
    }

    @Test("Interactive sign-in rejects a state mismatch (CSRF guard)")
    func interactiveStateMismatch() async {
        let transport = FakeTokenTransport(response: (Data(), 200))
        let authorizer = FakeAuthorizer(code: "c", overrideReturnedState: "tampered")
        let provider = EntraTokenProvider(
            config: Self.config, transport: transport,
            authorizer: authorizer, now: { Date() })

        await #expect(throws: AuthOnboardingError.providerConfiguration) {
            _ = try await provider.signInInteractively()
        }
    }

    @Test("ROPC sign-in is unsupported by Entra External ID")
    func ropcUnsupported() async {
        let provider = EntraTokenProvider(
            config: Self.config, transport: FakeTokenTransport(response: (Data(), 200)),
            authorizer: FakeAuthorizer(), now: { Date() })

        await #expect(throws: AuthOnboardingError.providerConfiguration) {
            _ = try await provider.signIn(username: "u", password: "p")
        }
    }
}

// MARK: - Test doubles

final class FakeTokenTransport: TokenEndpointTransport, @unchecked Sendable {
    private let response: (Data, Int)
    private(set) var lastURL: URL?
    private(set) var lastBodyParameters: [String: String] = [:]

    init(response: (Data, Int)) { self.response = response }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lastURL = request.url
        if let body = request.httpBody, let s = String(data: body, encoding: .utf8) {
            lastBodyParameters = Dictionary(uniqueKeysWithValues: s.split(separator: "&").map {
                let p = $0.split(separator: "=", maxSplits: 1)
                let k = String(p[0]).removingPercentEncoding ?? String(p[0])
                let v = p.count > 1 ? (String(p[1]).removingPercentEncoding ?? String(p[1])) : ""
                return (k, v)
            })
        }
        let http = HTTPURLResponse(
            url: request.url!, statusCode: response.1,
            httpVersion: nil, headerFields: nil)!
        return (response.0, http)
    }
}

final class FakeAuthorizer: AuthorizationCodeRequesting, @unchecked Sendable {
    private let code: String
    private let overrideReturnedState: String?
    private(set) var receivedURL: URL?

    init(code: String = "code", overrideReturnedState: String? = nil) {
        self.code = code
        self.overrideReturnedState = overrideReturnedState
    }

    func requestCode(authorizationURL: URL, redirectURI: URL, expectedState: String) async throws -> AuthorizationCodeResult {
        receivedURL = authorizationURL
        return AuthorizationCodeResult(
            code: code,
            state: overrideReturnedState ?? expectedState)
    }
}
