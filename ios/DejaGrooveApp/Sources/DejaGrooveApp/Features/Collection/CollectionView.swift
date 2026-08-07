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
    @State private var isEditing = false

    var body: some View {
        List {
            if currentRecord.album.coverImageUrl != nil || currentRecord.album.thumbnailUrl != nil {
                Section {
                    HStack {
                        Spacer()
                        AlbumArtwork(urlString: currentRecord.album.coverImageUrl ?? currentRecord.album.thumbnailUrl, size: 220)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
            }

            Section("Album") {
                detail("Artist", currentRecord.album.artist)
                detail("Title", currentRecord.album.title)
                detail("First Release Date", currentRecord.album.firstReleaseDate ?? currentRecord.album.firstReleaseYear.map(String.init) ?? currentRecord.album.releaseDate ?? currentRecord.album.releaseYear.map(String.init) ?? currentRecord.album.year.map(String.init))
                detail("Discogs Release Date", currentRecord.album.releaseDate ?? currentRecord.album.releaseYear.map(String.init))
                detail("Format", currentRecord.album.format)
                detail("Label", currentRecord.album.label)
                detail("Catalog Number", currentRecord.album.catalogNumber)
                detail("Country", currentRecord.album.country)
                detail("Barcode", currentRecord.album.barcode)
                detail("MusicBrainz ID", currentRecord.album.mbid)
                detail("Discogs Release", currentRecord.album.discogsReleaseId)
                detail("Discogs Master", currentRecord.album.discogsMasterId)
                detail("Discogs Quality", currentRecord.album.discogsDataQuality)
                detail("Discogs API Resource", currentRecord.album.discogsResourceUrl)
                if let discogsUrl = currentRecord.album.discogsUrl, let url = URL(string: discogsUrl) {
                    Link("Open In Discogs", destination: url)
                }
            }

            if let notes = currentRecord.notes, !notes.isEmpty {
                Section("My Notes") {
                    Text(notes)
                }
            }

            if let releaseNotes = currentRecord.album.releaseNotes, !releaseNotes.isEmpty {
                Section("Release Notes") {
                    Text(releaseNotes)
                }
            }

            if !currentRecord.album.genres.isEmpty || !currentRecord.album.styles.isEmpty {
                Section("Genre & Style") {
                    detail("Genres", currentRecord.album.genres.joined(separator: ", "))
                    detail("Styles", currentRecord.album.styles.joined(separator: ", "))
                }
            }

            if !currentRecord.album.companies.isEmpty {
                Section("Companies") {
                    ForEach(currentRecord.album.companies, id: \.self) { company in
                        Text(company)
                    }
                }
            }

            if !currentRecord.album.tracklist.isEmpty {
                Section("Tracklist") {
                    ForEach(Array(currentRecord.album.tracklist.enumerated()), id: \.offset) { _, track in
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

            if !currentRecord.album.identifiers.isEmpty {
                Section("Identifiers") {
                    ForEach(Array(currentRecord.album.identifiers.enumerated()), id: \.offset) { _, identifier in
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

            if let backCoverText = currentRecord.album.backCoverText, !backCoverText.isEmpty {
                Section("Back Cover") {
                    Text(backCoverText)
                }
            }

            if currentRecord.album.backCoverImageUrl != nil {
                Section("Back Cover Image") {
                    HStack {
                        Spacer()
                        AlbumArtwork(urlString: currentRecord.album.backCoverImageUrl, size: 220)
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
        .navigationTitle(currentRecord.album.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    isEditing = true
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
            }
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
        .sheet(isPresented: $isEditing) {
            AlbumEditView(record: currentRecord) { album, notes in
                Task {
                    await viewModel.updateRecord(id: record.id, album: album, notes: notes)
                    isEditing = false
                }
            }
        }
    }

    private var currentRecord: CollectionRecord {
        viewModel.record(id: record.id) ?? record
    }

    @ViewBuilder
    private func detail(_ label: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            LabeledContent(label, value: value)
        }
    }
}

private struct AlbumEditView: View {
    @Environment(\.dismiss) private var dismiss
    let record: CollectionRecord
    let onSave: (Album, String?) -> Void

    @State private var artist: String
    @State private var title: String
    @State private var firstReleaseDate: String
    @State private var firstReleaseYear: String
    @State private var releaseDate: String
    @State private var releaseYear: String
    @State private var format: String
    @State private var label: String
    @State private var catalogNumber: String
    @State private var country: String
    @State private var barcode: String
    @State private var coverImageUrl: String
    @State private var thumbnailUrl: String
    @State private var backCoverImageUrl: String
    @State private var notes: String
    @State private var releaseNotes: String
    @State private var backCoverText: String
    @State private var genres: String
    @State private var styles: String

    init(record: CollectionRecord, onSave: @escaping (Album, String?) -> Void) {
        self.record = record
        self.onSave = onSave
        _artist = State(initialValue: record.album.artist)
        _title = State(initialValue: record.album.title)
        _firstReleaseDate = State(initialValue: record.album.firstReleaseDate ?? "")
        _firstReleaseYear = State(initialValue: record.album.firstReleaseYear.map(String.init) ?? "")
        _releaseDate = State(initialValue: record.album.releaseDate ?? "")
        _releaseYear = State(initialValue: record.album.releaseYear.map(String.init) ?? "")
        _format = State(initialValue: record.album.format ?? "")
        _label = State(initialValue: record.album.label ?? "")
        _catalogNumber = State(initialValue: record.album.catalogNumber ?? "")
        _country = State(initialValue: record.album.country ?? "")
        _barcode = State(initialValue: record.album.barcode ?? "")
        _coverImageUrl = State(initialValue: record.album.coverImageUrl ?? "")
        _thumbnailUrl = State(initialValue: record.album.thumbnailUrl ?? "")
        _backCoverImageUrl = State(initialValue: record.album.backCoverImageUrl ?? "")
        _notes = State(initialValue: record.notes ?? "")
        _releaseNotes = State(initialValue: record.album.releaseNotes ?? "")
        _backCoverText = State(initialValue: record.album.backCoverText ?? "")
        _genres = State(initialValue: record.album.genres.joined(separator: ", "))
        _styles = State(initialValue: record.album.styles.joined(separator: ", "))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Required") {
                    TextField("Artist", text: $artist)
                        .textInputAutocapitalization(.words)
                    TextField("Title", text: $title)
                        .textInputAutocapitalization(.words)
                }

                Section("Release") {
                    TextField("First Release Date", text: $firstReleaseDate)
                    TextField("First Release Year", text: $firstReleaseYear)
                        .keyboardType(.numberPad)
                    TextField("Discogs Release Date", text: $releaseDate)
                    TextField("Discogs Release Year", text: $releaseYear)
                        .keyboardType(.numberPad)
                    TextField("Format", text: $format)
                    TextField("Label", text: $label)
                    TextField("Catalog Number", text: $catalogNumber)
                    TextField("Country", text: $country)
                    TextField("Barcode", text: $barcode)
                }

                Section("Classification") {
                    TextField("Genres", text: $genres)
                    TextField("Styles", text: $styles)
                }

                Section("Images") {
                    TextField("Front Cover URL", text: $coverImageUrl)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    TextField("Thumbnail URL", text: $thumbnailUrl)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    TextField("Back Cover URL", text: $backCoverImageUrl)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                }

                Section("Notes") {
                    TextField("My Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                    TextField("Release Notes", text: $releaseNotes, axis: .vertical)
                        .lineLimit(3...8)
                    TextField("Back Cover Text", text: $backCoverText, axis: .vertical)
                        .lineLimit(3...8)
                }
            }
            .navigationTitle("Edit Album")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(updatedAlbum, clean(notes))
                    }
                    .disabled(clean(artist) == nil || clean(title) == nil)
                }
            }
        }
    }

    private var updatedAlbum: Album {
        Album(
            mbid: record.album.mbid,
            discogsReleaseId: record.album.discogsReleaseId,
            discogsMasterId: record.album.discogsMasterId,
            discogsUrl: record.album.discogsUrl,
            discogsResourceUrl: record.album.discogsResourceUrl,
            title: clean(title) ?? record.album.title,
            artist: clean(artist) ?? record.album.artist,
            year: parseYear(firstReleaseYear) ?? parseYear(releaseYear) ?? record.album.year,
            format: clean(format),
            firstReleaseYear: parseYear(firstReleaseYear),
            releaseYear: parseYear(releaseYear),
            firstReleaseDate: clean(firstReleaseDate),
            releaseDate: clean(releaseDate),
            label: clean(label),
            catalogNumber: clean(catalogNumber),
            country: clean(country),
            barcode: clean(barcode),
            coverImageUrl: clean(coverImageUrl),
            thumbnailUrl: clean(thumbnailUrl),
            backCoverImageUrl: clean(backCoverImageUrl),
            backCoverText: clean(backCoverText),
            releaseNotes: clean(releaseNotes),
            genres: cleanList(genres),
            styles: cleanList(styles),
            companies: record.album.companies,
            tracklist: record.album.tracklist,
            identifiers: record.album.identifiers,
            discogsDataQuality: record.album.discogsDataQuality)
    }

    private func clean(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func cleanList(_ value: String) -> [String] {
        value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func parseYear(_ value: String) -> Int? {
        guard let cleanValue = clean(value), cleanValue.count == 4 else { return nil }
        return Int(cleanValue)
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
