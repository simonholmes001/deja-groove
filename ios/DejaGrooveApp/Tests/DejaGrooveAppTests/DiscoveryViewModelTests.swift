import Foundation
import XCTest
@testable import DejaGrooveApp

@MainActor
final class DiscoveryViewModelTests: XCTestCase {
    func testPrepareMusicAccessStoresAuthorizedStatus() async {
        let authorization = MusicAuthorizationControllerStub(status: .authorized)
        let sut = DiscoveryViewModel(
            api: DiscoveryApiClientSpy(),
            discoveryStore: DiscoveryStoreSpy(),
            audioDiscovery: AudioDiscoveryServiceStub(),
            candidateResolver: AlbumCandidateResolverStub(),
            musicAuthorization: authorization)

        await sut.prepareMusicAccess()

        XCTAssertEqual(.authorized, sut.musicAuthorizationStatus)
        XCTAssertNil(sut.message)
    }

    func testListeningVisualStateFollowsAudioDiscoveryLoading() async {
        let gate = AudioDiscoveryGate()
        let sut = DiscoveryViewModel(
            api: DiscoveryApiClientSpy(),
            discoveryStore: DiscoveryStoreSpy(),
            audioDiscovery: GatedAudioDiscoveryService(gate: gate),
            candidateResolver: AlbumCandidateResolverStub(),
            musicAuthorization: MusicAuthorizationControllerStub(status: .authorized))

        let task = Task { await sut.identifyPlayingAudio() }
        await gate.waitUntilStarted()

        XCTAssertTrue(sut.shouldShowListeningActivity)

        await gate.finish()
        await task.value

        XCTAssertFalse(sut.shouldShowListeningActivity)
    }

    func testPrepareMusicAccessExplainsDeniedAccessWithoutBlockingDiscovery() async {
        let authorization = MusicAuthorizationControllerStub(status: .denied)
        let sut = DiscoveryViewModel(
            api: DiscoveryApiClientSpy(),
            discoveryStore: DiscoveryStoreSpy(),
            audioDiscovery: AudioDiscoveryServiceStub(),
            candidateResolver: AlbumCandidateResolverStub(),
            musicAuthorization: authorization)

        await sut.prepareMusicAccess()

        XCTAssertEqual(.denied, sut.musicAuthorizationStatus)
        XCTAssertEqual("Apple Music access was not granted. Discovery can still save local history.", sut.message)
    }

    func testIdentifyPlayingAudioStoresHistoryAndAlbumCandidates() async {
        let track = AudioDiscoveryTrack(title: "Goodbye Pork Pie Hat", artist: "Charles Mingus", matchedAt: "2026-01-01T00:00:00Z")
        let album = Album(mbid: nil, discogsReleaseId: "249504", title: "Mingus Ah Um", artist: "Charles Mingus", year: 1959, format: "LP")
        let discoveryStore = DiscoveryStoreSpy()
        let sut = DiscoveryViewModel(
            api: DiscoveryApiClientSpy(),
            discoveryStore: discoveryStore,
            audioDiscovery: AudioDiscoveryServiceStub(track: track),
            candidateResolver: AlbumCandidateResolverStub(candidates: [album]),
            musicAuthorization: MusicAuthorizationControllerStub(status: .authorized))

        await sut.identifyPlayingAudio()

        XCTAssertEqual(track, sut.track)
        XCTAssertEqual([album], sut.candidates)
        XCTAssertEqual(1, sut.history.count)
        XCTAssertEqual("audio", sut.history.first?.source)
        let snapshot = await discoveryStore.snapshot()
        XCTAssertEqual(album, snapshot.entries.first?.album)
        XCTAssertEqual(track, snapshot.entries.first?.track)
    }

