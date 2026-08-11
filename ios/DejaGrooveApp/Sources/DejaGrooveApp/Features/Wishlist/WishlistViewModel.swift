import Foundation

@MainActor
public final class WishlistViewModel: ObservableObject {
    @Published public private(set) var entries: [WishlistEntry] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var errorMessage: String?
    @Published public var search = ""

    private let api: ApiClient

    public init(api: ApiClient) {
        self.api = api
    }

    public var visibleEntries: [WishlistEntry] {
        entries.filter { LocalWishlistRules.matchesSearch($0, search: search) }
    }

    public func load() async {
        isLoading = true
        errorMessage = nil
        do {
            entries = try await api.fetchWishlist(search: nil)
        } catch let error as ApiClientError {
            errorMessage = Self.message(for: error)
        } catch {
            errorMessage = "Unexpected error."
        }
        isLoading = false
    }

    public func deleteEntry(id: UUID) async {
        do {
            try await api.deleteWishlistEntry(id: id)
            entries.removeAll { $0.id == id }
            errorMessage = nil
        } catch let error as ApiClientError {
            errorMessage = Self.message(for: error)
        } catch {
            errorMessage = "Unexpected error."
        }
    }

    public func updatePreferences(id: UUID, preferences: WishlistPreferences) async {
        do {
            let updated = try await api.updateWishlistPreferences(id: id, preferences: preferences)
            if let index = entries.firstIndex(where: { $0.id == id }) {
                entries[index] = updated
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
            return "Failed to load Wishlist."
        }
    }
}
