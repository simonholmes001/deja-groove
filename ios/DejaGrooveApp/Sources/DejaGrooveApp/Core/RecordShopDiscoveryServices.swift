import Foundation

#if canImport(CoreLocation)
import CoreLocation
#endif

#if canImport(MapKit)
import MapKit
#endif

public enum RecordShopLocationAuthorizationStatus: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted
    case unavailable
}

public enum RecordShopInventoryStatus: Equatable, Sendable {
    case unknown
    case available(source: String, checkedAt: String?)

    public var isVerifiedAvailable: Bool {
        switch self {
        case .available:
            return true
        case .unknown:
            return false
        }
    }
}

public struct RecordShop: Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let distanceMeters: Double?
    public let address: String?
    public let phoneNumber: String?
    public let websiteURL: URL?
    public let directionsURL: URL?

    public init(
        id: String,
        name: String,
        distanceMeters: Double?,
        address: String?,
        phoneNumber: String?,
        websiteURL: URL?,
        directionsURL: URL?
    ) {
        self.id = id
        self.name = name
        self.distanceMeters = distanceMeters
        self.address = address
        self.phoneNumber = phoneNumber
        self.websiteURL = websiteURL
        self.directionsURL = directionsURL
    }
}

public struct RecordShopOpportunity: Equatable, Identifiable, Sendable {
    public let id: String
    public let shop: RecordShop
    public let inventoryStatus: RecordShopInventoryStatus

    public init(shop: RecordShop, inventoryStatus: RecordShopInventoryStatus) {
        self.id = shop.id
        self.shop = shop
        self.inventoryStatus = inventoryStatus
    }
}

public protocol RecordShopDiscoveryService: Sendable {
    var authorizationStatus: RecordShopLocationAuthorizationStatus { get async }
    func requestLocationAuthorization() async -> RecordShopLocationAuthorizationStatus
    func shopsNearCurrentLocation(for album: Album) async throws -> [RecordShopOpportunity]
    func shops(matching place: String, for album: Album) async throws -> [RecordShopOpportunity]
}

public struct UnavailableRecordShopDiscoveryService: RecordShopDiscoveryService {
    public init() {}

    public var authorizationStatus: RecordShopLocationAuthorizationStatus {
        get async { .unavailable }
    }

    public func requestLocationAuthorization() async -> RecordShopLocationAuthorizationStatus {
        .unavailable
    }

    public func shopsNearCurrentLocation(for album: Album) async throws -> [RecordShopOpportunity] {
        []
    }

    public func shops(matching place: String, for album: Album) async throws -> [RecordShopOpportunity] {
        []
    }
}

#if canImport(CoreLocation) && canImport(MapKit)
public final class MapKitRecordShopDiscoveryService: NSObject, RecordShopDiscoveryService, @unchecked Sendable {
    private let locationManager: CLLocationManager
    private let searchCompleter: MapKitRecordShopSearching
    private var authorizationContinuation: CheckedContinuation<RecordShopLocationAuthorizationStatus, Never>?
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?

