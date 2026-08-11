import Foundation
import XCTest
@testable import DejaGrooveApp

final class DiscoveryServicesTests: XCTestCase {
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
