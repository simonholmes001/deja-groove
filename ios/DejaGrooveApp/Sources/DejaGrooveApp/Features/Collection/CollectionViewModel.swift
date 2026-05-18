import Foundation

@MainActor
public final class CollectionViewModel: ObservableObject {
    @Published public private(set) var records: [CollectionRecord] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var errorMessage: String?
    @Published public var search: String = ""

    private let api: ApiClient

    public init(api: ApiClient) {
        self.api = api
    }

    public func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let response = try await api.fetchCollection(search: search.isEmpty ? nil : search)
            records = response.items
        } catch let error as ApiClientError {
            errorMessage = Self.message(for: error)
        } catch {
            errorMessage = "Unexpected error."
        }
        isLoading = false
    }

    private static func message(for error: ApiClientError) -> String {
        switch error {
        case .httpError(_, let apiError?):
            return apiError.message
        default:
            return "Failed to load collection."
        }
    }
}
