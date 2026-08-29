import Foundation

@MainActor
public final class NearbyRecordShopsViewModel: ObservableObject {
    public enum State: Equatable {
        case idle
        case loading
        case loaded([RecordShopOpportunity])
        case locationDenied
        case unavailable
        case error(String)
    }

    @Published public private(set) var state: State = .idle
    @Published public var placeSearch = ""

    private let album: Album
    private let discoveryService: RecordShopDiscoveryService

    public init(album: Album, discoveryService: RecordShopDiscoveryService) {
        self.album = album
        self.discoveryService = discoveryService
    }

    public func findNearCurrentLocation() async {
        placeSearch = ""
        state = .loading
        let authorization = await discoveryService.requestLocationAuthorization()
        switch authorization {
        case .authorized:
            await loadCurrentLocationShops()
        case .denied, .restricted:
            state = .locationDenied
        case .notDetermined:
            state = .idle
        case .unavailable:
            state = .unavailable
        }
    }

    public func searchPlace() async {
        let place = placeSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !place.isEmpty else {
            state = .idle
            return
        }

        state = .loading
        do {
            state = .loaded(try await discoveryService.shops(matching: place, for: album))
        } catch {
            state = .error("Failed to find record shops.")
        }
    }

    private func loadCurrentLocationShops() async {
        do {
            state = .loaded(try await discoveryService.shopsNearCurrentLocation(for: album))
        } catch {
            state = .error("Failed to find record shops near you.")
        }
    }
}
