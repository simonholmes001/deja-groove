import SwiftUI

#if os(iOS)
public struct DejaGrooveRootView: View {
    private let api: ApiClient
    private let onAuthenticationRequired: @Sendable () async -> Void
    @StateObject private var collectionViewModel: CollectionViewModel

    public init(
        api: ApiClient,
        onAuthenticationRequired: @escaping @Sendable () async -> Void = {}
    ) {
        self.api = api
        self.onAuthenticationRequired = onAuthenticationRequired
        _collectionViewModel = StateObject(wrappedValue: CollectionViewModel(
            api: api,
            onAuthenticationRequired: onAuthenticationRequired))
    }

    public var body: some View {
        TabView {
            ScanView(viewModel: ScanViewModel(api: api, onAuthenticationRequired: onAuthenticationRequired))
                .tabItem { Label("Scan", systemImage: "camera") }

            CollectionView(viewModel: collectionViewModel)
                .tabItem { Label("My Crate", systemImage: "square.stack") }

            CollectionsView(viewModel: collectionViewModel)
                .tabItem { Label("Collections", systemImage: "folder") }
        }
    }
}
#endif
