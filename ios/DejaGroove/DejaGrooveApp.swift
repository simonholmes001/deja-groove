import SwiftUI
import DejaGrooveApp

@main
struct DejaGrooveMobileApp: App {
    private let apiClient: ApiClient
    private let startupError: String?

    init() {
        switch AppConfiguration.load() {
        case .success(let config):
            apiClient = LocalProxyApiClientFactory.make(
                recognitionProxyBaseURL: config.recognitionProxyBaseURL,
                recognitionProxyKey: config.recognitionProxyKey)
            startupError = nil
        case .failure(let error):
            apiClient = DisabledApiClient()
            startupError = error.errorDescription
        }
    }

    var body: some Scene {
        WindowGroup {
            if let startupError {
                StartupConfigurationErrorView(message: startupError)
            } else {
                DejaGrooveRootView(api: apiClient)
            }
        }
    }
}

private struct StartupConfigurationErrorView: View {
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Text("Configuration Error")
                .font(.title2.bold())
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Text("Update build configuration values and relaunch.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(24)
    }
}

private struct DisabledApiClient: ApiClient {
    func scan(imageData: Data, clientScanId: UUID, capturedAtIso: String?) async throws -> ScanResponse {
        throw ApiClientError.encodingFailure
    }

    func resolve(requestId: UUID, selectedAlbum: Album) async throws -> ScanResponse {
        throw ApiClientError.encodingFailure
    }

    func addToCollection(album: Album, notes: String?, addAnyway: Bool) async throws -> CollectionItemResponse {
        throw ApiClientError.encodingFailure
    }

    func fetchCollection(search: String?) async throws -> CollectionListResponse {
        throw ApiClientError.encodingFailure
    }

    func patchCollection(id: UUID, format: String?, notes: String?) async throws -> CollectionItemResponse {
        throw ApiClientError.encodingFailure
    }

    func updateCollectionRecord(id: UUID, album: Album, notes: String?) async throws -> CollectionItemResponse {
        throw ApiClientError.encodingFailure
    }

    func deleteCollectionRecord(id: UUID) async throws {
        throw ApiClientError.encodingFailure
    }

    func fetchCrateCollections(search: String?) async throws -> [CrateCollection] {
        throw ApiClientError.encodingFailure
    }

    func createCrateCollection(name: String) async throws -> CrateCollection {
        throw ApiClientError.encodingFailure
    }

    func renameCrateCollection(id: UUID, name: String) async throws -> CrateCollection {
        throw ApiClientError.encodingFailure
    }

    func deleteCrateCollection(id: UUID) async throws {
        throw ApiClientError.encodingFailure
    }

    func addRecord(_ recordId: UUID, toCrateCollection collectionId: UUID) async throws -> CrateCollection {
        throw ApiClientError.encodingFailure
    }

    func removeRecord(_ recordId: UUID, fromCrateCollection collectionId: UUID) async throws -> CrateCollection {
        throw ApiClientError.encodingFailure
    }
}
