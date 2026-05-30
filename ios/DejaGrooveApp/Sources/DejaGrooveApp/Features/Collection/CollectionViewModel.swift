import Foundation

@MainActor
public final class CollectionViewModel: ObservableObject {
    @Published public private(set) var records: [CollectionRecord] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var requiresAuthentication = false
    @Published public var search: String = ""

    private let api: ApiClient
    private let onAuthenticationRequired: @Sendable () async -> Void

    public init(
        api: ApiClient,
        onAuthenticationRequired: @escaping @Sendable () async -> Void = {}
    ) {
        self.api = api
        self.onAuthenticationRequired = onAuthenticationRequired
    }

    public func load() async {
        isLoading = true
        errorMessage = nil
        requiresAuthentication = false
        do {
            let response = try await api.fetchCollection(search: search.isEmpty ? nil : search)
            records = response.items
        } catch let error as ApiClientError {
            if Self.isAuthenticationError(error) {
                records = []
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
}
