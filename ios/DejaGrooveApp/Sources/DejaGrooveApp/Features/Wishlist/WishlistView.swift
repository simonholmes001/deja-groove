import SwiftUI

#if os(iOS)
public struct WishlistView: View {
    @ObservedObject private var viewModel: WishlistViewModel
    @State private var editingEntry: WishlistEntry?

    public init(viewModel: WishlistViewModel) {
        self.viewModel = viewModel
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
    let onDelete: () -> Void
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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
#endif
