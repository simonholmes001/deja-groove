import Foundation

public protocol UUIDProviding: Sendable {
    func nextUUID() async -> UUID
}

public protocol ISO8601Clock: Sendable {
    func now() async -> String
}

public struct SystemUUIDProvider: UUIDProviding {
    public init() {}

    public func nextUUID() async -> UUID {
        UUID()
    }
}

public struct SystemISO8601Clock: ISO8601Clock {
    public init() {
    }

    public func now() async -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}

public actor PersistentLocalCollectionStore: LocalCollectionStore {
    private let documentStore: LocalCollectionDocumentStore
    private let idProvider: UUIDProviding
    private let clock: ISO8601Clock
    private let duplicateRequestIdProvider: UUIDProviding

    public init(
        fileURL: URL = PersistentLocalCollectionStore.defaultStoreURL(),
        idProvider: UUIDProviding = SystemUUIDProvider(),
        clock: ISO8601Clock = SystemISO8601Clock(),
        duplicateRequestIdProvider: UUIDProviding = SystemUUIDProvider()
    ) {
        self.documentStore = LocalCollectionDocumentStore(fileURL: fileURL)
        self.idProvider = idProvider
        self.clock = clock
        self.duplicateRequestIdProvider = duplicateRequestIdProvider
    }

    public func contains(album: Album) async throws -> Bool {
        let records = try documentStore.load().records
        return records.contains(where: { LocalCollectionRules.isDuplicate($0.album, album) })
    }

    public func addToCollection(album: Album, notes: String?, addAnyway: Bool) async throws -> CollectionItemResponse {
        var document = try documentStore.load()
        if !addAnyway, document.records.contains(where: { LocalCollectionRules.isDuplicate($0.album, album) }) {
            throw ApiClientError.httpError(
                409,
                ApiError(
                    code: "collection_duplicate",
                    message: "Album is already in the local collection.",
                    retryable: false,
                    requestId: await duplicateRequestIdProvider.nextUUID()))
        }

        let now = await clock.now()
        let record = CollectionRecord(
            id: await idProvider.nextUUID(),
            album: album,
            notes: notes,
            version: 1,
            createdAt: now,
            updatedAt: now)
        document.records.append(record)
        try documentStore.save(document)
        return Self.itemResponse(from: record)
    }

    public func fetchCollection(search: String?) async throws -> CollectionListResponse {
        let records = try documentStore.load().records
            .filter { LocalCollectionRules.matchesSearch($0, search: search) }
            .sorted { LocalCollectionRules.compareByArtistFamilyName($0, $1) }
        return CollectionListResponse(items: records, nextCursor: nil)
    }

    public func patchCollection(id: UUID, format: String?, notes: String?) async throws -> CollectionItemResponse {
        var document = try documentStore.load()
        guard let index = document.records.firstIndex(where: { $0.id == id }) else {
            throw ApiClientError.httpError(
                404,
                ApiError(
                    code: "collection_record_not_found",
                    message: "Collection record was not found.",
                    retryable: false,
                    requestId: await duplicateRequestIdProvider.nextUUID()))
        }

        let current = document.records[index]
        let patchedAlbum = Album(
            mbid: current.album.mbid,
            discogsReleaseId: current.album.discogsReleaseId,
            discogsMasterId: current.album.discogsMasterId,
            discogsUrl: current.album.discogsUrl,
            discogsResourceUrl: current.album.discogsResourceUrl,
            title: current.album.title,
            artist: current.album.artist,
            year: current.album.year,
            format: format ?? current.album.format,
            firstReleaseYear: current.album.firstReleaseYear,
            releaseYear: current.album.releaseYear,
            firstReleaseDate: current.album.firstReleaseDate,
            releaseDate: current.album.releaseDate,
            label: current.album.label,
            catalogNumber: current.album.catalogNumber,
            country: current.album.country,
            barcode: current.album.barcode,
            coverImageUrl: current.album.coverImageUrl,
            thumbnailUrl: current.album.thumbnailUrl,
            backCoverImageUrl: current.album.backCoverImageUrl,
            backCoverText: current.album.backCoverText,
            releaseNotes: current.album.releaseNotes,
            genres: current.album.genres,
            styles: current.album.styles,
            companies: current.album.companies,
            tracklist: current.album.tracklist,
            identifiers: current.album.identifiers,
            discogsDataQuality: current.album.discogsDataQuality)
        let patched = CollectionRecord(
            id: current.id,
            album: patchedAlbum,
            notes: notes ?? current.notes,
            version: current.version + 1,
            createdAt: current.createdAt,
            updatedAt: await clock.now())
        document.records[index] = patched
        try documentStore.save(document)
        return Self.itemResponse(from: patched)
    }

    public func updateCollectionRecord(id: UUID, album: Album, notes: String?) async throws -> CollectionItemResponse {
        var document = try documentStore.load()
        guard let index = document.records.firstIndex(where: { $0.id == id }) else {
            throw await recordNotFoundError()
        }

        let current = document.records[index]
        let updated = CollectionRecord(
            id: current.id,
            album: album,
            notes: notes,
            version: current.version + 1,
            createdAt: current.createdAt,
            updatedAt: await clock.now())
        document.records[index] = updated
        try documentStore.save(document)
        return Self.itemResponse(from: updated)
    }

    public func deleteCollectionRecord(id: UUID) async throws {
        var document = try documentStore.load()
        guard document.records.contains(where: { $0.id == id }) else {
            throw await recordNotFoundError()
        }
        document.records.removeAll { $0.id == id }
        let now = await clock.now()
        document.collections = document.collections.map { collection in
            let updatedIds = collection.recordIds.filter { $0 != id }
            return CrateCollection(
                id: collection.id,
                name: collection.name,
                recordIds: updatedIds,
                createdAt: collection.createdAt,
                updatedAt: updatedIds == collection.recordIds ? collection.updatedAt : now)
        }
        try documentStore.save(document)
    }

    public func fetchCrateCollections(search: String?) async throws -> [CrateCollection] {
        try documentStore.load().collections
            .filter { LocalCollectionRules.matchesCollectionSearch($0, search: search) }
            .sorted { lhs, rhs in
                LocalCollectionRules.normalized(lhs.name) < LocalCollectionRules.normalized(rhs.name)
            }
    }

    public func createCrateCollection(name: String) async throws -> CrateCollection {
        var document = try documentStore.load()
        let cleanName = LocalCollectionRules.cleanCollectionName(name)
        try await validateCollectionName(cleanName, in: document.collections)

        let now = await clock.now()
        let collection = CrateCollection(
            id: await idProvider.nextUUID(),
            name: cleanName,
            recordIds: [],
            createdAt: now,
            updatedAt: now)
        document.collections.append(collection)
        try documentStore.save(document)
        return collection
    }

    public func renameCrateCollection(id: UUID, name: String) async throws -> CrateCollection {
        var document = try documentStore.load()
        guard let index = document.collections.firstIndex(where: { $0.id == id }) else {
            throw await collectionNotFoundError()
        }

        let cleanName = LocalCollectionRules.cleanCollectionName(name)
        try await validateCollectionName(cleanName, in: document.collections, excluding: id)
        let current = document.collections[index]
        let renamed = CrateCollection(
            id: current.id,
            name: cleanName,
            recordIds: current.recordIds,
            createdAt: current.createdAt,
            updatedAt: await clock.now())
        document.collections[index] = renamed
        try documentStore.save(document)
        return renamed
    }

    public func deleteCrateCollection(id: UUID) async throws {
        var document = try documentStore.load()
        guard let index = document.collections.firstIndex(where: { $0.id == id }) else {
            throw await collectionNotFoundError()
        }
        document.collections.remove(at: index)
        try documentStore.save(document)
    }

    public func addRecord(_ recordId: UUID, toCrateCollection collectionId: UUID) async throws -> CrateCollection {
        var document = try documentStore.load()
        guard document.records.contains(where: { $0.id == recordId }) else {
            throw await recordNotFoundError()
        }
        guard let index = document.collections.firstIndex(where: { $0.id == collectionId }) else {
            throw await collectionNotFoundError()
        }
        let current = document.collections[index]
        let updatedIds = current.recordIds.contains(recordId) ? current.recordIds : current.recordIds + [recordId]
        let updated = CrateCollection(
            id: current.id,
            name: current.name,
            recordIds: updatedIds,
            createdAt: current.createdAt,
            updatedAt: await clock.now())
        document.collections[index] = updated
        try documentStore.save(document)
        return updated
    }

    public func removeRecord(_ recordId: UUID, fromCrateCollection collectionId: UUID) async throws -> CrateCollection {
        var document = try documentStore.load()
        guard let index = document.collections.firstIndex(where: { $0.id == collectionId }) else {
            throw await collectionNotFoundError()
        }
        let current = document.collections[index]
        let updated = CrateCollection(
            id: current.id,
            name: current.name,
            recordIds: current.recordIds.filter { $0 != recordId },
            createdAt: current.createdAt,
            updatedAt: await clock.now())
        document.collections[index] = updated
        try documentStore.save(document)
        return updated
    }

    public static func defaultStoreURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("DejaGroove", isDirectory: true)
            .appendingPathComponent("collection.json")
    }

    private static func itemResponse(from record: CollectionRecord) -> CollectionItemResponse {
        CollectionItemResponse(
            id: record.id,
            mbid: record.album.mbid,
            discogsReleaseId: record.album.discogsReleaseId,
            title: record.album.title,
            artist: record.album.artist,
            year: record.album.year,
            format: record.album.format,
            notes: record.notes,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt)
    }

    private func validateCollectionName(
        _ name: String,
        in collections: [CrateCollection],
        excluding excludedId: UUID? = nil
    ) async throws {
        guard !name.isEmpty else {
            throw ApiClientError.httpError(
                400,
                ApiError(
                    code: "collection_name_required",
                    message: "Collection name is required.",
                    retryable: false,
                    requestId: await duplicateRequestIdProvider.nextUUID()))
        }
        if collections.contains(where: { $0.id != excludedId && LocalCollectionRules.normalized($0.name) == LocalCollectionRules.normalized(name) }) {
            throw ApiClientError.httpError(
                409,
                ApiError(
                    code: "collection_name_duplicate",
                    message: "A collection with this name already exists.",
                    retryable: false,
                    requestId: await duplicateRequestIdProvider.nextUUID()))
        }
    }

    private func recordNotFoundError() async -> ApiClientError {
        ApiClientError.httpError(
            404,
            ApiError(
                code: "collection_record_not_found",
                message: "Collection record was not found.",
                retryable: false,
                requestId: await duplicateRequestIdProvider.nextUUID()))
    }

    private func collectionNotFoundError() async -> ApiClientError {
        ApiClientError.httpError(
            404,
            ApiError(
                code: "crate_collection_not_found",
                message: "Crate collection was not found.",
                retryable: false,
                requestId: await duplicateRequestIdProvider.nextUUID()))
    }
}
