import SwiftUI
import PhotosUI

#if os(iOS)
public struct ScanView: View {
    @StateObject private var viewModel: ScanViewModel
    @State private var selectedItem: PhotosPickerItem?

    public init(viewModel: ScanViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Scan")
                .font(.largeTitle.bold())
            Text(viewModel.guidance)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            PhotosPicker(selection: $selectedItem, matching: .images) {
                Text("Pick or Capture Cover")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .onChange(of: selectedItem) { _, newItem in
                Task {
                    guard let item = newItem,
                          let data = try? await item.loadTransferable(type: Data.self) else { return }
                    await viewModel.submitScan(imageData: data)
                }
            }

            switch viewModel.state {
            case .idle:
                Text("Take a clear photo to start.")
            case .loading:
                ProgressView("Analyzing cover...")
            case .error(let message):
                Text(message).foregroundStyle(.red)
            case .result(let response):
                ScanResultView(response: response) { candidate in
                    Task { await viewModel.resolve(requestId: response.requestId, candidate: candidate) }
                }
            }

            Spacer()
        }
        .padding()
    }
}

private struct ScanResultView: View {
    let response: ScanResponse
    let onResolve: (Album) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Status: \(response.status)")
                .font(.headline)
            if let album = response.album {
                Text("\(album.artist) — \(album.title)")
            }
            if response.status == "ambiguous" {
                Text("Select the correct release:")
                    .font(.subheadline.bold())
                ForEach(Array(response.candidates.enumerated()), id: \.offset) { _, candidate in
                    Button {
                        onResolve(candidate)
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(candidate.artist)
                                Text(candidate.title).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 6)
                }
            }
        }
    }
}
#endif
