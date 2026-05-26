import Foundation

@MainActor
public final class ScanViewModel: ObservableObject {
    @Published public private(set) var state: ScanState = .idle
    @Published public var guidance: String = "Center the album cover, avoid glare, and keep edges visible."
    @Published public private(set) var isLastErrorRetryable = false

    private let api: ApiClient
    private var lastSubmittedImageData: Data?

    public init(api: ApiClient) {
        self.api = api
    }

    public func submitScan(imageData: Data) async {
        lastSubmittedImageData = imageData
        isLastErrorRetryable = false
        state = .loading
        do {
            let response = try await api.scan(imageData: imageData, clientScanId: UUID(), capturedAtIso: ISO8601DateFormatter().string(from: Date()))
            state = .result(response)
            isLastErrorRetryable = false
            lastSubmittedImageData = nil
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
        state = .loading
        do {
            let response = try await api.resolve(requestId: requestId, selectedMbid: candidate.mbid, selectedDiscogsReleaseId: candidate.discogsReleaseId)
            state = .result(response)
            lastSubmittedImageData = nil
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
}

public enum ScanState: Equatable, Sendable {
    case idle
    case loading
    case result(ScanResponse)
    case error(String)
}
