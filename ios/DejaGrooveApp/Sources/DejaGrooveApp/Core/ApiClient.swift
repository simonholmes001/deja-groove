import Foundation

public enum ApiClientError: Error, Equatable {
    case invalidResponse
    case httpError(Int, ApiError?)
    case encodingFailure
}

public protocol ApiClient: Sendable {
    func scan(imageData: Data, clientScanId: UUID, capturedAtIso: String?) async throws -> ScanResponse
    func resolve(requestId: UUID, selectedAlbum: Album) async throws -> ScanResponse
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
