import XCTest

/// Astra on Apple TV, driven with the Siri Remote in the simulator (KP,
/// 2026-11-09: "menu/back button doesn't work … make scrolling work"):
/// Menu leaves Details and the player, the pages scroll, the streaming
/// sidebar opens. Runs against the demo server; the player test plays a local
/// video (`TEST_RUNNER_ASTRA_DEMO_VIDEO`, set by the launch-check workflow).
final class RemoteNavigationTests: XCTestCase {
  private var app: XCUIApplication!
  private let remote = XCUIRemote.shared

  override func setUpWithError() throws {
    continueAfterFailure = false
    app = XCUIApplication()
  }

  private func launch(_ arguments: [String] = []) {
    app.launchArguments = ["-AstraDemo", "YES"] + arguments
    app.launch()
  }

  private func press(_ button: XCUIRemote.Button, times: Int = 1) {
    for _ in 0..<times {
      remote.press(button)
      usleep(700_000)
      let focus = focusedElement
      print("ASTRA-FOCUS \(name) press \(button.rawValue) ->", focus.exists ? "\(focus.elementType.rawValue) '\(focus.label)' \(focus.frame)" : "none")
    }
  }

  private func shot(_ name: String) {
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  /// Home is on screen (its Continue Watching row).
  private var homeHero: XCUIElement { app.staticTexts["Continue Watching"].firstMatch }
  /// A Details page is open (its More button).
  private var detailsMore: XCUIElement { app.buttons["More"].firstMatch }

  private var focusedElement: XCUIElement {
    app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
  }

  private static let barItems = ["Search", "Home", "Movies", "Shows", "Watchlist", "Settings"]

  /// tvOS starts with focus in the tab bar; move down into the page (it
  /// can take a moment to have something focusable while Home loads).
  private func leaveTabBar() {
    for _ in 0..<8 {
      let label = focusedElement.exists ? focusedElement.label : ""
      guard label.isEmpty || Self.barItems.contains(label) else { return }
      press(.down)
      sleep(1)
    }
  }

  private func waitGone(_ element: XCUIElement, timeout: TimeInterval = 8) -> Bool {
    let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: element)
    return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
  }

  // MARK: Menu / Back

  func testMenuClosesDetailsOpenedAtLaunch() {
    launch(["-AstraDemoOpen", "101"])
    XCTAssertTrue(detailsMore.waitForExistence(timeout: 30), "Details didn't open")
    sleep(3)
    shot("details-before-menu")
    // Opened straight from launch nothing has focus yet; a first press gives it.
    if !focusedElement.exists { press(.down) }
    press(.menu)
    XCTAssertTrue(waitGone(detailsMore), "Menu didn't close Details")
    XCTAssertTrue(homeHero.waitForExistence(timeout: 10), "Menu didn't go back to Home")
    shot("home-after-menu")
  }

  func testOpenFromRowThenMenuGoesBack() {
    launch()
    XCTAssertTrue(homeHero.waitForExistence(timeout: 30), "Home didn't load")
    sleep(3)
    // Down from the hero into Continue Watching, then open the first card.
    leaveTabBar()
    press(.down)
    shot("home-row-focused")
    press(.select)
    XCTAssertTrue(detailsMore.waitForExistence(timeout: 15), "Selecting a card didn't open Details")
    sleep(2)
    shot("details-from-row")
    press(.menu)
    XCTAssertTrue(waitGone(detailsMore), "Menu didn't close Details")
    shot("home-after-back")
    // A second round trip, in case the first left focus somewhere stuck.
    press(.select)
    XCTAssertTrue(detailsMore.waitForExistence(timeout: 15), "Couldn't open Details a second time")
    press(.menu)
    XCTAssertTrue(waitGone(detailsMore), "Menu didn't close Details the second time")
  }

  func testLibraryScrollsAndMenuGoesBack() {
    launch(["-AstraDemoTab", "libraries"])
    XCTAssertTrue(app.buttons["Unwatched"].firstMatch.waitForExistence(timeout: 30), "Movies didn't load")
    sleep(4)
    // Down from the bar through the chips into the grid, and further down its rows.
    leaveTabBar()
    press(.down, times: 2)
    shot("library-grid-focused")
    press(.down, times: 2)
    shot("library-scrolled")
    press(.select)
    XCTAssertTrue(detailsMore.waitForExistence(timeout: 15), "Selecting a poster didn't open Details")
    sleep(2)
    press(.menu)
    XCTAssertTrue(waitGone(detailsMore), "Menu didn't go back to Library")
    shot("library-after-back")
  }

  // MARK: Scrolling

