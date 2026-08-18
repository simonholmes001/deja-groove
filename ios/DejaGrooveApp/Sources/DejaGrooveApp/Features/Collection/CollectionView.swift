import SwiftUI

#if os(iOS)
public struct CollectionView: View {
    @ObservedObject private var viewModel: CollectionViewModel
    @State private var editingRecord: CollectionRecord?
    @State private var assigningCollectionsRecord: CollectionRecord?
    @State private var selectedRecordId: UUID?

    public init(viewModel: CollectionViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            DejaGrooveScreen {
                ScrollViewReader { scrollProxy in
                    ZStack(alignment: .trailing) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 18) {
                                crateHeader
                                filters
                                albumList
                            }
                            .padding(.horizontal, 20)
                            .padding(.trailing, viewModel.alphabetIndexSections.count > 1 ? 18 : 0)
                            .padding(.top, 20)
                            .padding(.bottom, 110)
                        }

                        if viewModel.alphabetIndexSections.count > 1 {
                            AlphabetIndexRail(sections: viewModel.alphabetIndexSections) { sectionId in
                                withAnimation(.snappy) {
                                    scrollProxy.scrollTo(sectionId, anchor: .top)
                                }
                            }
                            .padding(.trailing, 4)
                        }
                    }
                }
            }
            .overlay {
                if viewModel.isLoading {
                    DejaGrooveLoadingOverlay(label: "Loading crate")
                }
            }
            .safeAreaInset(edge: .top) {
                if let error = viewModel.errorMessage {
                    DejaGrooveErrorBanner(message: error)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                }
            }
            .searchable(text: $viewModel.search)
            .navigationTitle("My Crate")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await viewModel.load() }
            .task { await viewModel.load() }
            .onSubmit(of: .search) { Task { await viewModel.load() } }
            .navigationDestination(item: $selectedRecordId) { recordId in
                if let record = viewModel.record(id: recordId) {
                    AlbumDetailView(record: record, viewModel: viewModel)
                }
            }
            .sheet(item: $editingRecord) { record in
                AlbumEditView(record: viewModel.record(id: record.id) ?? record) { album, notes in
                    Task {
                        await viewModel.updateRecord(id: record.id, album: album, notes: notes)
                        editingRecord = nil
                    }
                }
            }
            .sheet(item: $assigningCollectionsRecord) { record in
                CollectionAssignmentView(record: viewModel.record(id: record.id) ?? record, viewModel: viewModel)
            }
        }
    }

    private var crateHeader: some View {
        DejaGroovePanel {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [DejaGrooveStyle.blue, DejaGrooveStyle.coral],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing))
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 64, height: 64)

                VStack(alignment: .leading, spacing: 4) {
                    Text("My Crate")
                        .font(.system(size: 30, weight: .black, design: .rounded))
                    Text(crateSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    private var filters: some View {
        DejaGroovePanel {
            VStack(alignment: .leading, spacing: 14) {
                Text("Filter")
                    .font(.headline)

                VStack(spacing: 10) {
                    filterMenu(title: "Collection", systemImage: "folder", value: selectedCollectionName) {
                        Picker("Collection", selection: collectionSelection) {
                            Text("All").tag(UUID?.none)
                            ForEach(viewModel.crateCollections) { collection in
                                Text(collection.name).tag(Optional(collection.id))
                            }
                        }
                    }

                    filterMenu(title: "Artist", systemImage: "music.mic", value: viewModel.selectedArtist.isEmpty ? "All Artists" : viewModel.selectedArtist) {
                        Picker("Artist", selection: $viewModel.selectedArtist) {
                            Text("All Artists").tag("")
                            ForEach(viewModel.availableArtists, id: \.self) { artist in
                                Text(artist).tag(artist)
                            }
                        }
                    }

                    filterMenu(title: "Format", systemImage: "record.circle", value: viewModel.selectedFormat.isEmpty ? "All Formats" : viewModel.selectedFormat) {
                        Picker("Format", selection: $viewModel.selectedFormat) {
                            Text("All Formats").tag("")
                            ForEach(viewModel.availableFormats, id: \.self) { format in
                                Text(format).tag(format)
                            }
                        }
                    }
                }
            }
        }
    }

    private var albumList: some View {
        VStack(alignment: .leading, spacing: 12) {
            DejaGrooveSectionHeader(
                title: "Albums",
                detail: "\(viewModel.visibleRecords.count) shown")

            if !viewModel.isLoading && viewModel.visibleRecords.isEmpty {
                DejaGrooveEmptyState(
                    title: "No Albums",
                    systemImage: "square.stack.3d.up",
                    detail: "Adjust the filters or scan albums into My Crate.")
            } else {
                ForEach(viewModel.alphabetIndexSections) { section in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(section.letter)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .id(section.id)

                        ForEach(section.records, id: \.id) { record in
                            SwipeActionCard(actionCount: 3) {
                                Button {
                                    selectedRecordId = record.id
                                } label: {
                                    DejaGroovePanel {
                                        AlbumRow(record: record, collections: viewModel.collections(containing: record.id))
                                    }
                                }
                                .buttonStyle(.plain)
                            } actions: {
                                SwipeActionButton(title: "Edit", systemImage: "pencil", color: DejaGrooveStyle.blue) {
                                    editingRecord = record
                                }
                                SwipeActionButton(title: "Collection", systemImage: "folder", color: DejaGrooveStyle.ink) {
                                    assigningCollectionsRecord = record
                                }
                                SwipeActionButton(title: "Delete", systemImage: "trash", color: DejaGrooveStyle.coral) {
                                    Task { await viewModel.deleteRecord(id: record.id) }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var crateSubtitle: String {
        let albumCount = albumCountLabel(viewModel.records.count)
        let collectionCount = viewModel.crateCollections.count == 1 ? "1 collection" : "\(viewModel.crateCollections.count) collections"
        return "\(albumCount) across \(collectionCount)"
    }

    private var selectedCollectionName: String {
        guard let selectedCollectionId = viewModel.selectedCollectionId,
              let collection = viewModel.crateCollections.first(where: { $0.id == selectedCollectionId }) else {
            return "All"
        }
        return collection.name
    }

    private func filterMenu<Content: View>(
        title: String,
        systemImage: String,
        value: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(DejaGrooveStyle.blue)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }

            Spacer()

            content()
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(DejaGrooveStyle.blue)
        }
        .padding(12)
        .background(.white.opacity(0.56), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var collectionSelection: Binding<UUID?> {
        Binding(
            get: { viewModel.selectedCollectionId },
            set: { viewModel.selectedCollectionId = $0 })
    }
}

private struct DejaGrooveSectionHeader: View {
    let title: String
    let detail: String?

    init(title: String, detail: String? = nil) {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.title3.bold())
            Spacer()
            if let detail {
                Text(detail)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.62), in: Capsule())
            }
        }
        .padding(.horizontal, 4)
    }
}

private struct AlphabetIndexRail: View {
    let sections: [CollectionAlphabetSection]
    let onSelect: (String) -> Void

    var body: some View {
        VStack(spacing: 2) {
            ForEach(sections) { section in
                Button {
                    onSelect(section.id)
                } label: {
                    Text(section.letter)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(DejaGrooveStyle.blue)
                        .frame(width: 22, height: 18)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Jump to \(section.letter)")
            }
        }
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Album alphabet index")
    }
}

private struct DejaGrooveEmptyState: View {
    let title: String
    let systemImage: String
    let detail: String

    var body: some View {
        DejaGroovePanel {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(DejaGrooveStyle.blue)
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct DejaGrooveLoadingOverlay: View {
    let label: String

    var body: some View {
        VStack(spacing: 10) {
            ProgressView()
                .tint(DejaGrooveStyle.blue)
            Text(label)
                .font(.footnote.weight(.semibold))
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.10), radius: 16, y: 8)
    }
}

private struct DejaGrooveErrorBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(DejaGrooveStyle.coral)
            Text(message)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(DejaGrooveStyle.ink)
            Spacer()
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DejaGrooveStyle.coral.opacity(0.25), lineWidth: 1)
        }
    }
}

private struct SwipeActionCard<Content: View, Actions: View>: View {
    private let actionWidth: CGFloat = 76
    private let maxOffset: CGFloat
    let content: Content
    let actions: Actions
    @State private var offset: CGFloat = 0
    @State private var dragStartOffset: CGFloat?

    init(
        actionCount: Int = 2,
        @ViewBuilder content: () -> Content,
        @ViewBuilder actions: () -> Actions
    ) {
        maxOffset = CGFloat(actionCount) * actionWidth
        self.content = content()
        self.actions = actions()
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: 8) {
                actions
            }
            .padding(.trailing, 2)
            .zIndex(2)

            content
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(DejaGrooveStyle.paper))
                .offset(x: offset)
                .zIndex(3)
                .highPriorityGesture(
                    DragGesture(minimumDistance: 16)
                        .onChanged { value in
                            guard abs(value.translation.width) > abs(value.translation.height) else { return }
                            if dragStartOffset == nil {
                                dragStartOffset = offset
                            }
                            offset = min(0, max(-maxOffset, (dragStartOffset ?? 0) + value.translation.width))
                        }
                        .onEnded { value in
                            guard abs(value.translation.width) > abs(value.translation.height) else { return }
                            let projectedOffset = (dragStartOffset ?? 0) + value.translation.width
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                offset = projectedOffset < -(maxOffset * 0.35) ? -maxOffset : 0
                            }
                            dragStartOffset = nil
                        })
        }
        .contentShape(Rectangle())
    }
}

