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

final class AutoSkipCountdownTests: XCTestCase {
  func testFillsOverFiveSecondsThenFiresOnce() {
    var c = AutoSkipCountdown()
    let p = SkipPrompt.intro(to: 69)
    XCTAssertEqual(c.update(prompt: p, position: 10, intro: true, credits: false).progress, 0)
    XCTAssertEqual(c.update(prompt: p, position: 12.5, intro: true, credits: false).progress, 0.5)
    XCTAssertEqual(c.update(prompt: p, position: 15, intro: true, credits: false), .init(progress: 1, fire: true))
    // Seeking back into the same intro doesn't start it again.
    XCTAssertEqual(c.update(prompt: p, position: 11, intro: true, credits: false), .init(progress: nil, fire: false))
  }

  func testOffNextEpisodeAndCreditsSetting() {
    var c = AutoSkipCountdown()
    XCTAssertNil(c.update(prompt: .intro(to: 69), position: 3, intro: false, credits: true).progress)
    XCTAssertNil(c.update(prompt: .nextEpisode, position: 3, intro: true, credits: true).progress)
    XCTAssertNil(c.update(prompt: .credits(to: 3420), position: 3300, intro: true, credits: false).progress)
    XCTAssertEqual(c.update(prompt: .credits(to: 3420), position: 3300, intro: false, credits: true).progress, 0)
  }

  func testCancelKeepsTheButtonButStopsTheFill() {
    var c = AutoSkipCountdown()
    _ = c.update(prompt: .intro(to: 69), position: 1, intro: true, credits: false)
    c.cancel()
    XCTAssertEqual(c.update(prompt: .intro(to: 69), position: 9, intro: true, credits: false), .init(progress: nil, fire: false))
  }

  func testSeekBackWithinTheCountdownRestartsIt() {
    var c = AutoSkipCountdown()
    _ = c.update(prompt: .intro(to: 69), position: 20, intro: true, credits: false)
    XCTAssertEqual(c.update(prompt: .intro(to: 69), position: 18, intro: true, credits: false).progress, 0)
  }
}

extension AutoSkipCountdownTests {
  func testNoDelaySkipsAtOnceWithoutAFill() {
    var c = AutoSkipCountdown()
    XCTAssertEqual(
      c.update(prompt: .intro(to: 69), position: 0, intro: true, credits: false, delay: 0), .init(progress: nil, fire: true))
  }

  func testTenSecondDelay() {
    var c = AutoSkipCountdown()
    _ = c.update(prompt: .intro(to: 69), position: 0, intro: true, credits: false, delay: 10)
    XCTAssertEqual(c.update(prompt: .intro(to: 69), position: 5, intro: true, credits: false, delay: 10).progress, 0.5)
  }
}
