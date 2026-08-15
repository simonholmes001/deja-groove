import Foundation
import XCTest
@testable import DejaGrooveApp

final class PersistentLocalDiscoveryStoreTests: XCTestCase {
    func testAddFetchSearchPromoteAndDeleteDiscoveryEntries() async throws {
        let discoveryId = UUID(uuidString: "00000000-0000-0000-0000-000000000701")!
        let wishlistId = UUID(uuidString: "00000000-0000-0000-0000-000000000702")!
        let discoveryStore = PersistentLocalDiscoveryStore(
            fileURL: temporaryDiscoveryURL(),
            idProvider: DiscoveryFixedUUIDProvider(ids: [discoveryId]),
            clock: DiscoveryFixedISO8601Clock(instants: ["2026-01-01T00:00:00Z"]))
        let wishlistStore = PersistentLocalWishlistStore(
            fileURL: temporaryWishlistURL(),
            idProvider: DiscoveryFixedUUIDProvider(ids: [wishlistId]),
            clock: DiscoveryFixedISO8601Clock(instants: ["2026-01-02T00:00:00Z"]))
        let album = Album(mbid: nil, discogsReleaseId: nil, title: "Mingus Ah Um", artist: "Charles Mingus", year: 1959, format: "LP")

        let entry = try await discoveryStore.addDiscovery(source: "scan", album: album, track: nil)
        XCTAssertEqual(discoveryId, entry.id)

        let search = try await discoveryStore.fetchDiscoveries(search: "mingus")
        XCTAssertEqual([discoveryId], search.map(\.id))

        let wishlistEntry = try await discoveryStore.promoteDiscoveryToWishlist(id: discoveryId, wishlistStore: wishlistStore)
        XCTAssertEqual(wishlistId, wishlistEntry.id)
        XCTAssertEqual("Mingus Ah Um", wishlistEntry.album.title)

        try await discoveryStore.deleteDiscovery(id: discoveryId)
        let remaining = try await discoveryStore.fetchDiscoveries(search: nil)
        XCTAssertTrue(remaining.isEmpty)
    }

    func testContainsUsesSharedDuplicateRulesForDiscoveredAlbums() async throws {
        let discoveryStore = PersistentLocalDiscoveryStore(fileURL: temporaryDiscoveryURL())
        let discovered = Album(
            mbid: nil,
            discogsReleaseId: "3669035",
            title: "Footprints Live!",
            artist: "Wayne Shorter",
            year: 2002,
            format: "CD")
        let scanned = Album(
            mbid: nil,
            discogsReleaseId: "3669035",
            title: "Footprints Live!",
            artist: "Wayne Shorter",
            year: nil,
            format: nil)

        _ = try await discoveryStore.addDiscovery(source: "audio", album: discovered, track: nil)

        let contains = try await discoveryStore.contains(album: scanned)
        XCTAssertTrue(contains)
    }

    func testFetchDiscoveriesSortsByArtistFamilyNameThenTitle() async throws {
        let store = PersistentLocalDiscoveryStore(
            fileURL: temporaryDiscoveryURL(),
            idProvider: DiscoveryFixedUUIDProvider(ids: [
                UUID(uuidString: "00000000-0000-0000-0000-000000000711")!,
                UUID(uuidString: "00000000-0000-0000-0000-000000000712")!,
                UUID(uuidString: "00000000-0000-0000-0000-000000000713")!
            ]),
            clock: DiscoveryFixedISO8601Clock(instants: [
                "2026-01-03T00:00:00Z",
                "2026-01-02T00:00:00Z",
                "2026-01-01T00:00:00Z"
            ]))

        _ = try await store.addDiscovery(
            source: "audio",
            album: Album(mbid: nil, discogsReleaseId: nil, title: "Saxophone Colossus", artist: "Sonny Rollins", year: 1956, format: "LP"),
            track: nil)
        _ = try await store.addDiscovery(
            source: "audio",
            album: Album(mbid: nil, discogsReleaseId: nil, title: "Blue Train", artist: "John Coltrane", year: 1957, format: "LP"),
            track: nil)
        _ = try await store.addDiscovery(
            source: "audio",
            album: nil,
            track: AudioDiscoveryTrack(title: "Goodbye Pork Pie Hat", artist: "Charles Mingus", matchedAt: "2026-01-01T00:00:00Z"))

        let entries = try await store.fetchDiscoveries(search: nil)

        XCTAssertEqual(["Blue Train", "Goodbye Pork Pie Hat", "Saxophone Colossus"], entries.map { $0.album?.title ?? $0.track?.title ?? "" })
    }

    func testDeleteAllDiscoveriesClearsPersistedHistory() async throws {
        let store = PersistentLocalDiscoveryStore(
            fileURL: temporaryDiscoveryURL(),
            idProvider: DiscoveryFixedUUIDProvider(ids: [
                UUID(uuidString: "00000000-0000-0000-0000-000000000721")!,
                UUID(uuidString: "00000000-0000-0000-0000-000000000722")!
            ]),
            clock: DiscoveryFixedISO8601Clock(instants: [
                "2026-01-01T00:00:00Z",
                "2026-01-02T00:00:00Z"
            ]))

        _ = try await store.addDiscovery(
            source: "scan",
            album: Album(mbid: nil, discogsReleaseId: nil, title: "The Chemical Wedding", artist: "Bruce Dickinson", year: 1998, format: "CD"),
            track: nil)
        _ = try await store.addDiscovery(
            source: "audio",
            album: Album(mbid: nil, discogsReleaseId: nil, title: "Indigo", artist: "Miki Yamanaka", year: 2024, format: nil),
            track: AudioDiscoveryTrack(title: "Indigo", artist: "Miki Yamanaka", matchedAt: "2026-01-02T00:00:00Z"))

        try await store.deleteAllDiscoveries()

        let remaining = try await store.fetchDiscoveries(search: nil)
        XCTAssertTrue(remaining.isEmpty)
    }

    private func temporaryDiscoveryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("dejagroove-discovery-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("discovery.json")
    }

    private func temporaryWishlistURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("dejagroove-discovery-wishlist-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("wishlist.json")
    }
}

private actor DiscoveryFixedUUIDProvider: UUIDProviding {
    private var ids: [UUID]

    init(ids: [UUID]) {
        self.ids = ids
    }

    func nextUUID() async -> UUID {
        ids.isEmpty ? UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")! : ids.removeFirst()
    }
}

private actor DiscoveryFixedISO8601Clock: ISO8601Clock {
    private var instants: [String]

    init(instants: [String]) {
        self.instants = instants
    }

    func now() async -> String {
        instants.isEmpty ? "2026-01-01T00:00:00Z" : instants.removeFirst()
    }
}