  func testHomeScrollsDownTheRows() {
    launch()
    XCTAssertTrue(homeHero.waitForExistence(timeout: 30), "Home didn't load")
    sleep(4)
    let greats = app.staticTexts["All-Time Greats"].firstMatch
    let screen = app.windows.firstMatch.frame
    press(.down, times: 2)
    shot("home-scrolled-1")
    press(.down, times: 6)
    shot("home-scrolled-2")
    XCTAssertTrue(greats.exists, "No All-Time Greats row")
    XCTAssertLessThan(greats.frame.minY, screen.maxY, "Scrolling down didn't bring the last row on screen")
    // Up again to the hero.
    press(.up, times: 10)
    shot("home-back-to-top")
    XCTAssertGreaterThan(homeHero.frame.minY, screen.minY, "Scrolling up didn't return to the hero")
  }

  // MARK: Streaming sidebar and top bar

  func testStreamingCirclesOnTheLeft() {
    launch()
    XCTAssertTrue(homeHero.waitForExistence(timeout: 30), "Home didn't load")
    sleep(4)
    let netflix = app.buttons["Netflix"].firstMatch
    XCTAssertTrue(netflix.exists, "No Netflix in the sidebar")
    let size = netflix.frame.size
    leaveTabBar()
    press(.left, times: 2)
    sleep(1)
    shot("sidebar-focused")
    let services = ["For You", "Netflix", "Apple TV+", "Prime Video", "Disney+", "HBO Max", "Hulu"]
    XCTAssertTrue(services.contains(focusedElement.label), "Moving left didn't reach the streaming circles")
    // A fixed list: the circles don't grow into a panel.
    XCTAssertEqual(netflix.frame.width, size.width, accuracy: 30, "The sidebar changed size")
    press(.select)
    sleep(4)
    press(.right)
    sleep(1)
    shot("sidebar-after-choosing")
    XCTAssertFalse(services.contains(focusedElement.label), "Moving right didn't leave the circles")
  }

  func testTopBarMenuAndSettings() {
    launch()
    XCTAssertTrue(homeHero.waitForExistence(timeout: 30), "Home didn't load")
    sleep(4)
    leaveTabBar()
    press(.down)
    // Menu from the page goes up to the bar.
    press(.menu)
    sleep(1)
    shot("top-bar-focused")
    // (XCUITest can't read focus on the bar's items, so the bar is checked
    // by where Select goes from it.)
    // Right along the bar: Movies, Shows, Watchlist, then Settings at the far right.
    press(.right, times: 4)
    press(.select)
    sleep(3)
    shot("settings")
    let appearance = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Appearance")).firstMatch
    XCTAssertTrue(appearance.waitForExistence(timeout: 10), "Settings didn't open")
    // And back to Movies.
    press(.left, times: 3)
    press(.select)
    sleep(4)
    shot("movies")
    XCTAssertTrue(app.buttons["Unwatched"].firstMatch.waitForExistence(timeout: 10), "Movies didn't open")
  }

  // MARK: Player

  func testPlayerControlsAndMenuCloses() throws {
    let video = try XCTUnwrap(ProcessInfo.processInfo.environment["ASTRA_DEMO_VIDEO"], "No test video given")
    launch(["-AstraDemoPlay", video])
    let close = app.buttons["Close player"].firstMatch
    XCTAssertTrue(close.waitForExistence(timeout: 30), "The player didn't open")
    sleep(4)
    shot("player-playing")
    press(.playPause)
    sleep(2)
    shot("player-paused")
    // Down to the buttons row.
    press(.down)
    sleep(1)
    shot("player-buttons")
    // Menu: back to the timeline, hide the controls, then close (one press
    // at a time, so a spare press doesn't leave the app).
    for _ in 0..<4 where close.exists {
      press(.menu)
      sleep(1)
      print("ASTRA-FOCUS after Menu:", focusedElement.exists ? focusedElement.label : "none", "player open:", close.exists)
    }
    let closed = waitGone(close, timeout: 10)
    if !closed { print("ASTRA-FOCUS final:", focusedElement.debugDescription) }
    XCTAssertTrue(closed, "Menu didn't close the player")
    XCTAssertTrue(homeHero.waitForExistence(timeout: 10), "Closing the player didn't return to Home")
    sleep(2)
    shot("home-after-player")
    // Menu and Select still work after the player: down into Continue
    // Watching, open the first card.
    leaveTabBar()
    press(.down)
    press(.select)
    XCTAssertTrue(detailsMore.waitForExistence(timeout: 15), "Couldn't open Details after the player")
    press(.menu)
    XCTAssertTrue(waitGone(detailsMore), "Menu didn't close Details after the player")
  }
}
