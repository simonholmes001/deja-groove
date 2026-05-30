import SwiftUI

#if os(iOS)
public struct DejaGrooveRootView: View {
    private let api: ApiClient
    private let onAuthenticationRequired: @Sendable () async -> Void

    public init(
        api: ApiClient,
        onAuthenticationRequired: @escaping @Sendable () async -> Void = {}
    ) {
        self.api = api
        self.onAuthenticationRequired = onAuthenticationRequired
    }

    public var body: some View {
        TabView {
            ScanView(viewModel: ScanViewModel(api: api, onAuthenticationRequired: onAuthenticationRequired))
                .tabItem { Label("Scan", systemImage: "camera") }

            CollectionView(viewModel: CollectionViewModel(api: api, onAuthenticationRequired: onAuthenticationRequired))
                .tabItem { Label("My Crate", systemImage: "square.stack") }
        }
    }
}
#endif
