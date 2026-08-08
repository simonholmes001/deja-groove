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
            album: Album(
                mbid: "mbid-blue",
                discogsReleaseId: "249504",
                discogsMasterId: "52245",
                discogsUrl: "https://www.discogs.com/release/249504",
                discogsResourceUrl: "https://api.discogs.com/releases/249504",
                title: "Blue",
                artist: "Joni Mitchell",
                year: 1971,
                format: "vinyl",
                firstReleaseDate: nil,
                releaseDate: "1971-06",
                label: "Reprise",
                catalogNumber: "MS 2038",
                country: "US",
                barcode: "075992718127",
                coverImageUrl: "https://img.discogs.com/front.jpg",
                thumbnailUrl: "https://img.discogs.com/thumb.jpg",
                backCoverImageUrl: "https://img.discogs.com/back.jpg",
                releaseNotes: "Gatefold sleeve.",
                genres: ["Rock"],
                styles: ["Folk Rock"],
                companies: ["Record Company: Reprise Records"],
                tracklist: [AlbumTrack(position: "A1", title: "All I Want", duration: "3:34")],
                identifiers: [AlbumIdentifier(type: "Matrix / Runout", value: "MS2038A", description: "Side A")],
                discogsDataQuality: "Correct"),
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

        let barcodeSearch = try await store.fetchCollection(search: "075992718127")
        XCTAssertEqual(1, barcodeSearch.items.count)
        XCTAssertEqual("https://img.discogs.com/front.jpg", barcodeSearch.items.first?.album.coverImageUrl)

        let trackSearch = try await store.fetchCollection(search: "all i want")
        XCTAssertEqual(1, trackSearch.items.count)

        let companySearch = try await store.fetchCollection(search: "reprise records")
        XCTAssertEqual(1, companySearch.items.count)
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

    func testContainsUsesSameDuplicateRulesAsAdd() async throws {
        let store = try makeStore(
            ids: [UUID(uuidString: "00000000-0000-0000-0000-000000000221")!],
            instants: ["2026-01-01T00:00:00Z"])
        let stored = Album(mbid: nil, discogsReleaseId: nil, title: "Kind   of Blue", artist: "Miles Davis", year: 1959, format: nil)
        let scanned = Album(mbid: nil, discogsReleaseId: nil, title: "kind of blue", artist: "miles davis", year: 1959, format: nil)

        _ = try await store.addToCollection(album: stored, notes: nil, addAnyway: false)
        let containsScannedAlbum = try await store.contains(album: scanned)

        XCTAssertTrue(containsScannedAlbum)
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

    func testUpdateCollectionRecordPersistsEditedAlbumMetadata() async throws {
        let fileURL = temporaryStoreURL()
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000311")!
        let store = PersistentLocalCollectionStore(
            fileURL: fileURL,
            idProvider: FixedUUIDProvider(ids: [id]),
            clock: FixedISO8601Clock(instants: [
                "2026-01-01T00:00:00Z",
                "2026-01-05T00:00:00Z"
            ]),
            duplicateRequestIdProvider: FixedUUIDProvider(ids: []))
        _ = try await store.addToCollection(
            album: Album(mbid: nil, discogsReleaseId: "123", title: "Blu Train", artist: "John Coltrain", year: 1957, format: "LP"),
            notes: "rough",
            addAnyway: false)

        _ = try await store.updateCollectionRecord(
            id: id,
            album: Album(
                mbid: nil,
                discogsReleaseId: "123",
                title: "Blue Train",
                artist: "John Coltrane",
                year: 1957,
                format: "Vinyl LP",
                firstReleaseYear: 1957,
                releaseYear: 1957,
                firstReleaseDate: "1957",
                releaseDate: "1957",
                label: "Blue Note",
                catalogNumber: "BLP 1577",
                country: "US",
                releaseNotes: "Corrected local metadata.",
                genres: ["Jazz"],
                styles: ["Hard Bop"]),
            notes: "clean copy")

        let reloaded = PersistentLocalCollectionStore(
            fileURL: fileURL,
            idProvider: FixedUUIDProvider(ids: []),
            clock: FixedISO8601Clock(instants: []),
            duplicateRequestIdProvider: FixedUUIDProvider(ids: []))
        let records = try await reloaded.fetchCollection(search: "coltrane")
        let record = try XCTUnwrap(records.items.first)
        XCTAssertEqual("John Coltrane", record.album.artist)
        XCTAssertEqual("Blue Train", record.album.title)
        XCTAssertEqual("Blue Note", record.album.label)
        XCTAssertEqual(["Jazz"], record.album.genres)
        XCTAssertEqual("clean copy", record.notes)
        XCTAssertEqual(2, record.version)
        XCTAssertEqual("2026-01-01T00:00:00Z", record.createdAt)
        XCTAssertEqual("2026-01-05T00:00:00Z", record.updatedAt)
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

    func testCreateRenameDeleteCrateCollectionsAndAssignAlbums() async throws {
        let albumId = UUID(uuidString: "00000000-0000-0000-0000-000000000401")!
        let collectionId = UUID(uuidString: "00000000-0000-0000-0000-000000000402")!
        let store = try makeStore(
            ids: [albumId, collectionId],
            instants: [
                "2026-01-01T00:00:00Z",
                "2026-01-02T00:00:00Z",
                "2026-01-03T00:00:00Z",
                "2026-01-04T00:00:00Z"
            ])

        _ = try await store.addToCollection(
            album: Album(mbid: nil, discogsReleaseId: nil, title: "Blue", artist: "Joni Mitchell", year: 1971, format: "LP"),
            notes: nil,
            addAnyway: false)
        let favorites = try await store.createCrateCollection(name: "Favorites")
        XCTAssertEqual(collectionId, favorites.id)

        let assigned = try await store.addRecord(albumId, toCrateCollection: collectionId)
        XCTAssertEqual([albumId], assigned.recordIds)

        let renamed = try await store.renameCrateCollection(id: collectionId, name: "Sunday Records")
        XCTAssertEqual("Sunday Records", renamed.name)
        XCTAssertEqual([albumId], renamed.recordIds)

        let collections = try await store.fetchCrateCollections(search: "sunday")
        XCTAssertEqual(1, collections.count)

        try await store.deleteCrateCollection(id: collectionId)
        let remaining = try await store.fetchCrateCollections(search: nil)
        XCTAssertTrue(remaining.isEmpty)
    }

    func testDeleteCollectionRecordRemovesAlbumAndCollectionMembership() async throws {
        let albumId = UUID(uuidString: "00000000-0000-0000-0000-000000000431")!
        let collectionId = UUID(uuidString: "00000000-0000-0000-0000-000000000432")!
        let store = try makeStore(
            ids: [albumId, collectionId],
            instants: [
                "2026-01-01T00:00:00Z",
                "2026-01-02T00:00:00Z",
                "2026-01-03T00:00:00Z",
                "2026-01-04T00:00:00Z"
            ])

        _ = try await store.addToCollection(
            album: Album(mbid: nil, discogsReleaseId: nil, title: "Blue Train", artist: "John Coltrane", year: 1957, format: "LP"),
            notes: nil,
            addAnyway: false)
        _ = try await store.createCrateCollection(name: "Jazz")
        _ = try await store.addRecord(albumId, toCrateCollection: collectionId)

        try await store.deleteCollectionRecord(id: albumId)

        let records = try await store.fetchCollection(search: nil)
        let collections = try await store.fetchCrateCollections(search: nil)
        XCTAssertTrue(records.items.isEmpty)
        XCTAssertEqual(1, collections.count)
        XCTAssertTrue(collections.first?.recordIds.isEmpty ?? false)
        XCTAssertEqual("2026-01-04T00:00:00Z", collections.first?.updatedAt)
    }

    func testCollectionNameValidationRejectsEmptyAndDuplicateNames() async throws {
        let store = try makeStore(
            ids: [UUID(uuidString: "00000000-0000-0000-0000-000000000411")!],
            instants: ["2026-01-01T00:00:00Z"])

        do {
            _ = try await store.createCrateCollection(name: " ")
            XCTFail("Expected empty collection name to fail")
        } catch let error as ApiClientError {
            if case .httpError(let status, let apiError) = error {
                XCTAssertEqual(400, status)
                XCTAssertEqual("collection_name_required", apiError?.code)
            } else {
                XCTFail("Expected ApiClientError.httpError")
            }
        }

        _ = try await store.createCrateCollection(name: "Favorites")
        do {
            _ = try await store.createCrateCollection(name: " favorites ")
            XCTFail("Expected duplicate collection name to fail")
        } catch let error as ApiClientError {
            if case .httpError(let status, let apiError) = error {
                XCTAssertEqual(409, status)
                XCTAssertEqual("collection_name_duplicate", apiError?.code)
            } else {
                XCTFail("Expected ApiClientError.httpError")
            }
        }
    }

    func testMigratesLegacyFlatCollectionFile() async throws {
        let fileURL = temporaryStoreURL()
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let legacyJSON = """
        [
          {
            "id": "00000000-0000-0000-0000-000000000421",
            "album": {
              "mbid": null,
              "discogs_release_id": null,
              "title": "Hejira",
              "artist": "Joni Mitchell",
              "year": 1976,
              "format": "LP"
            },
            "notes": "legacy"
          }
        ]
        """
        try Data(legacyJSON.utf8).write(to: fileURL)

        let store = PersistentLocalCollectionStore(fileURL: fileURL)
        let records = try await store.fetchCollection(search: "hejira")
        let collections = try await store.fetchCrateCollections(search: nil)

        XCTAssertEqual(1, records.items.count)
        XCTAssertEqual("Hejira", records.items.first?.album.title)
        XCTAssertEqual("Joni Mitchell", records.items.first?.album.artist)
        XCTAssertEqual("legacy", records.items.first?.notes)
        XCTAssertEqual(1, records.items.first?.version)
        XCTAssertEqual("1970-01-01T00:00:00Z", records.items.first?.createdAt)
        XCTAssertEqual("1970-01-01T00:00:00Z", records.items.first?.updatedAt)
        XCTAssertTrue(collections.isEmpty)
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
