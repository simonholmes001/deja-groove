import Foundation

/// Errors raised while constructing PKCE material (RFC 7636).
public enum PkceError: Error, Equatable, Sendable {
    case invalidVerifierLength
}

/// A PKCE S256 code challenge derived from a verifier (RFC 7636 §4.2).
public struct PkceChallenge: Equatable, Sendable {
    public let value: String
    public let method = "S256"

    fileprivate init(value: String) {
        self.value = value
    }
}

/// A PKCE code verifier: a high-entropy string from the RFC 7636 unreserved
/// set, 43–128 characters long. Construction validates length so an invalid
/// verifier can never reach the authorization request.
public struct PkceCodeVerifier: Equatable, Sendable {
    public let value: String

    /// The unreserved character set permitted by RFC 7636 §4.1.
    private static let unreserved = Array(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    public init(value: String) throws {
        guard (43...128).contains(value.count) else {
            throw PkceError.invalidVerifierLength
        }
        self.value = value
    }

    /// Generates a cryptographically random 64-character verifier.
    public static func generate() -> PkceCodeVerifier {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let value = String(bytes.map { unreserved[Int($0) % unreserved.count] })
        // Length is fixed at 64 by construction; force-try is safe here.
        return try! PkceCodeVerifier(value: value)
    }

    /// The S256 challenge: BASE64URL(SHA256(verifier)) without padding.
    public var challenge: PkceChallenge {
        let digest = Sha256.digest(Array(value.utf8))
        return PkceChallenge(value: Data(digest).base64URLEncodedString())
    }
}

extension Data {
    /// Base64 URL-safe encoding without padding (RFC 7636 §A).
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
