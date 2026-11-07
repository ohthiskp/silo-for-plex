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

  func testDoubleTapRightSkipsForward() {
    point(0.85, 0.5).doubleTap()
    let badge = app.otherElements["astra.skip.forward"].firstMatch
    let any = app.descendants(matching: .any)["astra.skip.forward"]
    shot("after-double-tap-right")
    XCTAssertTrue(badge.waitForExistence(timeout: 2) || any.exists, "No +10 s badge after a double tap on the right")
  }

  func testDoubleTapLeftSkipsBack() {
    point(0.15, 0.5).doubleTap()
    let any = app.descendants(matching: .any)["astra.skip.back"]
    shot("after-double-tap-left")
    XCTAssertTrue(any.waitForExistence(timeout: 2), "No -10 s badge after a double tap on the left")
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
