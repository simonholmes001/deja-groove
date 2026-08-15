import Foundation
import XCTest
@testable import DejaGrooveApp

@MainActor
final class RegressionWorkflowTests: XCTestCase {
    func testScanAddToCratePreservesRichMetadataAndMarksFutureScansOwned() async throws {
        let album = richAlbum()
        let collectionStore = PersistentLocalCollectionStore(
            fileURL: temporaryStoreURL(named: "collection"),
            idProvider: RegressionFixedUUIDProvider(ids: [
                UUID(uuidString: "00000000-0000-0000-0000-000000000701")!
            ]),
            clock: RegressionFixedISO8601Clock(instants: [
                "2026-01-01T00:00:00Z"
            ]),
            duplicateRequestIdProvider: RegressionFixedUUIDProvider(ids: [
                UUID(uuidString: "00000000-0000-0000-0000-000000000702")!
            ]))
        let wishlistStore = PersistentLocalWishlistStore(fileURL: temporaryStoreURL(named: "wishlist"))
        let client = LocalProxyApiClient(
            scanRuntime: RegressionScanRuntime(response: ScanResponse(
                status: "safe_to_buy",
                confidence: 0.96,
                album: album,
                candidates: [],
                requestId: UUID(uuidString: "00000000-0000-0000-0000-000000000703")!)),
            collectionStore: collectionStore,
            wishlistStore: wishlistStore)
        let scanViewModel = ScanViewModel(api: client)
        let collectionViewModel = CollectionViewModel(api: client)

        await scanViewModel.submitScan(imageData: Data([0xFF, 0xD8, 0xFF]))
        await scanViewModel.addResultToCollection()
        await collectionViewModel.load()

        XCTAssertEqual("Added to My Crate.", scanViewModel.collectionMessage)
        guard case .result(let addedResponse) = scanViewModel.state else {
            return XCTFail("Expected scan result to remain visible after adding to My Crate")
        }
        XCTAssertEqual("owned", addedResponse.status)
        XCTAssertEqual(album, addedResponse.album)
        XCTAssertEqual("Impulse!", collectionViewModel.records.first?.album.label)
        XCTAssertEqual("AS-9148", collectionViewModel.records.first?.album.catalogNumber)
        XCTAssertEqual("US", collectionViewModel.records.first?.album.country)
        XCTAssertEqual(["Jazz"], collectionViewModel.records.first?.album.genres)
        XCTAssertEqual("Manifestation", collectionViewModel.records.first?.album.tracklist.first?.title)

        let secondScan = try await client.scan(
            imageData: Data([0xFF, 0xD8, 0xFF]),
            clientScanId: UUID(),
            capturedAtIso: nil)

        XCTAssertEqual("owned", secondScan.status)
        XCTAssertFalse(secondScan.canAddToCollection)
        XCTAssertEqual(album, secondScan.album)
    }

    func testScanSavedToDiscoveryHistoryMarksFutureScansAsDiscoveryMatch() async throws {
        let album = richAlbum()
        let collectionStore = PersistentLocalCollectionStore(fileURL: temporaryStoreURL(named: "collection"))
        let wishlistStore = PersistentLocalWishlistStore(fileURL: temporaryStoreURL(named: "wishlist"))
        let discoveryStore = PersistentLocalDiscoveryStore(fileURL: temporaryStoreURL(named: "discovery"))
        let client = LocalProxyApiClient(
            scanRuntime: RegressionScanRuntime(response: ScanResponse(
                status: "safe_to_buy",
                confidence: 0.96,
                album: album,
                candidates: [],
                requestId: UUID(uuidString: "00000000-0000-0000-0000-000000000704")!)),
            collectionStore: collectionStore,
            wishlistStore: wishlistStore,
            discoveryStore: discoveryStore)
        let scanViewModel = ScanViewModel(api: client, discoveryStore: discoveryStore)

        await scanViewModel.submitScan(imageData: Data([0xFF, 0xD8, 0xFF]))
        await scanViewModel.saveResultToDiscovery()
        let secondScan = try await client.scan(
            imageData: Data([0xFF, 0xD8, 0xFF]),
            clientScanId: UUID(),
            capturedAtIso: nil)

        XCTAssertEqual("Saved to Discovery History.", scanViewModel.collectionMessage)
        XCTAssertEqual("discovery_match", secondScan.status)
        XCTAssertTrue(secondScan.canAddToCollection)
        XCTAssertTrue(secondScan.canAddToWishlist)
        XCTAssertEqual(album, secondScan.album)
    }

