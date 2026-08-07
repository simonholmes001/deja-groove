import XCTest
@testable import DejaGrooveApp

final class ViewModelTests: XCTestCase {
    func testScanResponseNormalizesLegacySafeToBuyStatus() {
        let response = ScanResponse(
            status: "safetobuy",
            confidence: 0.91,
            album: Album(mbid: "a", discogsReleaseId: nil, title: "T", artist: "AR", year: 2000, format: nil),
            candidates: [],
            requestId: UUID()
        )

        XCTAssertEqual("safe_to_buy", response.status)
        XCTAssertTrue(response.canAddToCollection)
    }

    func testOwnedScanResponseCannotBeAddedAgain() {
        let response = ScanResponse(
            status: "owned",
            confidence: 0.91,
            album: Album(mbid: "a", discogsReleaseId: nil, title: "T", artist: "AR", year: 2000, format: nil),
            candidates: [],
            requestId: UUID()
        )

        XCTAssertEqual("owned", response.status)
        XCTAssertFalse(response.canAddToCollection)
    }

    func testScanViewModelHandlesAmbiguousResult() async {
        let response = ScanResponse(
            status: "ambiguous",
            confidence: 0.61,
            album: nil,
            candidates: [Album(mbid: "a", discogsReleaseId: nil, title: "T", artist: "AR", year: 2000, format: nil)],
            requestId: UUID()
        )
        let api = MockApiClient(scanResponse: response)
        let sut = await ScanViewModel(api: api)

        await sut.submitScan(imageData: Data([0xFF, 0xD8]))

        let state = await sut.state
        if case .result(let loaded) = state {
            XCTAssertEqual("ambiguous", loaded.status)
            XCTAssertEqual(1, loaded.candidates.count)
        } else {
            XCTFail("Expected result state")
        }
    }

    func testScanViewModelResolveCallsApi() async {
        let requestId = UUID()
        let resolved = ScanResponse(
            status: "safe_to_buy",
            confidence: 0.8,
            album: Album(mbid: "x", discogsReleaseId: nil, title: "X", artist: "Y", year: 1999, format: nil),
            candidates: [],
            requestId: requestId
        )
        let api = MockApiClient(scanResponse: resolved, resolveResponse: resolved)
        let sut = await ScanViewModel(api: api)

        let candidate = Album(mbid: "x", discogsReleaseId: nil, title: "X", artist: "Y", year: 1999, format: nil)
        await sut.resolve(requestId: requestId, candidate: candidate)

        let calls = await api.resolveCallCount
        XCTAssertEqual(1, calls)
    }

    func testCollectionViewModelLoadsRecords() async {
        let collectionId = UUID(uuidString: "00000000-0000-0000-0000-000000000501")!
        let response = CollectionListResponse(items: [
            CollectionRecord(
                id: UUID(),
                album: Album(mbid: "m", discogsReleaseId: nil, title: "Blue Train", artist: "John Coltrane", year: 1957, format: nil),
                notes: nil,
                version: 1,
                createdAt: "2026-01-01T00:00:00Z",
                updatedAt: "2026-01-01T00:00:00Z")
        ], nextCursor: nil)
        let api = MockApiClient(
            collectionResponse: response,
            crateCollections: [
                CrateCollection(id: collectionId, name: "Jazz", recordIds: [], createdAt: "", updatedAt: "")
            ])
        let sut = await CollectionViewModel(api: api)

        await sut.load()

        let records = await sut.records
        let collections = await sut.crateCollections
        XCTAssertEqual(1, records.count)
        XCTAssertEqual("John Coltrane", records.first?.album.artist)
        XCTAssertEqual("Jazz", collections.first?.name)
    }

