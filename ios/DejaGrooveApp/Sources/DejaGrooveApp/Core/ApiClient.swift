import Foundation

public enum ApiClientError: Error, Equatable {
    case invalidResponse
    case httpError(Int, ApiError?)
    case encodingFailure
}

public protocol ApiClient: Sendable {
    func scan(imageData: Data, clientScanId: UUID, capturedAtIso: String?) async throws -> ScanResponse
    func resolve(requestId: UUID, selectedMbid: String?, selectedDiscogsReleaseId: String?) async throws -> ScanResponse
    func fetchCollection(search: String?) async throws -> CollectionListResponse
}

public protocol HttpTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

public struct URLSessionTransport: HttpTransport {
    private let session: URLSession

    public init(session: URLSession) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}

public final class LiveApiClient: ApiClient, @unchecked Sendable {
    private let baseUrl: URL
    private let transport: HttpTransport
    private let authTokenProvider: @Sendable () async -> String?

    public init(
        baseUrl: URL,
        transport: HttpTransport = URLSessionTransport(session: .shared),
        authTokenProvider: @escaping @Sendable () async -> String? = { nil })
    {
        self.baseUrl = baseUrl
        self.transport = transport
        self.authTokenProvider = authTokenProvider
    }

    public func scan(imageData: Data, clientScanId: UUID, capturedAtIso: String?) async throws -> ScanResponse {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: baseUrl.appendingPathComponent("v1/scan"))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        await applyAuth(to: &request)

        var body = Data()
        body.appendMultipartField("clientScanId", value: clientScanId.uuidString, boundary: boundary)
        if let capturedAtIso {
            body.appendMultipartField("capturedAt", value: capturedAtIso, boundary: boundary)
        }
        body.appendMultipartFile("image", filename: "scan.jpg", mimeType: "image/jpeg", data: imageData, boundary: boundary)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        return try await send(request)
    }

    public func resolve(requestId: UUID, selectedMbid: String?, selectedDiscogsReleaseId: String?) async throws -> ScanResponse {
        var request = URLRequest(url: baseUrl.appendingPathComponent("v1/scan/\(requestId.uuidString)/resolve"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        await applyAuth(to: &request)
        let payload: [String: String?] = [
            "selected_mbid": selectedMbid,
            "selected_discogs_release_id": selectedDiscogsReleaseId
        ]
        request.httpBody = try JSONEncoder().encode(payload)
        return try await send(request)
    }

    public func fetchCollection(search: String?) async throws -> CollectionListResponse {
        var components = URLComponents(url: baseUrl.appendingPathComponent("v1/collection"), resolvingAgainstBaseURL: false)!
        if let search, !search.isEmpty {
            components.queryItems = [URLQueryItem(name: "search", value: search)]
        }
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        await applyAuth(to: &request)
        return try await send(request)
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await transport.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ApiClientError.invalidResponse }

        let decoder = JSONDecoder()
        if (200..<300).contains(http.statusCode) {
            return try decoder.decode(T.self, from: data)
        }

        let envelope = try? decoder.decode(ApiErrorEnvelope.self, from: data)
        throw ApiClientError.httpError(http.statusCode, envelope?.error)
    }

    private func applyAuth(to request: inout URLRequest) async {
        guard let token = await authTokenProvider(), !token.isEmpty else { return }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
}

private extension Data {
    mutating func appendMultipartField(_ name: String, value: String, boundary: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        append("\(value)\r\n".data(using: .utf8)!)
    }

    mutating func appendMultipartFile(_ name: String, filename: String, mimeType: String, data: Data, boundary: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        append(data)
        append("\r\n".data(using: .utf8)!)
    }
}
