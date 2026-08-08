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
    private struct StoreDocument: Codable {
        var records: [CollectionRecord]
        var collections: [CrateCollection]
    }

    private struct LegacyCollectionRecord: Decodable {
        let id: UUID
        let album: Album
        let notes: String?
        let version: Int?
        let createdAt: String?
        let updatedAt: String?

        enum CodingKeys: String, CodingKey {
            case id
            case album
            case notes
            case version
            case createdAt
            case updatedAt
        }

        func migratedRecord(defaultTimestamp: String) -> CollectionRecord {
            CollectionRecord(
                id: id,
                album: album,
                notes: notes,
                version: version ?? 1,
                createdAt: createdAt ?? defaultTimestamp,
                updatedAt: updatedAt ?? createdAt ?? defaultTimestamp)
        }
    }

    private let fileURL: URL
    private let idProvider: UUIDProviding
    private let clock: ISO8601Clock
    private let duplicateRequestIdProvider: UUIDProviding
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        fileURL: URL = PersistentLocalCollectionStore.defaultStoreURL(),
        idProvider: UUIDProviding = SystemUUIDProvider(),
        clock: ISO8601Clock = SystemISO8601Clock(),
        duplicateRequestIdProvider: UUIDProviding = SystemUUIDProvider()
    ) {
        self.fileURL = fileURL
        self.idProvider = idProvider
        self.clock = clock
        self.duplicateRequestIdProvider = duplicateRequestIdProvider
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
        self.decoder = JSONDecoder()
    }

    public func contains(album: Album) async throws -> Bool {
        let records = try loadDocument().records
        return records.contains(where: { Self.isDuplicate($0.album, album) })
    }

    public func addToCollection(album: Album, notes: String?, addAnyway: Bool) async throws -> CollectionItemResponse {
        var document = try loadDocument()
        if !addAnyway, document.records.contains(where: { Self.isDuplicate($0.album, album) }) {
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
        try save(document: document)
        return Self.itemResponse(from: record)
    }

    public func fetchCollection(search: String?) async throws -> CollectionListResponse {
        let records = try loadDocument().records
            .filter { Self.matchesSearch($0, search: search) }
            .sorted { lhs, rhs in
                Self.compareByArtistFamilyName(lhs, rhs)
            }
        return CollectionListResponse(items: records, nextCursor: nil)
    }

    public func patchCollection(id: UUID, format: String?, notes: String?) async throws -> CollectionItemResponse {
        var document = try loadDocument()
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
        try save(document: document)
        return Self.itemResponse(from: patched)
    }

    public func updateCollectionRecord(id: UUID, album: Album, notes: String?) async throws -> CollectionItemResponse {
        var document = try loadDocument()
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
        try save(document: document)
        return Self.itemResponse(from: updated)
    }

    public func deleteCollectionRecord(id: UUID) async throws {
        var document = try loadDocument()
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
        try save(document: document)
    }

    public func fetchCrateCollections(search: String?) async throws -> [CrateCollection] {
        try loadDocument().collections
            .filter { Self.matchesCollectionSearch($0, search: search) }
            .sorted { lhs, rhs in
                Self.normalized(lhs.name) < Self.normalized(rhs.name)
            }
    }

    public func createCrateCollection(name: String) async throws -> CrateCollection {
        var document = try loadDocument()
        let cleanName = Self.cleanCollectionName(name)
        try await validateCollectionName(cleanName, in: document.collections)

        let now = await clock.now()
        let collection = CrateCollection(
            id: await idProvider.nextUUID(),
            name: cleanName,
            recordIds: [],
            createdAt: now,
            updatedAt: now)
        document.collections.append(collection)
        try save(document: document)
        return collection
    }

    public func renameCrateCollection(id: UUID, name: String) async throws -> CrateCollection {
        var document = try loadDocument()
        guard let index = document.collections.firstIndex(where: { $0.id == id }) else {
            throw await collectionNotFoundError()
        }

        let cleanName = Self.cleanCollectionName(name)
        try await validateCollectionName(cleanName, in: document.collections, excluding: id)
        let current = document.collections[index]
        let renamed = CrateCollection(
            id: current.id,
            name: cleanName,
            recordIds: current.recordIds,
            createdAt: current.createdAt,
            updatedAt: await clock.now())
        document.collections[index] = renamed
        try save(document: document)
        return renamed
    }

    public func deleteCrateCollection(id: UUID) async throws {
        var document = try loadDocument()
        guard let index = document.collections.firstIndex(where: { $0.id == id }) else {
            throw await collectionNotFoundError()
        }
        document.collections.remove(at: index)
        try save(document: document)
    }

    public func addRecord(_ recordId: UUID, toCrateCollection collectionId: UUID) async throws -> CrateCollection {
        var document = try loadDocument()
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
        try save(document: document)
        return updated
    }

    public func removeRecord(_ recordId: UUID, fromCrateCollection collectionId: UUID) async throws -> CrateCollection {
        var document = try loadDocument()
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
        try save(document: document)
        return updated
    }

    public static func defaultStoreURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("DejaGroove", isDirectory: true)
            .appendingPathComponent("collection.json")
    }

    private func loadDocument() throws -> StoreDocument {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return StoreDocument(records: [], collections: [])
        }
        let data = try Data(contentsOf: fileURL)
        if data.isEmpty {
            return StoreDocument(records: [], collections: [])
        }
        if let document = try? decoder.decode(StoreDocument.self, from: data) {
            return document
        }
        if let records = try? decoder.decode([CollectionRecord].self, from: data) {
            return StoreDocument(records: records, collections: [])
        }
        let legacyRecords = try decoder.decode([LegacyCollectionRecord].self, from: data)
        return StoreDocument(
            records: legacyRecords.map { $0.migratedRecord(defaultTimestamp: "1970-01-01T00:00:00Z") },
            collections: [])
    }

    private func save(document: StoreDocument) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(document)
        try data.write(to: fileURL, options: [.atomic])
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

    private static func isDuplicate(_ lhs: Album, _ rhs: Album) -> Bool {
        if let lhsMbid = lhs.mbid, let rhsMbid = rhs.mbid, !lhsMbid.isEmpty, !rhsMbid.isEmpty {
            if lhsMbid == rhsMbid {
                return true
            }
        }
        if let lhsDiscogs = lhs.discogsReleaseId,
           let rhsDiscogs = rhs.discogsReleaseId,
           !lhsDiscogs.isEmpty,
           !rhsDiscogs.isEmpty {
            if lhsDiscogs == rhsDiscogs {
                return true
            }
        }
        return normalized(lhs.title) == normalized(rhs.title)
            && normalized(lhs.artist) == normalized(rhs.artist)
    }

    private static func compareByArtistFamilyName(_ lhs: CollectionRecord, _ rhs: CollectionRecord) -> Bool {
        let lhsKey = artistSortKey(lhs.album.artist)
        let rhsKey = artistSortKey(rhs.album.artist)
        if lhsKey != rhsKey {
            return lhsKey < rhsKey
        }
        let lhsTitle = titleSortKey(lhs.album.title)
        let rhsTitle = titleSortKey(rhs.album.title)
        if lhsTitle != rhsTitle {
            return lhsTitle < rhsTitle
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func artistSortKey(_ artist: String) -> String {
        let cleanArtist = normalized(artist)
        if cleanArtist.contains(",")
            || cleanArtist.contains("&")
            || cleanArtist.hasPrefix("the ")
            || cleanArtist.hasSuffix(" band")
            || cleanArtist.hasSuffix(" quartet")
            || cleanArtist.hasSuffix(" quintet")
            || cleanArtist.hasSuffix(" trio") {
            return cleanArtist
        }
        let parts = cleanArtist.split(separator: " ").map(String.init)
        guard parts.count >= 2 else { return cleanArtist }
        return "\(parts.last!) \(parts.dropLast().joined(separator: " "))"
    }

    private static func titleSortKey(_ title: String) -> String {
        let cleanTitle = normalized(title)
        for article in ["the ", "a ", "an "] where cleanTitle.hasPrefix(article) {
            return String(cleanTitle.dropFirst(article.count))
        }
        return cleanTitle
    }

    private static func matchesSearch(_ record: CollectionRecord, search: String?) -> Bool {
        guard let search, !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return true
        }
        let query = normalized(search)
        return normalized(record.album.title).contains(query)
            || normalized(record.album.artist).contains(query)
            || normalized(record.notes ?? "").contains(query)
            || normalized(record.album.format ?? "").contains(query)
            || normalized(record.album.label ?? "").contains(query)
            || normalized(record.album.catalogNumber ?? "").contains(query)
            || normalized(record.album.country ?? "").contains(query)
            || normalized(record.album.barcode ?? "").contains(query)
            || normalized(record.album.discogsReleaseId ?? "").contains(query)
            || normalized(record.album.discogsMasterId ?? "").contains(query)
            || normalized(record.album.discogsUrl ?? "").contains(query)
            || normalized(record.album.discogsResourceUrl ?? "").contains(query)
            || normalized(record.album.firstReleaseDate ?? "").contains(query)
            || normalized(record.album.releaseDate ?? "").contains(query)
            || normalized(record.album.genres.joined(separator: " ")).contains(query)
            || normalized(record.album.styles.joined(separator: " ")).contains(query)
            || normalized(record.album.companies.joined(separator: " ")).contains(query)
            || normalized(record.album.tracklist.map(\.title).joined(separator: " ")).contains(query)
            || normalized(record.album.identifiers.compactMap(\.value).joined(separator: " ")).contains(query)
            || normalized(record.album.backCoverText ?? "").contains(query)
            || normalized(record.album.releaseNotes ?? "").contains(query)
            || Self.year(record.album.year, matches: query)
            || Self.year(record.album.firstReleaseYear, matches: query)
            || Self.year(record.album.releaseYear, matches: query)
    }

    private static func matchesCollectionSearch(_ collection: CrateCollection, search: String?) -> Bool {
        guard let search, !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return true
        }
        return normalized(collection.name).contains(normalized(search))
    }

    private static func cleanCollectionName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func year(_ year: Int?, matches query: String) -> Bool {
        guard let year else { return false }
        return String(year).contains(query)
    }

    private static func normalized(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
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
        if collections.contains(where: { $0.id != excludedId && Self.normalized($0.name) == Self.normalized(name) }) {
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
