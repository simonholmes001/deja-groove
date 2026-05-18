import SwiftUI

#if os(iOS)
public struct DejaGrooveRootView: View {
    private let api: ApiClient

    public init(api: ApiClient) {
        self.api = api
    }

    public var body: some View {
        TabView {
            ScanView(viewModel: ScanViewModel(api: api))
                .tabItem { Label("Scan", systemImage: "camera") }

            CollectionView(viewModel: CollectionViewModel(api: api))
                .tabItem { Label("My Crate", systemImage: "square.stack") }
        }
    }
}
#endif
