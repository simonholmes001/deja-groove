import Foundation

public protocol LocalScanRuntime: Sendable {
    func scan(imageData: Data, clientScanId: UUID, capturedAtIso: String?) async throws -> ScanResponse
    func resolve(requestId: UUID, selectedMbid: String?, selectedDiscogsReleaseId: String?) async throws -> ScanResponse
}

public protocol LocalCollectionStore: Sendable {
    func contains(album: Album) async throws -> Bool
    func addToCollection(album: Album, notes: String?, addAnyway: Bool) async throws -> CollectionItemResponse
    func fetchCollection(search: String?) async throws -> CollectionListResponse
    func patchCollection(id: UUID, format: String?, notes: String?) async throws -> CollectionItemResponse
    func fetchCrateCollections(search: String?) async throws -> [CrateCollection]
    func createCrateCollection(name: String) async throws -> CrateCollection
    func renameCrateCollection(id: UUID, name: String) async throws -> CrateCollection
    func deleteCrateCollection(id: UUID) async throws
    func addRecord(_ recordId: UUID, toCrateCollection collectionId: UUID) async throws -> CrateCollection
    func removeRecord(_ recordId: UUID, fromCrateCollection collectionId: UUID) async throws -> CrateCollection
}

public final class LocalProxyApiClient: ApiClient, @unchecked Sendable {
    private let scanRuntime: LocalScanRuntime
    private let collectionStore: LocalCollectionStore

    public init(scanRuntime: LocalScanRuntime, collectionStore: LocalCollectionStore) {
        self.scanRuntime = scanRuntime
        self.collectionStore = collectionStore
    }

    public func scan(imageData: Data, clientScanId: UUID, capturedAtIso: String?) async throws -> ScanResponse {
        let response = try await scanRuntime.scan(
            imageData: imageData,
            clientScanId: clientScanId,
            capturedAtIso: capturedAtIso)
        guard let album = response.album, try await collectionStore.contains(album: album) else {
            return response
        }
        return ScanResponse(
            status: "owned",
            confidence: response.confidence,
            album: album,
            candidates: response.candidates,
            requestId: response.requestId)
    }

    public func resolve(requestId: UUID, selectedMbid: String?, selectedDiscogsReleaseId: String?) async throws -> ScanResponse {
        try await scanRuntime.resolve(
            requestId: requestId,
            selectedMbid: selectedMbid,
            selectedDiscogsReleaseId: selectedDiscogsReleaseId)
    }

    public func addToCollection(album: Album, notes: String?, addAnyway: Bool) async throws -> CollectionItemResponse {
        try await collectionStore.addToCollection(album: album, notes: notes, addAnyway: addAnyway)
    }

    public func fetchCollection(search: String?) async throws -> CollectionListResponse {
        try await collectionStore.fetchCollection(search: search)
    }

    public func patchCollection(id: UUID, format: String?, notes: String?) async throws -> CollectionItemResponse {
        try await collectionStore.patchCollection(id: id, format: format, notes: notes)
    }

    public func fetchCrateCollections(search: String?) async throws -> [CrateCollection] {
        try await collectionStore.fetchCrateCollections(search: search)
    }

    public func createCrateCollection(name: String) async throws -> CrateCollection {
        try await collectionStore.createCrateCollection(name: name)
    }

    public func renameCrateCollection(id: UUID, name: String) async throws -> CrateCollection {
        try await collectionStore.renameCrateCollection(id: id, name: name)
    }

    public func deleteCrateCollection(id: UUID) async throws {
        try await collectionStore.deleteCrateCollection(id: id)
    }

    public func addRecord(_ recordId: UUID, toCrateCollection collectionId: UUID) async throws -> CrateCollection {
        try await collectionStore.addRecord(recordId, toCrateCollection: collectionId)
    }

    public func removeRecord(_ recordId: UUID, fromCrateCollection collectionId: UUID) async throws -> CrateCollection {
        try await collectionStore.removeRecord(recordId, fromCrateCollection: collectionId)
    }
}

