import Foundation

public protocol LocalScanRuntime: Sendable {
    func scan(imageData: Data, clientScanId: UUID, capturedAtIso: String?) async throws -> ScanResponse
    func resolve(requestId: UUID, selectedAlbum: Album) async throws -> ScanResponse
}

public protocol LocalCollectionStore: Sendable {
    func contains(album: Album) async throws -> Bool
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

public final class LocalProxyApiClient: ApiClient, @unchecked Sendable {
    private let scanRuntime: LocalScanRuntime
    private let collectionStore: LocalCollectionStore
    private let wishlistStore: LocalWishlistStore
    private let discoveryStore: LocalDiscoveryStore

    public init(
        scanRuntime: LocalScanRuntime,
        collectionStore: LocalCollectionStore,
        wishlistStore: LocalWishlistStore = PersistentLocalWishlistStore(),
        discoveryStore: LocalDiscoveryStore = PersistentLocalDiscoveryStore()
    ) {
        self.scanRuntime = scanRuntime
        self.collectionStore = collectionStore
        self.wishlistStore = wishlistStore
        self.discoveryStore = discoveryStore
    }

    public func scan(imageData: Data, clientScanId: UUID, capturedAtIso: String?) async throws -> ScanResponse {
        let response = try await scanRuntime.scan(
            imageData: imageData,
            clientScanId: clientScanId,
            capturedAtIso: capturedAtIso)
        guard let album = response.album else {
            return response
        }
        return try await decorateScanResponse(response, album: album)
    }

    public func resolve(requestId: UUID, selectedAlbum: Album) async throws -> ScanResponse {
        let response = try await scanRuntime.resolve(
            requestId: requestId,
            selectedAlbum: selectedAlbum)
        guard let album = response.album else {
            return response
        }
        return try await decorateScanResponse(response, album: album)
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

    public func updateCollectionRecord(id: UUID, album: Album, notes: String?) async throws -> CollectionItemResponse {
        try await collectionStore.updateCollectionRecord(id: id, album: album, notes: notes)
    }

    public func deleteCollectionRecord(id: UUID) async throws {
        try await collectionStore.deleteCollectionRecord(id: id)
    }

    public func addToWishlist(
        album: Album,
        preferences: WishlistPreferences = WishlistPreferences(),
        sourceTrack: AudioDiscoveryTrack? = nil
    ) async throws -> WishlistEntry {
        try await wishlistStore.addToWishlist(album: album, preferences: preferences, sourceTrack: sourceTrack)
    }

    public func fetchWishlist(search: String?) async throws -> [WishlistEntry] {
        try await wishlistStore.fetchWishlist(search: search)
    }

    public func updateWishlistPreferences(id: UUID, preferences: WishlistPreferences) async throws -> WishlistEntry {
        try await wishlistStore.updateWishlistPreferences(id: id, preferences: preferences)
    }

    public func deleteWishlistEntry(id: UUID) async throws {
        try await wishlistStore.deleteWishlistEntry(id: id)
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

    private func decorateScanResponse(_ response: ScanResponse, album: Album) async throws -> ScanResponse {
        if try await collectionStore.contains(album: album) {
            return response.withStatus("owned")
        }
        if response.status == "safe_to_buy", try await wishlistStore.contains(album: album) {
            return response.withStatus("wishlist_match")
        }
        if response.status == "safe_to_buy", try await discoveryStore.contains(album: album) {
            return response.withStatus("discovery_match")
        }
        return response
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
            collectionStore: PersistentLocalCollectionStore(),
            wishlistStore: PersistentLocalWishlistStore(),
            discoveryStore: PersistentLocalDiscoveryStore())
    }

    public static func makeUnconfigured(recognitionProxyBaseURL: URL? = nil) -> LocalProxyApiClient {
        LocalProxyApiClient(
            scanRuntime: UnconfiguredLocalScanRuntime(recognitionProxyBaseURL: recognitionProxyBaseURL),
            collectionStore: UnconfiguredLocalCollectionStore(),
            wishlistStore: UnconfiguredLocalWishlistStore(),
            discoveryStore: UnconfiguredLocalDiscoveryStore())
    }
}

private struct UnconfiguredLocalScanRuntime: LocalScanRuntime {
    let recognitionProxyBaseURL: URL?

    func scan(imageData: Data, clientScanId: UUID, capturedAtIso: String?) async throws -> ScanResponse {
        throw unconfiguredError(message: "Local scan runtime is not configured yet.")
    }

    func resolve(requestId: UUID, selectedAlbum: Album) async throws -> ScanResponse {
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

    func updateCollectionRecord(id: UUID, album: Album, notes: String?) async throws -> CollectionItemResponse {
        throw unconfiguredError(message: "Local collection storage is not configured yet.")
    }

    func deleteCollectionRecord(id: UUID) async throws {
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

private struct UnconfiguredLocalWishlistStore: LocalWishlistStore {
    func contains(album: Album) async throws -> Bool {
        throw unconfiguredError(message: "Local wishlist storage is not configured yet.")
    }

    func addToWishlist(album: Album, preferences: WishlistPreferences, sourceTrack: AudioDiscoveryTrack?) async throws -> WishlistEntry {
        throw unconfiguredError(message: "Local wishlist storage is not configured yet.")
    }

    func fetchWishlist(search: String?) async throws -> [WishlistEntry] {
        throw unconfiguredError(message: "Local wishlist storage is not configured yet.")
    }

    func updateWishlistPreferences(id: UUID, preferences: WishlistPreferences) async throws -> WishlistEntry {
        throw unconfiguredError(message: "Local wishlist storage is not configured yet.")
    }

    func deleteWishlistEntry(id: UUID) async throws {
        throw unconfiguredError(message: "Local wishlist storage is not configured yet.")
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

private struct UnconfiguredLocalDiscoveryStore: LocalDiscoveryStore {
    func contains(album: Album) async throws -> Bool {
        throw unconfiguredError(message: "Local discovery storage is not configured yet.")
    }

    func addDiscovery(source: String, album: Album?, track: AudioDiscoveryTrack?) async throws -> DiscoveryEntry {
        throw unconfiguredError(message: "Local discovery storage is not configured yet.")
    }

    func fetchDiscoveries(search: String?) async throws -> [DiscoveryEntry] {
        throw unconfiguredError(message: "Local discovery storage is not configured yet.")
    }

    func promoteDiscoveryToWishlist(id: UUID, wishlistStore: LocalWishlistStore) async throws -> WishlistEntry {
        throw unconfiguredError(message: "Local discovery storage is not configured yet.")
    }

    func deleteDiscovery(id: UUID) async throws {
        throw unconfiguredError(message: "Local discovery storage is not configured yet.")
    }

    func deleteAllDiscoveries() async throws {
        throw unconfiguredError(message: "Local discovery storage is not configured yet.")
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
