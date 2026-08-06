import Foundation

public protocol LocalScanRuntime: Sendable {
    func scan(imageData: Data, clientScanId: UUID, capturedAtIso: String?) async throws -> ScanResponse
    func resolve(requestId: UUID, selectedMbid: String?, selectedDiscogsReleaseId: String?) async throws -> ScanResponse
}

public protocol LocalCollectionStore: Sendable {
    func addToCollection(album: Album, notes: String?, addAnyway: Bool) async throws -> CollectionItemResponse
    func fetchCollection(search: String?) async throws -> CollectionListResponse
    func patchCollection(id: UUID, format: String?, notes: String?) async throws -> CollectionItemResponse
}

public final class LocalProxyApiClient: ApiClient, @unchecked Sendable {
    private let scanRuntime: LocalScanRuntime
    private let collectionStore: LocalCollectionStore

    public init(scanRuntime: LocalScanRuntime, collectionStore: LocalCollectionStore) {
        self.scanRuntime = scanRuntime
        self.collectionStore = collectionStore
    }

    public func scan(imageData: Data, clientScanId: UUID, capturedAtIso: String?) async throws -> ScanResponse {
        try await scanRuntime.scan(imageData: imageData, clientScanId: clientScanId, capturedAtIso: capturedAtIso)
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
}

public enum LocalProxyApiClientFactory {
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
    func addToCollection(album: Album, notes: String?, addAnyway: Bool) async throws -> CollectionItemResponse {
        throw unconfiguredError(message: "Local collection storage is not configured yet.")
    }

    func fetchCollection(search: String?) async throws -> CollectionListResponse {
        throw unconfiguredError(message: "Local collection storage is not configured yet.")
    }

    func patchCollection(id: UUID, format: String?, notes: String?) async throws -> CollectionItemResponse {
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
