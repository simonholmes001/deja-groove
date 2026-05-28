import XCTest
@testable import DejaGrooveApp

final class ViewModelTests: XCTestCase {
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
        let response = CollectionListResponse(items: [
            CollectionRecord(
                id: UUID(),
                album: Album(mbid: "m", discogsReleaseId: nil, title: "Blue Train", artist: "John Coltrane", year: 1957, format: nil),
                notes: nil,
                version: 1,
                createdAt: "2026-01-01T00:00:00Z",
                updatedAt: "2026-01-01T00:00:00Z")
        ], nextCursor: nil)
        let api = MockApiClient(collectionResponse: response)
        let sut = await CollectionViewModel(api: api)

        await sut.load()

        let records = await sut.records
        XCTAssertEqual(1, records.count)
        XCTAssertEqual("John Coltrane", records.first?.album.artist)
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
    private(set) var resolveCallCount = 0
    private(set) var scanCallCount = 0
    private var scanErrorSequence: [ApiClientError]
    private var resolveErrorSequence: [ApiClientError]

    init(
        scanResponse: ScanResponse? = nil,
        resolveResponse: ScanResponse? = nil,
        collectionResponse: CollectionListResponse? = nil,
        scanErrorSequence: [ApiClientError] = [],
        resolveErrorSequence: [ApiClientError] = []
    ) {
        let fallback = ScanResponse(status: "no_match", confidence: 0, album: nil, candidates: [], requestId: UUID())
        self.scanResponse = scanResponse ?? fallback
        self.resolveResponse = resolveResponse ?? fallback
        self.collectionResponse = collectionResponse ?? CollectionListResponse(items: [], nextCursor: nil)
        self.scanErrorSequence = scanErrorSequence
        self.resolveErrorSequence = resolveErrorSequence
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

    func fetchCollection(search: String?) async throws -> CollectionListResponse { collectionResponse }

    func addToCollection(album: Album, notes: String?, addAnyway: Bool) async throws -> CollectionItemResponse {
        CollectionItemResponse(
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
        CollectionItemResponse(id: id, mbid: nil, discogsReleaseId: nil, title: "", artist: "", year: nil, format: format, notes: notes, createdAt: "", updatedAt: "")
    }
}
