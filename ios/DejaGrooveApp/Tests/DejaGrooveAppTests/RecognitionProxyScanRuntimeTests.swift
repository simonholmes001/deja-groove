import Foundation
import XCTest
@testable import DejaGrooveApp

final class RecognitionProxyScanRuntimeTests: XCTestCase {
    func testScanPostsMultipartImageToFunctionProxy() async throws {
        let requestId = UUID()
        let transport = RecognitionProxyRecordingTransport(responseData: Self.scanResponseJson(requestId: requestId))
        let runtime = RecognitionProxyScanRuntime(
            baseURL: URL(string: "https://func.example.com/")!,
            functionKey: "function-key-123",
            transport: transport)
        let clientScanId = UUID()

        let response = try await runtime.scan(
            imageData: Data("image-bytes".utf8),
            clientScanId: clientScanId,
            capturedAtIso: "2026-08-07T09:30:00Z")

        XCTAssertEqual(requestId, response.requestId)
        XCTAssertEqual("no_match", response.status)

        let request = await transport.lastRequest
        XCTAssertEqual("POST", request?.httpMethod)
        XCTAssertEqual("https://func.example.com/v1/scan", request?.url?.absoluteString)
        XCTAssertEqual("function-key-123", request?.value(forHTTPHeaderField: "x-functions-key"))
        XCTAssertTrue(request?.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)

        let body = String(data: request?.httpBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("name=\"clientScanId\""))
        XCTAssertTrue(body.contains(clientScanId.uuidString))
        XCTAssertTrue(body.contains("name=\"capturedAt\""))
        XCTAssertTrue(body.contains("2026-08-07T09:30:00Z"))
        XCTAssertTrue(body.contains("name=\"image\"; filename=\"scan.jpg\""))
        XCTAssertTrue(body.contains("Content-Type: image/jpeg"))
    }

    func testScanPropagatesFunctionProxyErrorEnvelope() async {
        let requestId = UUID()
        let transport = RecognitionProxyRecordingTransport(
            responseData: Self.errorJson(requestId: requestId),
            statusCode: 401)
        let runtime = RecognitionProxyScanRuntime(
            baseURL: URL(string: "https://func.example.com")!,
            functionKey: "bad-key",
            transport: transport)

        do {
            _ = try await runtime.scan(imageData: Data([0xFF]), clientScanId: UUID(), capturedAtIso: nil)
            XCTFail("Expected function proxy error")
        } catch let ApiClientError.httpError(statusCode, error) {
            XCTAssertEqual(401, statusCode)
            XCTAssertEqual("unauthorized", error?.code)
            XCTAssertEqual(requestId, error?.requestId)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testResolveIsExplicitlyNotConfiguredUntilAmbiguousFlowIsImplemented() async {
        let runtime = RecognitionProxyScanRuntime(
            baseURL: URL(string: "https://func.example.com")!,
            functionKey: "function-key-123",
            transport: RecognitionProxyRecordingTransport(responseData: Data()))
        let requestId = UUID()

        do {
            _ = try await runtime.resolve(requestId: requestId, selectedMbid: "mbid", selectedDiscogsReleaseId: nil)
            XCTFail("Expected local resolution to be unavailable")
        } catch let ApiClientError.httpError(statusCode, error) {
            XCTAssertEqual(501, statusCode)
            XCTAssertEqual("local_resolution_not_configured", error?.code)
            XCTAssertEqual(requestId, error?.requestId)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private static func scanResponseJson(requestId: UUID) -> Data {
        """
        {"status":"no_match","confidence":0.0,"album":null,"candidates":[],"request_id":"\(requestId.uuidString.lowercased())"}
        """.data(using: .utf8)!
    }

    private static func errorJson(requestId: UUID) -> Data {
        """
        {"error":{"code":"unauthorized","message":"A valid function key is required.","retryable":false,"request_id":"\(requestId.uuidString.lowercased())"}}
        """.data(using: .utf8)!
    }
}

actor RecognitionProxyRecordingTransport: HttpTransport {
    private(set) var lastRequest: URLRequest?
    private let responseData: Data
    private let statusCode: Int

    init(responseData: Data, statusCode: Int = 200) {
        self.responseData = responseData
        self.statusCode = statusCode
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://func.example.com/")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"])!
        return (responseData, response)
    }
}
