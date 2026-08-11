import SwiftUI

#if os(iOS)
public struct DiscoveryView: View {
    @ObservedObject private var viewModel: DiscoveryViewModel

    public init(viewModel: DiscoveryViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            DejaGrooveScreen {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
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
    private var currentMatch: some View {
        if let track = viewModel.track {
            DejaGroovePanel {
                VStack(alignment: .leading, spacing: 12) {
                    Label("\(track.artist) - \(track.title)", systemImage: "music.note")
                        .font(.headline)

                    if viewModel.candidates.isEmpty {
                        Text("No album candidates.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(viewModel.candidates.enumerated()), id: \.offset) { _, album in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(album.artist)
                                        .font(.subheadline.bold())
                                    Text(album.title)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button {
                                    Task { await viewModel.saveCandidateToWishlist(album) }
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

    private var history: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("History")
                    .font(.title3.bold())
                Spacer()
                Text("\(viewModel.visibleHistory.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
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
}
#endif
