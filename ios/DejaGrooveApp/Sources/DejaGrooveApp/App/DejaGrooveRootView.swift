import SwiftUI

#if os(iOS)
public struct DejaGrooveRootView: View {
    private let api: ApiClient
    @StateObject private var collectionViewModel: CollectionViewModel
    @StateObject private var wishlistViewModel: WishlistViewModel
    @StateObject private var discoveryViewModel: DiscoveryViewModel

    public init(api: ApiClient) {
        self.api = api
        _collectionViewModel = StateObject(wrappedValue: CollectionViewModel(api: api))
        _wishlistViewModel = StateObject(wrappedValue: WishlistViewModel(api: api))
        _discoveryViewModel = StateObject(wrappedValue: DiscoveryViewModel(
            api: api,
            audioDiscovery: DejaGrooveAudioDiscoveryFactory.make(),
            candidateResolver: DejaGrooveAlbumCandidateResolverFactory.make(),
            musicAuthorization: DejaGrooveMusicAuthorizationFactory.make()))
    }

    public var body: some View {
        TabView {
            ScanView(viewModel: ScanViewModel(api: api))
                .tabItem { Label("Scan", systemImage: "camera") }

            DiscoveryView(viewModel: discoveryViewModel)
                .tabItem { Label("Discover", systemImage: "waveform") }

            CollectionView(viewModel: collectionViewModel)
                .tabItem { Label("My Crate", systemImage: "square.stack") }

            WishlistView(viewModel: wishlistViewModel)
                .tabItem { Label("Wishlist", systemImage: "heart") }

            CollectionsView(viewModel: collectionViewModel)
                .tabItem { Label("Collections", systemImage: "folder") }
        }
    }
}
#endif

public enum DejaGrooveAudioDiscoveryFactory {
    public static func make() -> AudioDiscoveryService {
        #if canImport(ShazamKit) && canImport(AVFoundation)
        return ShazamKitAudioDiscoveryService()
        #else
        return UnavailableAudioDiscoveryService()
        #endif
    }
}

public enum DejaGrooveMusicAuthorizationFactory {
    public static func make() -> MusicAuthorizationControlling {
        #if canImport(MusicKit)
        return MusicKitAuthorizationController()
        #else
        return UnavailableMusicAuthorizationController()
        #endif
    }
}

public enum DejaGrooveAlbumCandidateResolverFactory {
    public static func make() -> AlbumCandidateResolver {
        #if canImport(MusicKit)
        return MusicKitAlbumCandidateResolver(fallback: AppleMusicAlbumCandidateResolver())
        #else
        return AppleMusicAlbumCandidateResolver()
        #endif
    }
}
