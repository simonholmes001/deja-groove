import Foundation
import Testing
@testable import DejaGrooveAuth

@Suite("Secure Random")
struct SecureRandomTests {
    @Test("System random returns the requested number of bytes")
    func systemRandomLength() throws {
        let bytes = try SystemRandom().bytes(48)
        #expect(bytes.count == 48)
    }

    @Test("Generator failure propagates instead of yielding weak output")
    func failurePropagates() {
        #expect(throws: SecureRandomError.generationFailed) {
            _ = try FailingRandom().bytes(32)
        }
    }

    @Test("Verifier generation propagates a random-source failure (fails closed)")
    func verifierFailsClosedOnRandomFailure() {
        #expect(throws: SecureRandomError.generationFailed) {
            _ = try PkceCodeVerifier.generate(using: FailingRandom())
        }
    }

    @Test("Generated verifier is unreserved-only and unbiased by construction")
    func verifierCharsetAndLength() throws {
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        for _ in 0..<50 {
            let v = try PkceCodeVerifier.generate(using: SystemRandom())
            #expect(v.value.allSatisfy { allowed.contains($0) })
            #expect((43...128).contains(v.value.count))
        }
    }
}

final class FailingRandom: SecureRandomGenerating, @unchecked Sendable {
    func bytes(_ count: Int) throws -> [UInt8] {
        throw SecureRandomError.generationFailed
    }
}