    func testCollectionViewModelSortsVisibleRecordsByArtistFamilyNameThenTitle() async {
        let response = CollectionListResponse(items: [
            CollectionRecord(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000531")!,
                album: Album(mbid: nil, discogsReleaseId: nil, title: "Saxophone Colossus", artist: "Sonny Rollins", year: 1956, format: nil),
                notes: nil,
                version: 1,
                createdAt: "2026-01-03T00:00:00Z",
                updatedAt: "2026-01-03T00:00:00Z"),
            CollectionRecord(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000532")!,
                album: Album(mbid: nil, discogsReleaseId: nil, title: "Blue Train", artist: "John Coltrane", year: 1957, format: nil),
                notes: nil,
                version: 1,
                createdAt: "2026-01-02T00:00:00Z",
                updatedAt: "2026-01-02T00:00:00Z"),
            CollectionRecord(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000533")!,
                album: Album(mbid: nil, discogsReleaseId: nil, title: "Mingus Ah Um", artist: "Charles Mingus", year: 1959, format: nil),
                notes: nil,
                version: 1,
                createdAt: "2026-01-01T00:00:00Z",
                updatedAt: "2026-01-01T00:00:00Z")
        ], nextCursor: nil)
        let sut = await CollectionViewModel(api: MockApiClient(collectionResponse: response))

        await sut.load()

        let titles = await sut.visibleRecords.map(\.album.title)
        XCTAssertEqual(["Blue Train", "Mingus Ah Um", "Saxophone Colossus"], titles)
    }

    func testCollectionViewModelDeletesRecordAndRefreshesCollections() async {
        let recordId = UUID(uuidString: "00000000-0000-0000-0000-000000000541")!
        let collectionId = UUID(uuidString: "00000000-0000-0000-0000-000000000542")!
        let api = MockApiClient(
            collectionResponse: CollectionListResponse(items: [
                CollectionRecord(
                    id: recordId,
                    album: Album(mbid: nil, discogsReleaseId: nil, title: "Blue Train", artist: "John Coltrane", year: 1957, format: nil),
                    notes: nil,
                    version: 1,
                    createdAt: "",
                    updatedAt: "")
            ], nextCursor: nil),
            crateCollections: [
                CrateCollection(id: collectionId, name: "Jazz", recordIds: [recordId], createdAt: "", updatedAt: "")
            ])
        let sut = await CollectionViewModel(api: api)

        await sut.load()
        await sut.deleteRecord(id: recordId)

        let records = await sut.records
        let deletedIds = await api.deletedRecordIds
        XCTAssertTrue(records.isEmpty)
        XCTAssertEqual([recordId], deletedIds)
    }


    func testCollectionViewModelFiltersBySearchArtistFormatAndCollection() async {
        let blueId = UUID(uuidString: "00000000-0000-0000-0000-000000000511")!
        let kindId = UUID(uuidString: "00000000-0000-0000-0000-000000000512")!
        let collectionId = UUID(uuidString: "00000000-0000-0000-0000-000000000513")!
        let response = CollectionListResponse(items: [
            CollectionRecord(
                id: blueId,
                album: Album(mbid: nil, discogsReleaseId: nil, title: "Blue", artist: "Joni Mitchell", year: 1971, format: "LP"),
                notes: "gatefold",
                version: 1,
                createdAt: "2026-01-01T00:00:00Z",
                updatedAt: "2026-01-01T00:00:00Z"),
            CollectionRecord(
                id: kindId,
                album: Album(mbid: nil, discogsReleaseId: nil, title: "Kind of Blue", artist: "Miles Davis", year: 1959, format: "CD"),
                notes: nil,
                version: 1,
                createdAt: "2026-01-02T00:00:00Z",
                updatedAt: "2026-01-02T00:00:00Z")
        ], nextCursor: nil)
        let api = MockApiClient(
            collectionResponse: response,
            crateCollections: [
                CrateCollection(id: collectionId, name: "Favorites", recordIds: [blueId], createdAt: "", updatedAt: "")
            ])
        let sut = await CollectionViewModel(api: api)

        await sut.load()
        await MainActor.run {
            sut.search = "blue"
            sut.selectedArtist = "Joni Mitchell"
            sut.selectedFormat = "LP"
            sut.selectedCollectionId = collectionId
        }

        let records = await sut.visibleRecords
        XCTAssertEqual([blueId], records.map(\.id))
    }

