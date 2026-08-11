import Foundation
import XCTest
@testable import DejaGrooveApp

final class RecognitionProxyConfigurationTests: XCTestCase {
    func testValidationRejectsExampleRecognitionProxyHost() {
        let result = RecognitionProxyConfiguration.validate(
            baseURL: URL(string: "https://func-deja-recognition.example")!,
            functionKey: "function-key")

        XCTAssertEqual(.placeholderBaseURL, result)
    }

    func testValidationRejectsPlaceholderRecognitionProxyKey() {
        let result = RecognitionProxyConfiguration.validate(
            baseURL: URL(string: "https://func-deja-recognition-dev-yzoqh3gf.azurewebsites.net")!,
            functionKey: "REPLACE_WITH_AZURE_FUNCTION_DEFAULT_KEY")

        XCTAssertEqual(.placeholderFunctionKey, result)
    }

    func testValidationAcceptsAzureWebsitesRecognitionProxyHostAndConfiguredKey() {
        let result = RecognitionProxyConfiguration.validate(
            baseURL: URL(string: "https://func-deja-recognition-dev-yzoqh3gf.azurewebsites.net")!,
            functionKey: "configured-key")

        XCTAssertNil(result)
    }
}
