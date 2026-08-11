import Foundation
import XCTest
@testable import DejaGrooveApp

final class ApiClientTests: XCTestCase {
    func testLocalProxyApiClientDelegatesScanAndCollectionCalls() async throws {
        let scanRuntime = LocalScanRuntimeSpy()
        let collectionStore = LocalCollectionStoreSpy()
        let client = LocalProxyApiClient(scanRuntime: scanRuntime, collectionStore: collectionStore)
        let album = Album(mbid: "m", discogsReleaseId: nil, title: "Blue", artist: "Joni Mitchell", year: 1971, format: nil)

        _ = try await client.scan(imageData: Data([0xFF, 0xD8]), clientScanId: UUID(), capturedAtIso: nil)
        _ = try await client.addToCollection(album: album, notes: "owned", addAnyway: false)
        _ = try await client.fetchCollection(search: "joni")

        let scanCallCount = await scanRuntime.scanCalls()
        let collectionSnapshot = await collectionStore.snapshot()
        XCTAssertEqual(1, scanCallCount)
        XCTAssertEqual(1, collectionSnapshot.addCallCount)
        XCTAssertEqual("joni", collectionSnapshot.lastSearch)
    }

    func testLocalProxyScanMarksExistingAlbumAsOwned() async throws {
        let album = Album(mbid: "mbid-blue", discogsReleaseId: nil, title: "Blue", artist: "Joni Mitchell", year: 1971, format: nil)
        let response = ScanResponse(
            status: "safe_to_buy",
            confidence: 0.9,
            album: album,
            candidates: [],
            requestId: UUID())
        let client = LocalProxyApiClient(
            scanRuntime: LocalScanRuntimeSpy(response: response),
            collectionStore: LocalCollectionStoreSpy(existingAlbums: [album]))

        let result = try await client.scan(imageData: Data([0xFF, 0xD8]), clientScanId: UUID(), capturedAtIso: nil)

        XCTAssertEqual("owned", result.status)
        XCTAssertFalse(result.canAddToCollection)
        XCTAssertEqual(album, result.album)
    }

    func testLocalProxyResolveMarksExistingSelectedCandidateAsOwned() async throws {
        let album = Album(mbid: "mbid-blue", discogsReleaseId: nil, title: "Blue", artist: "Joni Mitchell", year: 1971, format: nil)
        let client = LocalProxyApiClient(
            scanRuntime: LocalScanRuntimeSpy(),
            collectionStore: LocalCollectionStoreSpy(existingAlbums: [album]))

        let result = try await client.resolve(requestId: UUID(), selectedAlbum: album)

        XCTAssertEqual("owned", result.status)
        XCTAssertFalse(result.canAddToCollection)
        XCTAssertEqual(album, result.album)
    }

    @MainActor
    func testViewModelsCanUseLocalProxyApiClient() async {
        let scanRuntime = LocalScanRuntimeSpy(response: ScanResponse(
            status: "safe_to_buy",
            confidence: 0.9,
            album: Album(mbid: "m", discogsReleaseId: nil, title: "Blue", artist: "Joni Mitchell", year: 1971, format: nil),
            candidates: [],
            requestId: UUID()))
        let collectionStore = LocalCollectionStoreSpy(collectionResponse: CollectionListResponse(items: [
            CollectionRecord(
                id: UUID(),
                album: Album(mbid: "m", discogsReleaseId: nil, title: "Blue", artist: "Joni Mitchell", year: 1971, format: nil),
                notes: nil,
                version: 1,
                createdAt: "2026-01-01T00:00:00Z",
                updatedAt: "2026-01-01T00:00:00Z")
        ], nextCursor: nil))
        let client = LocalProxyApiClient(scanRuntime: scanRuntime, collectionStore: collectionStore)
        let scanViewModel = ScanViewModel(api: client)
        let collectionViewModel = CollectionViewModel(api: client)

        await scanViewModel.submitScan(imageData: Data([0xFF, 0xD8]))
        await collectionViewModel.load()

        if case .result(let response) = scanViewModel.state {
            XCTAssertEqual("safe_to_buy", response.status)
        } else {
            XCTFail("Expected local proxy scan result")
        }
        XCTAssertEqual(1, collectionViewModel.records.count)
        let scanCallCount = await scanRuntime.scanCalls()
        let collectionSnapshot = await collectionStore.snapshot()
        XCTAssertEqual(1, scanCallCount)
        XCTAssertEqual(1, collectionSnapshot.fetchCallCount)
    }

#if os(iOS)
    func testPhotoLibraryImagePreparerConvertsPngToJpeg() {
        let pngData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a7KQAAAAASUVORK5CYII=")!

        let prepared = PhotoLibraryScanImagePreparer.prepareForUpload(pngData)

        XCTAssertEqual([0xFF, 0xD8, 0xFF], Array(prepared?.prefix(3) ?? []))
    }
#endif

}