    func testIdentifyPlayingAudioStoresEnrichedAlbumCandidatesWithListeningLinks() async {
        let track = AudioDiscoveryTrack(title: "Indigo", artist: "Miki Yamanaka", matchedAt: "2026-08-14T10:23:00Z")
        let candidate = Album(
            mbid: nil,
            discogsReleaseId: nil,
            title: "Indigo",
            artist: "Miki Yamanaka",
            year: 2024,
            format: nil,
            listeningLinks: [AlbumListeningLink(provider: "Apple Music", url: "https://music.apple.com/album/indigo")])
        let enriched = Album(
            mbid: nil,
            discogsReleaseId: "123456",
            title: "Indigo",
            artist: "Miki Yamanaka",
            year: 2024,
            format: "Vinyl, LP",
            label: "Cellar Music",
            catalogNumber: "CM-123",
            country: "US",
            genres: ["Jazz"],
            styles: ["Contemporary Jazz"],
            tracklist: [AlbumTrack(position: "A1", title: "Indigo", duration: "4:12")],
            listeningLinks: [AlbumListeningLink(provider: "Apple Music", url: "https://music.apple.com/album/indigo")])
        let discoveryStore = DiscoveryStoreSpy()
        let sut = DiscoveryViewModel(
            api: DiscoveryApiClientSpy(),
            discoveryStore: discoveryStore,
            audioDiscovery: AudioDiscoveryServiceStub(track: track),
            candidateResolver: AlbumCandidateResolverStub(candidates: [candidate]),
            albumEnricher: AlbumMetadataEnricherStub(enrichedAlbums: [enriched]),
            musicAuthorization: MusicAuthorizationControllerStub(status: .authorized))

        await sut.identifyPlayingAudio()

        XCTAssertEqual("123456", sut.candidates.first?.discogsReleaseId)
        XCTAssertEqual("Cellar Music", sut.candidates.first?.label)
        XCTAssertEqual("CM-123", sut.candidates.first?.catalogNumber)
        XCTAssertEqual("US", sut.candidates.first?.country)
        XCTAssertEqual(["Jazz"], sut.candidates.first?.genres)
        XCTAssertEqual("Indigo", sut.candidates.first?.tracklist.first?.title)
        XCTAssertEqual("Apple Music", sut.candidates.first?.listeningLinks.first?.provider)
        let snapshot = await discoveryStore.snapshot()
        XCTAssertEqual(enriched, snapshot.entries.first?.album)
    }

    func testIdentifyPlayingAudioPrioritizesDiscogsEnrichedCandidateForHistory() async {
        let track = AudioDiscoveryTrack(title: "Sanctuary (Live)", artist: "Wayne Shorter", matchedAt: "2026-08-15T13:13:34Z")
        let sparse = Album(
            mbid: nil,
            discogsReleaseId: nil,
            title: "Sanctuary (Live)",
            artist: "Wayne Shorter",
            year: 2002,
            format: nil,
            listeningLinks: [AlbumListeningLink(provider: "Apple Music", url: "https://music.apple.com/track/sanctuary")])
        let albumCandidate = Album(
            mbid: nil,
            discogsReleaseId: nil,
            title: "Footprints Live!",
            artist: "Wayne Shorter",
            year: 2002,
            format: nil,
            listeningLinks: [AlbumListeningLink(provider: "Apple Music", url: "https://music.apple.com/album/footprints-live")])
        let discogsEnriched = Album(
            mbid: nil,
            discogsReleaseId: "1552461",
            discogsMasterId: "4321",
            title: "Footprints Live!",
            artist: "Wayne Shorter",
            year: 2002,
            format: "CD, Album",
            label: "Verve",
            catalogNumber: "314 589 679-2",
            country: "US",
            barcode: "731458967927",
            genres: ["Jazz"],
            styles: ["Post Bop"],
            tracklist: [AlbumTrack(position: "8", title: "Sanctuary", duration: "5:31")],
            identifiers: [AlbumIdentifier(type: "Barcode", value: "731458967927", description: nil)],
            listeningLinks: [AlbumListeningLink(provider: "Apple Music", url: "https://music.apple.com/album/footprints-live")])
        let discoveryStore = DiscoveryStoreSpy()
        let sut = DiscoveryViewModel(
            api: DiscoveryApiClientSpy(),
            discoveryStore: discoveryStore,
            audioDiscovery: AudioDiscoveryServiceStub(track: track),
            candidateResolver: AlbumCandidateResolverStub(candidates: [sparse, albumCandidate]),
            albumEnricher: AlbumMetadataEnricherStub(enrichedAlbums: [discogsEnriched]),
            musicAuthorization: MusicAuthorizationControllerStub(status: .authorized))

        await sut.identifyPlayingAudio()

        XCTAssertEqual("1552461", sut.candidates.first?.discogsReleaseId)
        XCTAssertEqual("Footprints Live!", sut.candidates.first?.title)
        let snapshot = await discoveryStore.snapshot()
        XCTAssertEqual("1552461", snapshot.entries.first?.album?.discogsReleaseId)
        XCTAssertEqual("Footprints Live!", snapshot.entries.first?.album?.title)
    }

