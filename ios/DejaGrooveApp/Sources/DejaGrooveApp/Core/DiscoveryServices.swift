import Foundation

public protocol AudioDiscoveryService: Sendable {
    func identifyCurrentAudio() async throws -> AudioDiscoveryTrack
}

public protocol AlbumCandidateResolver: Sendable {
    func albumCandidates(for track: AudioDiscoveryTrack) async throws -> [Album]
}

public protocol MusicCatalogLinkResolver: Sendable {
    func enrichListeningLinks(for album: Album) async throws -> Album
}

public enum MusicAuthorizationStatus: Equatable, Sendable {
    case authorized
    case denied
    case restricted
    case notDetermined
    case unavailable
}

public protocol MusicAuthorizationControlling: Sendable {
    func requestAuthorization() async -> MusicAuthorizationStatus
}

public struct UnavailableAudioDiscoveryService: AudioDiscoveryService {
    public init() {}

    public func identifyCurrentAudio() async throws -> AudioDiscoveryTrack {
        throw ApiClientError.httpError(
            501,
            ApiError(
                code: "audio_discovery_unavailable",
                message: "Audio discovery is not available in this build.",
                retryable: false,
                requestId: UUID()))
    }
}

public struct LocalAlbumCandidateResolver: AlbumCandidateResolver {
    private let musicCatalog: MusicCatalogLinkResolver

    public init(musicCatalog: MusicCatalogLinkResolver = UnavailableMusicCatalogLinkResolver()) {
        self.musicCatalog = musicCatalog
    }

    public func albumCandidates(for track: AudioDiscoveryTrack) async throws -> [Album] {
        let candidate = Album(
            mbid: nil,
            discogsReleaseId: nil,
            title: track.title,
            artist: track.artist,
            year: nil,
            format: nil,
            coverImageUrl: track.artworkUrl,
            thumbnailUrl: track.artworkUrl)
        return [try await musicCatalog.enrichListeningLinks(for: candidate)]
    }
}

public struct UnavailableMusicCatalogLinkResolver: MusicCatalogLinkResolver {
    public init() {}

    public func enrichListeningLinks(for album: Album) async throws -> Album {
        album
    }
}

public struct UnavailableMusicAuthorizationController: MusicAuthorizationControlling {
    public init() {}

    public func requestAuthorization() async -> MusicAuthorizationStatus {
        .unavailable
    }
}

public struct AppleMusicAlbumCandidateResolver: AlbumCandidateResolver {
    private let fallback: AlbumCandidateResolver
    private let transport: HttpTransport

    public init(
        fallback: AlbumCandidateResolver = LocalAlbumCandidateResolver(),
        transport: HttpTransport = URLSessionTransport(session: .shared)
    ) {
        self.fallback = fallback
        self.transport = transport
    }

    public func albumCandidates(for track: AudioDiscoveryTrack) async throws -> [Album] {
        let query = "\(track.artist) \(track.title)"
        guard var components = URLComponents(string: "https://itunes.apple.com/search") else {
            return try await fallback.albumCandidates(for: track)
        }
        components.queryItems = [
            URLQueryItem(name: "term", value: query),
            URLQueryItem(name: "entity", value: "album"),
            URLQueryItem(name: "limit", value: "8")
        ]
        guard let url = components.url else {
            return try await fallback.albumCandidates(for: track)
        }

        let request = URLRequest(url: url)
        let (data, response) = try await transport.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            return try await fallback.albumCandidates(for: track)
        }
        let decoded = try JSONDecoder().decode(AppleMusicSearchResponse.self, from: data)
        let albums = decoded.results.map { result in
            Album(
                mbid: nil,
                discogsReleaseId: nil,
                title: result.collectionName,
                artist: result.artistName,
                year: result.releaseDate.flatMap { String($0.prefix(4)) }.flatMap(Int.init),
                format: nil,
                releaseDate: result.releaseDate,
                coverImageUrl: result.artworkUrl100?.replacingOccurrences(of: "100x100", with: "600x600"),
                thumbnailUrl: result.artworkUrl100,
                listeningLinks: result.collectionViewUrl.map {
                    [AlbumListeningLink(provider: "Apple Music", url: $0, catalogId: result.collectionId.map(String.init))]
                } ?? [])
        }
        return albums.isEmpty ? try await fallback.albumCandidates(for: track) : albums
    }
}

