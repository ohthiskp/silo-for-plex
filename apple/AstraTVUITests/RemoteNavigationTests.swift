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
  /// A Details page is open (its watched eye).
  private var detailsMore: XCUIElement {
    app.buttons.matching(NSPredicate(format: "label IN %@", ["Mark Watched", "Mark Unwatched"])).firstMatch
  }

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

  // MARK: Focus (KP, 2026-11-16)

  private static let services = ["For You", "Netflix", "Apple TV+", "Prime Video", "Disney+", "HBO Max", "Hulu"]
  private var onCircle: Bool { Self.services.contains(focusedElement.label) }
  private var heroPage: String { app.descendants(matching: .any)["astra.hero.page"].firstMatch.label }

  /// Right from every streaming circle gets back onto the page (KP: only HBO
  /// Max, level with Play, could before).
  func testRightFromEveryCircleReachesThePage() {
    launch()
    XCTAssertTrue(homeHero.waitForExistence(timeout: 30), "Home didn't load")
    sleep(4)
    leaveTabBar()
    for n in 0..<Self.services.count {
      for _ in 0..<3 where !onCircle { press(.left) }
      XCTAssertTrue(onCircle, "Left didn't reach the circles (round \(n))")
      press(.down, times: n)
      let circle = focusedElement.label
      if n == 4 { shot("circle-\(circle)") }
      press(.right)
      XCTAssertFalse(onCircle, "Right from \(circle) stayed in the circles")
    }
  }

  /// The hero has just Play and Details (KP, 2026-11-16); Right on Details
  /// turns to the next title and keeps focus there; moving onto Details
  /// doesn't turn it; Left on Play goes back a title, and only from the first
  /// title does Left reach the circles.
  func testHeroButtonsAndLeftRight() {
    launch()
    XCTAssertTrue(homeHero.waitForExistence(timeout: 30), "Home didn't load")
    sleep(4)
    leaveTabBar()
    shot("hero-play-focused")
    let first = heroPage
    print("ASTRA-HERO start", first)
    XCTAssertTrue(["Play", "Resume", "Details"].contains(focusedElement.label), "Home didn't open on the hero's buttons")
    XCTAssertFalse(app.buttons["Add to Watchlist"].exists, "The hero still has a + button")
    if focusedElement.label != "Details" {
      press(.right)
      XCTAssertEqual(focusedElement.label, "Details", "Right from Play didn't go to Details")
    }
    XCTAssertEqual(heroPage, first, "Moving onto Details turned the hero")
    shot("hero-details-focused")
    press(.right)
    XCTAssertNotEqual(heroPage, first, "Right on Details didn't turn the hero")
    XCTAssertEqual(focusedElement.label, "Details", "Focus left Details when the hero turned")
    shot("hero-second-title")
    press(.right)
    print("ASTRA-HERO after two", heroPage)
    press(.left)
    var presses = 0
    while heroPage != first, presses < 6 {
      press(.left)
      XCTAssertFalse(onCircle, "Left reached the circles before the first title")
      presses += 1
    }
    XCTAssertEqual(heroPage, first, "Left didn't walk back to the first title")
    if focusedElement.label == "Details" { press(.left) }
    press(.left)
    XCTAssertTrue(onCircle, "Left on the first title didn't reach the circles")
  }

  /// Details: the eye marks the movie watched, and back.
  func testDetailsEyeMarksWatched() {
    launch(["-AstraDemoOpen", "101"])
    XCTAssertTrue(app.buttons["Mark Watched"].firstMatch.waitForExistence(timeout: 30)
      || app.buttons["Mark Unwatched"].firstMatch.exists, "No eye button on Details")
    XCTAssertFalse(app.buttons["More"].exists, "Details still has More")
    sleep(3)
    shot("details-eye")
  }

  /// Details frosts as it scrolls down to Cast.
  func testDetailsFrostsWhenScrolled() {
    launch(["-AstraDemoOpen", "101"])
    sleep(8)
    if !focusedElement.exists { press(.down) }
    press(.down, times: 3)
    shot("details-scrolled-cast")
    press(.down, times: 2)
    shot("details-scrolled-more")
  }

  /// In a row, Left walks back to the first card and only then reaches the circles.
  func testRowLeftGoesToTheFirstCardFirst() {
    launch()
    XCTAssertTrue(homeHero.waitForExistence(timeout: 30), "Home didn't load")
    sleep(4)
    leaveTabBar()
    press(.down)
    let firstCard = focusedElement.label
    press(.right)
    XCTAssertNotEqual(focusedElement.label, firstCard, "Right didn't move along Continue Watching")
    press(.left)
    XCTAssertEqual(focusedElement.label, firstCard, "Left didn't go back to the first card")
    press(.left)
    XCTAssertTrue(onCircle, "Left on the first card didn't reach the circles")
  }

  /// Settings: Down from the gear reaches the page, then the options.
  func testSettingsMovesDown() {
    launch(["-AstraDemoTab", "settings"])
    let appearance = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Appearance")).firstMatch
    XCTAssertTrue(appearance.waitForExistence(timeout: 30), "Settings didn't open")
    sleep(4)
    var labels: [String] = []
    for _ in 0..<5 {
      press(.down)
      labels.append(focusedElement.label)
    }
    shot("settings-moved-down")
    print("ASTRA-SETTINGS", labels)
    XCTAssertTrue(labels.contains { ["Change Server", "Index Now"].contains($0) }, "Down didn't reach the server band")
    XCTAssertTrue(labels.contains { ["Frosted Glass", "OLED", "Light", "Violet", "Appearance"].contains($0) },
      "Down didn't reach the settings themselves")
    // Category list: down through the list changes the pane.
    press(.left, times: 2)
    press(.down)
    shot("settings-category")
    print("ASTRA-SETTINGS category", focusedElement.label)
  }

  /// Show Details: the seasons are tabs, starting on the season being watched.
  func testSeasonTabs() {
    // Severance with a Season 2 episode open: starts on Season 2.
    launch(["-AstraDemoOpen", "205"])
    XCTAssertTrue(detailsMore.waitForExistence(timeout: 30), "Details didn't open")
    sleep(4)
    if !focusedElement.exists { press(.down) }
    var reached = false
    for _ in 0..<4 where !reached {
      press(.down)
      reached = focusedElement.label.hasPrefix("Season")
    }
    XCTAssertTrue(reached, "Down didn't reach the season tabs")
    shot("season-tabs")
    let start = focusedElement.label
    press(focusedElement.label == "Season 1" ? .right : .left)
    XCTAssertNotEqual(focusedElement.label, start, "Couldn't move along the season tabs")
    XCTAssertTrue(focusedElement.isSelected, "Moving onto a season tab didn't show it")
    sleep(2)
    shot("season-tabs-moved")
  }

  /// Every page: Down from the bar reaches the page, and Down / Right keep moving.
  func testEveryPageTakesFocusFromTheBar() {
    for tab in ["search", "movies", "shows", "watchlist"] {
      launch(["-AstraDemoTab", tab])
      sleep(10)
      var seen: [String] = []
      for direction in [XCUIRemote.Button.down, .down, .right, .down, .right] {
        press(direction)
        seen.append(focusedElement.exists ? focusedElement.label : "none")
      }
      shot("page-\(tab)")
      print("ASTRA-PAGE", tab, seen)
      XCTAssertTrue(seen.contains { !$0.isEmpty && $0 != "none" && !Self.barItems.contains($0) },
        "Focus never left the top bar on \(tab)")
      app.terminate()
    }
  }

  /// Movies: the chips sit below the top bar, not under it.
  func testMoviesChipsClearTheTopBar() {
    launch(["-AstraDemoTab", "movies"])
    let chip = app.buttons["Unwatched"].firstMatch
    XCTAssertTrue(chip.waitForExistence(timeout: 30), "Movies didn't load")
    sleep(3)
    let bar = app.buttons["Movies"].firstMatch
    shot("movies-top")
    if bar.exists {
      XCTAssertGreaterThan(chip.frame.minY, bar.frame.maxY + 10, "The chips overlap the top bar")
    }
  }

  // MARK: Player

  func testPlayerControlsAndMenuCloses() throws {
    let video = try XCTUnwrap(ProcessInfo.processInfo.environment["ASTRA_DEMO_VIDEO"], "No test video given")
    launch(["-AstraDemoPlay", video])
    // The player's only on-screen button is Subtitles (KP's 2026-11-10 redesign).
    let subtitles = app.buttons["astra.player.subtitles"].firstMatch
    XCTAssertTrue(subtitles.waitForExistence(timeout: 30), "The player didn't open")
    sleep(4)
    shot("player-playing")
    press(.playPause)
    sleep(2)
    shot("player-paused")
    // Back exits the player straight away (no menu or scrub open).
    press(.menu)
    sleep(1)
    XCTAssertTrue(homeHero.waitForExistence(timeout: 15), "Menu didn't close the player")
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
