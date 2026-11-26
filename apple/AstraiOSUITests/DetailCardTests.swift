import XCTest

/// Astra (KP, 2026-11-26): the iPhone Details card is a plain card like Plex's.
/// Dragging it doesn't close it; its X goes back to the page before. Driven
/// slowly against the demo server while the launch-check workflow records the
/// simulator's screen, so the motion can be watched without a phone.
final class DetailCardTests: XCTestCase {
  private var app: XCUIApplication!

  override func setUpWithError() throws {
    continueAfterFailure = true
    app = XCUIApplication()
    // Home scrolled to the poster rows.
    app.launchArguments = ["-AstraDemo", "YES", "-AstraDemoScroll", "640"]
    app.launch()
    sleep(12)
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

  /// A poster on Home: the first Top Trending one, else the hero.
  private func openTitle() {
    let poster = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Number '")).firstMatch
    if poster.waitForExistence(timeout: 5), poster.isHittable {
      poster.tap()
    } else {
      point(0.5, 0.3).tap()
    }
    sleep(3)
  }

  private var closeButton: XCUIElement { app.buttons["Close"].firstMatch }

  func testOnlyTheXClosesTheCard() {
    openTitle()
    XCTAssertTrue(closeButton.waitForExistence(timeout: 10), "Details didn't open as a card")
    shot("card-open")

    // Dragging the card down and to the side scrolls it; it stays open.
    point(0.5, 0.3).press(forDuration: 0.15, thenDragTo: point(0.72, 0.78), withVelocity: .slow, thenHoldForDuration: 0.8)
    sleep(2)
    shot("after-drag")
    XCTAssertTrue(closeButton.exists, "Dragging the card closed it")

    // The X goes back to Home.
    closeButton.tap()
    sleep(2)
    XCTAssertFalse(closeButton.exists, "The X didn't close the card")
    shot("after-close")
  }
}
