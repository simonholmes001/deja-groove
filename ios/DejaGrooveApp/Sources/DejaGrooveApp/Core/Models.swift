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

    enum CodingKeys: String, CodingKey {
        case status
        case confidence
        case album
        case candidates
        case requestId = "request_id"
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
