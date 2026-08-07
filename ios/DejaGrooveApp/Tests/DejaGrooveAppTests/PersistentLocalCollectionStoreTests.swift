import Foundation
import XCTest
@testable import DejaGrooveApp

final class PersistentLocalCollectionStoreTests: XCTestCase {
    func testAddFetchAndSearchCollectionRecords() async throws {
        let store = try makeStore(
            ids: [
                UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
                UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
            ],
            instants: [
                "2026-01-01T00:00:00Z",
                "2026-01-02T00:00:00Z"
            ])

        _ = try await store.addToCollection(
            album: Album(mbid: "mbid-blue", discogsReleaseId: nil, title: "Blue", artist: "Joni Mitchell", year: 1971, format: "vinyl"),
            notes: "gatefold",
            addAnyway: false)
        _ = try await store.addToCollection(
            album: Album(mbid: "mbid-kind", discogsReleaseId: nil, title: "Kind of Blue", artist: "Miles Davis", year: 1959, format: "vinyl"),
            notes: nil,
            addAnyway: false)

        let all = try await store.fetchCollection(search: nil)
        XCTAssertEqual(["Kind of Blue", "Blue"], all.items.map(\.album.title))
        XCTAssertEqual("2026-01-02T00:00:00Z", all.items.first?.createdAt)
        XCTAssertNil(all.nextCursor)

        let search = try await store.fetchCollection(search: "joni")
        XCTAssertEqual(1, search.items.count)
        XCTAssertEqual("Blue", search.items.first?.album.title)
        XCTAssertEqual("gatefold", search.items.first?.notes)
    }

    func testAddRejectsDuplicateAlbumUnlessAddAnywayIsTrue() async throws {
        let store = try makeStore(
            ids: [
                UUID(uuidString: "00000000-0000-0000-0000-000000000201")!,
                UUID(uuidString: "00000000-0000-0000-0000-000000000202")!
            ],
            instants: [
                "2026-01-01T00:00:00Z",
                "2026-01-02T00:00:00Z"
            ])
        let album = Album(mbid: "same-mbid", discogsReleaseId: nil, title: "Blue", artist: "Joni Mitchell", year: 1971, format: nil)

        _ = try await store.addToCollection(album: album, notes: nil, addAnyway: false)

        do {
            _ = try await store.addToCollection(album: album, notes: "duplicate", addAnyway: false)
            XCTFail("Expected duplicate add to fail")
        } catch let error as ApiClientError {
            XCTAssertEqual(
                ApiClientError.httpError(
                    409,
                    ApiError(
                        code: "collection_duplicate",
                        message: "Album is already in the local collection.",
                        retryable: false,
                        requestId: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!)),
                error)
        }

        _ = try await store.addToCollection(album: album, notes: "duplicate", addAnyway: true)
        let all = try await store.fetchCollection(search: nil)
        XCTAssertEqual(2, all.items.count)
    }

    func testAddRejectsDuplicateDiscogsReleaseEvenWhenMbidDiffers() async throws {
        let store = try makeStore(
            ids: [UUID(uuidString: "00000000-0000-0000-0000-000000000211")!],
            instants: ["2026-01-01T00:00:00Z"])
        let first = Album(mbid: "mbid-a", discogsReleaseId: "discogs-1", title: "Blue", artist: "Joni Mitchell", year: 1971, format: nil)
        let duplicate = Album(mbid: "mbid-b", discogsReleaseId: "discogs-1", title: "Blue", artist: "Joni Mitchell", year: 1971, format: nil)

        _ = try await store.addToCollection(album: first, notes: nil, addAnyway: false)

        do {
            _ = try await store.addToCollection(album: duplicate, notes: nil, addAnyway: false)
            XCTFail("Expected matching Discogs release ID to be treated as duplicate")
        } catch let error as ApiClientError {
            if case .httpError(let status, let apiError) = error {
                XCTAssertEqual(409, status)
                XCTAssertEqual("collection_duplicate", apiError?.code)
            } else {
                XCTFail("Expected ApiClientError.httpError")
            }
        }
    }

    func testPatchCollectionPreservesUnspecifiedFieldsAndPersistsToDisk() async throws {
        let fileURL = temporaryStoreURL()
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000301")!
        let store = PersistentLocalCollectionStore(
            fileURL: fileURL,
            idProvider: FixedUUIDProvider(ids: [id]),
            clock: FixedISO8601Clock(instants: [
                "2026-01-01T00:00:00Z",
                "2026-01-03T00:00:00Z"
            ]),
            duplicateRequestIdProvider: FixedUUIDProvider(ids: [UUID(uuidString: "00000000-0000-0000-0000-000000000000")!]))
        let album = Album(mbid: "mbid-blue", discogsReleaseId: nil, title: "Blue", artist: "Joni Mitchell", year: 1971, format: "vinyl")

        _ = try await store.addToCollection(album: album, notes: "first press", addAnyway: false)
        let patched = try await store.patchCollection(id: id, format: nil, notes: "clean copy")

        XCTAssertEqual("vinyl", patched.format)
        XCTAssertEqual("clean copy", patched.notes)
        XCTAssertEqual("2026-01-01T00:00:00Z", patched.createdAt)
        XCTAssertEqual("2026-01-03T00:00:00Z", patched.updatedAt)

        let reloaded = PersistentLocalCollectionStore(
            fileURL: fileURL,
            idProvider: FixedUUIDProvider(ids: []),
            clock: FixedISO8601Clock(instants: []),
            duplicateRequestIdProvider: FixedUUIDProvider(ids: []))
        let records = try await reloaded.fetchCollection(search: nil).items
        XCTAssertEqual(1, records.count)
        XCTAssertEqual("clean copy", records.first?.notes)
        XCTAssertEqual(2, records.first?.version)
    }

    func testPatchUnknownRecordReturnsNotFound() async throws {
        let store = try makeStore(ids: [], instants: [])

        do {
            _ = try await store.patchCollection(id: UUID(), format: "vinyl", notes: nil)
            XCTFail("Expected patching an unknown record to fail")
        } catch let error as ApiClientError {
            if case .httpError(let status, let apiError) = error {
                XCTAssertEqual(404, status)
                XCTAssertEqual("collection_record_not_found", apiError?.code)
            } else {
                XCTFail("Expected ApiClientError.httpError")
            }
        }
    }

    private func makeStore(ids: [UUID], instants: [String]) throws -> PersistentLocalCollectionStore {
        PersistentLocalCollectionStore(
            fileURL: temporaryStoreURL(),
            idProvider: FixedUUIDProvider(ids: ids),
            clock: FixedISO8601Clock(instants: instants),
            duplicateRequestIdProvider: FixedUUIDProvider(ids: [
                UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
            ]))
    }

    private func temporaryStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("dejagroove-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("collection.json")
    }
}

private actor FixedUUIDProvider: UUIDProviding {
    private var ids: [UUID]

    init(ids: [UUID]) {
        self.ids = ids
    }

    func nextUUID() async -> UUID {
        ids.isEmpty ? UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")! : ids.removeFirst()
    }
}

private actor FixedISO8601Clock: ISO8601Clock {
    private var instants: [String]

    init(instants: [String]) {
        self.instants = instants
    }

    func now() async -> String {
        instants.isEmpty ? "2026-01-01T00:00:00Z" : instants.removeFirst()
    }
}
