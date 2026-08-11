import Foundation

struct LocalCollectionDocument: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var records: [CollectionRecord]
    var collections: [CrateCollection]

    init(schemaVersion: Int = Self.currentSchemaVersion, records: [CollectionRecord], collections: [CrateCollection]) {
        self.schemaVersion = schemaVersion
        self.records = records
        self.collections = collections
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case records
        case collections
    }
}

struct LocalCollectionDocumentStore {
    private struct LegacyDocument: Decodable {
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

    let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileURL: URL) {
        self.fileURL = fileURL
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
        self.decoder = JSONDecoder()
    }

    func load() throws -> LocalCollectionDocument {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return LocalCollectionDocument(records: [], collections: [])
        }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else {
            return LocalCollectionDocument(records: [], collections: [])
        }

        do {
            return try decode(data)
        } catch {
            try quarantineCorruptFile()
            return LocalCollectionDocument(records: [], collections: [])
        }
    }

    func save(_ document: LocalCollectionDocument) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(document)
        try data.write(to: fileURL, options: [.atomic])
    }

    private func decode(_ data: Data) throws -> LocalCollectionDocument {
        if let document = try? decoder.decode(LocalCollectionDocument.self, from: data) {
            guard document.schemaVersion == LocalCollectionDocument.currentSchemaVersion else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: [],
                    debugDescription: "Unsupported collection schema version \(document.schemaVersion)."))
            }
            return document
        }
        if let legacyDocument = try? decoder.decode(LegacyDocument.self, from: data) {
            return LocalCollectionDocument(records: legacyDocument.records, collections: legacyDocument.collections)
        }
        if let records = try? decoder.decode([CollectionRecord].self, from: data) {
            return LocalCollectionDocument(records: records, collections: [])
        }
        let legacyRecords = try decoder.decode([LegacyCollectionRecord].self, from: data)
        return LocalCollectionDocument(
            records: legacyRecords.map { $0.migratedRecord(defaultTimestamp: "1970-01-01T00:00:00Z") },
            collections: [])
    }

    private func quarantineCorruptFile() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        let quarantineURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent("\(fileURL.lastPathComponent).corrupt-\(UUID().uuidString)")
        try FileManager.default.moveItem(at: fileURL, to: quarantineURL)
    }
}
