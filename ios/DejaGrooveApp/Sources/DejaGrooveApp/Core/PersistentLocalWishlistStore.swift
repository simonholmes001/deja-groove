import Foundation

public protocol LocalWishlistStore: Sendable {
    func contains(album: Album) async throws -> Bool
    func addToWishlist(album: Album, preferences: WishlistPreferences, sourceTrack: AudioDiscoveryTrack?) async throws -> WishlistEntry
    func fetchWishlist(search: String?) async throws -> [WishlistEntry]
    func updateWishlistPreferences(id: UUID, preferences: WishlistPreferences) async throws -> WishlistEntry
    func deleteWishlistEntry(id: UUID) async throws
}

struct LocalWishlistDocument: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var entries: [WishlistEntry]

    init(schemaVersion: Int = Self.currentSchemaVersion, entries: [WishlistEntry]) {
        self.schemaVersion = schemaVersion
        self.entries = entries
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case entries
    }
}

struct LocalWishlistDocumentStore {
    private let fileURL: URL
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(fileURL: URL) {
        self.fileURL = fileURL
        decoder = JSONDecoder()
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func load() throws -> LocalWishlistDocument {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return LocalWishlistDocument(entries: [])
        }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else {
            return LocalWishlistDocument(entries: [])
        }
        return try decoder.decode(LocalWishlistDocument.self, from: data)
    }

    func save(_ document: LocalWishlistDocument) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(document)
        try data.write(to: fileURL, options: [.atomic])
    }
}

public actor PersistentLocalWishlistStore: LocalWishlistStore {
    private let documentStore: LocalWishlistDocumentStore
    private let idProvider: UUIDProviding
    private let clock: ISO8601Clock

    public init(
        fileURL: URL = PersistentLocalWishlistStore.defaultStoreURL(),
        idProvider: UUIDProviding = SystemUUIDProvider(),
        clock: ISO8601Clock = SystemISO8601Clock()
    ) {
        self.documentStore = LocalWishlistDocumentStore(fileURL: fileURL)
        self.idProvider = idProvider
        self.clock = clock
    }

    public func contains(album: Album) async throws -> Bool {
        try documentStore.load().entries.contains { LocalCollectionRules.isDuplicate($0.album, album) }
    }

    public func addToWishlist(
        album: Album,
        preferences: WishlistPreferences = WishlistPreferences(),
        sourceTrack: AudioDiscoveryTrack? = nil
    ) async throws -> WishlistEntry {
        var document = try documentStore.load()
        if let existing = document.entries.first(where: { LocalCollectionRules.isDuplicate($0.album, album) }) {
            return existing
        }

        let now = await clock.now()
        let entry = WishlistEntry(
            id: await idProvider.nextUUID(),
            album: album,
            preferences: preferences,
            sourceTrack: sourceTrack,
            createdAt: now,
            updatedAt: now)
        document.entries.append(entry)
        try documentStore.save(document)
        return entry
    }

    public func fetchWishlist(search: String?) async throws -> [WishlistEntry] {
        try documentStore.load().entries
            .filter { LocalWishlistRules.matchesSearch($0, search: search) }
            .sorted { LocalWishlistRules.compareEntries($0, $1) }
    }

    public func updateWishlistPreferences(id: UUID, preferences: WishlistPreferences) async throws -> WishlistEntry {
        var document = try documentStore.load()
        guard let index = document.entries.firstIndex(where: { $0.id == id }) else {
            throw wishlistEntryNotFoundError()
        }

        let current = document.entries[index]
        let updated = WishlistEntry(
            id: current.id,
            album: current.album,
            preferences: preferences,
            sourceTrack: current.sourceTrack,
            createdAt: current.createdAt,
            updatedAt: await clock.now())
        document.entries[index] = updated
        try documentStore.save(document)
        return updated
    }

    public func deleteWishlistEntry(id: UUID) async throws {
        var document = try documentStore.load()
        guard document.entries.contains(where: { $0.id == id }) else {
            throw wishlistEntryNotFoundError()
        }
        document.entries.removeAll { $0.id == id }
        try documentStore.save(document)
    }

    public static func defaultStoreURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("DejaGroove", isDirectory: true)
            .appendingPathComponent("wishlist.json")
    }

    private func wishlistEntryNotFoundError() -> ApiClientError {
        ApiClientError.httpError(
            404,
            ApiError(
                code: "wishlist_entry_not_found",
                message: "Wishlist entry was not found.",
                retryable: false,
                requestId: UUID()))
    }
}

public enum LocalWishlistRules {
    public static func matchesSearch(_ entry: WishlistEntry, search: String?) -> Bool {
        guard let search, !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return true
        }
        let query = LocalCollectionRules.normalized(search)
        let fields: [String?] = [
            entry.album.title,
            entry.album.artist,
            entry.album.format,
            entry.album.label,
            entry.album.catalogNumber,
            entry.album.country,
            entry.preferences.targetFormat,
            entry.preferences.country,
            entry.preferences.label,
            entry.preferences.catalogNumber,
            entry.preferences.notes,
            entry.sourceTrack?.title,
            entry.sourceTrack?.artist
        ]
        return fields.compactMap { $0 }.contains {
            LocalCollectionRules.normalized($0).contains(query)
        }
    }

    public static func compareEntries(_ lhs: WishlistEntry, _ rhs: WishlistEntry) -> Bool {
        LocalCollectionRules.compareAlbumsByArtistFamilyName(
            lhs.album,
            rhs.album,
            lhsTieBreaker: lhs.id.uuidString,
            rhsTieBreaker: rhs.id.uuidString)
    }
}
