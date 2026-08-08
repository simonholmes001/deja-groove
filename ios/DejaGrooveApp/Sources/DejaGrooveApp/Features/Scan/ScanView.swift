import SwiftUI
import PhotosUI

#if os(iOS)
public struct ScanView: View {
    @StateObject private var viewModel: ScanViewModel
    @StateObject private var inputCoordinator: ScanInputCoordinator
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedCandidateIndex: Int?
    @State private var detailAlbum: Album?

    public init(viewModel: ScanViewModel, inputCoordinator: ScanInputCoordinator = ScanInputCoordinator()) {
        _viewModel = StateObject(wrappedValue: viewModel)
        _inputCoordinator = StateObject(wrappedValue: inputCoordinator)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Scan")
                .font(.largeTitle.bold())
            Text(viewModel.guidance)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                inputCoordinator.handlePrimaryAction()
            } label: {
                Text("Pick or Capture Cover")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .confirmationDialog("Scan Source", isPresented: $inputCoordinator.isSourceDialogPresented) {
                if inputCoordinator.isCameraAvailable {
                    Button("Take Photo") {
                        inputCoordinator.chooseCamera()
                    }
                }
                Button("Choose from Library") {
                    inputCoordinator.choosePhotoLibrary()
                }
                Button("Cancel", role: .cancel) {}
            }
            .photosPicker(isPresented: $inputCoordinator.isPhotoLibraryPresented, selection: $selectedItem, matching: .images)
            .onChange(of: selectedItem) { _, newItem in
                Task {
                    guard let item = newItem,
                          let data = try? await item.loadTransferable(type: Data.self),
                          let preparedData = PhotoLibraryScanImagePreparer.prepareForUpload(data) else {
                        await viewModel.handleSelectedImagePreparationFailure()
                        return
                    }
                    await viewModel.submitScan(imageData: preparedData)
                }
            }
            .sheet(isPresented: $inputCoordinator.isCameraPresented) {
                CameraCaptureView(
                    onImageCaptured: { data in
                        inputCoordinator.dismissCamera()
                        Task { await viewModel.submitScan(imageData: data) }
                    },
                    onCancel: {
                        inputCoordinator.dismissCamera()
                    }
                )
                .ignoresSafeArea()
            }

            switch viewModel.state {
            case .idle:
                Text("Take a clear photo to start.")
                qualityGuidance
            case .loading(let progress):
                ProgressView(progress.message)
            case .error(let message):
                VStack(alignment: .leading, spacing: 8) {
                    Text(message).foregroundStyle(.red)
                    if viewModel.isLastErrorRetryable {
                        Button("Retry Scan") {
                            Task { await viewModel.retryLastScan() }
                        }
                    }
                }
            case .result(let response):
                ScanResultView(
                    response: response,
                    selectedCandidateIndex: $selectedCandidateIndex,
                    onShowDetails: { album in
                        detailAlbum = album
                    },
                    onResolve: { candidate in
                        Task {
                            await viewModel.resolve(requestId: response.requestId, candidate: candidate)
                            selectedCandidateIndex = nil
                        }
                    })
                if response.canAddToCollection {
                    Button("Add To My Crate") {
                        Task { await viewModel.addResultToCollection() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            if let collectionMessage = viewModel.collectionMessage {
                Text(collectionMessage)
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            }

            Spacer()
        }
        .padding()
        .sheet(isPresented: detailAlbumBinding) {
            if let detailAlbum {
                NavigationStack {
                    ScanAlbumDetailView(album: detailAlbum, canAddToCrate: currentResultCanAddToCollection) {
                        Task {
                            await viewModel.addResultToCollection()
                            self.detailAlbum = nil
                        }
                    }
                }
            }
        }
    }

    private var detailAlbumBinding: Binding<Bool> {
        Binding(
            get: { detailAlbum != nil },
            set: { isPresented in
                if !isPresented {
                    detailAlbum = nil
                }
            })
    }

    private var currentResultCanAddToCollection: Bool {
        if case .result(let response) = viewModel.state {
            return response.canAddToCollection
        }
        return false
    }

    private var qualityGuidance: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Capture tips")
                .font(.subheadline.bold())
            Text("Use bright light, avoid reflections, and fill most of the frame with the album cover.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ScanResultView: View {
    let response: ScanResponse
    @Binding var selectedCandidateIndex: Int?
    let onShowDetails: (Album) -> Void
    let onResolve: (Album) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("Status:")
                    .font(.headline)
                Text(statusLabel)
                    .font(.headline.bold())
                    .foregroundStyle(statusColor)
            }
            if let album = response.album {
                Button {
                    onShowDetails(album)
                } label: {
                    ScanAlbumSummary(album: album)
                }
                .buttonStyle(.plain)
            }
            if response.status == "ambiguous" {
                Text("Select the correct release:")
                    .font(.subheadline.bold())
                ForEach(Array(response.candidates.enumerated()), id: \.offset) { _, candidate in
                    Button {
                        if let index = response.candidates.firstIndex(of: candidate) {
                            selectedCandidateIndex = index
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(candidate.artist)
                                Text(candidate.title).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: selectedCandidateIndex == response.candidates.firstIndex(of: candidate) ? "checkmark.circle.fill" : "circle")
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 6)
                }

                Button("Resolve Selection") {
                    guard let selectedCandidateIndex,
                          response.candidates.indices.contains(selectedCandidateIndex) else { return }
                    onResolve(response.candidates[selectedCandidateIndex])
                }
                .disabled(selectedCandidateIndex == nil || !response.candidates.indices.contains(selectedCandidateIndex ?? -1))
            }
        }
        .onChange(of: response.requestId) { _, _ in
            selectedCandidateIndex = nil
        }
    }

    private var statusLabel: String {
        switch response.status {
        case "safe_to_buy":
            return "SAFE TO BUY"
        case "owned":
            return "DUPLICATE"
        case "ambiguous":
            return "AMBIGUOUS"
        case "no_match":
            return "NO MATCH"
        default:
            return response.status
                .replacingOccurrences(of: "_", with: " ")
                .uppercased()
        }
    }

    private var statusColor: Color {
        switch response.status {
        case "safe_to_buy":
            return .green
        case "owned":
            return .red
        case "ambiguous":
            return .orange
        default:
            return .secondary
        }
    }
}

private struct ScanAlbumDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let album: Album
    let canAddToCrate: Bool
    let onAdd: () -> Void

