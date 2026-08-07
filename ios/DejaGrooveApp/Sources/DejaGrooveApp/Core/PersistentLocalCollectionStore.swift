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

    public func addToCollection(album: Album, notes: String?, addAnyway: Bool) async throws -> CollectionItemResponse {
        var records = try loadRecords()
        if !addAnyway, records.contains(where: { Self.isDuplicate($0.album, album) }) {
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
        records.append(record)
        try save(records: records)
        return Self.itemResponse(from: record)
    }

    public func fetchCollection(search: String?) async throws -> CollectionListResponse {
        let records = try loadRecords()
            .filter { Self.matchesSearch($0, search: search) }
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.createdAt > rhs.createdAt
            }
        return CollectionListResponse(items: records, nextCursor: nil)
    }

    public func patchCollection(id: UUID, format: String?, notes: String?) async throws -> CollectionItemResponse {
        var records = try loadRecords()
        guard let index = records.firstIndex(where: { $0.id == id }) else {
            throw ApiClientError.httpError(
                404,
                ApiError(
                    code: "collection_record_not_found",
                    message: "Collection record was not found.",
                    retryable: false,
                    requestId: await duplicateRequestIdProvider.nextUUID()))
        }

        let current = records[index]
        let patchedAlbum = Album(
            mbid: current.album.mbid,
            discogsReleaseId: current.album.discogsReleaseId,
            title: current.album.title,
            artist: current.album.artist,
            year: current.album.year,
            format: format ?? current.album.format)
        let patched = CollectionRecord(
            id: current.id,
            album: patchedAlbum,
            notes: notes ?? current.notes,
            version: current.version + 1,
            createdAt: current.createdAt,
            updatedAt: await clock.now())
        records[index] = patched
        try save(records: records)
        return Self.itemResponse(from: patched)
    }

    public static func defaultStoreURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("DejaGroove", isDirectory: true)
            .appendingPathComponent("collection.json")
    }

    private func loadRecords() throws -> [CollectionRecord] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        if data.isEmpty {
            return []
        }
        return try decoder.decode([CollectionRecord].self, from: data)
    }

    private func save(records: [CollectionRecord]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(records)
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

    private static func matchesSearch(_ record: CollectionRecord, search: String?) -> Bool {
        guard let search, !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return true
        }
        let query = normalized(search)
        return normalized(record.album.title).contains(query)
            || normalized(record.album.artist).contains(query)
            || normalized(record.notes ?? "").contains(query)
    }

    private static func normalized(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
    }
}
