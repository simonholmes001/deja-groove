import Foundation

@MainActor
public final class DiscoveryViewModel: ObservableObject {
    @Published public private(set) var track: AudioDiscoveryTrack?
    @Published public private(set) var candidates: [Album] = []
    @Published public private(set) var history: [DiscoveryEntry] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var message: String?
    @Published public private(set) var musicAuthorizationStatus: MusicAuthorizationStatus = .unavailable
    @Published public var search = ""

    private let api: ApiClient
    private let discoveryStore: LocalDiscoveryStore
    private let audioDiscovery: AudioDiscoveryService
    private let candidateResolver: AlbumCandidateResolver
    private let musicAuthorization: MusicAuthorizationControlling

    public init(
        api: ApiClient,
        discoveryStore: LocalDiscoveryStore = PersistentLocalDiscoveryStore(),
        audioDiscovery: AudioDiscoveryService = UnavailableAudioDiscoveryService(),
        candidateResolver: AlbumCandidateResolver = LocalAlbumCandidateResolver(),
        musicAuthorization: MusicAuthorizationControlling = UnavailableMusicAuthorizationController()
    ) {
        self.api = api
        self.discoveryStore = discoveryStore
        self.audioDiscovery = audioDiscovery
        self.candidateResolver = candidateResolver
        self.musicAuthorization = musicAuthorization
    }

    public var visibleHistory: [DiscoveryEntry] {
        history.filter { LocalDiscoveryRules.matchesSearch($0, search: search) }
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
        do {
            let match = try await audioDiscovery.identifyCurrentAudio()
            track = match
            candidates = try await candidateResolver.albumCandidates(for: match)
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
            _ = try await api.addToWishlist(album: album, preferences: WishlistPreferences(), sourceTrack: track)
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

    private static func message(for error: ApiClientError) -> String {
        switch error {
        case .httpError(_, let apiError?):
            return apiError.message
        default:
            return "Discovery failed."
        }
    }
}
