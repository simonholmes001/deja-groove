import Foundation

public struct Album: Codable, Equatable, Sendable {
    public let mbid: String?
    public let discogsReleaseId: String?
    public let discogsMasterId: String?
    public let discogsUrl: String?
    public let discogsResourceUrl: String?
    public let title: String
    public let artist: String
    public let year: Int?
    public let firstReleaseYear: Int?
    public let releaseYear: Int?
    public let firstReleaseDate: String?
    public let releaseDate: String?
    public let format: String?
    public let label: String?
    public let catalogNumber: String?
    public let country: String?
    public let barcode: String?
    public let coverImageUrl: String?
    public let thumbnailUrl: String?
    public let backCoverImageUrl: String?
    public let backCoverText: String?
    public let releaseNotes: String?
    public let genres: [String]
    public let styles: [String]
    public let companies: [String]
    public let tracklist: [AlbumTrack]
    public let identifiers: [AlbumIdentifier]
    public let discogsDataQuality: String?

    public init(
        mbid: String?,
        discogsReleaseId: String?,
        discogsMasterId: String? = nil,
        discogsUrl: String? = nil,
        discogsResourceUrl: String? = nil,
        title: String,
        artist: String,
        year: Int?,
        format: String?,
        firstReleaseYear: Int? = nil,
        releaseYear: Int? = nil,
        firstReleaseDate: String? = nil,
        releaseDate: String? = nil,
        label: String? = nil,
        catalogNumber: String? = nil,
        country: String? = nil,
        barcode: String? = nil,
        coverImageUrl: String? = nil,
        thumbnailUrl: String? = nil,
        backCoverImageUrl: String? = nil,
        backCoverText: String? = nil,
        releaseNotes: String? = nil,
        genres: [String] = [],
        styles: [String] = [],
        companies: [String] = [],
        tracklist: [AlbumTrack] = [],
        identifiers: [AlbumIdentifier] = [],
        discogsDataQuality: String? = nil
    ) {
        self.mbid = mbid
        self.discogsReleaseId = discogsReleaseId
        self.discogsMasterId = discogsMasterId
        self.discogsUrl = discogsUrl
        self.discogsResourceUrl = discogsResourceUrl
        self.title = title
        self.artist = artist
        self.year = year
        self.format = format
        self.firstReleaseYear = firstReleaseYear
        self.releaseYear = releaseYear
        self.firstReleaseDate = firstReleaseDate
        self.releaseDate = releaseDate
        self.label = label
        self.catalogNumber = catalogNumber
        self.country = country
        self.barcode = barcode
        self.coverImageUrl = coverImageUrl
        self.thumbnailUrl = thumbnailUrl
        self.backCoverImageUrl = backCoverImageUrl
        self.backCoverText = backCoverText
        self.releaseNotes = releaseNotes
        self.genres = genres
        self.styles = styles
        self.companies = companies
        self.tracklist = tracklist
        self.identifiers = identifiers
        self.discogsDataQuality = discogsDataQuality
    }

