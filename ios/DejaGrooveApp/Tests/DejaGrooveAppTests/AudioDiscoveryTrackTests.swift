import XCTest
@testable import DejaGrooveApp

final class AudioDiscoveryTrackTests: XCTestCase {
    func testAppleMusicSearchURLUsesArtistAndTitle() {
        let track = AudioDiscoveryTrack(
            title: "Rock 'N' Roll Damnation",
            artist: "AC/DC",
            appleMusicId: "574050330",
            matchedAt: "2026-08-14T12:05:14Z")

        XCTAssertEqual(
            URL(string: "https://music.apple.com/search?term=AC/DC%20Rock%20'N'%20Roll%20Damnation"),
            track.appleMusicSearchURL)
    }
}