public struct AppleMusicCatalogLinkResolver: MusicCatalogLinkResolver {
    private let transport: HttpTransport

    public init(transport: HttpTransport = URLSessionTransport(session: .shared)) {
        self.transport = transport
    }

    public func enrichListeningLinks(for album: Album) async throws -> Album {
        let track = AudioDiscoveryTrack(title: album.title, artist: album.artist, matchedAt: ISO8601DateFormatter().string(from: Date()))
        let candidates = try await AppleMusicAlbumCandidateResolver(transport: transport).albumCandidates(for: track)
        guard let match = candidates.first else {
            return album
        }
        return Album(
            mbid: album.mbid,
            discogsReleaseId: album.discogsReleaseId,
            discogsMasterId: album.discogsMasterId,
            discogsUrl: album.discogsUrl,
            discogsResourceUrl: album.discogsResourceUrl,
            title: album.title,
            artist: album.artist,
            year: album.year,
            format: album.format,
            firstReleaseYear: album.firstReleaseYear,
            releaseYear: album.releaseYear,
            firstReleaseDate: album.firstReleaseDate,
            releaseDate: album.releaseDate,
            label: album.label,
            catalogNumber: album.catalogNumber,
            country: album.country,
            barcode: album.barcode,
            coverImageUrl: album.coverImageUrl ?? match.coverImageUrl,
            thumbnailUrl: album.thumbnailUrl ?? match.thumbnailUrl,
            backCoverImageUrl: album.backCoverImageUrl,
            backCoverText: album.backCoverText,
            releaseNotes: album.releaseNotes,
            genres: album.genres,
            styles: album.styles,
            companies: album.companies,
            tracklist: album.tracklist,
            identifiers: album.identifiers,
            discogsDataQuality: album.discogsDataQuality,
            listeningLinks: album.listeningLinks.isEmpty ? match.listeningLinks : album.listeningLinks)
    }
}

private struct AppleMusicSearchResponse: Decodable {
    let results: [AppleMusicSearchAlbum]
}

private struct AppleMusicSearchAlbum: Decodable {
    let artistName: String
    let collectionName: String
    let collectionId: Int?
    let collectionViewUrl: String?
    let artworkUrl100: String?
    let releaseDate: String?
}

#if canImport(MusicKit)
import MusicKit

public struct MusicKitAuthorizationController: MusicAuthorizationControlling {
    public init() {}

    public func requestAuthorization() async -> MusicAuthorizationStatus {
        switch await MusicAuthorization.request() {
        case .authorized:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .unavailable
        }
    }
}

public struct MusicKitAlbumCandidateResolver: AlbumCandidateResolver {
    private let fallback: AlbumCandidateResolver

    public init(fallback: AlbumCandidateResolver = AppleMusicAlbumCandidateResolver()) {
        self.fallback = fallback
    }

    public func albumCandidates(for track: AudioDiscoveryTrack) async throws -> [Album] {
        do {
            let query = "\(track.artist) \(track.title)"
            var request = MusicCatalogSearchRequest(term: query, types: [MusicKit.Album.self])
            request.limit = 8
            let response = try await request.response()
            let albums = response.albums.map(Self.album(from:))
            return albums.isEmpty ? try await fallback.albumCandidates(for: track) : albums
        } catch {
            return try await fallback.albumCandidates(for: track)
        }
    }