    func testCollectionViewModelCreatesAndAssignsCollections() async {
        let recordId = UUID(uuidString: "00000000-0000-0000-0000-000000000521")!
        let collectionId = UUID(uuidString: "00000000-0000-0000-0000-000000000522")!
        let api = MockApiClient(
            collectionResponse: CollectionListResponse(items: [
                CollectionRecord(
                    id: recordId,
                    album: Album(mbid: nil, discogsReleaseId: nil, title: "Blue", artist: "Joni Mitchell", year: 1971, format: "LP"),
                    notes: nil,
                    version: 1,
                    createdAt: "",
                    updatedAt: "")
            ], nextCursor: nil),
            crateCollections: [],
            createdCollection: CrateCollection(id: collectionId, name: "Favorites", recordIds: [], createdAt: "", updatedAt: ""))
        let sut = await CollectionViewModel(api: api)

        await sut.load()
        await sut.createCollection(named: "Favorites")
        await sut.setRecord(recordId, in: collectionId, isIncluded: true)

        let collections = await sut.crateCollections
        XCTAssertEqual("Favorites", collections.first?.name)
        XCTAssertEqual([recordId], collections.first?.recordIds)
    }

    func testCollectionViewModelAuthenticationErrorShowsSignInMessageAndRefreshesAuthState() async {
        let tracker = CallbackTracker()
        let authError = ApiClientError.httpError(
            401,
            ApiError(code: "auth_required", message: "Authentication is required.", retryable: false, requestId: UUID()))
        let api = MockApiClient(collectionErrorSequence: [authError])
        let sut = await CollectionViewModel(api: api, onAuthenticationRequired: {
            await tracker.markCalled()
        })

        await sut.load()

        let requiresAuthentication = await sut.requiresAuthentication
        let errorMessage = await sut.errorMessage
        XCTAssertTrue(requiresAuthentication)
        XCTAssertEqual("Sign in to view My Crate.", errorMessage)
        let callbackCount = await tracker.callCount
        XCTAssertEqual(1, callbackCount)
    }

    func testScanViewModelAddToCollectionAuthenticationErrorShowsFriendlyMessageAndRefreshesAuthState() async {
        let tracker = CallbackTracker()
        let response = ScanResponse(
            status: "safe_to_buy",
            confidence: 0.9,
            album: Album(mbid: "m", discogsReleaseId: nil, title: "T", artist: "A", year: 2001, format: nil),
            candidates: [],
            requestId: UUID())
        let authError = ApiClientError.httpError(
            401,
            ApiError(code: "auth_required", message: "Authentication is required.", retryable: false, requestId: UUID()))
        let api = MockApiClient(scanResponse: response, addToCollectionErrorSequence: [authError])
        let sut = await ScanViewModel(api: api, onAuthenticationRequired: {
            await tracker.markCalled()
        })

        await sut.submitScan(imageData: Data([0xFF, 0xD8]))
        await sut.addResultToCollection()

        let message = await sut.collectionMessage
        XCTAssertEqual("Sign in to add this album to My Crate.", message)
        let callbackCount = await tracker.callCount
        XCTAssertEqual(1, callbackCount)
    }

    func testScanViewModelClearsResultAfterSuccessfulAddToCollection() async {
        let response = ScanResponse(
            status: "safe_to_buy",
            confidence: 0.9,
            album: Album(mbid: "m", discogsReleaseId: nil, title: "T", artist: "A", year: 2001, format: nil),
            candidates: [],
            requestId: UUID())
        let api = MockApiClient(scanResponse: response)
        let sut = await ScanViewModel(api: api)

        await sut.submitScan(imageData: Data([0xFF, 0xD8]))
        await sut.addResultToCollection()

        let state = await sut.state
        let message = await sut.collectionMessage
        XCTAssertEqual(.idle, state)
        XCTAssertEqual("Added to My Crate.", message)
    }

