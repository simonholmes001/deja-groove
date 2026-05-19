import Foundation

/// Static configuration for the Entra External ID (CIAM) tenant.
public struct EntraConfig: Sendable, Equatable {
    public let authority: URL
    public let clientID: String
    public let redirectURI: URL
    public let scopes: [String]

    public init(authority: URL, clientID: String, redirectURI: URL, scopes: [String]) {
        self.authority = authority
        self.clientID = clientID
        self.redirectURI = redirectURI
        self.scopes = scopes
    }

    var tokenEndpoint: URL { authority.appendingPathComponent("oauth2/v2.0/token") }
    var authorizeEndpoint: URL { authority.appendingPathComponent("oauth2/v2.0/authorize") }
}

/// Transport seam for the OAuth token endpoint — lets tests inject responses
/// without network. Mirrors the `HttpTransport` pattern used by the API client.
public protocol TokenEndpointTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTokenTransport: TokenEndpointTransport {
    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AuthOnboardingError.networkUnavailable
        }
        return (data, http)
    }
}

public struct AuthorizationCodeResult: Sendable, Equatable {
    public let code: String
    public let state: String
    public init(code: String, state: String) {
        self.code = code
        self.state = state
    }
}

/// The interactive browser leg of the auth-code flow. Production conforms via
/// `ASWebAuthenticationSession`; tests inject a fake. Kept deliberately thin so
/// the only untestable surface is the system UI presentation itself.
public protocol AuthorizationCodeRequesting: Sendable {
    func requestCode(
        authorizationURL: URL,
        redirectURI: URL,
        expectedState: String
    ) async throws -> AuthorizationCodeResult
}

/// Concrete `AuthTokenProvider` for Entra External ID using OAuth 2.0
/// Authorization Code + PKCE for sign-in and the refresh-token grant for
/// silent renewal. ROPC (`signIn(username:password:)`) is intentionally
/// unsupported — Entra External ID does not offer it for consumer identity.
public final class EntraTokenProvider: AuthTokenProvider, @unchecked Sendable {
    private let config: EntraConfig
    private let transport: TokenEndpointTransport
    private let authorizer: AuthorizationCodeRequesting
    private let now: @Sendable () -> Date

    public init(
        config: EntraConfig,
        transport: TokenEndpointTransport,
        authorizer: AuthorizationCodeRequesting,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.config = config
        self.transport = transport
        self.authorizer = authorizer
        self.now = now
    }

    public func signIn(username: String, password: String) async throws -> AuthSession {
        // Resource Owner Password Credentials is not available for Entra
        // External ID consumer identity; interactive PKCE is required.
        throw AuthOnboardingError.providerConfiguration
    }

    public func signInInteractively() async throws -> AuthSession {
        let verifier = PkceCodeVerifier.generate()
        let state = Self.randomURLSafeToken()

        var components = URLComponents(url: config.authorizeEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI.absoluteString),
            URLQueryItem(name: "scope", value: config.scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: verifier.challenge.value),
            URLQueryItem(name: "code_challenge_method", value: verifier.challenge.method),
            URLQueryItem(name: "state", value: state)
        ]

        let result = try await authorizer.requestCode(
            authorizationURL: components.url!,
            redirectURI: config.redirectURI,
            expectedState: state)

        guard result.state == state else {
            // State mismatch — possible CSRF / interception.
            throw AuthOnboardingError.providerConfiguration
        }

        return try await exchange(parameters: [
            "grant_type": "authorization_code",
            "code": result.code,
            "redirect_uri": config.redirectURI.absoluteString,
            "client_id": config.clientID,
            "code_verifier": verifier.value
        ])
    }

    public func refresh(using refreshToken: String) async throws -> AuthSession {
        try await exchange(parameters: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": config.clientID,
            "scope": config.scopes.joined(separator: " ")
        ])
    }

    // MARK: - Token endpoint exchange

    private func exchange(parameters: [String: String]) async throws -> AuthSession {
        var request = URLRequest(url: config.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formURLEncoded(parameters).data(using: .utf8)

        let (data, http): (Data, HTTPURLResponse)
        do {
            (data, http) = try await transport.send(request)
        } catch let error as AuthOnboardingError {
            throw error
        } catch {
            throw AuthOnboardingError.networkUnavailable
        }

        guard (200..<300).contains(http.statusCode) else {
            // 400/401 from the token endpoint means the grant is bad
            // (expired/revoked refresh token, invalid code); anything else is
            // a provider/configuration problem.
            throw (http.statusCode == 400 || http.statusCode == 401)
                ? AuthOnboardingError.invalidCredentials
                : AuthOnboardingError.providerConfiguration
        }

        return try Self.mapSession(from: data, now: now())
    }

    private static func mapSession(from data: Data, now: Date) throws -> AuthSession {
        struct TokenResponse: Decodable {
            let access_token: String
            let refresh_token: String
            let expires_in: Int
            let id_token: String
        }
        guard let token = try? JSONDecoder().decode(TokenResponse.self, from: data) else {
            throw AuthOnboardingError.providerConfiguration
        }
        guard let subject = Self.subject(fromIDToken: token.id_token) else {
            throw AuthOnboardingError.providerConfiguration
        }
        return AuthSession(
            accessToken: token.access_token,
            refreshToken: token.refresh_token,
            expiresAt: now.addingTimeInterval(TimeInterval(token.expires_in)),
            userID: subject)
    }

    /// Reads the `sub` claim from the id_token. The client does not validate
    /// the signature — the API performs full JWT validation; the client only
    /// needs the stable subject as a local scoping/display key.
    private static func subject(fromIDToken idToken: String) -> String? {
        let parts = idToken.split(separator: ".")
        guard parts.count == 3,
              let payload = base64URLDecode(String(parts[1])),
              let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let sub = json["sub"] as? String,
              !sub.isEmpty else {
            return nil
        }
        return sub
    }

    private static func base64URLDecode(_ value: String) -> Data? {
        var s = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s.append("=") }
        return Data(base64Encoded: s)
    }

    private static func formURLEncoded(_ parameters: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return parameters
            .map { key, value in
                let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
                let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(k)=\(v)"
            }
            .joined(separator: "&")
    }

    private static func randomURLSafeToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }
}