    func testIdentifyPlayingAudioRejectsEnrichedAlbumsThatDoNotContainMatchedTrack() async {
        let track = AudioDiscoveryTrack(title: "Flash Of The Blade", artist: "Iron Maiden", matchedAt: "2026-08-15T15:16:00Z")
        let powerslave = Album(
            mbid: nil,
            discogsReleaseId: nil,
            title: "Powerslave",
            artist: "Iron Maiden",
            year: 1984,
            format: nil,
            listeningLinks: [AlbumListeningLink(provider: "Apple Music", url: "https://music.apple.com/album/powerslave")])
        let wrongBlade = Album(
            mbid: nil,
            discogsReleaseId: nil,
            title: "The Best Of Rusty Blade",
            artist: "Rusty Blade",
            year: 2010,
            format: nil,
            listeningLinks: [AlbumListeningLink(provider: "Apple Music", url: "https://music.apple.com/album/rusty-blade")])
        let enrichedPowerslave = Album(
            mbid: nil,
            discogsReleaseId: "865721",
            title: "Powerslave",
            artist: "Iron Maiden",
            year: 1984,
            format: "Vinyl, LP, Album",
            label: "EMI",
            catalogNumber: "POWER 1",
            tracklist: [
                AlbumTrack(position: "A1", title: "Aces High", duration: nil),
                AlbumTrack(position: "A2", title: "2 Minutes To Midnight", duration: nil),
                AlbumTrack(position: "A3", title: "Losfer Words (Big 'Orra)", duration: nil),
                AlbumTrack(position: "A4", title: "Flash Of The Blade", duration: nil)
            ],
            listeningLinks: [AlbumListeningLink(provider: "Apple Music", url: "https://music.apple.com/album/powerslave")])
        let enrichedWrongBlade = Album(
            mbid: nil,
            discogsReleaseId: "999999",
            discogsMasterId: "888888",
            title: "The Best Of Rusty Blade",
            artist: "Rusty Blade",
            year: 2010,
            format: "CD, Compilation",
            label: "Wrong Label",
            catalogNumber: "WRONG-1",
            country: "MY",
            tracklist: [AlbumTrack(position: "1", title: "Not Flash Of The Blade", duration: nil)],
            identifiers: [AlbumIdentifier(type: "Barcode", value: "123", description: nil)],
            listeningLinks: [AlbumListeningLink(provider: "Apple Music", url: "https://music.apple.com/album/rusty-blade")])
        let discoveryStore = DiscoveryStoreSpy()
        let sut = DiscoveryViewModel(
            api: DiscoveryApiClientSpy(),
            discoveryStore: discoveryStore,
            audioDiscovery: AudioDiscoveryServiceStub(track: track),
            candidateResolver: AlbumCandidateResolverStub(candidates: [wrongBlade, powerslave]),
            albumEnricher: AlbumMetadataEnricherStub(enrichedAlbums: [enrichedWrongBlade, enrichedPowerslave]),
            musicAuthorization: MusicAuthorizationControllerStub(status: .authorized))

        await sut.identifyPlayingAudio()

        XCTAssertEqual(["Powerslave"], sut.candidates.map(\.title))
        XCTAssertEqual("865721", sut.candidates.first?.discogsReleaseId)
        let snapshot = await discoveryStore.snapshot()
        XCTAssertEqual("Powerslave", snapshot.entries.first?.album?.title)
    }

    func testIdentifyPlayingAudioSurfacesServiceMessageWhenMicrophonePermissionIsDenied() async {
        let error = ApiClientError.httpError(
            403,
            ApiError(
                code: "microphone_permission_denied",
                message: "Microphone access is required to identify audio.",
                retryable: false,
                requestId: UUID()))
        let sut = DiscoveryViewModel(
            api: DiscoveryApiClientSpy(),
            discoveryStore: DiscoveryStoreSpy(),
            audioDiscovery: AudioDiscoveryServiceStub(error: error),
            candidateResolver: AlbumCandidateResolverStub(),
            musicAuthorization: MusicAuthorizationControllerStub(status: .authorized))

        await sut.identifyPlayingAudio()

        XCTAssertEqual("Microphone access is required to identify audio.", sut.message)
        XCTAssertFalse(sut.isLoading)
    }