actor LocalScanRuntimeSpy: LocalScanRuntime {
    private(set) var scanCallCount = 0
    private(set) var resolveCallCount = 0
    private let response: ScanResponse

    init(response: ScanResponse = ScanResponse(status: "no_match", confidence: 0, album: nil, candidates: [], requestId: UUID())) {
        self.response = response
    }

    func scan(imageData: Data, clientScanId: UUID, capturedAtIso: String?) async throws -> ScanResponse {
        scanCallCount += 1
        return response
    }

    func resolve(requestId: UUID, selectedAlbum: Album) async throws -> ScanResponse {
        resolveCallCount += 1
        return ScanResponse(status: "safe_to_buy", confidence: 1, album: selectedAlbum, candidates: [], requestId: requestId)
    }

    func scanCalls() -> Int {
        scanCallCount
    }
}

actor LocalCollectionStoreSpy: LocalCollectionStore {
    private(set) var addCallCount = 0
    private(set) var fetchCallCount = 0
    private(set) var patchCallCount = 0
    private(set) var containsCallCount = 0
    private(set) var lastSearch: String?
    private let collectionResponse: CollectionListResponse
    private let existingAlbums: [Album]

    init(
        collectionResponse: CollectionListResponse = CollectionListResponse(items: [], nextCursor: nil),
        existingAlbums: [Album] = []
    ) {
        self.collectionResponse = collectionResponse
        self.existingAlbums = existingAlbums
    }

    func contains(album: Album) async throws -> Bool {
        containsCallCount += 1
        return existingAlbums.contains(album)
    }

    func addToCollection(album: Album, notes: String?, addAnyway: Bool) async throws -> CollectionItemResponse {
        addCallCount += 1
        return CollectionItemResponse(
            id: UUID(),
            mbid: album.mbid,
            discogsReleaseId: album.discogsReleaseId,
            title: album.title,
            artist: album.artist,
            year: album.year,
            format: album.format,
            notes: notes,
            createdAt: "",
            updatedAt: "")
    }

    func fetchCollection(search: String?) async throws -> CollectionListResponse {
        fetchCallCount += 1
        lastSearch = search
        return collectionResponse
    }

    func patchCollection(id: UUID, format: String?, notes: String?) async throws -> CollectionItemResponse {
        patchCallCount += 1
        return CollectionItemResponse(
            id: id,
            mbid: nil,
            discogsReleaseId: nil,
            title: "",
            artist: "",
            year: nil,
            format: format,
            notes: notes,
            createdAt: "",
            updatedAt: "")
    }

    func updateCollectionRecord(id: UUID, album: Album, notes: String?) async throws -> CollectionItemResponse {
        CollectionItemResponse(
            id: id,
            mbid: album.mbid,
            discogsReleaseId: album.discogsReleaseId,
            title: album.title,
            artist: album.artist,
            year: album.year,
            format: album.format,
            notes: notes,
            createdAt: "",
            updatedAt: "")
    }

    func deleteCollectionRecord(id: UUID) async throws {
    }

    func fetchCrateCollections(search: String?) async throws -> [CrateCollection] {
        []
    }

    func createCrateCollection(name: String) async throws -> CrateCollection {
        CrateCollection(id: UUID(), name: name, recordIds: [], createdAt: "", updatedAt: "")
    }

    func renameCrateCollection(id: UUID, name: String) async throws -> CrateCollection {
        CrateCollection(id: id, name: name, recordIds: [], createdAt: "", updatedAt: "")
    }

    func deleteCrateCollection(id: UUID) async throws {
    }

    func addRecord(_ recordId: UUID, toCrateCollection collectionId: UUID) async throws -> CrateCollection {
        CrateCollection(id: collectionId, name: "", recordIds: [recordId], createdAt: "", updatedAt: "")
    }

    func removeRecord(_ recordId: UUID, fromCrateCollection collectionId: UUID) async throws -> CrateCollection {
        CrateCollection(id: collectionId, name: "", recordIds: [], createdAt: "", updatedAt: "")
    }

    func snapshot() -> LocalCollectionStoreSnapshot {
        LocalCollectionStoreSnapshot(
            addCallCount: addCallCount,
            fetchCallCount: fetchCallCount,
            patchCallCount: patchCallCount,
            lastSearch: lastSearch)
    }
}

struct LocalCollectionStoreSnapshot {
    let addCallCount: Int
    let fetchCallCount: Int
    let patchCallCount: Int
    let lastSearch: String?
}
