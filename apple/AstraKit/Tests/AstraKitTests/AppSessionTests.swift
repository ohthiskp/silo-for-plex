import XCTest

@testable import AstraKit

/// KP, 2026-11-14: the iPhone app was stopped twice and no crash screen showed,
/// because a kill by iOS (memory, watchdog) never reaches a signal handler.
final class AppSessionTests: XCTestCase {
  private func record(foreground: Bool = true) -> AppSessionRecord {
    AppSessionRecord(
      version: "3.1.0 (1)", osVersion: "27.1", bootTime: 1_000, launched: Date(timeIntervalSince1970: 1_794_000_000),
      inForeground: foreground)
  }

  func testOnScreenRunThatNeverEndedWasStoppedBySystem() {
    XCTAssertTrue(AppSession.endedUnexpectedly(record(), version: "3.1.0 (1)", osVersion: "27.1", bootTime: 1_001))
  }

  func testNormalEndsAreNotReported() {
    // First launch ever.
    XCTAssertFalse(AppSession.endedUnexpectedly(nil, version: "3.1.0 (1)", osVersion: "27.1", bootTime: 1_000))
    // In the background: iOS ends background apps all the time.
    XCTAssertFalse(
      AppSession.endedUnexpectedly(record(foreground: false), version: "3.1.0 (1)", osVersion: "27.1", bootTime: 1_000))
    // Quit normally.
    var quit = record()
    quit.endedCleanly = true
    XCTAssertFalse(AppSession.endedUnexpectedly(quit, version: "3.1.0 (1)", osVersion: "27.1", bootTime: 1_000))
    // A TestFlight update, an iOS update, a restart.
    XCTAssertFalse(AppSession.endedUnexpectedly(record(), version: "3.1.0 (2)", osVersion: "27.1", bootTime: 1_000))
    XCTAssertFalse(AppSession.endedUnexpectedly(record(), version: "3.1.0 (1)", osVersion: "27.2", bootTime: 1_000))
    XCTAssertFalse(AppSession.endedUnexpectedly(record(), version: "3.1.0 (1)", osVersion: "27.1", bootTime: 9_000))
  }

  func testMemoryKillReportReadsInPlainWords() {
    var r = record()
    r.note("Playing Dune: Part Two (4K)", at: Date(timeIntervalSince1970: 1_794_000_100))
    r.recordMemory(usedMB: 2_900, leftMB: 120)
    r.memoryWarnings = 2
    r.lastSeen = Date(timeIntervalSince1970: 1_794_000_200)
    let text = AppSession.report(for: r)
    XCTAssertTrue(text.contains("Playing Dune: Part Two (4K)"), text)
    XCTAssertTrue(text.contains("2900 MB in use, 120 MB left, peak 2900 MB, 2 low-memory warning(s)"), text)

    let s = CrashReportText.summary(of: text)
    XCTAssertEqual(s.what, "Stopped by iOS (watchdog or memory)")
    XCTAssertEqual(s.detail, "Astra ran out of memory and iOS closed it.")
    XCTAssertEqual(s.version, "3.1.0 (1)")
    XCTAssertEqual(s.time, Date(timeIntervalSince1970: 1_794_000_200))
  }

  func testFreezeIsNamed() {
    var r = record()
    r.frozenSince = Date(timeIntervalSince1970: 1_794_000_050)
    XCTAssertEqual(AppSession.likelyCause(of: r), .freeze)
    XCTAssertEqual(CrashReportText.summary(of: AppSession.report(for: r)).detail, "Astra stopped responding and iOS closed it.")
    XCTAssertEqual(AppSession.likelyCause(of: record()), .unknown)
  }

  func testActivityKeepsOnlyTheLatest() {
    var r = record()
    for i in 0..<30 { r.note("step \(i)") }
    XCTAssertEqual(r.activity.count, AppSessionRecord.activityLimit)
    XCTAssertTrue(r.activity.last!.hasSuffix("step 29"))
  }

  func testRecordSurvivesDisk() throws {
    var r = record()
    r.note("Opened Home")
    let back = try JSONDecoder().decode(AppSessionRecord.self, from: JSONEncoder().encode(r))
    XCTAssertEqual(back, r)
  }
}
