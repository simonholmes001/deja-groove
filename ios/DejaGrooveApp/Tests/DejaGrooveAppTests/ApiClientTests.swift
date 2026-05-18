import Foundation
import XCTest
@testable import DejaGrooveApp

final class ApiClientTests: XCTestCase {
    func testScanAddsAuthorizationHeaderWhenTokenProvided() async throws {
        let transport = RecordingTransport(responseData: Self.scanResponseJson)
        let client = LiveApiClient(
            baseUrl: URL(string: "https://api.example.com/")!,
            transport: transport,
            authTokenProvider: { "token-123" })

        _ = try await client.scan(
            imageData: Data([0xFF, 0xD8]),
            clientScanId: UUID(),
            capturedAtIso: nil)

        let request = await transport.lastRequest
        XCTAssertEqual("Bearer token-123", request?.value(forHTTPHeaderField: "Authorization"))
    }

    func testResolveAddsAuthorizationHeaderWhenTokenProvided() async throws {
        let transport = RecordingTransport(responseData: Self.scanResponseJson)
        let client = LiveApiClient(
            baseUrl: URL(string: "https://api.example.com/")!,
            transport: transport,
            authTokenProvider: { "token-456" })

        _ = try await client.resolve(
            requestId: UUID(),
            selectedMbid: "mbid-1",
            selectedDiscogsReleaseId: nil)

        let request = await transport.lastRequest
        XCTAssertEqual("Bearer token-456", request?.value(forHTTPHeaderField: "Authorization"))
    }

    func testCollectionAddsAuthorizationHeaderWhenTokenProvided() async throws {
        let transport = RecordingTransport(responseData: Self.collectionResponseJson)
        let client = LiveApiClient(
            baseUrl: URL(string: "https://api.example.com/")!,
            transport: transport,
            authTokenProvider: { "token-789" })

        _ = try await client.fetchCollection(search: "miles")

        let request = await transport.lastRequest
        XCTAssertEqual("Bearer token-789", request?.value(forHTTPHeaderField: "Authorization"))
    }

    private static let scanResponseJson = """
    {"status":"no_match","confidence":0.0,"album":null,"candidates":[],"request_id":"00000000-0000-0000-0000-000000000001"}
    """.data(using: .utf8)!

    private static let collectionResponseJson = """
    {"items":[],"next_cursor":null}
    """.data(using: .utf8)!
}

actor RecordingTransport: HttpTransport {
    private(set) var lastRequest: URLRequest?
    private let responseData: Data

    init(responseData: Data) {
        self.responseData = responseData
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://api.example.com/")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"])!
        return (responseData, response)
    }
}