    func testSaveCandidateToWishlistUsesCurrentSourceTrack() async {
        let track = AudioDiscoveryTrack(title: "Case of You", artist: "Joni Mitchell", matchedAt: "2026-01-01T00:00:00Z")
        let album = Album(mbid: nil, discogsReleaseId: nil, title: "Blue", artist: "Joni Mitchell", year: 1971, format: "LP")
        let api = DiscoveryApiClientSpy()
        let sut = DiscoveryViewModel(
            api: api,
            discoveryStore: DiscoveryStoreSpy(),
            audioDiscovery: AudioDiscoveryServiceStub(track: track),
            candidateResolver: AlbumCandidateResolverStub(candidates: [album]),
            musicAuthorization: MusicAuthorizationControllerStub(status: .authorized))

        await sut.identifyPlayingAudio()
        await sut.saveCandidateToWishlist(album)

        let snapshot = await api.snapshot()
        XCTAssertEqual(album, snapshot.wishlistAlbums.first)
        XCTAssertEqual(track, snapshot.sourceTracks.first)
        XCTAssertEqual("Added to Wishlist.", sut.message)
    }

    func testSaveCandidateToWishlistRetriesEnrichmentBeforePersistingSparseAlbum() async {
        let track = AudioDiscoveryTrack(title: "Sanctuary (Live)", artist: "Wayne Shorter", matchedAt: "2026-08-14T11:39:41Z")
        let sparse = Album(
            mbid: nil,
            discogsReleaseId: nil,
            title: "Sanctuary (Live)",
            artist: "Wayne Shorter",
            year: nil,
            format: nil)
        let enriched = Album(
            mbid: nil,
            discogsReleaseId: "3669035",
            title: "Footprints Live!",
            artist: "Wayne Shorter",
            year: 2002,
            format: "CD, Album",
            releaseDate: "2002",
            label: "Verve Records",
            catalogNumber: "589 679-2",
            country: "Europe",
            genres: ["Jazz"],
            tracklist: [AlbumTrack(position: "8", title: "Sanctuary", duration: "5:31")],
            listeningLinks: [AlbumListeningLink(provider: "Apple Music", url: "https://music.apple.com/search?term=Wayne+Shorter+Footprints+Live%21")])
        let api = DiscoveryApiClientSpy()
        let enricher = SequencedAlbumMetadataEnricherStub(results: [
            .failure(ApiClientError.invalidResponse),
            .success(enriched)
        ])
        let sut = DiscoveryViewModel(
            api: api,
            discoveryStore: DiscoveryStoreSpy(),
            audioDiscovery: AudioDiscoveryServiceStub(track: track),
            candidateResolver: AlbumCandidateResolverStub(candidates: [sparse]),
            albumEnricher: enricher,
            musicAuthorization: MusicAuthorizationControllerStub(status: .authorized))

        await sut.identifyPlayingAudio()
        XCTAssertEqual("Sanctuary (Live)", sut.candidates.first?.title)

        await sut.saveCandidateToWishlist(sparse)

        let snapshot = await api.snapshot()
        XCTAssertEqual("Footprints Live!", snapshot.wishlistAlbums.first?.title)
        XCTAssertEqual("3669035", snapshot.wishlistAlbums.first?.discogsReleaseId)
        XCTAssertEqual("Verve Records", snapshot.wishlistAlbums.first?.label)
        XCTAssertEqual("Apple Music", snapshot.wishlistAlbums.first?.listeningLinks.first?.provider)
        XCTAssertEqual(track, snapshot.sourceTracks.first)
    }

    func testClearAllHistoryRemovesVisibleAndPersistedDiscoveries() async {
        let discoveryStore = DiscoveryStoreSpy()
        let sut = DiscoveryViewModel(
            api: DiscoveryApiClientSpy(),
            discoveryStore: discoveryStore,
            audioDiscovery: AudioDiscoveryServiceStub(),
            candidateResolver: AlbumCandidateResolverStub(candidates: [
                Album(mbid: nil, discogsReleaseId: nil, title: "Indigo", artist: "Miki Yamanaka", year: 2024, format: nil)
            ]),
            musicAuthorization: MusicAuthorizationControllerStub(status: .authorized))

        await sut.identifyPlayingAudio()
        XCTAssertEqual(1, sut.history.count)

        await sut.clearAllHistory()

        XCTAssertTrue(sut.history.isEmpty)
        let snapshot = await discoveryStore.snapshot()
        XCTAssertTrue(snapshot.entries.isEmpty)
    }
}

