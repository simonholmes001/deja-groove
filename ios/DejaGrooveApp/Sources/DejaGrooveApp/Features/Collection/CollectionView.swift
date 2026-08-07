import SwiftUI

#if os(iOS)
public struct CollectionView: View {
    @StateObject private var viewModel: CollectionViewModel
    @State private var isManagingCollections = false

    public init(viewModel: CollectionViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        NavigationStack {
            List {
                filters

                Section {
                    ForEach(viewModel.visibleRecords, id: \.id) { record in
                        NavigationLink {
                            AlbumDetailView(record: record, viewModel: viewModel)
                        } label: {
                            AlbumRow(record: record, collections: viewModel.collections(containing: record.id))
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task { await viewModel.deleteRecord(id: record.id) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }

                    if !viewModel.isLoading && viewModel.visibleRecords.isEmpty {
                        ContentUnavailableView("No Albums", systemImage: "square.stack", description: Text("Adjust the filters or scan albums into My Crate."))
                    }
                }
            }
            .overlay {
                if viewModel.isLoading { ProgressView("Loading...") }
                if let error = viewModel.errorMessage { Text(error).foregroundStyle(.red) }
            }
            .searchable(text: $viewModel.search)
            .navigationTitle("My Crate")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isManagingCollections = true
                    } label: {
                        Label("Collections", systemImage: "folder.badge.gearshape")
                    }
                }
            }
            .sheet(isPresented: $isManagingCollections) {
                ManageCollectionsView(viewModel: viewModel)
            }
            .refreshable { await viewModel.load() }
            .task { await viewModel.load() }
            .onSubmit(of: .search) { Task { await viewModel.load() } }
        }
    }

    private var filters: some View {
        Section {
            Picker("Collection", selection: collectionSelection) {
                Text("All My Crate").tag(UUID?.none)
                ForEach(viewModel.crateCollections) { collection in
                    Text(collection.name).tag(Optional(collection.id))
                }
            }

            Picker("Artist", selection: $viewModel.selectedArtist) {
                Text("All Artists").tag("")
                ForEach(viewModel.availableArtists, id: \.self) { artist in
                    Text(artist).tag(artist)
                }
            }

            Picker("Format", selection: $viewModel.selectedFormat) {
                Text("All Formats").tag("")
                ForEach(viewModel.availableFormats, id: \.self) { format in
                    Text(format).tag(format)
                }
            }
        }
    }

    private var collectionSelection: Binding<UUID?> {
        Binding(
            get: { viewModel.selectedCollectionId },
            set: { viewModel.selectedCollectionId = $0 })
    }
}

private struct AlbumRow: View {
    let record: CollectionRecord
    let collections: [CrateCollection]

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AlbumArtwork(urlString: record.album.thumbnailUrl ?? record.album.coverImageUrl, size: 56)

