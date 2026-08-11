import Foundation
import XCTest
@testable import DejaGrooveApp

final class PersistentLocalWishlistStoreTests: XCTestCase {
    func testAddFetchSearchUpdateAndDeleteWishlistEntries() async throws {
        let entryId = UUID(uuidString: "00000000-0000-0000-0000-000000000601")!
        let store = PersistentLocalWishlistStore(
            fileURL: temporaryStoreURL(),
            idProvider: WishlistFixedUUIDProvider(ids: [entryId]),
            clock: WishlistFixedISO8601Clock(instants: [
                "2026-01-01T00:00:00Z",
                "2026-01-02T00:00:00Z"
            ]))
        let album = Album(
            mbid: nil,
            discogsReleaseId: "249504",
            title: "Blue",
            artist: "Joni Mitchell",
            year: 1971,
            format: "LP",
            label: "Reprise",
            catalogNumber: "MS 2038",
            country: "US")

        let added = try await store.addToWishlist(
            album: album,
            preferences: WishlistPreferences(targetFormat: "LP", country: "US", label: "Reprise", catalogNumber: "MS 2038", notes: "clean early copy"),
            sourceTrack: AudioDiscoveryTrack(title: "A Case of You", artist: "Joni Mitchell", matchedAt: "2026-01-01T00:00:00Z"))

        XCTAssertEqual(entryId, added.id)
        XCTAssertEqual("Blue", added.album.title)
        XCTAssertEqual("LP", added.preferences.targetFormat)
        XCTAssertEqual("A Case of You", added.sourceTrack?.title)

        let search = try await store.fetchWishlist(search: "case")
        XCTAssertEqual([entryId], search.map(\.id))

        let updated = try await store.updateWishlistPreferences(
            id: entryId,
            preferences: WishlistPreferences(targetFormat: "Vinyl LP", country: "Canada", label: nil, catalogNumber: nil, notes: "Canadian pressing"))
        XCTAssertEqual("Canada", updated.preferences.country)
        XCTAssertEqual("2026-01-02T00:00:00Z", updated.updatedAt)

        let containsAlbum = try await store.contains(album: album)
        XCTAssertTrue(containsAlbum)

        try await store.deleteWishlistEntry(id: entryId)
        let remaining = try await store.fetchWishlist(search: nil)
        XCTAssertTrue(remaining.isEmpty)
    }

    func testFetchWishlistSortsByArtistFamilyNameThenTitle() async throws {
        let store = PersistentLocalWishlistStore(
            fileURL: temporaryStoreURL(),
            idProvider: WishlistFixedUUIDProvider(ids: [
                UUID(uuidString: "00000000-0000-0000-0000-000000000611")!,
                UUID(uuidString: "00000000-0000-0000-0000-000000000612")!,
                UUID(uuidString: "00000000-0000-0000-0000-000000000613")!
            ]),
            clock: WishlistFixedISO8601Clock(instants: [
                "2026-01-01T00:00:00Z",
                "2026-01-02T00:00:00Z",
                "2026-01-03T00:00:00Z"
            ]))

        _ = try await store.addToWishlist(
            album: Album(mbid: nil, discogsReleaseId: nil, title: "Blue", artist: "Joni Mitchell", year: 1971, format: "LP"),
            preferences: WishlistPreferences(),
            sourceTrack: nil)
        _ = try await store.addToWishlist(
            album: Album(mbid: nil, discogsReleaseId: nil, title: "Mingus Ah Um", artist: "Charles Mingus", year: 1959, format: "LP"),
            preferences: WishlistPreferences(),
            sourceTrack: nil)
        _ = try await store.addToWishlist(
            album: Album(mbid: nil, discogsReleaseId: nil, title: "Kind of Blue", artist: "Miles Davis", year: 1959, format: "LP"),
            preferences: WishlistPreferences(),
            sourceTrack: nil)

        let entries = try await store.fetchWishlist(search: nil)

        XCTAssertEqual(["Miles Davis", "Charles Mingus", "Joni Mitchell"], entries.map(\.album.artist))
    }

    private func temporaryStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("dejagroove-wishlist-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("wishlist.json")
    }
}

private actor WishlistFixedUUIDProvider: UUIDProviding {
    private var ids: [UUID]

    init(ids: [UUID]) {
        self.ids = ids
    }

    func nextUUID() async -> UUID {
        ids.isEmpty ? UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")! : ids.removeFirst()
    }
}

private actor WishlistFixedISO8601Clock: ISO8601Clock {
    private var instants: [String]

    init(instants: [String]) {
        self.instants = instants
    }

    func now() async -> String {
        instants.isEmpty ? "2026-01-01T00:00:00Z" : instants.removeFirst()
    }
}