private struct MusicAuthorizationControllerStub: MusicAuthorizationControlling {
    let status: MusicAuthorizationStatus

    func requestAuthorization() async -> MusicAuthorizationStatus {
        status
    }
}

private struct AudioDiscoveryServiceStub: AudioDiscoveryService {
    var track: AudioDiscoveryTrack = AudioDiscoveryTrack(title: "Track", artist: "Artist", matchedAt: "2026-01-01T00:00:00Z")
    var error: Error?

    func identifyCurrentAudio() async throws -> AudioDiscoveryTrack {
        if let error {
            throw error
        }
        return track
    }
}

private struct GatedAudioDiscoveryService: AudioDiscoveryService {
    let gate: AudioDiscoveryGate

    func identifyCurrentAudio() async throws -> AudioDiscoveryTrack {
        await gate.markStarted()
        await gate.waitUntilFinished()
        return AudioDiscoveryTrack(title: "Track", artist: "Artist", matchedAt: "2026-01-01T00:00:00Z")
    }
}

private actor AudioDiscoveryGate {
    private var startedContinuation: CheckedContinuation<Void, Never>?
    private var finishContinuation: CheckedContinuation<Void, Never>?
    private var hasStarted = false
    private var hasFinished = false

    func markStarted() {
        hasStarted = true
        startedContinuation?.resume()
        startedContinuation = nil
    }

    func waitUntilStarted() async {
        if hasStarted { return }
        await withCheckedContinuation { continuation in
            startedContinuation = continuation
        }
    }

    func waitUntilFinished() async {
        if hasFinished { return }
        await withCheckedContinuation { continuation in
            finishContinuation = continuation
        }
    }

    func finish() {
        hasFinished = true
        finishContinuation?.resume()
        finishContinuation = nil
    }
}

private struct AlbumCandidateResolverStub: AlbumCandidateResolver {
    var candidates: [Album] = []

    func albumCandidates(for track: AudioDiscoveryTrack) async throws -> [Album] {
        candidates
    }
}

private struct AlbumMetadataEnricherStub: AlbumMetadataEnricher {
    var enrichedAlbums: [Album] = []

    func enrich(album: Album) async throws -> Album {
        enrichedAlbums.first { $0.title == album.title && $0.artist == album.artist } ?? album
    }
}

private final class SequencedAlbumMetadataEnricherStub: AlbumMetadataEnricher, @unchecked Sendable {
    private var results: [Result<Album, Error>]

    init(results: [Result<Album, Error>]) {
        self.results = results
    }

    func enrich(album: Album) async throws -> Album {
        guard !results.isEmpty else { return album }
        switch results.removeFirst() {
        case .success(let enriched):
            return enriched
        case .failure(let error):
            throw error
        }
    }
}

private actor DiscoveryStoreSpy: LocalDiscoveryStore {
    private(set) var entries: [DiscoveryEntry] = []

    func contains(album: Album) async throws -> Bool {
        entries.contains {
            guard let discoveredAlbum = $0.album else { return false }
            return LocalCollectionRules.isDuplicate(discoveredAlbum, album)
        }
    }

    func addDiscovery(source: String, album: Album?, track: AudioDiscoveryTrack?) async throws -> DiscoveryEntry {
        let entry = DiscoveryEntry(id: UUID(), source: source, album: album, track: track, createdAt: "2026-01-01T00:00:00Z")
        entries.append(entry)
        return entry
    }

    func fetchDiscoveries(search: String?) async throws -> [DiscoveryEntry] {
        entries
    }

    func promoteDiscoveryToWishlist(id: UUID, wishlistStore: LocalWishlistStore) async throws -> WishlistEntry {
        guard let entry = entries.first(where: { $0.id == id }), let album = entry.album else {
            throw ApiClientError.invalidResponse
        }
        return try await wishlistStore.addToWishlist(album: album, preferences: WishlistPreferences(), sourceTrack: entry.track)
    }

    func deleteDiscovery(id: UUID) async throws {
        entries.removeAll { $0.id == id }
    }

    func deleteAllDiscoveries() async throws {
        entries.removeAll()
    }

    func snapshot() -> DiscoveryStoreSnapshot {
        DiscoveryStoreSnapshot(entries: entries)
    }
}

