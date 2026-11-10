import XCTest

/// Astra: the iPhone player's taps, driven like a finger in the simulator.
/// Runs against the demo server with a local test video
/// (`TEST_RUNNER_ASTRA_DEMO_VIDEO`, set by the launch-check workflow).
final class PlayerGestureTests: XCTestCase {
  private var app: XCUIApplication!

  override func setUpWithError() throws {
    continueAfterFailure = true
    let video = try XCTUnwrap(ProcessInfo.processInfo.environment["ASTRA_DEMO_VIDEO"], "No test video given")
    app = XCUIApplication()
    app.launchArguments = ["-AstraDemo", "YES", "-AstraDemoPlay", video]
    app.launch()
    // A real phone turns to landscape for the player; do the same.
    XCUIDevice.shared.orientation = .landscapeLeft
    // The player opens two seconds after launch, then rotates to landscape.
    XCTAssertTrue(app.buttons["Close Player"].waitForExistence(timeout: 20), "The player didn't open")
    sleep(5)
  }

  private func point(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
    app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y))
  }

  private func shot(_ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  private func badge(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }

  func testDoubleTapRightSkipsForward() {
    point(0.85, 0.5).doubleTap()
    // Checked before the screenshot: on a busy runner a screenshot can outlast the badge.
    let found = badge("astra.skip.forward").waitForExistence(timeout: 5)
    shot("after-double-tap-right")
    XCTAssertTrue(found, "No +10 s badge after a double tap on the right")
  }

  func testDoubleTapLeftSkipsBack() {
    point(0.15, 0.5).doubleTap()
    let found = badge("astra.skip.back").waitForExistence(timeout: 5)
    shot("after-double-tap-left")
    XCTAssertTrue(found, "No -10 s badge after a double tap on the left")
  }

  /// With the controls showing (a tap first), a double tap beside them still skips.
  func testDoubleTapWithControlsShowing() {
    sleep(5)
    point(0.5, 0.5).tap()
    sleep(1)
    shot("controls-showing")
    point(0.88, 0.45).doubleTap()
    let found = badge("astra.skip.forward").waitForExistence(timeout: 5)
    shot("after-double-tap-with-controls")
    XCTAssertTrue(found, "No +10 s badge when the controls were showing")
  }

  /// Whether `element` is on screen and tappable. Hidden controls can leave
  /// the button with no valid frame, and `isHittable` then fails the test
  /// ("Failed to determine hittability") instead of returning false.
  private func showing(_ element: XCUIElement) -> Bool {
    guard element.exists, !element.frame.isEmpty, element.frame.minX.isFinite else { return false }
    return element.isHittable
  }

  func testSingleTapTogglesControls() {
    let close = app.buttons["Close Player"]
    // The controls hide by themselves after a few seconds of playback.
    sleep(5)
    let before = showing(close)
    point(0.3, 0.35).tap()
    // The controls fade; give the change up to 5 s instead of one fixed look.
    var after = showing(close)
    for _ in 0..<10 where after == before {
      usleep(500_000)
      after = showing(close)
    }
    shot("after-single-tap")
    XCTAssertNotEqual(before, after, "A single tap didn't show or hide the controls (before: \(before))")
  }

  func testSwipeOnTheRightChangesVolume() {
    point(0.85, 0.7).press(forDuration: 0.05, thenDragTo: point(0.85, 0.3))
    shot("after-swipe-right")
    XCTAssertTrue(badge("astra.level.volume").waitForExistence(timeout: 2), "No volume level after a swipe on the right")
  }

  func testSwipeOnTheLeftChangesBrightness() {
    point(0.15, 0.3).press(forDuration: 0.05, thenDragTo: point(0.15, 0.7))
    shot("after-swipe-left")
    XCTAssertTrue(
      badge("astra.level.brightness").waitForExistence(timeout: 2), "No brightness level after a swipe on the left")
  }

  /// KP (2026-11-10): ⋯ top right opens Audio / Quality / Speed / Chapters.
  func testMoreMenuOpens() {
    point(0.5, 0.35).tap()
    let more = app.buttons["astra.player.more"]
    XCTAssertTrue(more.waitForExistence(timeout: 5), "No ⋯ button")
    if !showing(more) { point(0.5, 0.35).tap() }
    more.tap()
    let found = badge("astra.player.moreMenu").waitForExistence(timeout: 3)
    shot("more-menu")
    XCTAssertTrue(found, "The ⋯ menu didn't open")
  }
}
