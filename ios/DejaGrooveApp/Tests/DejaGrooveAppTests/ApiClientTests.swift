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

    func testPatchCollection_BuildsCorrectRequest() async throws {
        let id = UUID()
        let transport = RecordingTransport(responseData: Self.patchCollectionResponseJson(id: id))
        let client = LiveApiClient(
            baseUrl: URL(string: "https://api.example.com/")!,
            transport: transport,
            authTokenProvider: { "token-patch" })

        _ = try await client.patchCollection(id: id, format: "vinyl", notes: "my notes")

        let request = await transport.lastRequest
        XCTAssertEqual("PATCH", request?.httpMethod)
        XCTAssertTrue(request?.url?.absoluteString.contains(id.uuidString.lowercased()) == true)
        XCTAssertEqual("Bearer token-patch", request?.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual("application/json", request?.value(forHTTPHeaderField: "Content-Type"))
    }

    func testPatchCollection_DecodesResponse() async throws {
        let id = UUID()
        let transport = RecordingTransport(responseData: Self.patchCollectionResponseJson(id: id))
        let client = LiveApiClient(
            baseUrl: URL(string: "https://api.example.com/")!,
            transport: transport,
            authTokenProvider: { nil })

        let result = try await client.patchCollection(id: id, format: "vinyl", notes: "my notes")

        XCTAssertEqual(id, result.id)
        XCTAssertEqual("vinyl", result.format)
        XCTAssertEqual("my notes", result.notes)
        XCTAssertEqual("Kind of Blue", result.title)
        XCTAssertEqual("Miles Davis", result.artist)
    }

    private static let scanResponseJson = """
    {"status":"no_match","confidence":0.0,"album":null,"candidates":[],"request_id":"00000000-0000-0000-0000-000000000001"}
    """.data(using: .utf8)!

    private static let collectionResponseJson = """
    {"items":[],"next_cursor":null}
    """.data(using: .utf8)!

    private static func patchCollectionResponseJson(id: UUID) -> Data {
        """
        {"id":"\(id.uuidString.lowercased())","mbid":"some-mbid","discogs_release_id":null,"title":"Kind of Blue","artist":"Miles Davis","year":1959,"format":"vinyl","notes":"my notes","created_at":"2024-01-01T00:00:00Z","updated_at":"2024-01-02T00:00:00Z"}
        """.data(using: .utf8)!
    }
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
