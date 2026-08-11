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
