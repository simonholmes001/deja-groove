import Foundation

public enum ApiClientError: Error, Equatable {
    case invalidResponse
    case httpError(Int, ApiError?)
    case encodingFailure
}

public protocol ApiClient: Sendable {
    func scan(imageData: Data, clientScanId: UUID, capturedAtIso: String?) async throws -> ScanResponse
    func resolve(requestId: UUID, selectedMbid: String?, selectedDiscogsReleaseId: String?) async throws -> ScanResponse
    func addToCollection(album: Album, notes: String?, addAnyway: Bool) async throws -> CollectionItemResponse
    func fetchCollection(search: String?) async throws -> CollectionListResponse
    func patchCollection(id: UUID, format: String?, notes: String?) async throws -> CollectionItemResponse
    func updateCollectionRecord(id: UUID, album: Album, notes: String?) async throws -> CollectionItemResponse
    func deleteCollectionRecord(id: UUID) async throws
    func fetchCrateCollections(search: String?) async throws -> [CrateCollection]
    func createCrateCollection(name: String) async throws -> CrateCollection
    func renameCrateCollection(id: UUID, name: String) async throws -> CrateCollection
    func deleteCrateCollection(id: UUID) async throws
    func addRecord(_ recordId: UUID, toCrateCollection collectionId: UUID) async throws -> CrateCollection
    func removeRecord(_ recordId: UUID, fromCrateCollection collectionId: UUID) async throws -> CrateCollection
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

    public func addToCollection(album: Album, notes: String?, addAnyway: Bool = false) async throws -> CollectionItemResponse {
        var request = URLRequest(url: baseUrl.appendingPathComponent("v1/collection"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        await applyAuth(to: &request)
        request.httpBody = try JSONEncoder().encode(AddCollectionBody(
            mbid: album.mbid,
            discogsReleaseId: album.discogsReleaseId,
            title: album.title,
            artist: album.artist,
            year: album.year,
            notes: notes,
            addAnyway: addAnyway
        ))
        return try await send(request)
    }

    public func patchCollection(id: UUID, format: String?, notes: String?) async throws -> CollectionItemResponse {
        var request = URLRequest(url: baseUrl.appendingPathComponent("v1/collection/\(id.uuidString.lowercased())"))
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        await applyAuth(to: &request)
        request.httpBody = try JSONEncoder().encode(PatchCollectionBody(format: format, notes: notes))
        return try await send(request)
    }

    public func updateCollectionRecord(id: UUID, album: Album, notes: String?) async throws -> CollectionItemResponse {
        throw unsupportedLocalCollectionManagementError()
    }

    public func deleteCollectionRecord(id: UUID) async throws {
        throw unsupportedLocalCollectionManagementError()
    }

    public func fetchCrateCollections(search: String?) async throws -> [CrateCollection] {
        throw unsupportedLocalCollectionManagementError()
    }

    public func createCrateCollection(name: String) async throws -> CrateCollection {
        throw unsupportedLocalCollectionManagementError()
    }

    public func renameCrateCollection(id: UUID, name: String) async throws -> CrateCollection {
        throw unsupportedLocalCollectionManagementError()
    }

    public func deleteCrateCollection(id: UUID) async throws {
        throw unsupportedLocalCollectionManagementError()
    }

    public func addRecord(_ recordId: UUID, toCrateCollection collectionId: UUID) async throws -> CrateCollection {
        throw unsupportedLocalCollectionManagementError()
    }

    public func removeRecord(_ recordId: UUID, fromCrateCollection collectionId: UUID) async throws -> CrateCollection {
        throw unsupportedLocalCollectionManagementError()
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

    private func unsupportedLocalCollectionManagementError() -> ApiClientError {
        ApiClientError.httpError(
            501,
            ApiError(
                code: "local_collection_management_only",
                message: "Collection management is only implemented by the local runtime client.",
                retryable: false,
                requestId: UUID()))
    }
}

/// Encodes only the fields present in a PATCH request body.
/// Nil fields are omitted from the JSON output, preserving true PATCH semantics.
private struct PatchCollectionBody: Encodable {
    let format: String?
    let notes: String?

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(format, forKey: .format)
        try container.encodeIfPresent(notes, forKey: .notes)
    }

    private enum CodingKeys: String, CodingKey {
        case format, notes
    }
}

private struct AddCollectionBody: Encodable {
    let mbid: String?
    let discogsReleaseId: String?
    let title: String?
    let artist: String?
    let year: Int?
    let notes: String?
    let addAnyway: Bool

    enum CodingKeys: String, CodingKey {
        case mbid
        case discogsReleaseId = "discogs_release_id"
        case title
        case artist
        case year
        case notes
        case addAnyway = "add_anyway"
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
