import XCTest
@testable import DejaGrooveApp

@MainActor
final class NearbyRecordShopsViewModelTests: XCTestCase {
    func testFindNearCurrentLocationReportsDeniedWithoutSearching() async {
        let service = StubRecordShopDiscoveryService(authorization: .denied)
        let sut = NearbyRecordShopsViewModel(album: Self.album, discoveryService: service)

        await sut.findNearCurrentLocation()

        XCTAssertEqual(.locationDenied, sut.state)
        let currentLocationCalls = await service.currentLocationSearchCount
        XCTAssertEqual(0, currentLocationCalls)
    }

    func testFindNearCurrentLocationReturnsNoShopState() async {
        let service = StubRecordShopDiscoveryService(authorization: .authorized, currentLocationResults: [])
        let sut = NearbyRecordShopsViewModel(album: Self.album, discoveryService: service)

        await sut.findNearCurrentLocation()

        XCTAssertEqual(.loaded([]), sut.state)
    }

    func testFindNearCurrentLocationReturnsNearbyShopsWithUnknownInventory() async {
        let opportunity = RecordShopOpportunity(
            shop: RecordShop(
                id: "rough-trade",
                name: "Rough Trade",
                distanceMeters: 350,
                address: "64 Rue Example",
                phoneNumber: "+33123456789",
                websiteURL: URL(string: "https://example.com"),
                directionsURL: URL(string: "http://maps.apple.com/?q=Rough%20Trade")),
            inventoryStatus: .unknown)
        let service = StubRecordShopDiscoveryService(authorization: .authorized, currentLocationResults: [opportunity])
        let sut = NearbyRecordShopsViewModel(album: Self.album, discoveryService: service)

        await sut.findNearCurrentLocation()

        XCTAssertEqual(.loaded([opportunity]), sut.state)
        XCTAssertFalse(opportunity.inventoryStatus.isVerifiedAvailable)
    }

    func testSearchPlaceTrimsManualLocationAndReturnsResults() async {
        let opportunity = RecordShopOpportunity(
            shop: RecordShop(
                id: "amoeba",
                name: "Amoeba Music",
                distanceMeters: nil,
                address: "Los Angeles, CA",
                phoneNumber: nil,
                websiteURL: nil,
                directionsURL: nil),
            inventoryStatus: .unknown)
        let service = StubRecordShopDiscoveryService(authorization: .notDetermined, placeResults: [opportunity])
        let sut = NearbyRecordShopsViewModel(album: Self.album, discoveryService: service)
        sut.placeSearch = "  Los Angeles  "

        await sut.searchPlace()

        XCTAssertEqual(.loaded([opportunity]), sut.state)
        let searchedPlaces = await service.searchedPlaces
        XCTAssertEqual(["Los Angeles"], searchedPlaces)
    }

    func testAvailableInventoryRequiresReliableSource() {
        XCTAssertFalse(RecordShopInventoryStatus.unknown.isVerifiedAvailable)
        XCTAssertTrue(RecordShopInventoryStatus.available(source: "Store catalog", checkedAt: "2026-08-29T00:00:00Z").isVerifiedAvailable)
    }

    private static let album = Album(
        mbid: nil,
        discogsReleaseId: nil,
        title: "Mingus Ah Um",
        artist: "Charles Mingus",
        year: 1959,
        format: "Vinyl")
}

private actor StubRecordShopDiscoveryService: RecordShopDiscoveryService {
    let authorization: RecordShopLocationAuthorizationStatus
    let currentLocationResults: [RecordShopOpportunity]
    let placeResults: [RecordShopOpportunity]
    private(set) var currentLocationSearchCount = 0
    private(set) var searchedPlaces: [String] = []

    init(
        authorization: RecordShopLocationAuthorizationStatus,
        currentLocationResults: [RecordShopOpportunity] = [],
        placeResults: [RecordShopOpportunity] = []
    ) {
        self.authorization = authorization
        self.currentLocationResults = currentLocationResults
        self.placeResults = placeResults
    }

    var authorizationStatus: RecordShopLocationAuthorizationStatus {
        authorization
    }

    func requestLocationAuthorization() async -> RecordShopLocationAuthorizationStatus {
        authorization
    }

    func shopsNearCurrentLocation(for album: Album) async throws -> [RecordShopOpportunity] {
        currentLocationSearchCount += 1
        return currentLocationResults
    }

    func shops(matching place: String, for album: Album) async throws -> [RecordShopOpportunity] {
        searchedPlaces.append(place)
        return placeResults
    }
}