    enum CodingKeys: String, CodingKey {
        case mbid
        case discogsReleaseId = "discogs_release_id"
        case discogsMasterId = "discogs_master_id"
        case discogsUrl = "discogs_url"
        case discogsResourceUrl = "discogs_resource_url"
        case title
        case artist
        case year
        case firstReleaseYear = "first_release_year"
        case releaseYear = "release_year"
        case firstReleaseDate = "first_release_date"
        case releaseDate = "release_date"
        case format
        case label
        case catalogNumber = "catalog_number"
        case country
        case barcode
        case coverImageUrl = "cover_image_url"
        case thumbnailUrl = "thumbnail_url"
        case backCoverImageUrl = "back_cover_image_url"
        case backCoverText = "back_cover_text"
        case releaseNotes = "release_notes"
        case genres
        case styles
        case companies
        case tracklist
        case identifiers
        case discogsDataQuality = "discogs_data_quality"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            mbid: try container.decodeIfPresent(String.self, forKey: .mbid),
            discogsReleaseId: try container.decodeIfPresent(String.self, forKey: .discogsReleaseId),
            discogsMasterId: try container.decodeIfPresent(String.self, forKey: .discogsMasterId),
            discogsUrl: try container.decodeIfPresent(String.self, forKey: .discogsUrl),
            discogsResourceUrl: try container.decodeIfPresent(String.self, forKey: .discogsResourceUrl),
            title: try container.decode(String.self, forKey: .title),
            artist: try container.decode(String.self, forKey: .artist),
            year: try container.decodeIfPresent(Int.self, forKey: .year),
            format: try container.decodeIfPresent(String.self, forKey: .format),
            firstReleaseYear: try container.decodeIfPresent(Int.self, forKey: .firstReleaseYear),
            releaseYear: try container.decodeIfPresent(Int.self, forKey: .releaseYear),
            firstReleaseDate: try container.decodeIfPresent(String.self, forKey: .firstReleaseDate),
            releaseDate: try container.decodeIfPresent(String.self, forKey: .releaseDate),
            label: try container.decodeIfPresent(String.self, forKey: .label),
            catalogNumber: try container.decodeIfPresent(String.self, forKey: .catalogNumber),
            country: try container.decodeIfPresent(String.self, forKey: .country),
            barcode: try container.decodeIfPresent(String.self, forKey: .barcode),
            coverImageUrl: try container.decodeIfPresent(String.self, forKey: .coverImageUrl),
            thumbnailUrl: try container.decodeIfPresent(String.self, forKey: .thumbnailUrl),
            backCoverImageUrl: try container.decodeIfPresent(String.self, forKey: .backCoverImageUrl),
            backCoverText: try container.decodeIfPresent(String.self, forKey: .backCoverText),
            releaseNotes: try container.decodeIfPresent(String.self, forKey: .releaseNotes),
            genres: try container.decodeIfPresent([String].self, forKey: .genres) ?? [],
            styles: try container.decodeIfPresent([String].self, forKey: .styles) ?? [],
            companies: try container.decodeIfPresent([String].self, forKey: .companies) ?? [],
            tracklist: try container.decodeIfPresent([AlbumTrack].self, forKey: .tracklist) ?? [],
            identifiers: try container.decodeIfPresent([AlbumIdentifier].self, forKey: .identifiers) ?? [],
            discogsDataQuality: try container.decodeIfPresent(String.self, forKey: .discogsDataQuality))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(mbid, forKey: .mbid)
        try container.encodeIfPresent(discogsReleaseId, forKey: .discogsReleaseId)
        try container.encodeIfPresent(discogsMasterId, forKey: .discogsMasterId)
        try container.encodeIfPresent(discogsUrl, forKey: .discogsUrl)
        try container.encodeIfPresent(discogsResourceUrl, forKey: .discogsResourceUrl)
        try container.encode(title, forKey: .title)
        try container.encode(artist, forKey: .artist)
        try container.encodeIfPresent(year, forKey: .year)
        try container.encodeIfPresent(firstReleaseYear, forKey: .firstReleaseYear)
        try container.encodeIfPresent(releaseYear, forKey: .releaseYear)
        try container.encodeIfPresent(firstReleaseDate, forKey: .firstReleaseDate)
        try container.encodeIfPresent(releaseDate, forKey: .releaseDate)
        try container.encodeIfPresent(format, forKey: .format)
        try container.encodeIfPresent(label, forKey: .label)
        try container.encodeIfPresent(catalogNumber, forKey: .catalogNumber)
        try container.encodeIfPresent(country, forKey: .country)
        try container.encodeIfPresent(barcode, forKey: .barcode)
        try container.encodeIfPresent(coverImageUrl, forKey: .coverImageUrl)
        try container.encodeIfPresent(thumbnailUrl, forKey: .thumbnailUrl)
        try container.encodeIfPresent(backCoverImageUrl, forKey: .backCoverImageUrl)
        try container.encodeIfPresent(backCoverText, forKey: .backCoverText)
        try container.encodeIfPresent(releaseNotes, forKey: .releaseNotes)
        try container.encode(genres, forKey: .genres)
        try container.encode(styles, forKey: .styles)
        try container.encode(companies, forKey: .companies)
        try container.encode(tracklist, forKey: .tracklist)
        try container.encode(identifiers, forKey: .identifiers)
        try container.encodeIfPresent(discogsDataQuality, forKey: .discogsDataQuality)
    }
}

