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
    shot("after-double-tap-right")
    XCTAssertTrue(badge("astra.skip.forward").waitForExistence(timeout: 3), "No +10 s badge after a double tap on the right")
  }

  func testDoubleTapLeftSkipsBack() {
    point(0.15, 0.5).doubleTap()
    shot("after-double-tap-left")
    XCTAssertTrue(badge("astra.skip.back").waitForExistence(timeout: 3), "No -10 s badge after a double tap on the left")
  }

  /// With the controls showing (a tap first), a double tap beside them still skips.
  func testDoubleTapWithControlsShowing() {
    sleep(5)
    point(0.5, 0.5).tap()
    sleep(1)
    shot("controls-showing")
    point(0.88, 0.45).doubleTap()
    shot("after-double-tap-with-controls")
    XCTAssertTrue(
      badge("astra.skip.forward").waitForExistence(timeout: 3), "No +10 s badge when the controls were showing")
  }

  func testSingleTapTogglesControls() {
    let close = app.buttons["Close Player"]
    // The controls hide by themselves after a few seconds of playback.
    sleep(5)
    let before = close.isHittable
    point(0.3, 0.35).tap()
    sleep(2)
    let after = close.isHittable
    shot("after-single-tap")
    XCTAssertNotEqual(before, after, "A single tap didn't show or hide the controls (before: \(before))")
  }
}
