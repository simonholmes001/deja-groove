import Foundation

@MainActor
public final class CollectionViewModel: ObservableObject {
    @Published public private(set) var records: [CollectionRecord] = []
    @Published public private(set) var crateCollections: [CrateCollection] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var errorMessage: String?
    @Published public var search: String = ""
    @Published public var selectedArtist: String = ""
    @Published public var selectedFormat: String = ""
    @Published public var selectedCollectionId: UUID?

    private let api: ApiClient

    public init(api: ApiClient) {
        self.api = api
    }

    public var visibleRecords: [CollectionRecord] {
        records.filter { record in
            matchesSearch(record)
                && matchesArtist(record)
                && matchesFormat(record)
                && matchesCollection(record)
        }
        .sorted { LocalCollectionRules.compareByArtistFamilyName($0, $1) }
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

    public func records(in collection: CrateCollection) -> [CollectionRecord] {
        records
            .filter { collection.recordIds.contains($0.id) }
            .sorted { LocalCollectionRules.compareByArtistFamilyName($0, $1) }
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
        do {
            let response = try await api.fetchCollection(search: search.isEmpty ? nil : search)
            records = response.items
            crateCollections = try await api.fetchCrateCollections(search: nil)
        } catch let error as ApiClientError {
            errorMessage = Self.message(for: error)
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

    private func matchesSearch(_ record: CollectionRecord) -> Bool {
        LocalCollectionRules.matchesSearch(record, search: search)
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
            .sorted { LocalCollectionRules.normalized($0) < LocalCollectionRules.normalized($1) }
    }
}
