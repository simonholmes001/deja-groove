import Foundation

public protocol LocalDiscoveryStore: Sendable {
    func addDiscovery(source: String, album: Album?, track: AudioDiscoveryTrack?) async throws -> DiscoveryEntry
    func fetchDiscoveries(search: String?) async throws -> [DiscoveryEntry]
    func promoteDiscoveryToWishlist(id: UUID, wishlistStore: LocalWishlistStore) async throws -> WishlistEntry
    func deleteDiscovery(id: UUID) async throws
    func deleteAllDiscoveries() async throws
}

struct LocalDiscoveryDocument: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var entries: [DiscoveryEntry]

    init(schemaVersion: Int = Self.currentSchemaVersion, entries: [DiscoveryEntry]) {
        self.schemaVersion = schemaVersion
        self.entries = entries
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case entries
    }
}

struct LocalDiscoveryDocumentStore {
    private let fileURL: URL
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(fileURL: URL) {
        self.fileURL = fileURL
        decoder = JSONDecoder()
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func load() throws -> LocalDiscoveryDocument {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return LocalDiscoveryDocument(entries: [])
        }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else {
            return LocalDiscoveryDocument(entries: [])
        }
        return try decoder.decode(LocalDiscoveryDocument.self, from: data)
    }

    func save(_ document: LocalDiscoveryDocument) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(document)
        try data.write(to: fileURL, options: [.atomic])
    }
}

public actor PersistentLocalDiscoveryStore: LocalDiscoveryStore {
    private let documentStore: LocalDiscoveryDocumentStore
    private let idProvider: UUIDProviding
    private let clock: ISO8601Clock

    public init(
        fileURL: URL = PersistentLocalDiscoveryStore.defaultStoreURL(),
        idProvider: UUIDProviding = SystemUUIDProvider(),
        clock: ISO8601Clock = SystemISO8601Clock()
    ) {
        self.documentStore = LocalDiscoveryDocumentStore(fileURL: fileURL)
        self.idProvider = idProvider
        self.clock = clock
    }

    public func addDiscovery(source: String, album: Album?, track: AudioDiscoveryTrack?) async throws -> DiscoveryEntry {
        var document = try documentStore.load()
        let entry = DiscoveryEntry(
            id: await idProvider.nextUUID(),
            source: source,
            album: album,
            track: track,
            createdAt: await clock.now())
        document.entries.append(entry)
        try documentStore.save(document)
        return entry
    }

    public func fetchDiscoveries(search: String?) async throws -> [DiscoveryEntry] {
        try documentStore.load().entries
            .filter { LocalDiscoveryRules.matchesSearch($0, search: search) }
            .sorted { LocalDiscoveryRules.compareEntries($0, $1) }
    }

    public func promoteDiscoveryToWishlist(id: UUID, wishlistStore: LocalWishlistStore) async throws -> WishlistEntry {
        let document = try documentStore.load()
        guard let entry = document.entries.first(where: { $0.id == id }), let album = entry.album else {
            throw discoveryEntryNotFoundError()
        }
        return try await wishlistStore.addToWishlist(
            album: album,
            preferences: WishlistPreferences(),
            sourceTrack: entry.track)
    }

    public func deleteDiscovery(id: UUID) async throws {
        var document = try documentStore.load()
        guard document.entries.contains(where: { $0.id == id }) else {
            throw discoveryEntryNotFoundError()
        }
        document.entries.removeAll { $0.id == id }
        try documentStore.save(document)
    }

    public func deleteAllDiscoveries() async throws {
        var document = try documentStore.load()
        document.entries.removeAll()
        try documentStore.save(document)
    }

    public static func defaultStoreURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("DejaGroove", isDirectory: true)
            .appendingPathComponent("discovery.json")
    }

    private func discoveryEntryNotFoundError() -> ApiClientError {
        ApiClientError.httpError(
            404,
            ApiError(
                code: "discovery_entry_not_found",
                message: "Discovery entry was not found.",
                retryable: false,
                requestId: UUID()))
    }
}

public enum LocalDiscoveryRules {
    public static func compareEntries(_ lhs: DiscoveryEntry, _ rhs: DiscoveryEntry) -> Bool {
        let lhsAlbum = sortableAlbum(for: lhs)
        let rhsAlbum = sortableAlbum(for: rhs)
        return LocalCollectionRules.compareAlbumsByArtistFamilyName(
            lhsAlbum,
            rhsAlbum,
            lhsTieBreaker: lhs.id.uuidString,
            rhsTieBreaker: rhs.id.uuidString)
    }

    public static func matchesSearch(_ entry: DiscoveryEntry, search: String?) -> Bool {
        guard let search, !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return true
        }
        let query = LocalCollectionRules.normalized(search)
        let fields: [String?] = [
            entry.source,
            entry.album?.artist,
            entry.album?.title,
            entry.album?.format,
            entry.album?.label,
            entry.track?.artist,
            entry.track?.title
        ]
        return fields.compactMap { $0 }.contains {
            LocalCollectionRules.normalized($0).contains(query)
        }
    }

    private static func sortableAlbum(for entry: DiscoveryEntry) -> Album {
        if let album = entry.album {
            return album
        }
        if let track = entry.track {
            return Album(
                mbid: nil,
                discogsReleaseId: nil,
                title: track.title,
                artist: track.artist,
                year: nil,
                format: nil,
                coverImageUrl: track.artworkUrl,
                thumbnailUrl: track.artworkUrl)
        }
        return Album(
            mbid: nil,
            discogsReleaseId: nil,
            title: entry.createdAt,
            artist: entry.source,
            year: nil,
            format: nil)
    }
}
