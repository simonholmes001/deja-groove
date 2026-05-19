import Foundation
import Security

public enum SecureRandomError: Error, Equatable, Sendable {
    case generationFailed
}

/// Source of cryptographically secure random bytes. Injectable so the
/// fail-closed behaviour can be unit-tested without a real CSPRNG failure.
public protocol SecureRandomGenerating: Sendable {
    func bytes(_ count: Int) throws -> [UInt8]
}

/// Production CSPRNG. The `SecRandomCopyBytes` status is checked and any
/// failure throws — it is never silently ignored, so a degraded RNG can never
/// produce a predictable PKCE verifier or CSRF state token.
public struct SystemRandom: SecureRandomGenerating {
    public init() {}

    public func bytes(_ count: Int) throws -> [UInt8] {
        var buffer = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &buffer)
        guard status == errSecSuccess else {
            throw SecureRandomError.generationFailed
        }
        return buffer
    }
}
