import Foundation
import XCTest
@testable import DejaGrooveApp

final class DiscoveryServicesTests: XCTestCase {
    func testRecognitionProxyAlbumMetadataEnricherPostsAlbumAndDecodesSharedMetadata() async throws {
        let payload = """
        {
          "album": {
            "discogs_release_id": "123456",
            "title": "Indigo",
            "artist": "Miki Yamanaka",
            "year": 2024,
            "format": "Vinyl, LP",
            "label": "Cellar Music",
            "catalog_number": "CM-123",
            "country": "US",
            "genres": ["Jazz"],
            "tracklist": [{ "position": "A1", "title": "Indigo", "duration": "4:12" }],
            "listening_links": [{ "provider": "Apple Music", "url": "https://music.apple.com/album/indigo" }]
          },
          "request_id": "f0a47ed2-0054-41e7-9ea8-6b74b3f4afe8"
        }
        """
        let transport = CapturingHttpTransport(data: Data(payload.utf8), statusCode: 200)
        let enricher = RecognitionProxyAlbumMetadataEnricher(
            baseURL: URL(string: "https://proxy.example")!,
            functionKey: "function-key",
            transport: transport)

        let album = try await enricher.enrich(album: Album(
            mbid: nil,
            discogsReleaseId: nil,
            title: "Indigo",
            artist: "Miki Yamanaka",
            year: 2024,
            format: nil))

        XCTAssertEqual(URL(string: "https://proxy.example/v1/enrich"), transport.lastRequest?.url)
        XCTAssertEqual("POST", transport.lastRequest?.httpMethod)
        XCTAssertEqual("function-key", transport.lastRequest?.value(forHTTPHeaderField: "x-functions-key"))
        XCTAssertEqual("123456", album.discogsReleaseId)
        XCTAssertEqual("Cellar Music", album.label)
        XCTAssertEqual("CM-123", album.catalogNumber)
        XCTAssertEqual("US", album.country)
        XCTAssertEqual("Indigo", album.tracklist.first?.title)
        XCTAssertEqual("Apple Music", album.listeningLinks.first?.provider)
    }

    func testAppleMusicAlbumCandidateResolverMapsCatalogResultsToAlbumCandidates() async throws {
        let payload = """
        {
          "results": [
            {
              "artistName": "Charles Mingus",
              "collectionName": "Mingus Ah Um",
              "collectionId": 1440857781,
              "collectionViewUrl": "https://music.apple.com/us/album/mingus-ah-um/1440857781",
              "artworkUrl100": "https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/artwork/100x100bb.jpg",
              "releaseDate": "1959-09-14T12:00:00Z"
            }
          ]
        }
        """
        let resolver = AppleMusicAlbumCandidateResolver(
            transport: StaticHttpTransport(data: Data(payload.utf8), statusCode: 200))

        let candidates = try await resolver.albumCandidates(for: AudioDiscoveryTrack(
            title: "Goodbye Pork Pie Hat",
            artist: "Charles Mingus",
            matchedAt: "2026-01-01T00:00:00Z"))

        XCTAssertEqual(1, candidates.count)
        XCTAssertEqual("Charles Mingus", candidates.first?.artist)
        XCTAssertEqual("Mingus Ah Um", candidates.first?.title)
        XCTAssertEqual(1959, candidates.first?.year)
        XCTAssertEqual("Apple Music", candidates.first?.listeningLinks.first?.provider)
        XCTAssertEqual("1440857781", candidates.first?.listeningLinks.first?.catalogId)
    }

    func testAppleMusicAlbumCandidateResolverFiltersCatalogResultsToMatchedArtist() async throws {
        let payload = """
        {
          "results": [
            {
              "artistName": "Iron Maiden",
              "collectionName": "Powerslave",
              "collectionId": 123,
              "collectionViewUrl": "https://music.apple.com/us/album/powerslave/123",
              "artworkUrl100": "https://is1-ssl.mzstatic.com/image/thumb/Music/powerslave/100x100bb.jpg",
              "releaseDate": "1984-09-03T12:00:00Z"
            },
            {
              "artistName": "Rusty Blade",
              "collectionName": "The Best Of Rusty Blade",
              "collectionId": 456,
              "collectionViewUrl": "https://music.apple.com/us/album/the-best-of-rusty-blade/456",
              "artworkUrl100": "https://is1-ssl.mzstatic.com/image/thumb/Music/rusty/100x100bb.jpg",
              "releaseDate": "2010-01-01T12:00:00Z"
            },
            {
              "artistName": "Various Artists",
              "collectionName": "Spider-Man: Into the Spider-Verse",
              "collectionId": 789,
              "collectionViewUrl": "https://music.apple.com/us/album/spider-verse/789",
              "artworkUrl100": "https://is1-ssl.mzstatic.com/image/thumb/Music/spider/100x100bb.jpg",
              "releaseDate": "2018-12-14T12:00:00Z"
            }
          ]
        }
        """
        let resolver = AppleMusicAlbumCandidateResolver(
            transport: StaticHttpTransport(data: Data(payload.utf8), statusCode: 200))

        let candidates = try await resolver.albumCandidates(for: AudioDiscoveryTrack(
            title: "Flash Of The Blade",
            artist: "Iron Maiden",
            matchedAt: "2026-08-15T15:16:00Z"))

        XCTAssertEqual(1, candidates.count)
        XCTAssertEqual("Iron Maiden", candidates.first?.artist)
        XCTAssertEqual("Powerslave", candidates.first?.title)
    }
}

private final class CapturingHttpTransport: HttpTransport, @unchecked Sendable {
    let data: Data
    let statusCode: Int
    private(set) var lastRequest: URLRequest?

    init(data: Data, statusCode: Int) {
        self.data = data
        self.statusCode = statusCode
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil)!
        return (data, response)
    }
}

private struct StaticHttpTransport: HttpTransport {
    let data: Data
    let statusCode: Int

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil)!
        return (data, response)
    }
}
