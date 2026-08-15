import SwiftUI

#if os(iOS)
public struct DiscoveryView: View {
    @ObservedObject private var viewModel: DiscoveryViewModel
    @State private var selectedAlbum: Album?
    @State private var selectedTrack: AudioDiscoveryTrack?
    @State private var isConfirmingClearHistory = false

    public init(viewModel: DiscoveryViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            DejaGrooveScreen {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        listeningActivity
                        currentMatch
                        history
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 110)
                }
            }
            .searchable(text: $viewModel.search)
            .navigationTitle("Discover")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await viewModel.load() }
            .task {
                await viewModel.prepareMusicAccess()
                await viewModel.load()
            }
            .sheet(item: selectedAlbumBinding) { album in
                NavigationStack {
                    DiscoveryAlbumDetailView(album: album.album)
                }
            }
            .sheet(item: selectedTrackBinding) { track in
                NavigationStack {
                    DiscoveryTrackDetailView(track: track.track)
                }
            }
            .confirmationDialog("Clear Discovery History?", isPresented: $isConfirmingClearHistory, titleVisibility: .visible) {
                Button("Clear History", role: .destructive) {
                    Task { await viewModel.clearAllHistory() }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private var header: some View {
        DejaGroovePanel {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 42))
                        .foregroundStyle(DejaGrooveStyle.blue)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Discover")
                            .font(.system(size: 30, weight: .black, design: .rounded))
                        Text("Identify audio and save wanted albums.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Button {
                    Task { await viewModel.identifyPlayingAudio() }
                } label: {
                    Label(viewModel.isLoading ? "Listening" : "Identify Playing Song", systemImage: "waveform")
                }
                .disabled(viewModel.isLoading)
                .buttonStyle(DejaGroovePrimaryButtonStyle())

                if let message = viewModel.message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var listeningActivity: some View {
        if viewModel.shouldShowListeningActivity {
            DejaGroovePanel {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 14) {
                        ListeningWaveformView()
                            .frame(width: 84, height: 48)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Listening...")
                                .font(.headline)
                            Text("Identifying the track and finding likely album releases.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                    }

                    ProgressView()
                        .progressViewStyle(.linear)
                        .tint(DejaGrooveStyle.blue)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Listening and identifying the current song")
            }
        }
    }

    @ViewBuilder
    private var currentMatch: some View {
        if let track = viewModel.track {
            DejaGroovePanel {
                VStack(alignment: .leading, spacing: 12) {
                    Button {
                        selectedTrack = track
                    } label: {
                        Label("\(track.artist) - \(track.title)", systemImage: "music.note")
                            .font(.headline)
                    }
                    .buttonStyle(.plain)

                    if viewModel.candidates.isEmpty {
                        Text("No album candidates.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(viewModel.candidateResults.enumerated()), id: \.offset) { _, result in
                            HStack {
                                Button {
                                    selectedAlbum = result.album
                                } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(result.album.artist)
                                            .font(.subheadline.bold())
                                        Text(result.album.title)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                                Spacer()
                                Text(statusLabel(for: result.status))
                                    .font(.caption2.bold())
                                    .foregroundStyle(statusColor(for: result.status))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(statusColor(for: result.status).opacity(0.12), in: Capsule())
                                if result.status != "owned" && result.status != "wishlist_match" {
                                    Button {
                                        Task { await viewModel.saveCandidateToWishlist(result.album) }
                                    } label: {
                                        Image(systemName: "heart")
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func statusLabel(for status: String) -> String {
        switch status {
        case "safe_to_buy":
            return "SAFE"
        case "owned":
            return "IN CRATE"
        case "wishlist_match":
            return "WISHLIST"
        case "discovery_match":
            return "DISCOVERED"
        default:
            return status.replacingOccurrences(of: "_", with: " ").uppercased()
        }
    }

    private func statusColor(for status: String) -> Color {
        switch status {
        case "safe_to_buy":
            return .green
        case "owned":
            return .red
        case "wishlist_match":
            return DejaGrooveStyle.blue
        case "discovery_match":
            return .purple
        default:
            return .secondary
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("History")
                    .font(.title3.bold())
                Spacer()
                Text("\(viewModel.visibleHistory.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if !viewModel.history.isEmpty {
                    Button(role: .destructive) {
                        isConfirmingClearHistory = true
                    } label: {
                        Image(systemName: "trash.slash")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Clear Discovery History")
                }
            }
            .padding(.horizontal, 4)

            if viewModel.visibleHistory.isEmpty {
                DejaGroovePanel {
                    Text("No discoveries yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(viewModel.visibleHistory) { entry in
                    DejaGroovePanel {
                        HStack(alignment: .top, spacing: 12) {
                            Button {
                                if let album = entry.album {
                                    selectedAlbum = album
                                } else if let track = entry.track {
                                    selectedTrack = track
                                }
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: entry.source == "audio" ? "waveform" : "camera")
                                        .font(.title3)
                                        .foregroundStyle(DejaGrooveStyle.blue)
                                        .frame(width: 28)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(entry.album?.artist ?? entry.track?.artist ?? entry.source.capitalized)
                                            .font(.subheadline.bold())
                                        Text(entry.album?.title ?? entry.track?.title ?? entry.createdAt)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                }
                            }
                            .buttonStyle(.plain)
                            Spacer()
                            Button(role: .destructive) {
                                Task { await viewModel.deleteDiscovery(id: entry.id) }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
        }
    }

    private var selectedAlbumBinding: Binding<IdentifiedAlbum?> {
        Binding(
            get: { selectedAlbum.map(IdentifiedAlbum.init(album:)) },
            set: { value in
                if value == nil {
                    selectedAlbum = nil
                }
            })
    }

    private var selectedTrackBinding: Binding<IdentifiedTrack?> {
        Binding(
            get: { selectedTrack.map(IdentifiedTrack.init(track:)) },
            set: { value in
                if value == nil {
                    selectedTrack = nil
                }
            })
    }
}

private struct IdentifiedAlbum: Identifiable {
    let album: Album

    var id: String {
        [
            album.discogsReleaseId,
            album.mbid,
            album.artist,
            album.title,
            album.releaseDate,
            album.year.map(String.init)
        ]
        .compactMap { $0 }
        .joined(separator: "|")
    }
}

private struct IdentifiedTrack: Identifiable {
    let track: AudioDiscoveryTrack

    var id: String {
        [
            track.shazamId,
            track.appleMusicId,
            track.artist,
            track.title,
            track.matchedAt
        ]
        .compactMap { $0 }
        .joined(separator: "|")
    }
}

private struct DiscoveryAlbumDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let album: Album

    var body: some View {
        List {
            if album.coverImageUrl != nil || album.thumbnailUrl != nil {
                Section {
                    HStack {
                        Spacer()
                        DiscoveryArtwork(urlString: album.coverImageUrl ?? album.thumbnailUrl, size: 220)
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

            if !album.listeningLinks.isEmpty {
                Section("Listen") {
                    ForEach(album.listeningLinks, id: \.url) { link in
                        if let url = URL(string: link.url) {
                            Link(link.provider, destination: url)
                        }
                    }
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
        }
    }

    @ViewBuilder
    private func detail(_ label: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            LabeledContent(label, value: value)
        }
    }
}

private struct DiscoveryTrackDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let track: AudioDiscoveryTrack

    var body: some View {
        List {
            if let artworkUrl = track.artworkUrl {
                Section {
                    HStack {
                        Spacer()
                        DiscoveryArtwork(urlString: artworkUrl, size: 220)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
            }

            Section("Track") {
                LabeledContent("Artist", value: track.artist)
                LabeledContent("Title", value: track.title)
                detail("Genre", track.genre)
                detail("Shazam ID", track.shazamId)
                detail("Apple Music ID", track.appleMusicId)
                LabeledContent("Matched", value: track.matchedAt)
            }

            Section("Listen") {
                Link("Apple Music", destination: track.appleMusicSearchURL)
            }
        }
        .navigationTitle(track.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") { dismiss() }
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

private struct DiscoveryArtwork: View {
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

private struct ListeningWaveformView: View {
    @State private var isAnimating = false

    private let heights: [CGFloat] = [0.32, 0.72, 0.46, 0.9, 0.58]

    var body: some View {
        HStack(alignment: .center, spacing: 7) {
            ForEach(Array(heights.enumerated()), id: \.offset) { index, height in
                RoundedRectangle(cornerRadius: 3)
                    .fill(index.isMultiple(of: 2) ? DejaGrooveStyle.blue : DejaGrooveStyle.coral)
                    .frame(width: 9, height: 44 * (isAnimating ? height : max(0.2, 1 - height)))
                    .animation(
                        .easeInOut(duration: 0.48 + Double(index) * 0.06)
                            .repeatForever(autoreverses: true),
                        value: isAnimating)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { isAnimating = true }
    }
}
#endif
