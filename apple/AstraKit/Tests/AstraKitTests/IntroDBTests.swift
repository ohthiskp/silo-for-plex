import XCTest

@testable import AstraKit

final class IntroDBTests: XCTestCase {
  func testEpisodeRequestAndDecode() async throws {
    let json = """
      {"imdb_id":"tt0387199","media_type":"tv","is_movie":false,"season":1,"episode":1,
       "intro":{"start_sec":0,"end_sec":69,"start_ms":0,"end_ms":69000,"confidence":1,"submission_count":1},
       "recap":null,"outro":{"start_sec":1700.5,"end_sec":1745,"start_ms":1700500,"end_ms":1745000},
       "post_credits":null,"no_intro":false,"no_recap":false,"no_outro":false}
      """
    let transport = FakeTransport { _ in (200, Data(json.utf8)) }
    let markers = try await IntroDBClient(transport: transport).markers(imdbID: "tt0387199", season: 1, episode: 1)
    let url = URLComponents(url: try XCTUnwrap(transport.requests.first?.url), resolvingAgainstBaseURL: false)!
    XCTAssertEqual(url.host, "api.introdb.app")
    XCTAssertEqual(url.path, "/segments")
    let query = Dictionary(uniqueKeysWithValues: (url.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    XCTAssertEqual(query, ["imdb_id": "tt0387199", "season": "1", "episode": "1"])
    XCTAssertEqual(
      markers,
      [PlexMarker(kind: .intro, start: 0, end: 69), PlexMarker(kind: .credits, start: 1700.5, end: 1745, isFinal: true)])
  }

  func testMovieRequestAndNothingTimed() async throws {
    let json = #"{"imdb_id":"tt0371746","is_movie":true,"intro":null,"outro":null,"post_credits":null}"#
    let transport = FakeTransport { _ in (200, Data(json.utf8)) }
    let markers = try await IntroDBClient(transport: transport).markers(imdbID: "tt0371746", season: nil, episode: nil)
    let url = URLComponents(url: try XCTUnwrap(transport.requests.first?.url), resolvingAgainstBaseURL: false)!
    XCTAssertEqual(url.queryItems?.first { $0.name == "is_movie" }?.value, "true")
    XCTAssertEqual(markers, [])
  }

  func testCreditsBeforeAPostCreditsSceneAreNotFinal() async throws {
    let json = """
      {"intro":null,"outro":{"start_sec":7000,"end_sec":7400},"post_credits":{"start_sec":7400,"end_sec":7460}}
      """
    let transport = FakeTransport { _ in (200, Data(json.utf8)) }
    let markers = try await IntroDBClient(transport: transport).markers(imdbID: "tt1", season: nil, episode: nil)
    XCTAssertEqual(markers, [PlexMarker(kind: .credits, start: 7000, end: 7400, isFinal: false)])
  }

  func testPlexMarkersWinAndIntroDBFillsTheGap() {
    let plexCredits = PlexMarker(kind: .credits, start: 1690, end: 1745, isFinal: true)
    let merged = PlexMarker.merged(
      plex: [plexCredits],
      introDB: [PlexMarker(kind: .intro, start: 0, end: 69), PlexMarker(kind: .credits, start: 1700, end: 1745)])
    XCTAssertEqual(merged, [PlexMarker(kind: .intro, start: 0, end: 69), plexCredits])
  }

  func testIMDbIDFromGuids() {
    var item = PlexMetadata(ratingKey: "1", type: .show, title: "Entourage")
    item.guids = [PlexGuid(id: "tmdb://1"), PlexGuid(id: "imdb://tt0387199")]
    XCTAssertEqual(item.imdbID, "tt0387199")
  }
}
