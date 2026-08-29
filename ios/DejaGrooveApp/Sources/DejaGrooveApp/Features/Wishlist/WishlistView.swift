import SwiftUI

#if os(iOS)
public struct WishlistView: View {
    @ObservedObject private var viewModel: WishlistViewModel
    private let recordShopDiscovery: RecordShopDiscoveryService
    @State private var editingEntry: WishlistEntry?
    @State private var selectedEntry: WishlistEntry?

    public init(
        viewModel: WishlistViewModel,
        recordShopDiscovery: RecordShopDiscoveryService = DejaGrooveRecordShopDiscoveryFactory.make()
    ) {
        self.viewModel = viewModel
        self.recordShopDiscovery = recordShopDiscovery
    }

    public var body: some View {
        NavigationStack {
            DejaGrooveScreen {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        entries
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 110)
                }
            }
            .overlay {
                if viewModel.isLoading {
                    ProgressView("Loading Wishlist")
                        .padding(18)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .searchable(text: $viewModel.search)
            .navigationTitle("Wishlist")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await viewModel.load() }
            .task { await viewModel.load() }
            .sheet(item: $editingEntry) { entry in
                WishlistPreferenceEditView(entry: entry) { preferences in
                    Task {
                        await viewModel.updatePreferences(id: entry.id, preferences: preferences)
                        editingEntry = nil
                    }
                }
            }
            .sheet(item: $selectedEntry) { entry in
                NavigationStack {
                    WishlistAlbumDetailView(entry: entry, recordShopDiscovery: recordShopDiscovery)
                }
            }
        }
    }

    private var header: some View {
        DejaGroovePanel {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(DejaGrooveStyle.coral)
                    Image(systemName: "heart.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 60, height: 60)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Wishlist")
                        .font(.system(size: 30, weight: .black, design: .rounded))
                    Text(viewModel.entries.count == 1 ? "1 wanted album" : "\(viewModel.entries.count) wanted albums")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    private var entries: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !viewModel.isLoading && viewModel.visibleEntries.isEmpty {
                DejaGroovePanel {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "heart")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(DejaGrooveStyle.coral)
                        Text("No Wishlist Albums")
                            .font(.headline)
                        Text("Save wanted albums from scan results or future discovery flows.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ForEach(viewModel.visibleEntries) { entry in
                    DejaGroovePanel {
                        WishlistEntryRow(entry: entry) {
                            selectedEntry = entry
                        } onDelete: {
                            Task { await viewModel.deleteEntry(id: entry.id) }
                        } onEdit: {
                            editingEntry = entry
                        }
                    }
                }
            }
        }
    }
}

private struct WishlistEntryRow: View {
    let entry: WishlistEntry
    let onOpen: () -> Void
    let onDelete: () -> Void
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Button(action: onOpen) {
                    HStack(alignment: .top, spacing: 12) {
                        WishlistArtwork(urlString: entry.album.thumbnailUrl ?? entry.album.coverImageUrl)

                        VStack(alignment: .leading, spacing: 5) {
                            Text(entry.album.artist)
                                .font(.headline)
                            Text(entry.album.title)
                                .font(.subheadline)
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                Spacer()
                Button(action: onEdit) {
                    Image(systemName: "slider.horizontal.3")
                }
                .buttonStyle(.borderless)
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }

            if let sourceTrack = entry.sourceTrack {
                Label("\(sourceTrack.artist) - \(sourceTrack.title)", systemImage: "waveform")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !entry.album.listeningLinks.isEmpty {
                HStack {
                    ForEach(entry.album.listeningLinks, id: \.url) { link in
                        if let url = URL(string: link.url) {
                            Link(link.provider, destination: url)
                                .font(.caption.weight(.semibold))
                        }
                    }
                }
            }
        }
    }

    private var subtitle: String {
        [
            entry.preferences.targetFormat ?? entry.album.format,
            entry.preferences.country ?? entry.album.country,
            entry.preferences.label ?? entry.album.label,
            entry.preferences.catalogNumber ?? entry.album.catalogNumber
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: " • ")
    }
}

private struct WishlistAlbumDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let entry: WishlistEntry
    let recordShopDiscovery: RecordShopDiscoveryService

