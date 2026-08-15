import Foundation

public struct DiscoveryCandidateResult: Equatable, Sendable {
    public let album: Album
    public let status: String
}

@MainActor
public final class DiscoveryViewModel: ObservableObject {
    @Published public private(set) var track: AudioDiscoveryTrack?
    @Published public private(set) var candidates: [Album] = []
    @Published public private(set) var candidateResults: [DiscoveryCandidateResult] = []
    @Published public private(set) var history: [DiscoveryEntry] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var message: String?
    @Published public private(set) var musicAuthorizationStatus: MusicAuthorizationStatus = .unavailable
    @Published public var search = ""

    private let api: ApiClient
    private let collectionStore: LocalCollectionStore
    private let wishlistStore: LocalWishlistStore
    private let discoveryStore: LocalDiscoveryStore
    private let audioDiscovery: AudioDiscoveryService
    private let candidateResolver: AlbumCandidateResolver
    private let albumEnricher: AlbumMetadataEnricher
    private let musicAuthorization: MusicAuthorizationControlling

    public init(
        api: ApiClient,
        collectionStore: LocalCollectionStore = PersistentLocalCollectionStore(),
        wishlistStore: LocalWishlistStore = PersistentLocalWishlistStore(),
        discoveryStore: LocalDiscoveryStore = PersistentLocalDiscoveryStore(),
        audioDiscovery: AudioDiscoveryService = UnavailableAudioDiscoveryService(),
        candidateResolver: AlbumCandidateResolver = LocalAlbumCandidateResolver(),
        albumEnricher: AlbumMetadataEnricher = NoopAlbumMetadataEnricher(),
        musicAuthorization: MusicAuthorizationControlling = UnavailableMusicAuthorizationController()
    ) {
        self.api = api
        self.collectionStore = collectionStore
        self.wishlistStore = wishlistStore
        self.discoveryStore = discoveryStore
        self.audioDiscovery = audioDiscovery
        self.candidateResolver = candidateResolver
        self.albumEnricher = albumEnricher
        self.musicAuthorization = musicAuthorization
    }

    public var visibleHistory: [DiscoveryEntry] {
        history.filter { LocalDiscoveryRules.matchesSearch($0, search: search) }
    }

    public var shouldShowListeningActivity: Bool {
        isLoading
    }

    public func load() async {
        do {
            history = try await discoveryStore.fetchDiscoveries(search: nil)
        } catch {
            message = "Failed to load Discovery History."
        }
    }

    public func prepareMusicAccess() async {
        let status = await musicAuthorization.requestAuthorization()
        musicAuthorizationStatus = status
        switch status {
        case .authorized, .notDetermined:
            message = nil
        case .denied:
            message = "Apple Music access was not granted. Discovery can still save local history."
        case .restricted:
            message = "Apple Music access is restricted on this device. Discovery can still save local history."
        case .unavailable:
            message = nil
        }
    }

    public func identifyPlayingAudio() async {
        isLoading = true
        message = nil
        candidateResults = []
        candidates = []
        do {
            let match = try await audioDiscovery.identifyCurrentAudio()
            track = match
            candidateResults = try await decorateCandidateResults(
                await enrichAlbums(try await candidateResolver.albumCandidates(for: match), for: match))
            candidates = candidateResults.map(\.album)
            _ = try await discoveryStore.addDiscovery(source: "audio", album: candidates.first, track: match)
            history = try await discoveryStore.fetchDiscoveries(search: nil)
            message = candidates.isEmpty ? "Audio identified. No album candidates found." : nil
        } catch let error as ApiClientError {
            message = Self.message(for: error)
        } catch {
            message = "Audio discovery failed."
        }
        isLoading = false
    }

    public func saveCandidateToWishlist(_ album: Album) async {
        do {
            let albumToSave = await albumForWishlistSave(album)
            _ = try await api.addToWishlist(album: albumToSave, preferences: WishlistPreferences(), sourceTrack: track)
            message = "Added to Wishlist."
        } catch let error as ApiClientError {
            message = Self.message(for: error)
        } catch {
            message = "Failed to add to Wishlist."
        }
    }

    public func deleteDiscovery(id: UUID) async {
        do {
            try await discoveryStore.deleteDiscovery(id: id)
            history.removeAll { $0.id == id }
            message = nil
        } catch {
            message = "Failed to delete discovery."
        }
    }

    public func clearAllHistory() async {
        do {
            try await discoveryStore.deleteAllDiscoveries()
            history.removeAll()
            message = nil
        } catch {
            message = "Failed to clear discovery history."
        }
    }

    private func enrichAlbums(_ albums: [Album], for track: AudioDiscoveryTrack) async -> [Album] {
        var enrichedAlbums: [Album] = []
        for album in albums {
            do {
                let enriched = try await albumEnricher.enrich(album: album)
                enrichedAlbums.append(preservingListeningLinks(from: album, in: enriched))
            } catch {
                enrichedAlbums.append(album)
            }
        }
        return enrichedAlbums
            .filter { isPlausibleAlbumCandidate($0, for: track) }
            .sorted(by: discogsEnrichedAlbumsFirst)
    }

    private func decorateCandidateResults(_ albums: [Album]) async throws -> [DiscoveryCandidateResult] {
        var results: [DiscoveryCandidateResult] = []
        for album in albums {
            results.append(DiscoveryCandidateResult(album: album, status: try await status(for: album)))
        }
        return results
    }

