import XCTest

@testable import AstraKit

final class SkipMarkersTests: XCTestCase {
  private let intro = SkipMarker(kind: .intro, start: 60, end: 120)
  private let credits = SkipMarker(kind: .credits, start: 3300, end: 3420, isFinal: true)

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
    let mid = SkipMarker(kind: .credits, start: 3000, end: 3200, isFinal: false)
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
