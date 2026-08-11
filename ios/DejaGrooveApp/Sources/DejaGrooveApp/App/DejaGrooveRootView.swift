import SwiftUI

#if os(iOS)
public struct DejaGrooveRootView: View {
    private let api: ApiClient
    @StateObject private var collectionViewModel: CollectionViewModel

    public init(api: ApiClient) {
        self.api = api
        _collectionViewModel = StateObject(wrappedValue: CollectionViewModel(api: api))
    }

    public var body: some View {
        TabView {
            ScanView(viewModel: ScanViewModel(api: api))
                .tabItem { Label("Scan", systemImage: "camera") }

            CollectionView(viewModel: collectionViewModel)
                .tabItem { Label("My Crate", systemImage: "square.stack") }

            CollectionsView(viewModel: collectionViewModel)
                .tabItem { Label("Collections", systemImage: "folder") }
        }
    }
}
#endif
