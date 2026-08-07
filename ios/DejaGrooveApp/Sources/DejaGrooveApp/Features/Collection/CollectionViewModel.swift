import Foundation

@MainActor
public final class CollectionViewModel: ObservableObject {
    @Published public private(set) var records: [CollectionRecord] = []
    @Published public private(set) var crateCollections: [CrateCollection] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var requiresAuthentication = false
    @Published public var search: String = ""
    @Published public var selectedArtist: String = ""
    @Published public var selectedFormat: String = ""
    @Published public var selectedCollectionId: UUID?

    private let api: ApiClient
    private let onAuthenticationRequired: @Sendable () async -> Void

    public init(
        api: ApiClient,
        onAuthenticationRequired: @escaping @Sendable () async -> Void = {}
    ) {
        self.api = api
        self.onAuthenticationRequired = onAuthenticationRequired
    }

    public var visibleRecords: [CollectionRecord] {
        records.filter { record in
            matchesSearch(record)
                && matchesArtist(record)
                && matchesFormat(record)
                && matchesCollection(record)
        }
        .sorted {
            Self.compareByArtistFamilyName($0, $1)
        }
    }

    public var availableArtists: [String] {
        uniqueSorted(records.map(\.album.artist))
    }

    public var availableFormats: [String] {
        uniqueSorted(records.compactMap(\.album.format))
    }

    public func collections(containing recordId: UUID) -> [CrateCollection] {
        crateCollections.filter { $0.recordIds.contains(recordId) }
    }

    public func record(id: UUID) -> CollectionRecord? {
        records.first { $0.id == id }
    }

    public func isRecord(_ recordId: UUID, in collectionId: UUID) -> Bool {
        crateCollections.first(where: { $0.id == collectionId })?.recordIds.contains(recordId) ?? false
    }

    public func load() async {
        isLoading = true
        errorMessage = nil
        requiresAuthentication = false
        do {
            let response = try await api.fetchCollection(search: search.isEmpty ? nil : search)
            records = response.items
            crateCollections = try await api.fetchCrateCollections(search: nil)
        } catch let error as ApiClientError {
            if Self.isAuthenticationError(error) {
                records = []
                crateCollections = []
                requiresAuthentication = true
                errorMessage = "Sign in to view My Crate."
                await onAuthenticationRequired()
            } else {
                errorMessage = Self.message(for: error)
            }
        } catch {
            errorMessage = "Unexpected error."
        }
        isLoading = false
    }

    public func createCollection(named name: String) async {
        do {
            _ = try await api.createCrateCollection(name: name)
            crateCollections = try await api.fetchCrateCollections(search: nil)
            errorMessage = nil
        } catch let error as ApiClientError {
            errorMessage = Self.message(for: error)
        } catch {
            errorMessage = "Unexpected error."
        }
    }

    public func renameCollection(id: UUID, name: String) async {
        do {
            _ = try await api.renameCrateCollection(id: id, name: name)
            crateCollections = try await api.fetchCrateCollections(search: nil)
            errorMessage = nil
        } catch let error as ApiClientError {
            errorMessage = Self.message(for: error)
        } catch {
            errorMessage = "Unexpected error."
        }
    }

    public func deleteCollection(id: UUID) async {
        do {
            try await api.deleteCrateCollection(id: id)
            if selectedCollectionId == id {
                selectedCollectionId = nil
            }
            crateCollections = try await api.fetchCrateCollections(search: nil)
            errorMessage = nil
        } catch let error as ApiClientError {
            errorMessage = Self.message(for: error)
        } catch {
            errorMessage = "Unexpected error."
        }
    }

    public func setRecord(_ recordId: UUID, in collectionId: UUID, isIncluded: Bool) async {
        do {
            if isIncluded {
                _ = try await api.addRecord(recordId, toCrateCollection: collectionId)
            } else {
                _ = try await api.removeRecord(recordId, fromCrateCollection: collectionId)
            }
            crateCollections = try await api.fetchCrateCollections(search: nil)
            errorMessage = nil
        } catch let error as ApiClientError {
            errorMessage = Self.message(for: error)
        } catch {
            errorMessage = "Unexpected error."
        }
    }