    var body: some View {
        List {
            if album.coverImageUrl != nil || album.thumbnailUrl != nil {
                Section {
                    HStack {
                        Spacer()
                        AlbumArtwork(urlString: album.coverImageUrl ?? album.thumbnailUrl, size: 220)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
            }

            Section("Album") {
                detail("Artist", album.artist)
                detail("Title", album.title)
                detail("First Release Date", album.firstReleaseDate ?? album.firstReleaseYear.map(String.init) ?? album.releaseDate ?? album.releaseYear.map(String.init) ?? album.year.map(String.init))
                detail("Discogs Release Date", album.releaseDate ?? album.releaseYear.map(String.init))
                detail("Format", album.format)
                detail("Label", album.label)
                detail("Catalog Number", album.catalogNumber)
                detail("Country", album.country)
                detail("Barcode", album.barcode)
                detail("Discogs Release", album.discogsReleaseId)
                detail("Discogs Master", album.discogsMasterId)
                detail("Discogs Quality", album.discogsDataQuality)
                if let discogsUrl = album.discogsUrl, let url = URL(string: discogsUrl) {
                    Link("Open In Discogs", destination: url)
                }
            }

            if let releaseNotes = album.releaseNotes, !releaseNotes.isEmpty {
                Section("Release Notes") {
                    Text(releaseNotes)
                }
            }

            if !album.genres.isEmpty || !album.styles.isEmpty {
                Section("Genre & Style") {
                    detail("Genres", album.genres.joined(separator: ", "))
                    detail("Styles", album.styles.joined(separator: ", "))
                }
            }

            if !album.tracklist.isEmpty {
                Section("Tracklist") {
                    ForEach(Array(album.tracklist.enumerated()), id: \.offset) { _, track in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title)
                            HStack(spacing: 8) {
                                if let position = track.position, !position.isEmpty {
                                    Text(position)
                                }
                                if let duration = track.duration, !duration.isEmpty {
                                    Text(duration)
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !album.identifiers.isEmpty {
                Section("Identifiers") {
                    ForEach(Array(album.identifiers.enumerated()), id: \.offset) { _, identifier in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(identifier.type)
                            Text([identifier.value, identifier.description]
                                .compactMap { $0 }
                                .joined(separator: " - "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(album.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if canAddToCrate {
                    Button {
                        onAdd()
                    } label: {
                        Label("Add To My Crate", systemImage: "plus.circle.fill")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func detail(_ label: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            LabeledContent(label, value: value)
        }
    }
}

private struct ScanAlbumSummary: View {
    let album: Album

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AlbumArtwork(urlString: album.thumbnailUrl ?? album.coverImageUrl, size: 72)

            VStack(alignment: .leading, spacing: 6) {
                Text(album.artist)
                    .font(.headline)
                Text(album.title)
                    .font(.subheadline)

                if let firstRelease = album.firstReleaseDate ?? album.firstReleaseYear.map(String.init) ?? album.releaseDate ?? album.releaseYear.map(String.init) ?? album.year.map(String.init) {
                    Label(firstRelease, systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let format = album.format, !format.isEmpty {
                    Label(format, systemImage: "record.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let label = album.label, !label.isEmpty {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let catalogNumber = album.catalogNumber, !catalogNumber.isEmpty {
                    Text(catalogNumber)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct AlbumArtwork: View {
    let urlString: String?
    let size: CGFloat

    var body: some View {
        Group {
            if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        ZStack {
            Rectangle()
                .fill(.secondary.opacity(0.12))
            Image(systemName: "record.circle")
                .foregroundStyle(.secondary)
        }
    }
}
#endif
