import XCTest

@testable import AstraKit

final class SkipMarkersTests: XCTestCase {
  func testMarkersRequestAndDecodeSkipUnknownTypes() async throws {
    let json = """
      {"MediaContainer":{"Metadata":[{"ratingKey":"7","type":"episode","title":"Pilot","Marker":[
        {"id":1,"type":"credits","startTimeOffset":"3300000","endTimeOffset":3420000,"final":true},
        {"id":2,"type":"commercial","startTimeOffset":10,"endTimeOffset":20},
        {"id":3,"type":"intro","startTimeOffset":62000,"endTimeOffset":122500}
      ]}]}}
      """
    let transport = FakeTransport { _ in (200, Data(json.utf8)) }
    let client = PlexServerClient(
      baseURL: URL(string: "https://s.test:32400")!, token: "t", serverName: "S", info: testInfo, transport: transport)
    let markers = try await client.markers(ratingKey: "7")
    let url = URLComponents(url: try XCTUnwrap(transport.requests.first?.url), resolvingAgainstBaseURL: false)!
    XCTAssertEqual(url.path, "/library/metadata/7")
    XCTAssertEqual(url.queryItems?.first { $0.name == "includeMarkers" }?.value, "1")
    XCTAssertEqual(
      markers,
      [
        PlexMarker(kind: .intro, start: 62, end: 122.5),
        PlexMarker(kind: .credits, start: 3300, end: 3420, isFinal: true),
      ])
  }

  func testNoMarkersIsEmpty() async throws {
    let json = #"{"MediaContainer":{"Metadata":[{"ratingKey":"7","type":"movie","title":"Film"}]}}"#
    let transport = FakeTransport { _ in (200, Data(json.utf8)) }
    let client = PlexServerClient(
      baseURL: URL(string: "https://s.test:32400")!, token: "t", serverName: "S", info: testInfo, transport: transport)
    let markers = try await client.markers(ratingKey: "7")
    XCTAssertEqual(markers, [])
  }

  private let intro = PlexMarker(kind: .intro, start: 60, end: 120)
  private let credits = PlexMarker(kind: .credits, start: 3300, end: 3420, isFinal: true)

  func testIntroPrompt() {
    XCTAssertNil(SkipPrompt.at(30, duration: 3420, markers: [intro, credits], hasNext: false))
    XCTAssertEqual(SkipPrompt.at(60, duration: 3420, markers: [intro, credits], hasNext: false), .intro(to: 120))
    XCTAssertEqual(SkipPrompt.at(100, duration: 3420, markers: [intro, credits], hasNext: true), .intro(to: 120))
    // Gone in the intro's last second and after it.
    XCTAssertNil(SkipPrompt.at(119.5, duration: 3420, markers: [intro, credits], hasNext: false))
    XCTAssertNil(SkipPrompt.at(200, duration: 3420, markers: [intro, credits], hasNext: false))
  }

  func testCreditsOnAMovieSkipToTheEnd() {
    XCTAssertEqual(SkipPrompt.at(3350, duration: 3420, markers: [credits], hasNext: false), .credits(to: 3420))
  }

  func testFinalCreditsOfAnEpisodeShowNextEpisode() {
    XCTAssertEqual(SkipPrompt.at(3350, duration: 3420, markers: [credits], hasNext: true), .nextEpisode)
  }

  func testMidEpisodeCreditsSkipToTheSceneAfter() {
    let mid = PlexMarker(kind: .credits, start: 3000, end: 3200, isFinal: false)
    XCTAssertEqual(SkipPrompt.at(3100, duration: 3420, markers: [mid], hasNext: true), .credits(to: 3200))
  }

  func testLastSecondsShowNextEpisodeWithoutMarkers() {
    XCTAssertEqual(SkipPrompt.at(3410, duration: 3420, markers: [], hasNext: true), .nextEpisode)
    XCTAssertNil(SkipPrompt.at(3410, duration: 3420, markers: [], hasNext: false))
    XCTAssertNil(SkipPrompt.at(3000, duration: 3420, markers: [], hasNext: true))
  }

  func testUnknownDurationShowsNothing() {
    XCTAssertNil(SkipPrompt.at(70, duration: 0, markers: [intro], hasNext: false))
  }
}
