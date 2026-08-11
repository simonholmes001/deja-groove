import Foundation
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
        DejaGrooveScreen {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Scan")
                            .font(.system(size: 44, weight: .black, design: .rounded))
                        Text(viewModel.guidance)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button {
                        inputCoordinator.handlePrimaryAction()
                    } label: {
                        Label("Pick or Capture Cover", systemImage: "camera.viewfinder")
                    }
                    .buttonStyle(DejaGroovePrimaryButtonStyle())
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

                    content

                    if let collectionMessage = viewModel.collectionMessage {
                        Text(collectionMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 110)
            }
        }
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

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle:
            DejaGroovePanel {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "record.circle")
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(DejaGrooveStyle.blue)
                    Text("Take a clear photo to start.")
                        .font(.headline)
                    qualityGuidance
                }
            }
        case .loading(let progress):
            ScanLoadingView(progress: progress)
        case .error(let message):
            DejaGroovePanel {
                VStack(alignment: .leading, spacing: 8) {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    if viewModel.isLastErrorRetryable {
                        Button("Retry Scan") {
                            Task { await viewModel.retryLastScan() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        case .result(let response):
            DejaGroovePanel {
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
            }
            if response.canAddToCollection {
                Button("Add To My Crate") {
                    Task { await viewModel.addResultToCollection() }
                }
                .buttonStyle(DejaGroovePrimaryButtonStyle())
            }
            if response.canAddToWishlist {
                Button {
                    Task { await viewModel.addResultToWishlist() }
                } label: {
                    Label("Add To Wishlist", systemImage: "heart")
                }
                .buttonStyle(.borderedProminent)
            }
            Button {
                Task { await viewModel.saveResultToDiscovery() }
            } label: {
                Label("Save For Later", systemImage: "clock")
            }
            .buttonStyle(.bordered)
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

private struct ScanLoadingView: View {
    let progress: ScanProgress
    @State private var isAnimating = false

    var body: some View {
        DejaGroovePanel {
            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(DejaGrooveStyle.ink)
                        .frame(width: 132, height: 132)
                        .shadow(color: .black.opacity(0.22), radius: 18, y: 10)

                    ForEach(0..<5, id: \.self) { index in
                        Circle()
                            .stroke(.white.opacity(0.10), lineWidth: 1)
                            .frame(width: 42 + CGFloat(index * 18), height: 42 + CGFloat(index * 18))
                    }

                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [DejaGrooveStyle.blue, DejaGrooveStyle.coral],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing))
                        .frame(width: 40, height: 40)

                    Rectangle()
                        .fill(.white.opacity(0.72))
                        .frame(width: 4, height: 62)
                        .offset(y: -34)
                        .rotationEffect(.degrees(isAnimating ? 360 : 0))
                }
                .rotationEffect(.degrees(isAnimating ? 360 : 0))
                .animation(.linear(duration: 1.4).repeatForever(autoreverses: false), value: isAnimating)
                .onAppear { isAnimating = true }

                VStack(spacing: 6) {
                    Text(progress.title)
                        .font(.headline)
                    Text(progress.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
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
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(statusColor.opacity(0.12), in: Capsule())
            }
            if let album = response.album {
                Button {
                    onShowDetails(album)
                } label: {
                    ScanAlbumSummary(album: album)
                }
                .buttonStyle(.plain)
            }
            if let timings = response.timings {
                ScanTimingSummary(timings: timings)
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
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(candidate.artist) - \(candidate.title)")
                                    .font(.subheadline.bold())
                                Text(candidateSubtitle(candidate))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
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
                .buttonStyle(.borderedProminent)
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
        case "wishlist_match":
            return "WISHLIST MATCH"
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
        case "wishlist_match":
            return DejaGrooveStyle.blue
        case "ambiguous":
            return .orange
        default:
            return .secondary
        }
    }

    private func candidateSubtitle(_ candidate: Album) -> String {
        [
            candidate.releaseYear.map(String.init) ?? candidate.year.map(String.init),
            candidate.label,
            candidate.catalogNumber,
            candidate.format,
            candidate.country,
            candidate.discogsReleaseId.map { "Discogs \($0)" }
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: " • ")
    }
}

private struct ScanTimingSummary: View {
    let timings: ScanTimings

    var body: some View {
        Label(summary, systemImage: timings.enrichmentTimedOut ? "clock.badge.exclamationmark" : "clock")
            .font(.caption)
            .foregroundStyle(timings.enrichmentTimedOut ? .orange : .secondary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var summary: String {
        let timeout = timings.enrichmentTimedOut ? " • metadata timed out" : ""
        let appTiming = timings.clientElapsedMs.map { "App \(seconds($0)) • " } ?? ""
        return "\(appTiming)server \(seconds(timings.totalMs)) • upload \(seconds(timings.imageReadMs)) • recognition \(seconds(timings.recognitionMs)) • metadata \(seconds(timings.enrichmentMs)) • \(bytes(timings.imageBytes))\(timeout)"
    }

    private func seconds(_ milliseconds: Int) -> String {
        String(format: "%.1fs", Double(milliseconds) / 1000)
    }

    private func bytes(_ value: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(value))
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

            if !album.listeningLinks.isEmpty {
                Section("Listen") {
                    ForEach(album.listeningLinks, id: \.url) { link in
                        if let url = URL(string: link.url) {
                            Link(link.provider, destination: url)
                        }
                    }
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
        .contentShape(Rectangle())
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

private extension ScanProgress {
    var title: String {
        switch self {
        case .uploading:
            return "Preparing cover"
        case .recognizing:
            return "Listening for the record"
        case .resolving:
            return "Locking in release"
        }
    }

    var detail: String {
        switch self {
        case .uploading:
            return "Preparing the cover image for a clean match."
        case .recognizing:
            return "Matching the cover artwork and visible text."
        case .resolving:
            return "Applying the selected release to the scan result."
        }
    }
}
#endif