    public func deleteRecord(id: UUID) async {
        do {
            try await api.deleteCollectionRecord(id: id)
            records.removeAll { $0.id == id }
            crateCollections = try await api.fetchCrateCollections(search: nil)
            errorMessage = nil
        } catch let error as ApiClientError {
            errorMessage = Self.message(for: error)
        } catch {
            errorMessage = "Unexpected error."
        }
    }

    public func updateRecord(id: UUID, album: Album, notes: String?) async {
        do {
            _ = try await api.updateCollectionRecord(id: id, album: album, notes: notes)
            if let index = records.firstIndex(where: { $0.id == id }) {
                let current = records[index]
                records[index] = CollectionRecord(
                    id: current.id,
                    album: album,
                    notes: notes,
                    version: current.version + 1,
                    createdAt: current.createdAt,
                    updatedAt: current.updatedAt)
            }
            errorMessage = nil
        } catch let error as ApiClientError {
            errorMessage = Self.message(for: error)
        } catch {
            errorMessage = "Unexpected error."
        }
    }

    private static func message(for error: ApiClientError) -> String {
        switch error {
        case .httpError(_, let apiError?):
            return apiError.message
        default:
            return "Failed to load collection."
        }
    }

    private static func isAuthenticationError(_ error: ApiClientError) -> Bool {
        switch error {
        case .httpError(let status, _):
            return status == 401 || status == 403
        default:
            return false
        }
    }

    private func matchesSearch(_ record: CollectionRecord) -> Bool {
        let cleanSearch = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanSearch.isEmpty else { return true }
        let query = Self.normalized(cleanSearch)
        let searchable = [
            record.album.artist,
            record.album.title,
            record.album.format,
            record.album.label,
            record.album.catalogNumber,
            record.album.country,
            record.album.backCoverText,
            record.album.releaseNotes,
            record.notes,
            record.album.year.map(String.init),
            record.album.firstReleaseYear.map(String.init),
            record.album.releaseYear.map(String.init)
        ].compactMap { $0 }
        return searchable.contains { Self.normalized($0).contains(query) }
    }

    private func matchesArtist(_ record: CollectionRecord) -> Bool {
        selectedArtist.isEmpty || record.album.artist == selectedArtist
    }

    private func matchesFormat(_ record: CollectionRecord) -> Bool {
        selectedFormat.isEmpty || record.album.format == selectedFormat
    }

    private func matchesCollection(_ record: CollectionRecord) -> Bool {
        guard let selectedCollectionId else { return true }
        return crateCollections
            .first(where: { $0.id == selectedCollectionId })?
            .recordIds
            .contains(record.id) ?? false
    }

    private func uniqueSorted(_ values: [String]) -> [String] {
        Array(Set(values.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }))
            .sorted { Self.normalized($0) < Self.normalized($1) }
    }

    private static func compareByArtistFamilyName(_ lhs: CollectionRecord, _ rhs: CollectionRecord) -> Bool {
        let lhsArtist = artistSortKey(lhs.album.artist)
        let rhsArtist = artistSortKey(rhs.album.artist)
        if lhsArtist != rhsArtist {
            return lhsArtist < rhsArtist
        }
        let lhsTitle = titleSortKey(lhs.album.title)
        let rhsTitle = titleSortKey(rhs.album.title)
        if lhsTitle != rhsTitle {
            return lhsTitle < rhsTitle
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func artistSortKey(_ artist: String) -> String {
        let cleanArtist = normalized(artist)
        if cleanArtist.contains(",")
            || cleanArtist.contains("&")
            || cleanArtist.hasPrefix("the ")
            || cleanArtist.hasSuffix(" band")
            || cleanArtist.hasSuffix(" quartet")
            || cleanArtist.hasSuffix(" quintet")
            || cleanArtist.hasSuffix(" trio") {
            return cleanArtist
        }
        let parts = cleanArtist.split(separator: " ").map(String.init)
        guard parts.count >= 2 else { return cleanArtist }
        return "\(parts.last!) \(parts.dropLast().joined(separator: " "))"
    }

    private static func titleSortKey(_ title: String) -> String {
        let cleanTitle = normalized(title)
        for article in ["the ", "a ", "an "] where cleanTitle.hasPrefix(article) {
            return String(cleanTitle.dropFirst(article.count))
        }
        return cleanTitle
    }

    private static func normalized(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
    }
}