    var body: some View {
        List {
            if entry.album.coverImageUrl != nil || entry.album.thumbnailUrl != nil {
                Section {
                    HStack {
                        Spacer()
                        WishlistDetailArtwork(urlString: entry.album.coverImageUrl ?? entry.album.thumbnailUrl, size: 220)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
            }

            Section("Album") {
                detail("Artist", entry.album.artist)
                detail("Title", entry.album.title)
                detail("First Release Date", entry.album.firstReleaseDate ?? entry.album.firstReleaseYear.map(String.init) ?? entry.album.releaseDate ?? entry.album.releaseYear.map(String.init) ?? entry.album.year.map(String.init))
                detail("Discogs Release Date", entry.album.releaseDate ?? entry.album.releaseYear.map(String.init))
                detail("Format", entry.album.format)
                detail("Label", entry.album.label)
                detail("Catalog Number", entry.album.catalogNumber)
                detail("Country", entry.album.country)
                detail("Barcode", entry.album.barcode)
                detail("Discogs Release", entry.album.discogsReleaseId)
                detail("Discogs Master", entry.album.discogsMasterId)
                detail("Discogs Quality", entry.album.discogsDataQuality)
                if let discogsUrl = entry.album.discogsUrl, let url = URL(string: discogsUrl) {
                    Link("Open In Discogs", destination: url)
                }
            }

            Section("Wanted Pressing") {
                detail("Format", entry.preferences.targetFormat)
                detail("Release Year", entry.preferences.releaseYear.map(String.init))
                detail("Country", entry.preferences.country)
                detail("Label", entry.preferences.label)
                detail("Catalog Number", entry.preferences.catalogNumber)
                detail("Barcode", entry.preferences.barcode)
                detail("Condition Notes", entry.preferences.conditionNotes)
                detail("Price Note", entry.preferences.priceNote)
                detail("Notes", entry.preferences.notes)
            }

            Section("Nearby Record Shops") {
                NearbyRecordShopsSection(entry: entry, discoveryService: recordShopDiscovery)
            }

            if let sourceTrack = entry.sourceTrack {
                Section("Discovery Source") {
                    detail("Artist", sourceTrack.artist)
                    detail("Track", sourceTrack.title)
                    detail("Genre", sourceTrack.genre)
                    detail("Matched", sourceTrack.matchedAt)
                    detail("Shazam ID", sourceTrack.shazamId)
                    detail("Apple Music ID", sourceTrack.appleMusicId)
                }
            }

            if !entry.album.listeningLinks.isEmpty {
                Section("Listen") {
                    ForEach(entry.album.listeningLinks, id: \.url) { link in
                        if let url = URL(string: link.url) {
                            Link(link.provider, destination: url)
                        }
                    }
                    AppleMusicLibraryAddButton(album: entry.album)
                }
            }

            if let releaseNotes = entry.album.releaseNotes, !releaseNotes.isEmpty {
                Section("Release Notes") {
                    Text(releaseNotes)
                }
            }

            if !entry.album.genres.isEmpty || !entry.album.styles.isEmpty {
                Section("Genre & Style") {
                    detail("Genres", entry.album.genres.joined(separator: ", "))
                    detail("Styles", entry.album.styles.joined(separator: ", "))
                }
            }

            if !entry.album.tracklist.isEmpty {
                Section("Tracklist") {
                    ForEach(Array(entry.album.tracklist.enumerated()), id: \.offset) { _, track in
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

            if !entry.album.identifiers.isEmpty {
                Section("Identifiers") {
                    ForEach(Array(entry.album.identifiers.enumerated()), id: \.offset) { _, identifier in
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
        .navigationTitle(entry.album.title)
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

private struct NearbyRecordShopsSection: View {
    @StateObject private var viewModel: NearbyRecordShopsViewModel

    init(entry: WishlistEntry, discoveryService: RecordShopDiscoveryService) {
        _viewModel = StateObject(wrappedValue: NearbyRecordShopsViewModel(
            album: entry.album,
            discoveryService: discoveryService))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Use your location or a place search to find record shops. Album availability is shown only when backed by a reliable inventory source.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button {
                Task { await viewModel.findNearCurrentLocation() }
            } label: {
                Label("Find Shops Near Me", systemImage: "location")
            }

            HStack(spacing: 8) {
                TextField("Search a city or postcode", text: $viewModel.placeSearch)
                    .textInputAutocapitalization(.words)
                Button {
                    Task { await viewModel.searchPlace() }
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Search record shops")
            }

            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle:
            EmptyView()
        case .loading:
            ProgressView("Finding record shops")
        case .loaded(let opportunities):
            if opportunities.isEmpty {
                Label("No nearby record shops found.", systemImage: "mappin.slash")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(opportunities) { opportunity in
                    RecordShopOpportunityRow(opportunity: opportunity)
                }
            }
        case .locationDenied:
            Label("Location access is off. Search a place manually or enable location in Settings.", systemImage: "location.slash")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .unavailable:
            Label("Record shop discovery is unavailable on this device.", systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .error(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

private struct RecordShopOpportunityRow: View {
    let opportunity: RecordShopOpportunity

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(opportunity.shop.name)
                .font(.subheadline.weight(.semibold))
            if let distance = formattedDistance {
                Text(distance)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let address = opportunity.shop.address, !address.isEmpty {
                Text(address)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Label(inventoryText, systemImage: inventoryIcon)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                if let phoneNumber = opportunity.shop.phoneNumber,
                   let url = URL(string: "tel://\(phoneNumber.filter { !$0.isWhitespace })") {
                    Link("Call", destination: url)
                        .font(.caption.weight(.semibold))
                }
                if let websiteURL = opportunity.shop.websiteURL {
                    Link("Website", destination: websiteURL)
                        .font(.caption.weight(.semibold))
                }
                if let directionsURL = opportunity.shop.directionsURL {
                    Link("Directions", destination: directionsURL)
                        .font(.caption.weight(.semibold))
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var formattedDistance: String? {
        guard let meters = opportunity.shop.distanceMeters else { return nil }
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .naturalScale
        formatter.numberFormatter.maximumFractionDigits = 1
        return formatter.string(from: Measurement(value: meters, unit: UnitLength.meters))
    }

    private var inventoryText: String {
        switch opportunity.inventoryStatus {
        case .unknown:
            return "Inventory unknown"
        case .available(let source, _):
            return "Available via \(source)"
        }
    }

    private var inventoryIcon: String {
        opportunity.inventoryStatus.isVerifiedAvailable ? "checkmark.seal" : "questionmark.circle"
    }
}

private struct WishlistPreferenceEditView: View {
    @Environment(\.dismiss) private var dismiss
    let entry: WishlistEntry
    let onSave: (WishlistPreferences) -> Void

    @State private var targetFormat: String
    @State private var releaseYear: String
    @State private var country: String
    @State private var label: String
    @State private var catalogNumber: String
    @State private var barcode: String
    @State private var conditionNotes: String
    @State private var priceNote: String
    @State private var notes: String

    init(entry: WishlistEntry, onSave: @escaping (WishlistPreferences) -> Void) {
        self.entry = entry
        self.onSave = onSave
        _targetFormat = State(initialValue: entry.preferences.targetFormat ?? "")
        _releaseYear = State(initialValue: entry.preferences.releaseYear.map(String.init) ?? "")
        _country = State(initialValue: entry.preferences.country ?? "")
        _label = State(initialValue: entry.preferences.label ?? "")
        _catalogNumber = State(initialValue: entry.preferences.catalogNumber ?? "")
        _barcode = State(initialValue: entry.preferences.barcode ?? "")
        _conditionNotes = State(initialValue: entry.preferences.conditionNotes ?? "")
        _priceNote = State(initialValue: entry.preferences.priceNote ?? "")
        _notes = State(initialValue: entry.preferences.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Wanted Pressing") {
                    TextField("Format", text: $targetFormat)
                    TextField("Release Year", text: $releaseYear)
                        .keyboardType(.numberPad)
                    TextField("Country", text: $country)
                    TextField("Label", text: $label)
                    TextField("Catalog Number", text: $catalogNumber)
                    TextField("Barcode", text: $barcode)
                }

                Section("Notes") {
                    TextField("Condition Notes", text: $conditionNotes, axis: .vertical)
                    TextField("Price Note", text: $priceNote)
                    TextField("General Notes", text: $notes, axis: .vertical)
                }
            }
            .navigationTitle("Wishlist Preferences")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(WishlistPreferences(
                            targetFormat: clean(targetFormat),
                            releaseYear: Int(clean(releaseYear) ?? ""),
                            country: clean(country),
                            label: clean(label),
                            catalogNumber: clean(catalogNumber),
                            barcode: clean(barcode),
                            discogsReleaseId: entry.preferences.discogsReleaseId,
                            discogsMasterId: entry.preferences.discogsMasterId,
                            conditionNotes: clean(conditionNotes),
                            priceNote: clean(priceNote),
                            notes: clean(notes)))
                    }
                }
            }
        }
    }

    private func clean(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct WishlistArtwork: View {
    let urlString: String?

    var body: some View {
        Group {
            if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 6))
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

private struct WishlistDetailArtwork: View {
    let urlString: String?
    let size: CGFloat

    var body: some View {
        Group {
            if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
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