    private static func album(from catalogAlbum: MusicKit.Album) -> Album {
        let releaseDate = catalogAlbum.releaseDate.map(Self.formattedReleaseDate)
        return Album(
            mbid: nil,
            discogsReleaseId: nil,
            title: catalogAlbum.title,
            artist: catalogAlbum.artistName,
            year: catalogAlbum.releaseDate.map { Calendar(identifier: .gregorian).component(.year, from: $0) },
            format: nil,
            releaseDate: releaseDate,
            label: catalogAlbum.recordLabelName,
            barcode: catalogAlbum.upc,
            coverImageUrl: catalogAlbum.artwork?.url(width: 600, height: 600)?.absoluteString,
            thumbnailUrl: catalogAlbum.artwork?.url(width: 100, height: 100)?.absoluteString,
            genres: catalogAlbum.genreNames,
            listeningLinks: catalogAlbum.url.map {
                [AlbumListeningLink(provider: "Apple Music", url: $0.absoluteString, catalogId: catalogAlbum.id.rawValue)]
            } ?? [])
    }

    private static func formattedReleaseDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.string(from: date)
    }
}
#endif

#if canImport(ShazamKit) && canImport(AVFoundation)
import AVFoundation
import ShazamKit

public final class ShazamKitAudioDiscoveryService: NSObject, AudioDiscoveryService, @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let session = SHSession()
    private let timeoutNanoseconds: UInt64
    private var continuation: CheckedContinuation<AudioDiscoveryTrack, Error>?
    private var timeoutTask: Task<Void, Never>?

    public init(timeoutSeconds: TimeInterval = 12) {
        self.timeoutNanoseconds = UInt64(timeoutSeconds * 1_000_000_000)
        super.init()
        session.delegate = self
    }

    public func identifyCurrentAudio() async throws -> AudioDiscoveryTrack {
        #if os(iOS)
        guard await requestMicrophonePermission() else {
            throw ApiClientError.httpError(
                403,
                ApiError(
                    code: "microphone_permission_denied",
                    message: "Microphone access is required to identify audio.",
                    retryable: false,
                    requestId: UUID()))
        }
        try configureAudioSession()
        #endif

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            do {
                let input = engine.inputNode
                let format = input.outputFormat(forBus: 0)
                input.installTap(onBus: 0, bufferSize: 8192, format: format) { [weak self] buffer, audioTime in
                    self?.session.matchStreamingBuffer(buffer, at: audioTime)
                }
                try engine.start()
                timeoutTask = Task { [weak self, timeoutNanoseconds] in
                    try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                    guard !Task.isCancelled else { return }
                    self?.finish(with: .failure(ApiClientError.httpError(
                        408,
                        ApiError(
                            code: "audio_discovery_timeout",
                            message: "Audio discovery timed out.",
                            retryable: true,
                            requestId: UUID()))))
                }
            } catch {
                self.continuation = nil
                continuation.resume(throwing: error)
            }
        }
    }

    private func finish(with result: Result<AudioDiscoveryTrack, Error>) {
        timeoutTask?.cancel()
        timeoutTask = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        #endif
        guard let continuation else { return }
        self.continuation = nil
        switch result {
        case .success(let track):
            continuation.resume(returning: track)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }

    #if os(iOS)
    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func configureAudioSession() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .default, options: [.duckOthers])
        try audioSession.setActive(true)
    }
    #endif
}

extension ShazamKitAudioDiscoveryService: SHSessionDelegate {
    public func session(_ session: SHSession, didFind match: SHMatch) {
        guard let mediaItem = match.mediaItems.first else {
            finish(with: .failure(ApiClientError.invalidResponse))
            return
        }
        let track = AudioDiscoveryTrack(
            title: mediaItem.title ?? "Unknown Track",
            artist: mediaItem.artist ?? "Unknown Artist",
            shazamId: mediaItem.shazamID,
            appleMusicId: mediaItem.appleMusicID,
            artworkUrl: mediaItem.artworkURL?.absoluteString,
            genre: mediaItem.genres.first,
            matchedAt: ISO8601DateFormatter().string(from: Date()))
        finish(with: .success(track))
    }

    public func session(_ session: SHSession, didNotFindMatchFor signature: SHSignature, error: Error?) {
        finish(with: .failure(error ?? ApiClientError.httpError(
            404,
            ApiError(
                code: "audio_no_match",
                message: "No audio match was found.",
                retryable: false,
                requestId: UUID()))))
    }
}
#endif
