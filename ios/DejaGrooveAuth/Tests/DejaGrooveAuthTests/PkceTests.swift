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

    @Test("Generated verifier uses only the RFC 7636 unreserved character set")
    func generatedVerifierCharset() {
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        for _ in 0..<50 {
            let verifier = PkceCodeVerifier.generate()
            #expect(verifier.value.allSatisfy { allowed.contains($0) })
            #expect((43...128).contains(verifier.value.count))
        }
    }

    @Test("Generated verifiers are unique across invocations")
    func generatedVerifierUniqueness() {
        let values = Set((0..<100).map { _ in PkceCodeVerifier.generate().value })
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