    func testDiscoverSaveToWishlistStoresSourceTrackAndSortsWishlistByArtistFamilyName() async throws {
        let collectionStore = PersistentLocalCollectionStore(fileURL: temporaryStoreURL(named: "collection"))
        let wishlistStore = PersistentLocalWishlistStore(
            fileURL: temporaryStoreURL(named: "wishlist"),
            idProvider: RegressionFixedUUIDProvider(ids: [
                UUID(uuidString: "00000000-0000-0000-0000-000000000711")!,
                UUID(uuidString: "00000000-0000-0000-0000-000000000712")!
            ]),
            clock: RegressionFixedISO8601Clock(instants: [
                "2026-01-02T00:00:00Z",
                "2026-01-03T00:00:00Z"
            ]))
        let discoveryStore = PersistentLocalDiscoveryStore(
            fileURL: temporaryStoreURL(named: "discovery"),
            idProvider: RegressionFixedUUIDProvider(ids: [
                UUID(uuidString: "00000000-0000-0000-0000-000000000713")!
            ]),
            clock: RegressionFixedISO8601Clock(instants: [
                "2026-01-01T00:00:00Z"
            ]))
        let client = LocalProxyApiClient(
            scanRuntime: RegressionScanRuntime(),
            collectionStore: collectionStore,
            wishlistStore: wishlistStore)
        let sourceTrack = AudioDiscoveryTrack(
            title: "Goodbye Pork Pie Hat",
            artist: "Charles Mingus",
            shazamId: "shazam-1",
            appleMusicId: "apple-1",
            artworkUrl: "https://example.com/mingus.jpg",
            genre: "Jazz",
            matchedAt: "2026-01-01T00:00:00Z")
        let mingus = Album(
            mbid: nil,
            discogsReleaseId: "123",
            title: "Mingus Ah Um",
            artist: "Charles Mingus",
            year: 1959,
            format: "LP")
        let coltrane = Album(
            mbid: nil,
            discogsReleaseId: "456",
            title: "Blue Train",
            artist: "John Coltrane",
            year: 1957,
            format: "LP")
        let discoveryViewModel = DiscoveryViewModel(
            api: client,
            discoveryStore: discoveryStore,
            audioDiscovery: RegressionAudioDiscoveryService(track: sourceTrack),
            candidateResolver: RegressionAlbumCandidateResolver(candidates: [mingus]),
            musicAuthorization: RegressionMusicAuthorizationController(status: .authorized))

        await discoveryViewModel.identifyPlayingAudio()
        await discoveryViewModel.saveCandidateToWishlist(mingus)
        _ = try await client.addToWishlist(album: coltrane, preferences: WishlistPreferences(), sourceTrack: nil)

        let history = try await discoveryStore.fetchDiscoveries(search: nil)
        let wishlist = try await client.fetchWishlist(search: nil)

        XCTAssertEqual([mingus], discoveryViewModel.candidates)
        XCTAssertEqual(sourceTrack, history.first?.track)
        XCTAssertEqual(mingus, history.first?.album)
        XCTAssertEqual(["Blue Train", "Mingus Ah Um"], wishlist.map(\.album.title))
        XCTAssertEqual(sourceTrack, wishlist.first(where: { $0.album.title == "Mingus Ah Um" })?.sourceTrack)
    }