    func testScanViewModelRetryableHttpErrorExposesRetryFlagAndCanRetryLastScan() async {
        let failure = ApiClientError.httpError(
            503,
            ApiError(code: "scan_provider_unavailable", message: "try again", retryable: true, requestId: UUID()))
        let success = ScanResponse(
            status: "safe_to_buy",
            confidence: 0.9,
            album: Album(mbid: "m", discogsReleaseId: nil, title: "T", artist: "A", year: 2001, format: nil),
            candidates: [],
            requestId: UUID())

        let api = MockApiClient(scanResponse: success, scanErrorSequence: [failure])
        let sut = await ScanViewModel(api: api)

        await sut.submitScan(imageData: Data([0x1]))
        let retryable = await sut.isLastErrorRetryable
        XCTAssertTrue(retryable)

        await sut.retryLastScan()

        let scanCalls = await api.scanCallCount
        XCTAssertEqual(2, scanCalls)
        let state = await sut.state
        if case .result(let result) = state {
            XCTAssertEqual("safe_to_buy", result.status)
        } else {
            XCTFail("Expected result state after retry")
        }
        let retryableAfterSuccess = await sut.isLastErrorRetryable
        XCTAssertFalse(retryableAfterSuccess)
    }

    func testRetryLastScan_NoPreviousSubmission_DoesNothing() async {
        let api = MockApiClient()
        let sut = await ScanViewModel(api: api)

        await sut.retryLastScan()

        let scanCalls = await api.scanCallCount
        XCTAssertEqual(0, scanCalls)
        let state = await sut.state
        XCTAssertEqual(.idle, state)
    }

    func testResolveRetryableHttpError_DoesNotExposeScanRetryAction() async {
        let resolveError = ApiClientError.httpError(
            503,
            ApiError(code: "scan_provider_unavailable", message: "try again", retryable: true, requestId: UUID()))
        let api = MockApiClient(resolveErrorSequence: [resolveError])
        let sut = await ScanViewModel(api: api)

        let candidate = Album(mbid: "x", discogsReleaseId: nil, title: "X", artist: "Y", year: 1999, format: nil)
        await sut.resolve(requestId: UUID(), candidate: candidate)

        let retryable = await sut.isLastErrorRetryable
        XCTAssertFalse(retryable)
        let state = await sut.state
        if case .error = state {
        } else {
            XCTFail("Expected error state")
        }
    }
}

