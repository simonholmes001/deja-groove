import Foundation

public struct Album: Codable, Equatable, Sendable {
    public let mbid: String?
    public let discogsReleaseId: String?
    public let title: String
    public let artist: String
    public let year: Int?
    public let format: String?

    enum CodingKeys: String, CodingKey {
        case mbid
        case discogsReleaseId = "discogs_release_id"
        case title
        case artist
        case year
        case format
    }
}

public struct ScanResponse: Codable, Equatable, Sendable {
    public let status: String
    public let confidence: Float
    public let album: Album?
    public let candidates: [Album]
    public let requestId: UUID

    public init(status: String, confidence: Float, album: Album?, candidates: [Album], requestId: UUID) {
        self.status = Self.normalizeStatus(status)
        self.confidence = confidence
        self.album = album
        self.candidates = candidates
        self.requestId = requestId
    }

    public var canAddToCollection: Bool {
        album != nil && status == "safe_to_buy"
    }

    enum CodingKeys: String, CodingKey {
        case status
        case confidence
        case album
        case candidates
        case requestId = "request_id"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            status: try container.decode(String.self, forKey: .status),
            confidence: try container.decode(Float.self, forKey: .confidence),
            album: try container.decodeIfPresent(Album.self, forKey: .album),
            candidates: try container.decode([Album].self, forKey: .candidates),
            requestId: try container.decode(UUID.self, forKey: .requestId)
        )
    }

    private static func normalizeStatus(_ status: String) -> String {
        let collapsed = status
            .unicodeScalars
            .filter(CharacterSet.alphanumerics.contains)
            .map(String.init)
            .joined()
            .lowercased()

        switch collapsed {
        case "owned":
            return "owned"
        case "safetobuy":
            return "safe_to_buy"
        case "ambiguous":
            return "ambiguous"
        case "nomatch":
            return "no_match"
        default:
            return status.lowercased()
        }
    }
}

public struct CollectionRecord: Codable, Equatable, Sendable {
    public let id: UUID
    public let album: Album
    public let notes: String?
    public let version: Int
    public let createdAt: DateTime
    public let updatedAt: DateTime

    public typealias DateTime = String
}

public struct CollectionListResponse: Codable, Equatable, Sendable {
    public let items: [CollectionRecord]
    public let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case items
        case nextCursor = "next_cursor"
    }
}

public struct ApiErrorEnvelope: Codable, Equatable, Sendable {
    public let error: ApiError
}

public struct ApiError: Codable, Equatable, Sendable {
    public let code: String
    public let message: String
    public let retryable: Bool
    public let requestId: UUID

    enum CodingKeys: String, CodingKey {
        case code
        case message
        case retryable
        case requestId = "request_id"
    }
}

public struct CollectionItemResponse: Codable, Equatable, Sendable {
    public let id: UUID
    public let mbid: String?
    public let discogsReleaseId: String?
    public let title: String
    public let artist: String
    public let year: Int?
    public let format: String?
    public let notes: String?
    public let createdAt: String
    public let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case mbid
        case discogsReleaseId = "discogs_release_id"
        case title
        case artist
        case year
        case format
        case notes
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
