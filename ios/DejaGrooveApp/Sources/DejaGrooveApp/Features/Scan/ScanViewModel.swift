import Foundation

@MainActor
public final class ScanViewModel: ObservableObject {
    @Published public private(set) var state: ScanState = .idle
    @Published public var guidance: String = "Center the album cover, avoid glare, and keep edges visible."

    private let api: ApiClient

    public init(api: ApiClient) {
        self.api = api
    }

    public func submitScan(imageData: Data) async {
        state = .loading
        do {
            let response = try await api.scan(imageData: imageData, clientScanId: UUID(), capturedAtIso: ISO8601DateFormatter().string(from: Date()))
            state = .result(response)
        } catch let error as ApiClientError {
            state = .error(Self.message(for: error))
        } catch {
            state = .error("Unexpected error. Please try again.")
        }
    }

    public func resolve(requestId: UUID, candidate: Album) async {
        state = .loading
        do {
            let response = try await api.resolve(requestId: requestId, selectedMbid: candidate.mbid, selectedDiscogsReleaseId: candidate.discogsReleaseId)
            state = .result(response)
        } catch let error as ApiClientError {
            state = .error(Self.message(for: error))
        } catch {
            state = .error("Unexpected error. Please try again.")
        }
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
}

public enum ScanState: Equatable, Sendable {
    case idle
    case loading
    case result(ScanResponse)
    case error(String)
}
