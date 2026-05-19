import Foundation
import Testing
@testable import DejaGrooveAuth

@Suite("PKCE")
struct PkceTests {
    @Test("S256 challenge matches the RFC 7636 Appendix B test vector")
    func rfc7636AppendixBVector() throws {
        // RFC 7636 §B: verifier -> known S256 challenge.
        let verifier = try PkceCodeVerifier(value: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")

        #expect(verifier.challenge.value == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        #expect(verifier.challenge.method == "S256")
    }

    @Test("Generated verifiers are unique across invocations")
    func generatedVerifierUniqueness() throws {
        let values = Set(try (0..<100).map { _ in try PkceCodeVerifier.generate().value })
        #expect(values.count == 100)
    }

    @Test("Verifier rejects values outside the RFC length bounds")
    func verifierLengthValidation() {
        #expect(throws: PkceError.invalidVerifierLength) {
            _ = try PkceCodeVerifier(value: String(repeating: "a", count: 42))
        }
        #expect(throws: PkceError.invalidVerifierLength) {
            _ = try PkceCodeVerifier(value: String(repeating: "a", count: 129))
        }
    }
}