actor MockApiClient: ApiClient {
    let scanResponse: ScanResponse
    let resolveResponse: ScanResponse
    let collectionResponse: CollectionListResponse
    private(set) var crateCollections: [CrateCollection]
    private let createdCollection: CrateCollection?
    private(set) var resolveCallCount = 0
    private(set) var scanCallCount = 0
    private var scanErrorSequence: [ApiClientError]
    private var resolveErrorSequence: [ApiClientError]
    private var collectionErrorSequence: [ApiClientError]
    private var addToCollectionErrorSequence: [ApiClientError]
    private(set) var deletedRecordIds: [UUID] = []

    init(
        scanResponse: ScanResponse? = nil,
        resolveResponse: ScanResponse? = nil,
        collectionResponse: CollectionListResponse? = nil,
        crateCollections: [CrateCollection] = [],
        createdCollection: CrateCollection? = nil,
        scanErrorSequence: [ApiClientError] = [],
        resolveErrorSequence: [ApiClientError] = [],
        collectionErrorSequence: [ApiClientError] = [],
        addToCollectionErrorSequence: [ApiClientError] = []
    ) {
        let fallback = ScanResponse(status: "no_match", confidence: 0, album: nil, candidates: [], requestId: UUID())
        self.scanResponse = scanResponse ?? fallback
        self.resolveResponse = resolveResponse ?? fallback
        self.collectionResponse = collectionResponse ?? CollectionListResponse(items: [], nextCursor: nil)
        self.crateCollections = crateCollections
        self.createdCollection = createdCollection
        self.scanErrorSequence = scanErrorSequence
        self.resolveErrorSequence = resolveErrorSequence
        self.collectionErrorSequence = collectionErrorSequence
        self.addToCollectionErrorSequence = addToCollectionErrorSequence
    }

    func scan(imageData: Data, clientScanId: UUID, capturedAtIso: String?) async throws -> ScanResponse {
        scanCallCount += 1
        if !scanErrorSequence.isEmpty {
            throw scanErrorSequence.removeFirst()
        }
        return scanResponse
    }

    func resolve(requestId: UUID, selectedMbid: String?, selectedDiscogsReleaseId: String?) async throws -> ScanResponse {
        resolveCallCount += 1
        if !resolveErrorSequence.isEmpty {
            throw resolveErrorSequence.removeFirst()
        }
        return resolveResponse
    }

    func fetchCollection(search: String?) async throws -> CollectionListResponse {
        if !collectionErrorSequence.isEmpty {
            throw collectionErrorSequence.removeFirst()
        }
        return collectionResponse
    }

    func addToCollection(album: Album, notes: String?, addAnyway: Bool) async throws -> CollectionItemResponse {
        if !addToCollectionErrorSequence.isEmpty {
            throw addToCollectionErrorSequence.removeFirst()
        }
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
            updatedAt: ""
        )
    }

    func patchCollection(id: UUID, format: String?, notes: String?) async throws -> CollectionItemResponse {
        return CollectionItemResponse(id: id, mbid: nil, discogsReleaseId: nil, title: "", artist: "", year: nil, format: format, notes: notes, createdAt: "", updatedAt: "")
    }

    func deleteCollectionRecord(id: UUID) async throws {
        deletedRecordIds.append(id)
        crateCollections = crateCollections.map { collection in
            CrateCollection(
                id: collection.id,
                name: collection.name,
                recordIds: collection.recordIds.filter { $0 != id },
                createdAt: collection.createdAt,
                updatedAt: collection.updatedAt)
        }
    }

    func fetchCrateCollections(search: String?) async throws -> [CrateCollection] {
        guard let search, !search.isEmpty else { return crateCollections }
        return crateCollections.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    func createCrateCollection(name: String) async throws -> CrateCollection {
        let collection = createdCollection ?? CrateCollection(id: UUID(), name: name, recordIds: [], createdAt: "", updatedAt: "")
        crateCollections.append(collection)
        return collection
    }

    func renameCrateCollection(id: UUID, name: String) async throws -> CrateCollection {
        guard let index = crateCollections.firstIndex(where: { $0.id == id }) else {
            throw ApiClientError.invalidResponse
        }
        let current = crateCollections[index]
        let renamed = CrateCollection(id: current.id, name: name, recordIds: current.recordIds, createdAt: current.createdAt, updatedAt: current.updatedAt)
        crateCollections[index] = renamed
        return renamed
    }

    func deleteCrateCollection(id: UUID) async throws {
        crateCollections.removeAll { $0.id == id }
    }

    func addRecord(_ recordId: UUID, toCrateCollection collectionId: UUID) async throws -> CrateCollection {
        guard let index = crateCollections.firstIndex(where: { $0.id == collectionId }) else {
            throw ApiClientError.invalidResponse
        }
        let current = crateCollections[index]
        let recordIds = current.recordIds.contains(recordId) ? current.recordIds : current.recordIds + [recordId]
        let updated = CrateCollection(id: current.id, name: current.name, recordIds: recordIds, createdAt: current.createdAt, updatedAt: current.updatedAt)
        crateCollections[index] = updated
        return updated
    }

    func removeRecord(_ recordId: UUID, fromCrateCollection collectionId: UUID) async throws -> CrateCollection {
        guard let index = crateCollections.firstIndex(where: { $0.id == collectionId }) else {
            throw ApiClientError.invalidResponse
        }
        let current = crateCollections[index]
        let updated = CrateCollection(id: current.id, name: current.name, recordIds: current.recordIds.filter { $0 != recordId }, createdAt: current.createdAt, updatedAt: current.updatedAt)
        crateCollections[index] = updated
        return updated
    }
}

actor CallbackTracker {
    private(set) var callCount = 0

    func markCalled() {
        callCount += 1
    }
}