    func testScanContractDecodesEnrichedMetadataUsedByDetailsViews() throws {
        let json = """
        {
          "status": "safe_to_buy",
          "confidence": 0.96,
          "request_id": "00000000-0000-0000-0000-000000000721",
          "candidates": [],
          "album": {
            "mbid": "mbid-1",
            "discogs_release_id": "249504",
            "discogs_master_id": "38276",
            "discogs_url": "https://www.discogs.com/release/249504",
            "discogs_resource_url": "https://api.discogs.com/releases/249504",
            "title": "Cosmic Music",
            "artist": "John Coltrane & Alice Coltrane",
            "year": 1968,
            "first_release_year": 1968,
            "release_year": 1968,
            "first_release_date": "1968",
            "release_date": "1968",
            "format": "Vinyl, LP",
            "label": "Impulse!",
            "catalog_number": "AS-9148",
            "country": "US",
            "barcode": "0123456789",
            "cover_image_url": "https://example.com/front.jpg",
            "thumbnail_url": "https://example.com/thumb.jpg",
            "back_cover_image_url": "https://example.com/back.jpg",
            "back_cover_text": "Recorded in New York.",
            "release_notes": "Gatefold pressing.",
            "genres": ["Jazz"],
            "styles": ["Free Jazz"],
            "companies": ["ABC Records"],
            "tracklist": [
              { "position": "A1", "title": "Manifestation", "duration": "11:37" }
            ],
            "identifiers": [
              { "type": "Matrix / Runout", "value": "AS-9148-A", "description": "Side A" }
            ],
            "discogs_data_quality": "Correct",
            "listening_links": [
              { "provider": "Apple Music", "url": "https://music.apple.com/album/1", "catalog_id": "1", "preview_url": "https://example.com/preview.m4a" }
            ]
          }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(ScanResponse.self, from: json)

        XCTAssertEqual("safe_to_buy", response.status)
        XCTAssertEqual("Impulse!", response.album?.label)
        XCTAssertEqual("AS-9148", response.album?.catalogNumber)
        XCTAssertEqual("US", response.album?.country)
        XCTAssertEqual("Gatefold pressing.", response.album?.releaseNotes)
        XCTAssertEqual(["Jazz"], response.album?.genres)
        XCTAssertEqual(["Free Jazz"], response.album?.styles)
        XCTAssertEqual("Manifestation", response.album?.tracklist.first?.title)
        XCTAssertEqual("Matrix / Runout", response.album?.identifiers.first?.type)
        XCTAssertEqual("Apple Music", response.album?.listeningLinks.first?.provider)
    }

    private func richAlbum() -> Album {
        Album(
            mbid: "mbid-1",
            discogsReleaseId: "249504",
            discogsMasterId: "38276",
            discogsUrl: "https://www.discogs.com/release/249504",
            discogsResourceUrl: "https://api.discogs.com/releases/249504",
            title: "Cosmic Music",
            artist: "John Coltrane & Alice Coltrane",
            year: 1968,
            format: "Vinyl, LP",
            firstReleaseYear: 1968,
            releaseYear: 1968,
            firstReleaseDate: "1968",
            releaseDate: "1968",
            label: "Impulse!",
            catalogNumber: "AS-9148",
            country: "US",
            barcode: "0123456789",
            coverImageUrl: "https://example.com/front.jpg",
            thumbnailUrl: "https://example.com/thumb.jpg",
            backCoverImageUrl: "https://example.com/back.jpg",
            backCoverText: "Recorded in New York.",
            releaseNotes: "Gatefold pressing.",
            genres: ["Jazz"],
            styles: ["Free Jazz"],
            companies: ["ABC Records"],
            tracklist: [AlbumTrack(position: "A1", title: "Manifestation", duration: "11:37")],
            identifiers: [AlbumIdentifier(type: "Matrix / Runout", value: "AS-9148-A", description: "Side A")],
            discogsDataQuality: "Correct",
            listeningLinks: [AlbumListeningLink(
                provider: "Apple Music",
                url: "https://music.apple.com/album/1",
                catalogId: "1",
                previewUrl: "https://example.com/preview.m4a")])
    }

    private func temporaryStoreURL(named name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("DejaGrooveRegressionTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("\(name).json")
    }
}

private actor RegressionScanRuntime: LocalScanRuntime {
    private let response: ScanResponse

    init(response: ScanResponse = ScanResponse(status: "no_match", confidence: 0, album: nil, candidates: [], requestId: UUID())) {
        self.response = response
    }

    func scan(imageData: Data, clientScanId: UUID, capturedAtIso: String?) async throws -> ScanResponse {
        response
    }

    func resolve(requestId: UUID, selectedAlbum: Album) async throws -> ScanResponse {
        ScanResponse(status: "safe_to_buy", confidence: 1, album: selectedAlbum, candidates: [], requestId: requestId)
    }
}

private struct RegressionAudioDiscoveryService: AudioDiscoveryService {
    let track: AudioDiscoveryTrack

    func identifyCurrentAudio() async throws -> AudioDiscoveryTrack {
        track
    }
}

private struct RegressionAlbumCandidateResolver: AlbumCandidateResolver {
    let candidates: [Album]

    func albumCandidates(for track: AudioDiscoveryTrack) async throws -> [Album] {
        candidates
    }
}

private struct RegressionMusicAuthorizationController: MusicAuthorizationControlling {
    let status: MusicAuthorizationStatus

    func requestAuthorization() async -> MusicAuthorizationStatus {
        status
    }
}

private actor RegressionFixedUUIDProvider: UUIDProviding {
    private var ids: [UUID]

    init(ids: [UUID]) {
        self.ids = ids
    }

    func nextUUID() async -> UUID {
        ids.isEmpty ? UUID() : ids.removeFirst()
    }
}

private actor RegressionFixedISO8601Clock: ISO8601Clock {
    private var instants: [String]

    init(instants: [String]) {
        self.instants = instants
    }

    func now() async -> String {
        instants.isEmpty ? "2026-01-01T00:00:00Z" : instants.removeFirst()
    }
}