public struct AlbumTrack: Codable, Equatable, Sendable {
    public let position: String?
    public let title: String
    public let duration: String?

    public init(position: String?, title: String, duration: String?) {
        self.position = position
        self.title = title
        self.duration = duration
    }
}

public struct AlbumIdentifier: Codable, Equatable, Sendable {
    public let type: String
    public let value: String?
    public let description: String?

    public init(type: String, value: String?, description: String?) {
        self.type = type
        self.value = value
        self.description = description
    }
}

public struct ScanResponse: Codable, Equatable, Sendable {
    public let status: String
    public let confidence: Float
    public let album: Album?
    public let candidates: [Album]
    public let timings: ScanTimings?
    public let requestId: UUID

    public init(status: String, confidence: Float, album: Album?, candidates: [Album], timings: ScanTimings? = nil, requestId: UUID) {
        self.status = Self.normalizeStatus(status)
        self.confidence = confidence
        self.album = album
        self.candidates = candidates
        self.timings = timings
        self.requestId = requestId
    }

    public var canAddToCollection: Bool {
        album != nil && status == "safe_to_buy"
    }

    public func withClientElapsedMs(_ clientElapsedMs: Int) -> ScanResponse {
        ScanResponse(
            status: status,
            confidence: confidence,
            album: album,
            candidates: candidates,
            timings: timings?.withClientElapsedMs(clientElapsedMs),
            requestId: requestId)
    }

    enum CodingKeys: String, CodingKey {
        case status
        case confidence
        case album
        case candidates
        case timings
        case requestId = "request_id"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            status: try container.decode(String.self, forKey: .status),
            confidence: try container.decode(Float.self, forKey: .confidence),
            album: try container.decodeIfPresent(Album.self, forKey: .album),
            candidates: try container.decode([Album].self, forKey: .candidates),
            timings: try container.decodeIfPresent(ScanTimings.self, forKey: .timings),
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

public struct ScanTimings: Codable, Equatable, Sendable {
    public let totalMs: Int
    public let imageReadMs: Int
    public let recognitionMs: Int
    public let enrichmentMs: Int
    public let imageBytes: Int
    public let enrichmentTimedOut: Bool
    public let clientElapsedMs: Int?

    public init(
        totalMs: Int,
        imageReadMs: Int,
        recognitionMs: Int,
        enrichmentMs: Int,
        imageBytes: Int,
        enrichmentTimedOut: Bool,
        clientElapsedMs: Int? = nil
    ) {
        self.totalMs = totalMs
        self.imageReadMs = imageReadMs
        self.recognitionMs = recognitionMs
        self.enrichmentMs = enrichmentMs
        self.imageBytes = imageBytes
        self.enrichmentTimedOut = enrichmentTimedOut
        self.clientElapsedMs = clientElapsedMs
    }

    public func withClientElapsedMs(_ clientElapsedMs: Int) -> ScanTimings {
        ScanTimings(
            totalMs: totalMs,
            imageReadMs: imageReadMs,
            recognitionMs: recognitionMs,
            enrichmentMs: enrichmentMs,
            imageBytes: imageBytes,
            enrichmentTimedOut: enrichmentTimedOut,
            clientElapsedMs: clientElapsedMs)
    }

    enum CodingKeys: String, CodingKey {
        case totalMs = "total_ms"
        case imageReadMs = "image_read_ms"
        case recognitionMs = "recognition_ms"
        case enrichmentMs = "enrichment_ms"
        case imageBytes = "image_bytes"
        case enrichmentTimedOut = "enrichment_timed_out"
        case clientElapsedMs = "client_elapsed_ms"
    }
}

public struct CollectionRecord: Codable, Equatable, Identifiable, Sendable {
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

public struct CrateCollection: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let recordIds: [UUID]
    public let createdAt: String
    public let updatedAt: String

    public init(id: UUID, name: String, recordIds: [UUID], createdAt: String, updatedAt: String) {
        self.id = id
        self.name = name
        self.recordIds = recordIds
        self.createdAt = createdAt
        self.updatedAt = updatedAt
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
