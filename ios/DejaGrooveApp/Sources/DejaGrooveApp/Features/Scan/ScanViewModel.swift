import Foundation

@MainActor
public final class ScanViewModel: ObservableObject {
    @Published public private(set) var state: ScanState = .idle
    @Published public var guidance: String = "Center the album cover, avoid glare, and keep edges visible."
    @Published public private(set) var isLastErrorRetryable = false
    @Published public private(set) var collectionMessage: String?

    private let api: ApiClient
    private var lastSubmittedImageData: Data?

    public init(api: ApiClient) {
        self.api = api
    }

    public func submitScan(imageData: Data) async {
        lastSubmittedImageData = imageData
        isLastErrorRetryable = false
        state = .loading(.uploading)
        let startedAt = Date()
        do {
            await Task.yield()
            state = .loading(.recognizing)
            let response = try await api.scan(imageData: imageData, clientScanId: UUID(), capturedAtIso: ISO8601DateFormatter().string(from: Date()))
            state = .result(response.withClientElapsedMs(Self.elapsedMs(since: startedAt)))
            isLastErrorRetryable = false
            lastSubmittedImageData = nil
            collectionMessage = nil
        } catch let error as ApiClientError {
            isLastErrorRetryable = Self.isRetryable(error)
            if !isLastErrorRetryable {
                lastSubmittedImageData = nil
            }
            state = .error(Self.message(for: error))
        } catch {
            lastSubmittedImageData = nil
            state = .error("Unexpected error. Please try again.")
        }
    }

    public func resolve(requestId: UUID, candidate: Album) async {
        isLastErrorRetryable = false
        state = .loading(.resolving)
        do {
            let response = try await api.resolve(requestId: requestId, selectedAlbum: candidate)
            state = .result(response)
            lastSubmittedImageData = nil
            collectionMessage = nil
        } catch let error as ApiClientError {
            isLastErrorRetryable = false
            lastSubmittedImageData = nil
            state = .error(Self.message(for: error))
        } catch {
            lastSubmittedImageData = nil
            state = .error("Unexpected error. Please try again.")
        }
    }

    public func retryLastScan() async {
        guard let imageData = lastSubmittedImageData else { return }
        await submitScan(imageData: imageData)
    }

    public func addResultToCollection() async {
        guard case .result(let response) = state, let album = response.album else { return }
        do {
            _ = try await api.addToCollection(album: album, notes: nil, addAnyway: false)
            collectionMessage = "Added to My Crate."
            state = .idle
        } catch let error as ApiClientError {
            switch error {
            case .httpError(_, let apiError?):
                collectionMessage = apiError.message
            default:
                collectionMessage = "Failed to add to collection."
            }
        } catch {
            collectionMessage = "Failed to add to collection."
        }
    }

    public func handleSelectedImagePreparationFailure() {
        lastSubmittedImageData = nil
        isLastErrorRetryable = false
        state = .error("Selected image could not be prepared for upload. Please choose another photo.")
    }

    private static func message(for error: ApiClientError) -> String {
        switch error {
        case .httpError(_, let apiError?):
            return apiError.message
        case .httpError(let status, _):
            return "Request failed with status \(status)."
        default:
            return "Network error. Check your connection and retry."
        }
    }

    private static func isRetryable(_ error: ApiClientError) -> Bool {
        switch error {
        case .httpError(_, let apiError?):
            return apiError.retryable
        case .httpError:
            return false
        case .invalidResponse, .encodingFailure:
            return true
        }
    }

    private static func elapsedMs(since startedAt: Date) -> Int {
        max(0, Int(Date().timeIntervalSince(startedAt) * 1000))
    }
}

public enum ScanState: Equatable, Sendable {
    case idle
    case loading(ScanProgress)
    case result(ScanResponse)
    case error(String)
}

public enum ScanProgress: Equatable, Sendable {
    case uploading
    case recognizing
    case resolving

    var message: String {
        switch self {
        case .uploading:
            return "Preparing and uploading cover..."
        case .recognizing:
            return "Recognizing album..."
        case .resolving:
            return "Resolving selected release..."
        }
    }
}