    private func status(for album: Album) async throws -> String {
        if try await collectionStore.contains(album: album) {
            return "owned"
        }
        if try await wishlistStore.contains(album: album) {
            return "wishlist_match"
        }
        if try await discoveryStore.contains(album: album) {
            return "discovery_match"
        }
        return "safe_to_buy"
    }

    private func discogsEnrichedAlbumsFirst(_ lhs: Album, _ rhs: Album) -> Bool {
        let lhsScore = enrichmentScore(lhs)
        let rhsScore = enrichmentScore(rhs)
        if lhsScore != rhsScore {
            return lhsScore > rhsScore
        }
        return LocalCollectionRules.compareAlbumsByArtistFamilyName(
            lhs,
            rhs,
            lhsTieBreaker: lhs.discogsReleaseId ?? lhs.mbid ?? lhs.title,
            rhsTieBreaker: rhs.discogsReleaseId ?? rhs.mbid ?? rhs.title)
    }

    private func enrichmentScore(_ album: Album) -> Int {
        var score = 0
        if album.discogsReleaseId != nil { score += 100 }
        if album.discogsMasterId != nil { score += 25 }
        if album.catalogNumber != nil { score += 10 }
        if album.country != nil { score += 10 }
        if !album.tracklist.isEmpty { score += 10 }
        if !album.identifiers.isEmpty { score += 10 }
        if album.label != nil { score += 5 }
        return score
    }

    private func isPlausibleAlbumCandidate(_ album: Album, for track: AudioDiscoveryTrack) -> Bool {
        guard artistMatches(album.artist, track.artist) else { return false }
        guard !album.tracklist.isEmpty else { return true }
        return album.tracklist.contains { albumTrack in
            normalizedTitle(albumTrack.title) == normalizedTitle(track.title)
        }
    }

    private func artistMatches(_ candidate: String, _ matchedArtist: String) -> Bool {
        let candidate = normalizedArtist(candidate)
        let matchedArtist = normalizedArtist(matchedArtist)
        guard !candidate.isEmpty, !matchedArtist.isEmpty else { return false }
        return candidate == matchedArtist
            || candidate.contains(matchedArtist)
            || matchedArtist.contains(candidate)
    }

    private func normalizedArtist(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: #"(?i)\s+(feat\.?|featuring|with)\s+.*$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedTitle(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: #"\([^)]*\)"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func albumForWishlistSave(_ album: Album) async -> Album {
        let currentCandidate = matchingCurrentCandidate(for: album) ?? album
        do {
            let enriched = try await albumEnricher.enrich(album: currentCandidate)
            return preservingListeningLinks(from: currentCandidate, in: enriched)
        } catch {
            return currentCandidate
        }
    }

    private func matchingCurrentCandidate(for album: Album) -> Album? {
        candidates.first { isSameAlbum($0, album) }
    }

    private func isSameAlbum(_ lhs: Album, _ rhs: Album) -> Bool {
        if let lhsDiscogs = lhs.discogsReleaseId, let rhsDiscogs = rhs.discogsReleaseId {
            return lhsDiscogs == rhsDiscogs
        }
        if let lhsMbid = lhs.mbid, let rhsMbid = rhs.mbid {
            return lhsMbid == rhsMbid
        }
        return LocalCollectionRules.normalized(lhs.artist) == LocalCollectionRules.normalized(rhs.artist)
            && LocalCollectionRules.normalized(lhs.title) == LocalCollectionRules.normalized(rhs.title)
    }

    private func preservingListeningLinks(from original: Album, in enriched: Album) -> Album {
        guard enriched.listeningLinks.isEmpty, !original.listeningLinks.isEmpty else {
            return enriched
        }
        return Album(
            mbid: enriched.mbid,
            discogsReleaseId: enriched.discogsReleaseId,
            discogsMasterId: enriched.discogsMasterId,
            discogsUrl: enriched.discogsUrl,
            discogsResourceUrl: enriched.discogsResourceUrl,
            title: enriched.title,
            artist: enriched.artist,
            year: enriched.year,
            format: enriched.format,
            firstReleaseYear: enriched.firstReleaseYear,
            releaseYear: enriched.releaseYear,
            firstReleaseDate: enriched.firstReleaseDate,
            releaseDate: enriched.releaseDate,
            label: enriched.label,
            catalogNumber: enriched.catalogNumber,
            country: enriched.country,
            barcode: enriched.barcode,
            coverImageUrl: enriched.coverImageUrl,
            thumbnailUrl: enriched.thumbnailUrl,
            backCoverImageUrl: enriched.backCoverImageUrl,
            backCoverText: enriched.backCoverText,
            releaseNotes: enriched.releaseNotes,
            genres: enriched.genres,
            styles: enriched.styles,
            companies: enriched.companies,
            tracklist: enriched.tracklist,
            identifiers: enriched.identifiers,
            discogsDataQuality: enriched.discogsDataQuality,
            listeningLinks: original.listeningLinks)
    }

    private static func message(for error: ApiClientError) -> String {
        switch error {
        case .httpError(_, let apiError?):
            return apiError.message
        default:
            return "Discovery failed."
        }
    }
}