private struct SwipeActionButton: View {
    let title: String
    let systemImage: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            VStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.headline.weight(.bold))
                Text(title)
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(width: 68, height: 74)
            .background(color, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct AlbumRow: View {
    let record: CollectionRecord
    let collections: [CrateCollection]

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            AlbumArtwork(urlString: record.album.thumbnailUrl ?? record.album.coverImageUrl, size: 68)

            VStack(alignment: .leading, spacing: 6) {
                Text(record.album.artist)
                    .font(.headline)
                    .lineLimit(1)
                Text(record.album.title)
                    .font(.subheadline)
                    .foregroundStyle(DejaGrooveStyle.ink)
                    .lineLimit(2)

                FlowLine(items: rowMetadata)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !collections.isEmpty {
                    Label(collections.map(\.name).joined(separator: ", "), systemImage: "folder.fill")
                        .font(.caption)
                        .foregroundStyle(DejaGrooveStyle.blue)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
        }
    }

    private var rowMetadata: [String] {
        [
            record.album.firstReleaseDate
                ?? record.album.firstReleaseYear.map(String.init)
                ?? record.album.releaseDate
                ?? record.album.releaseYear.map(String.init)
                ?? record.album.year.map(String.init),
            record.album.format,
            record.album.label
        ]
        .compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
    }
}

private struct FlowLine: View {
    let items: [String]

    var body: some View {
        Text(items.joined(separator: " - "))
            .lineLimit(2)
    }
}

public struct CollectionsView: View {
    @ObservedObject private var viewModel: CollectionViewModel
    @State private var newCollectionName = ""
    @State private var editingCollection: CrateCollection?
    @State private var selectedCollectionId: UUID?

    public init(viewModel: CollectionViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            DejaGrooveScreen {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        collectionsHeader
                        createCollectionPanel
                        collectionsList
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 110)
                }
            }
            .overlay {
                if viewModel.isLoading {
                    DejaGrooveLoadingOverlay(label: "Loading collections")
                }
            }
            .safeAreaInset(edge: .top) {
                if let error = viewModel.errorMessage {
                    DejaGrooveErrorBanner(message: error)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                }
            }
            .navigationTitle("Collections")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await viewModel.load() }
            .task { await viewModel.load() }
            .navigationDestination(item: $selectedCollectionId) { collectionId in
                if let collection = viewModel.crateCollections.first(where: { $0.id == collectionId }) {
                    CollectionDetailView(collection: collection, viewModel: viewModel)
                }
            }
            .sheet(item: $editingCollection) { collection in
                CollectionRenameView(collection: collection) { name in
                    Task {
                        await viewModel.renameCollection(id: collection.id, name: name)
                        editingCollection = nil
                    }
                }
            }
        }
    }

    private var collectionsHeader: some View {
        DejaGroovePanel {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [DejaGrooveStyle.blue, DejaGrooveStyle.coral],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing))
                    Image(systemName: "folder.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 64, height: 64)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Collections")
                        .font(.system(size: 30, weight: .black, design: .rounded))
                    Text(collectionsSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    private var createCollectionPanel: some View {
        DejaGroovePanel {
            VStack(alignment: .leading, spacing: 12) {
                Text("New Collection")
                    .font(.headline)
                HStack(spacing: 10) {
                    TextField("Collection name", text: $newCollectionName)
                        .textInputAutocapitalization(.words)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .background(.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    Button {
                        let name = newCollectionName
                        Task {
                            await viewModel.createCollection(named: name)
                            if viewModel.errorMessage == nil {
                                newCollectionName = ""
                            }
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.headline.weight(.bold))
                            .frame(width: 44, height: 44)
                    }
                    .foregroundStyle(.white)
                    .background(
                        DejaGrooveStyle.blue,
                        in: Circle())
                    .disabled(newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
                }
            }
        }
    }

    private var collectionsList: some View {
        VStack(alignment: .leading, spacing: 12) {
            DejaGrooveSectionHeader(
                title: "Your Collections",
                detail: "\(viewModel.crateCollections.count) total")

            if !viewModel.isLoading && viewModel.crateCollections.isEmpty {
                DejaGrooveEmptyState(
                    title: "No Collections",
                    systemImage: "folder.badge.plus",
                    detail: "Create collections to organize albums from My Crate.")
            } else {
                ForEach(viewModel.crateCollections) { collection in
                    SwipeActionCard {
                        Button {
                            selectedCollectionId = collection.id
                        } label: {
                            DejaGroovePanel {
                                CollectionRow(
                                    collection: collection,
                                    records: viewModel.records(in: collection))
                            }
                        }
                        .buttonStyle(.plain)
                    } actions: {
                        SwipeActionButton(title: "Edit", systemImage: "pencil", color: DejaGrooveStyle.blue) {
                            editingCollection = collection
                        }
                        SwipeActionButton(title: "Delete", systemImage: "trash", color: DejaGrooveStyle.coral) {
                            Task { await viewModel.deleteCollection(id: collection.id) }
                        }
                    }
                }
            }
        }
    }

    private var collectionsSubtitle: String {
        let albumCount = albumCountLabel(viewModel.records.count)
        let collectionCount = viewModel.crateCollections.count == 1 ? "1 collection" : "\(viewModel.crateCollections.count) collections"
        return "\(collectionCount) organizing \(albumCount)"
    }
}

private struct CollectionRenameView: View {
    @Environment(\.dismiss) private var dismiss
    let collection: CrateCollection
    let onSave: (String) -> Void
    @State private var draftName: String

    init(collection: CrateCollection, onSave: @escaping (String) -> Void) {
        self.collection = collection
        self.onSave = onSave
        _draftName = State(initialValue: collection.name)
    }

    var body: some View {
        NavigationStack {
            DejaGrooveScreen {
                VStack(alignment: .leading, spacing: 18) {
                    DejaGroovePanel {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Rename Collection")
                                .font(.title3.bold())
                            TextField("Collection name", text: $draftName)
                                .textInputAutocapitalization(.words)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 12)
                                .background(.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle(collection.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(draftName)
                    }
                    .disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct CollectionRow: View {
    let collection: CrateCollection
    let records: [CollectionRecord]

    var body: some View {
        HStack(spacing: 14) {
            CollectionInitialsTile(name: collection.name)

            VStack(alignment: .leading, spacing: 6) {
                Text(collection.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(albumCountLabel(collection.recordIds.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let firstArtist = records.first?.album.artist {
                    Text(firstArtist)
                        .font(.caption)
                        .foregroundStyle(DejaGrooveStyle.blue)
                        .lineLimit(1)
                }
            }
            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
        }
    }
}

private struct CollectionArtworkStack: View {
    let collectionName: String
    let records: [CollectionRecord]

    var body: some View {
        ZStack {
            if artworkRecords.isEmpty {
                CollectionInitialsTile(name: collectionName)
            } else {
                ForEach(Array(artworkRecords.prefix(3).enumerated()), id: \.element.id) { index, record in
                    AlbumArtwork(
                        urlString: record.album.thumbnailUrl ?? record.album.coverImageUrl,
                        size: 52)
                    .rotationEffect(.degrees(Double(index - 1) * 6))
                    .offset(x: CGFloat(index) * 8, y: CGFloat(index) * -3)
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                }
            }
        }
        .frame(width: 78, height: 62)
    }

    private var artworkRecords: [CollectionRecord] {
        records.filter { record in
            record.album.thumbnailUrl != nil || record.album.coverImageUrl != nil
        }
    }
}

private struct CollectionInitialsTile: View {
    let name: String

    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [DejaGrooveStyle.blue.opacity(0.85), DejaGrooveStyle.coral.opacity(0.85)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing))
            .overlay {
                Text(initials)
                    .font(.headline.weight(.black))
                    .foregroundStyle(.white)
            }
            .frame(width: 58, height: 58)
            .shadow(color: DejaGrooveStyle.blue.opacity(0.18), radius: 10, y: 6)
    }

    private var initials: String {
        let words = name
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
        let value = String(words).uppercased()
        return value.isEmpty ? "#" : value
    }
}

private func albumCountLabel(_ count: Int) -> String {
    count == 1 ? "1 album" : "\(count) albums"
}

private struct CollectionDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let collection: CrateCollection
    @ObservedObject var viewModel: CollectionViewModel
    @State private var draftName: String
    @State private var editingRecord: CollectionRecord?
    @State private var assigningCollectionsRecord: CollectionRecord?
    @State private var selectedRecordId: UUID?
    @State private var isAddingAlbums = false

    init(collection: CrateCollection, viewModel: CollectionViewModel) {
        self.collection = collection
        self.viewModel = viewModel
        _draftName = State(initialValue: collection.name)
    }

    var body: some View {
        DejaGrooveScreen {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    detailHeader
                    renamePanel
                    addAlbumsPanel
                    recordsPanel
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 110)
            }
        }
        .navigationTitle(currentCollection.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    isAddingAlbums = true
                } label: {
                    Label("Add Albums", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    Task {
                        await viewModel.deleteCollection(id: currentCollection.id)
                        dismiss()
                    }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .sheet(isPresented: $isAddingAlbums) {
            AddAlbumsToCollectionView(collection: currentCollection, viewModel: viewModel)
        }
        .navigationDestination(item: $selectedRecordId) { recordId in
            if let record = viewModel.record(id: recordId) {
                AlbumDetailView(record: record, viewModel: viewModel)
            }
        }
        .sheet(item: $editingRecord) { record in
            AlbumEditView(record: viewModel.record(id: record.id) ?? record) { album, notes in
                Task {
                    await viewModel.updateRecord(id: record.id, album: album, notes: notes)
                    editingRecord = nil
                }
            }
        }
        .sheet(item: $assigningCollectionsRecord) { record in
            CollectionAssignmentView(record: viewModel.record(id: record.id) ?? record, viewModel: viewModel)
        }
    }

    private var currentCollection: CrateCollection {
        viewModel.crateCollections.first(where: { $0.id == collection.id }) ?? collection
    }

    private var currentRecords: [CollectionRecord] {
        viewModel.records(in: currentCollection)
    }

    private var detailHeader: some View {
        DejaGroovePanel {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    CollectionArtworkStack(collectionName: currentCollection.name, records: currentRecords)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(currentCollection.name)
                            .font(.system(size: 28, weight: .black, design: .rounded))
                            .lineLimit(2)
                        Text(albumCountLabel(currentCollection.recordIds.count))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                if let firstArtist = currentRecords.first?.album.artist {
                    Label(firstArtist, systemImage: "music.mic")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DejaGrooveStyle.blue)
                        .lineLimit(1)
                }
            }
        }
    }

    private var renamePanel: some View {
        DejaGroovePanel {
            VStack(alignment: .leading, spacing: 12) {
                Text("Name")
                    .font(.headline)
                HStack(spacing: 10) {
                    TextField("Collection name", text: $draftName)
                        .textInputAutocapitalization(.words)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .background(.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    Button {
                        Task { await viewModel.renameCollection(id: currentCollection.id, name: draftName) }
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.headline.weight(.bold))
                            .frame(width: 44, height: 44)
                    }
                    .foregroundStyle(.white)
                    .background(DejaGrooveStyle.blue, in: Circle())
                    .disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
                }
            }
        }
    }

    private var addAlbumsPanel: some View {
        Button {
            isAddingAlbums = true
        } label: {
            DejaGroovePanel {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [DejaGrooveStyle.blue, DejaGrooveStyle.coral],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing))
                        Image(systemName: "plus")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 48, height: 48)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Add Albums")
                            .font(.headline)
                        Text("Choose from My Crate")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var recordsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            DejaGrooveSectionHeader(
                title: "Albums",
                detail: "\(currentRecords.count) total")

            if currentRecords.isEmpty {
                DejaGrooveEmptyState(
                    title: "No Albums",
                    systemImage: "square.stack.3d.up",
                    detail: "Tap Add Albums to choose records from My Crate.")
            } else {
                ForEach(currentRecords, id: \.id) { record in
                    SwipeActionCard(actionCount: 3) {
                        Button {
                            selectedRecordId = record.id
                        } label: {
                            DejaGroovePanel {
                                AlbumRow(record: record, collections: viewModel.collections(containing: record.id))
                            }
                        }
                        .buttonStyle(.plain)
                    } actions: {
                        SwipeActionButton(title: "Edit", systemImage: "pencil", color: DejaGrooveStyle.blue) {
                            editingRecord = record
                        }
                        SwipeActionButton(title: "Collection", systemImage: "folder", color: DejaGrooveStyle.ink) {
                            assigningCollectionsRecord = record
                        }
                        SwipeActionButton(title: "Remove", systemImage: "minus.circle", color: DejaGrooveStyle.coral) {
                            Task {
                                await viewModel.setRecord(record.id, in: currentCollection.id, isIncluded: false)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct CollectionAssignmentView: View {
    @Environment(\.dismiss) private var dismiss
    let record: CollectionRecord
    @ObservedObject var viewModel: CollectionViewModel

    var body: some View {
        NavigationStack {
            DejaGrooveScreen {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        DejaGroovePanel {
                            HStack(spacing: 14) {
                                AlbumArtwork(urlString: currentRecord.album.thumbnailUrl ?? currentRecord.album.coverImageUrl, size: 64)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(currentRecord.album.artist)
                                        .font(.headline)
                                        .lineLimit(1)
                                    Text(currentRecord.album.title)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                Spacer()
                            }
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            DejaGrooveSectionHeader(
                                title: "Collections",
                                detail: "\(viewModel.crateCollections.count) total")

                            if viewModel.crateCollections.isEmpty {
                                DejaGrooveEmptyState(
                                    title: "No Collections",
                                    systemImage: "folder.badge.plus",
                                    detail: "Create a collection first, then assign this album.")
                            } else {
                                ForEach(viewModel.crateCollections) { collection in
                                    Button {
                                        Task {
                                            await viewModel.setRecord(
                                                currentRecord.id,
                                                in: collection.id,
                                                isIncluded: !viewModel.isRecord(currentRecord.id, in: collection.id))
                                        }
                                    } label: {
                                        DejaGroovePanel {
                                            HStack(spacing: 12) {
                                                Image(systemName: viewModel.isRecord(currentRecord.id, in: collection.id) ? "checkmark.circle.fill" : "circle")
                                                    .font(.title3)
                                                    .foregroundStyle(viewModel.isRecord(currentRecord.id, in: collection.id) ? DejaGrooveStyle.blue : .secondary)
                                                VStack(alignment: .leading, spacing: 3) {
                                                    Text(collection.name)
                                                        .font(.headline)
                                                    Text(albumCountLabel(collection.recordIds.count))
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                }
                                                Spacer()
                                            }
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 44)
                }
            }
            .navigationTitle("Collections")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var currentRecord: CollectionRecord {
        viewModel.record(id: record.id) ?? record
    }
}

private struct AddAlbumsToCollectionView: View {
    @Environment(\.dismiss) private var dismiss
    let collection: CrateCollection
    @ObservedObject var viewModel: CollectionViewModel
    @State private var search = ""

    var body: some View {
        NavigationStack {
            DejaGrooveScreen {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        DejaGroovePanel {
                            HStack(spacing: 14) {
                                CollectionArtworkStack(collectionName: currentCollection.name, records: viewModel.records(in: currentCollection))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(currentCollection.name)
                                        .font(.title3.bold())
                                        .lineLimit(2)
                                    Text("Add albums from My Crate")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            DejaGrooveSectionHeader(
                                title: "Available Albums",
                                detail: "\(availableRecords.count) shown")

                            if availableRecords.isEmpty {
                                DejaGrooveEmptyState(
                                    title: "No Albums",
                                    systemImage: "checkmark.circle",
                                    detail: "Every matching My Crate album is already in this collection.")
                            } else {
                                ForEach(availableRecords) { record in
                                    DejaGroovePanel {
                                        HStack(spacing: 12) {
                                            AlbumArtwork(urlString: record.album.thumbnailUrl ?? record.album.coverImageUrl, size: 58)
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(record.album.artist)
                                                    .font(.headline)
                                                    .lineLimit(1)
                                                Text(record.album.title)
                                                    .font(.subheadline)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(2)
                                            }
                                            Spacer()
                                            Button {
                                                Task {
                                                    await viewModel.setRecord(record.id, in: currentCollection.id, isIncluded: true)
                                                }
                                            } label: {
                                                Image(systemName: "plus")
                                                    .font(.headline.weight(.bold))
                                                    .frame(width: 42, height: 42)
                                            }
                                            .foregroundStyle(.white)
                                            .background(DejaGrooveStyle.blue, in: Circle())
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 44)
                }
            }
            .searchable(text: $search)
            .navigationTitle("Add Albums")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var currentCollection: CrateCollection {
        viewModel.crateCollections.first(where: { $0.id == collection.id }) ?? collection
    }

    private var availableRecords: [CollectionRecord] {
        viewModel.records
            .filter { !currentCollection.recordIds.contains($0.id) }
            .filter { record in
                let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !query.isEmpty else { return true }
                return [record.album.artist, record.album.title, record.album.format, record.album.label]
                    .compactMap { $0 }
                    .contains { $0.localizedCaseInsensitiveContains(query) }
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

private struct AlbumDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let record: CollectionRecord
    @ObservedObject var viewModel: CollectionViewModel
    @State private var isEditing = false

    var body: some View {
        List {
            if currentRecord.album.coverImageUrl != nil || currentRecord.album.thumbnailUrl != nil {
                Section {
                    VStack(spacing: 12) {
                        HStack {
                            Spacer()
                            AlbumArtwork(urlString: currentRecord.album.coverImageUrl ?? currentRecord.album.thumbnailUrl, size: 220)
                            Spacer()
                        }
                        Button(role: .destructive) {
                            Task {
                                await viewModel.updateRecord(
                                    id: record.id,
                                    album: albumRemovingFrontArtwork(currentRecord.album),
                                    notes: currentRecord.notes)
                            }
                        } label: {
                            Label("Remove Front Cover Image", systemImage: "trash")
                        }
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

            if !currentRecord.album.listeningLinks.isEmpty {
                Section("Listen") {
                    ForEach(currentRecord.album.listeningLinks, id: \.url) { link in
                        if let url = URL(string: link.url) {
                            Link(link.provider, destination: url)
                        }
                    }
                    AppleMusicLibraryAddButton(album: currentRecord.album)
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
                    VStack(spacing: 12) {
                        HStack {
                            Spacer()
                            AlbumArtwork(urlString: currentRecord.album.backCoverImageUrl, size: 220)
                            Spacer()
                        }
                        Button(role: .destructive) {
                            Task {
                                await viewModel.updateRecord(
                                    id: record.id,
                                    album: albumRemovingBackArtwork(currentRecord.album),
                                    notes: currentRecord.notes)
                            }
                        } label: {
                            Label("Remove Back Cover Image", systemImage: "trash")
                        }
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

    private func albumRemovingFrontArtwork(_ album: Album) -> Album {
        albumReplacingArtwork(album, coverImageUrl: nil, thumbnailUrl: nil, backCoverImageUrl: album.backCoverImageUrl)
    }

    private func albumRemovingBackArtwork(_ album: Album) -> Album {
        albumReplacingArtwork(album, coverImageUrl: album.coverImageUrl, thumbnailUrl: album.thumbnailUrl, backCoverImageUrl: nil)
    }

    private func albumReplacingArtwork(
        _ album: Album,
        coverImageUrl: String?,
        thumbnailUrl: String?,
        backCoverImageUrl: String?
    ) -> Album {
        Album(
            mbid: album.mbid,
            discogsReleaseId: album.discogsReleaseId,
            discogsMasterId: album.discogsMasterId,
            discogsUrl: album.discogsUrl,
            discogsResourceUrl: album.discogsResourceUrl,
            title: album.title,
            artist: album.artist,
            year: album.year,
            format: album.format,
            firstReleaseYear: album.firstReleaseYear,
            releaseYear: album.releaseYear,
            firstReleaseDate: album.firstReleaseDate,
            releaseDate: album.releaseDate,
            label: album.label,
            catalogNumber: album.catalogNumber,
            country: album.country,
            barcode: album.barcode,
            coverImageUrl: coverImageUrl,
            thumbnailUrl: thumbnailUrl,
            backCoverImageUrl: backCoverImageUrl,
            backCoverText: album.backCoverText,
            releaseNotes: album.releaseNotes,
            genres: album.genres,
            styles: album.styles,
            companies: album.companies,
            tracklist: album.tracklist,
            identifiers: album.identifiers,
            discogsDataQuality: album.discogsDataQuality)
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

#endif
