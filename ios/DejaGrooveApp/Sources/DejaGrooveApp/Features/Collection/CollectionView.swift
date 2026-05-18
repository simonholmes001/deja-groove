import SwiftUI

#if os(iOS)
public struct CollectionView: View {
    @StateObject private var viewModel: CollectionViewModel

    public init(viewModel: CollectionViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        NavigationStack {
            List(viewModel.records, id: \.id) { record in
                VStack(alignment: .leading) {
                    Text(record.album.artist).font(.headline)
                    Text(record.album.title)
                    if let notes = record.notes, !notes.isEmpty {
                        Text(notes).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .overlay {
                if viewModel.isLoading { ProgressView("Loading...") }
                if let error = viewModel.errorMessage { Text(error).foregroundStyle(.red) }
            }
            .searchable(text: $viewModel.search)
            .navigationTitle("My Crate")
            .task { await viewModel.load() }
            .onSubmit(of: .search) { Task { await viewModel.load() } }
        }
    }
}
#endif