public enum LocalProxyApiClientFactory {
    public static func make(recognitionProxyBaseURL: URL? = nil, recognitionProxyKey: String? = nil) -> LocalProxyApiClient {
        let scanRuntime: LocalScanRuntime
        if let recognitionProxyBaseURL, let recognitionProxyKey, !recognitionProxyKey.isEmpty {
            scanRuntime = RecognitionProxyScanRuntime(
                baseURL: recognitionProxyBaseURL,
                functionKey: recognitionProxyKey)
        } else {
            scanRuntime = UnconfiguredLocalScanRuntime(recognitionProxyBaseURL: recognitionProxyBaseURL)
        }

        return LocalProxyApiClient(
            scanRuntime: scanRuntime,
            collectionStore: PersistentLocalCollectionStore())
    }

    public static func makeUnconfigured(recognitionProxyBaseURL: URL? = nil) -> LocalProxyApiClient {
        LocalProxyApiClient(
            scanRuntime: UnconfiguredLocalScanRuntime(recognitionProxyBaseURL: recognitionProxyBaseURL),
            collectionStore: UnconfiguredLocalCollectionStore())
    }
}

private struct UnconfiguredLocalScanRuntime: LocalScanRuntime {
    let recognitionProxyBaseURL: URL?

    func scan(imageData: Data, clientScanId: UUID, capturedAtIso: String?) async throws -> ScanResponse {
        throw unconfiguredError(message: "Local scan runtime is not configured yet.")
    }

    func resolve(requestId: UUID, selectedMbid: String?, selectedDiscogsReleaseId: String?) async throws -> ScanResponse {
        throw unconfiguredError(message: "Local scan resolution is not configured yet.")
    }

    private func unconfiguredError(message: String) -> ApiClientError {
        ApiClientError.httpError(
            503,
            ApiError(
                code: "local_runtime_not_configured",
                message: message,
                retryable: false,
                requestId: UUID()))
    }
}

private struct UnconfiguredLocalCollectionStore: LocalCollectionStore {
    func contains(album: Album) async throws -> Bool {
        throw unconfiguredError(message: "Local collection storage is not configured yet.")
    }

    func addToCollection(album: Album, notes: String?, addAnyway: Bool) async throws -> CollectionItemResponse {
        throw unconfiguredError(message: "Local collection storage is not configured yet.")
    }

    func fetchCollection(search: String?) async throws -> CollectionListResponse {
        throw unconfiguredError(message: "Local collection storage is not configured yet.")
    }

    func patchCollection(id: UUID, format: String?, notes: String?) async throws -> CollectionItemResponse {
        throw unconfiguredError(message: "Local collection storage is not configured yet.")
    }

    func fetchCrateCollections(search: String?) async throws -> [CrateCollection] {
        throw unconfiguredError(message: "Local collection storage is not configured yet.")
    }

    func createCrateCollection(name: String) async throws -> CrateCollection {
        throw unconfiguredError(message: "Local collection storage is not configured yet.")
    }

    func renameCrateCollection(id: UUID, name: String) async throws -> CrateCollection {
        throw unconfiguredError(message: "Local collection storage is not configured yet.")
    }

    func deleteCrateCollection(id: UUID) async throws {
        throw unconfiguredError(message: "Local collection storage is not configured yet.")
    }

    func addRecord(_ recordId: UUID, toCrateCollection collectionId: UUID) async throws -> CrateCollection {
        throw unconfiguredError(message: "Local collection storage is not configured yet.")
    }

    func removeRecord(_ recordId: UUID, fromCrateCollection collectionId: UUID) async throws -> CrateCollection {
        throw unconfiguredError(message: "Local collection storage is not configured yet.")
    }

    private func unconfiguredError(message: String) -> ApiClientError {
        ApiClientError.httpError(
            503,
            ApiError(
                code: "local_runtime_not_configured",
                message: message,
                retryable: false,
                requestId: UUID()))
    }
}