    public init(
        locationManager: CLLocationManager = CLLocationManager(),
        searchCompleter: MapKitRecordShopSearching = MapKitRecordShopSearcher()
    ) {
        self.locationManager = locationManager
        self.searchCompleter = searchCompleter
        super.init()
        self.locationManager.delegate = self
        self.locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    public var authorizationStatus: RecordShopLocationAuthorizationStatus {
        get async {
            Self.mapAuthorizationStatus(locationManager.authorizationStatus)
        }
    }

    public func requestLocationAuthorization() async -> RecordShopLocationAuthorizationStatus {
        let current = Self.mapAuthorizationStatus(locationManager.authorizationStatus)
        guard current == .notDetermined else { return current }
        guard CLLocationManager.locationServicesEnabled() else { return .unavailable }

        return await withCheckedContinuation { continuation in
            authorizationContinuation = continuation
            locationManager.requestWhenInUseAuthorization()
        }
    }

    public func shopsNearCurrentLocation(for album: Album) async throws -> [RecordShopOpportunity] {
        let status = await requestLocationAuthorization()
        guard status == .authorized else { return [] }
        let location = try await currentLocation()
        let shops = try await searchCompleter.searchRecordShops(near: location, query: "record store vinyl records")
        return shops.map { RecordShopOpportunity(shop: $0, inventoryStatus: .unknown) }
    }

    public func shops(matching place: String, for album: Album) async throws -> [RecordShopOpportunity] {
        let trimmed = place.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let shops = try await searchCompleter.searchRecordShops(in: trimmed, query: "record store vinyl records")
        return shops.map { RecordShopOpportunity(shop: $0, inventoryStatus: .unknown) }
    }

    private func currentLocation() async throws -> CLLocation {
        if let location = locationManager.location {
            return location
        }
        return try await withCheckedThrowingContinuation { continuation in
            locationContinuation = continuation
            locationManager.requestLocation()
        }
    }

    private static func mapAuthorizationStatus(_ status: CLAuthorizationStatus) -> RecordShopLocationAuthorizationStatus {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .authorizedAlways, .authorizedWhenInUse:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .unavailable
        }
    }
}

extension MapKitRecordShopDiscoveryService: CLLocationManagerDelegate {
    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard let continuation = authorizationContinuation else { return }
        authorizationContinuation = nil
        continuation.resume(returning: Self.mapAuthorizationStatus(manager.authorizationStatus))
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let continuation = locationContinuation else { return }
        locationContinuation = nil
        if let location = locations.last {
            continuation.resume(returning: location)
        } else {
            continuation.resume(throwing: CLError(.locationUnknown))
        }
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard let continuation = locationContinuation else { return }
        locationContinuation = nil
        continuation.resume(throwing: error)
    }
}

public protocol MapKitRecordShopSearching: Sendable {
    func searchRecordShops(near location: CLLocation, query: String) async throws -> [RecordShop]
    func searchRecordShops(in place: String, query: String) async throws -> [RecordShop]
}

public struct MapKitRecordShopSearcher: MapKitRecordShopSearching {
    public init() {}

    public func searchRecordShops(near location: CLLocation, query: String) async throws -> [RecordShop] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: 20_000,
            longitudinalMeters: 20_000)
        return try await search(request: request, origin: location)
    }

    public func searchRecordShops(in place: String, query: String) async throws -> [RecordShop] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "\(query) \(place)"
        return try await search(request: request, origin: nil)
    }

    private func search(request: MKLocalSearch.Request, origin: CLLocation?) async throws -> [RecordShop] {
        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems.map { item in
            let placemarkLocation = item.placemark.location
            let distance = origin.flatMap { origin in placemarkLocation?.distance(from: origin) }
            let directionsURL = item.placemark.location.flatMap { location in
                var components = URLComponents(string: "http://maps.apple.com/")!
                components.queryItems = [
                    URLQueryItem(name: "q", value: item.name ?? "Record Shop"),
                    URLQueryItem(name: "ll", value: "\(location.coordinate.latitude),\(location.coordinate.longitude)")
                ]
                return components.url
            }
            return RecordShop(
                id: itemIdentifier(item),
                name: item.name ?? "Record Shop",
                distanceMeters: distance,
                address: formattedAddress(for: item.placemark),
                phoneNumber: item.phoneNumber,
                websiteURL: item.url,
                directionsURL: directionsURL)
        }
    }

    private func itemIdentifier(_ item: MKMapItem) -> String {
        if let location = item.placemark.location {
            return [
                item.name ?? "record-shop",
                String(format: "%.5f", location.coordinate.latitude),
                String(format: "%.5f", location.coordinate.longitude)
            ].joined(separator: "-")
        }
        return item.name ?? UUID().uuidString
    }

    private func formattedAddress(for placemark: MKPlacemark) -> String? {
        [
            placemark.subThoroughfare,
            placemark.thoroughfare,
            placemark.locality,
            placemark.administrativeArea,
            placemark.postalCode
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: ", ")
    }
}
#endif