private struct DiscoveryStoreSnapshot {
    let entries: [DiscoveryEntry]
}

private actor DiscoveryApiClientSpy: ApiClient {
    private(set) var wishlistAlbums: [Album] = []
    private(set) var sourceTracks: [AudioDiscoveryTrack?] = []

    func scan(imageData: Data, clientScanId: UUID, capturedAtIso: String?) async throws -> ScanResponse {
        ScanResponse(status: "no_match", confidence: 0, album: nil, candidates: [], requestId: UUID())
    }

    func resolve(requestId: UUID, selectedAlbum: Album) async throws -> ScanResponse {
        ScanResponse(status: "safe_to_buy", confidence: 1, album: selectedAlbum, candidates: [], requestId: requestId)
    }

    func fetchCollection(search: String?) async throws -> CollectionListResponse {
        CollectionListResponse(items: [], nextCursor: nil)
    }

    func addToCollection(album: Album, notes: String?, addAnyway: Bool) async throws -> CollectionItemResponse {
        CollectionItemResponse(id: UUID(), mbid: album.mbid, discogsReleaseId: album.discogsReleaseId, title: album.title, artist: album.artist, year: album.year, format: album.format, notes: notes, createdAt: "", updatedAt: "")
    }

    func patchCollection(id: UUID, format: String?, notes: String?) async throws -> CollectionItemResponse {
        CollectionItemResponse(id: id, mbid: nil, discogsReleaseId: nil, title: "", artist: "", year: nil, format: format, notes: notes, createdAt: "", updatedAt: "")
    }

    func updateCollectionRecord(id: UUID, album: Album, notes: String?) async throws -> CollectionItemResponse {
        CollectionItemResponse(id: id, mbid: album.mbid, discogsReleaseId: album.discogsReleaseId, title: album.title, artist: album.artist, year: album.year, format: album.format, notes: notes, createdAt: "", updatedAt: "")
    }

    func deleteCollectionRecord(id: UUID) async throws {}

    func addToWishlist(album: Album, preferences: WishlistPreferences, sourceTrack: AudioDiscoveryTrack?) async throws -> WishlistEntry {
        wishlistAlbums.append(album)
        sourceTracks.append(sourceTrack)
        return WishlistEntry(id: UUID(), album: album, preferences: preferences, sourceTrack: sourceTrack, createdAt: "", updatedAt: "")
    }

    func fetchWishlist(search: String?) async throws -> [WishlistEntry] {
        []
    }

    func updateWishlistPreferences(id: UUID, preferences: WishlistPreferences) async throws -> WishlistEntry {
        WishlistEntry(id: id, album: Album(mbid: nil, discogsReleaseId: nil, title: "", artist: "", year: nil, format: nil), preferences: preferences, sourceTrack: nil, createdAt: "", updatedAt: "")
    }

    func deleteWishlistEntry(id: UUID) async throws {}

    func fetchCrateCollections(search: String?) async throws -> [CrateCollection] {
        []
    }

    func createCrateCollection(name: String) async throws -> CrateCollection {
        CrateCollection(id: UUID(), name: name, recordIds: [], createdAt: "", updatedAt: "")
    }

    func renameCrateCollection(id: UUID, name: String) async throws -> CrateCollection {
        CrateCollection(id: id, name: name, recordIds: [], createdAt: "", updatedAt: "")
    }

    func deleteCrateCollection(id: UUID) async throws {}

    func addRecord(_ recordId: UUID, toCrateCollection collectionId: UUID) async throws -> CrateCollection {
        CrateCollection(id: collectionId, name: "", recordIds: [recordId], createdAt: "", updatedAt: "")
    }

    func removeRecord(_ recordId: UUID, fromCrateCollection collectionId: UUID) async throws -> CrateCollection {
        CrateCollection(id: collectionId, name: "", recordIds: [], createdAt: "", updatedAt: "")
    }

    func snapshot() -> DiscoveryApiClientSnapshot {
        DiscoveryApiClientSnapshot(wishlistAlbums: wishlistAlbums, sourceTracks: sourceTracks)
    }
}

private struct DiscoveryApiClientSnapshot {
    let wishlistAlbums: [Album]
    let sourceTracks: [AudioDiscoveryTrack?]
}