            VStack(alignment: .leading, spacing: 4) {
                Text(record.album.artist)
                    .font(.headline)
                Text(record.album.title)
                    .font(.subheadline)
                HStack(spacing: 8) {
                    if let firstRelease = record.album.firstReleaseDate ?? record.album.firstReleaseYear.map(String.init) ?? record.album.releaseDate ?? record.album.releaseYear.map(String.init) ?? record.album.year.map(String.init) {
                        Label(firstRelease, systemImage: "calendar")
                    }
                    if let format = record.album.format, !format.isEmpty {
                        Label(format, systemImage: "record.circle")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if !collections.isEmpty {
                    Text(collections.map(\.name).joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
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

private struct AlbumDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let record: CollectionRecord
    @ObservedObject var viewModel: CollectionViewModel

    var body: some View {
        List {
            if record.album.coverImageUrl != nil || record.album.thumbnailUrl != nil {
                Section {
                    HStack {
                        Spacer()
                        AlbumArtwork(urlString: record.album.coverImageUrl ?? record.album.thumbnailUrl, size: 220)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
            }

            Section("Album") {
                detail("Artist", record.album.artist)
                detail("Title", record.album.title)
                detail("First Release Date", record.album.firstReleaseDate ?? record.album.firstReleaseYear.map(String.init) ?? record.album.releaseDate ?? record.album.releaseYear.map(String.init) ?? record.album.year.map(String.init))
                detail("Discogs Release Date", record.album.releaseDate ?? record.album.releaseYear.map(String.init))
                detail("Format", record.album.format)
                detail("Label", record.album.label)
                detail("Catalog Number", record.album.catalogNumber)
                detail("Country", record.album.country)
                detail("Barcode", record.album.barcode)
                detail("MusicBrainz ID", record.album.mbid)
                detail("Discogs Release", record.album.discogsReleaseId)
                detail("Discogs Master", record.album.discogsMasterId)
                detail("Discogs Quality", record.album.discogsDataQuality)
                detail("Discogs API Resource", record.album.discogsResourceUrl)
                if let discogsUrl = record.album.discogsUrl, let url = URL(string: discogsUrl) {
                    Link("Open In Discogs", destination: url)
                }
            }

            if let notes = record.notes, !notes.isEmpty {
                Section("My Notes") {
                    Text(notes)
                }
            }

            if let releaseNotes = record.album.releaseNotes, !releaseNotes.isEmpty {
                Section("Release Notes") {
                    Text(releaseNotes)
                }
            }

            if !record.album.genres.isEmpty || !record.album.styles.isEmpty {
                Section("Genre & Style") {
                    detail("Genres", record.album.genres.joined(separator: ", "))
                    detail("Styles", record.album.styles.joined(separator: ", "))
                }
            }

            if !record.album.companies.isEmpty {
                Section("Companies") {
                    ForEach(record.album.companies, id: \.self) { company in
                        Text(company)
                    }
                }
            }

            if !record.album.tracklist.isEmpty {
                Section("Tracklist") {
                    ForEach(Array(record.album.tracklist.enumerated()), id: \.offset) { _, track in
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

            if !record.album.identifiers.isEmpty {
                Section("Identifiers") {
                    ForEach(Array(record.album.identifiers.enumerated()), id: \.offset) { _, identifier in
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

            if let backCoverText = record.album.backCoverText, !backCoverText.isEmpty {
                Section("Back Cover") {
                    Text(backCoverText)
                }
            }

            if record.album.backCoverImageUrl != nil {
                Section("Back Cover Image") {
                    HStack {
                        Spacer()
                        AlbumArtwork(urlString: record.album.backCoverImageUrl, size: 220)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
            }

            Section("Collections") {
                if viewModel.crateCollections.isEmpty {
                    Text("Create collections from My Crate to organize this album.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.crateCollections) { collection in
                        let isIncluded = viewModel.isRecord(record.id, in: collection.id)
                        Button {
                            Task {
                                await viewModel.setRecord(record.id, in: collection.id, isIncluded: !isIncluded)
                            }
                        } label: {
                            HStack {
                                Text(collection.name)
                                Spacer()
                                Image(systemName: isIncluded ? "checkmark.circle.fill" : "circle")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(record.album.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    Task {
                        await viewModel.deleteRecord(id: record.id)
                        dismiss()
                    }
                } label: {
                    Label("Delete", systemImage: "trash")
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

private struct ManageCollectionsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: CollectionViewModel
    @State private var newCollectionName = ""
    @State private var draftNames: [UUID: String] = [:]

    var body: some View {
        NavigationStack {
            List {
                Section("New Collection") {
                    HStack {
                        TextField("Collection name", text: $newCollectionName)
                            .textInputAutocapitalization(.words)
                        Button {
                            let name = newCollectionName
                            newCollectionName = ""
                            Task { await viewModel.createCollection(named: name) }
                        } label: {
                            Label("Add", systemImage: "plus.circle.fill")
                        }
                        .disabled(newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                Section("Collections") {
                    if viewModel.crateCollections.isEmpty {
                        Text("No collections yet.")
                            .foregroundStyle(.secondary)
                    }

                    ForEach(viewModel.crateCollections) { collection in
                        HStack {
                            TextField("Collection name", text: binding(for: collection))
                                .textInputAutocapitalization(.words)
                            Text("\(collection.recordIds.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button {
                                Task {
                                    await viewModel.renameCollection(
                                        id: collection.id,
                                        name: draftNames[collection.id] ?? collection.name)
                                }
                            } label: {
                                Image(systemName: "checkmark")
                            }
                            Button(role: .destructive) {
                                Task { await viewModel.deleteCollection(id: collection.id) }
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Collections")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                draftNames = Dictionary(uniqueKeysWithValues: viewModel.crateCollections.map { ($0.id, $0.name) })
            }
        }
    }

    private func binding(for collection: CrateCollection) -> Binding<String> {
        Binding(
            get: { draftNames[collection.id] ?? collection.name },
            set: { draftNames[collection.id] = $0 })
    }
}
#endif
