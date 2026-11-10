import Foundation
import XCTest

@testable import AstraKit

/// KP's player mockups (2026-11-10): audio names, subtitle size/style/sync, the clock.
final class PlayerOptionsTests: XCTestCase {
  func testAtmosFromMpvProfileOrPlexTitle() {
    XCTAssertEqual(
      AudioTrackLabel.make(language: "English", codec: "truehd", channels: 8, profile: "Dolby TrueHD + Dolby Atmos"),
      "English · Dolby Atmos 7.1")
    XCTAssertEqual(
      AudioTrackLabel.make(language: "English", codec: "eac3", channels: 6, plexTitle: "English (EAC3 5.1 Atmos)"),
      "English · Dolby Atmos 5.1")
  }

  func testPlainFormats() {
    XCTAssertEqual(AudioTrackLabel.make(language: "English", codec: "ac3", channels: 6), "English · Dolby Digital 5.1")
    XCTAssertEqual(AudioTrackLabel.make(language: "Spanish", codec: "aac", channels: 2), "Spanish · AAC Stereo")
    XCTAssertEqual(
      AudioTrackLabel.make(language: "English", codec: "dts", channels: 8, profile: "DTS-HD MA"), "English · DTS-HD MA 7.1")
    XCTAssertEqual(AudioTrackLabel.make(language: nil, codec: nil, channels: nil, trackTitle: "Track 2"), "Track 2")
  }

  func testCommentaryKeepsItsName() {
    XCTAssertEqual(
      AudioTrackLabel.make(language: "English", codec: "aac", channels: 2, trackTitle: "Director's Commentary"),
      "English · AAC Stereo · Director's Commentary")
    // A title that only repeats the format is dropped.
    XCTAssertEqual(
      AudioTrackLabel.make(language: "English", codec: "ac3", channels: 6, trackTitle: "Surround 5.1"),
      "English · Dolby Digital 5.1")
  }

  func testSubtitleSizeAndStyleAreSaved() throws {
    let defaults = try XCTUnwrap(UserDefaults(suiteName: "PlayerOptionsTests"))
    defaults.removePersistentDomain(forName: "PlayerOptionsTests")
    XCTAssertEqual(SubtitleSize.current(defaults), .medium)
    XCTAssertEqual(SubtitleLook.current(defaults), .whiteNoBackground)
    SubtitleSize.large.save(defaults)
    SubtitleLook.yellow.save(defaults)
    XCTAssertEqual(SubtitleSize.current(defaults), .large)
    XCTAssertEqual(SubtitleSize.current(defaults).scale, 1.25)
    XCTAssertEqual(SubtitleLook.current(defaults), .yellow)
    XCTAssertTrue(SubtitleLook.whiteOnBlack.mpvOptions.contains { $0.0 == "sub-border-style" && $0.1 == "background-box" })
  }

  func testSubtitleSync() {
    XCTAssertEqual(SubtitleSync.adjusted(0, by: 3), 0.3, accuracy: 0.0001)
    XCTAssertEqual(SubtitleSync.adjusted(0.3, by: -5), -0.2, accuracy: 0.0001)
    XCTAssertEqual(SubtitleSync.adjusted(9.95, by: 10), 10)
    XCTAssertEqual(SubtitleSync.label(0), "0.0s")
    XCTAssertEqual(SubtitleSync.label(0.3), "+0.3s")
    XCTAssertEqual(SubtitleSync.label(-1.2), "\u{2212}1.2s")
  }

  func testClockAndEndsAt() {
    XCTAssertEqual(PlaybackClock.format(18 * 60 + 14), "18:14")
    XCTAssertEqual(PlaybackClock.format(3600 + 37 * 60 + 32), "1:37:32")
    let utc = TimeZone(identifier: "UTC")!
    let now = Date(timeIntervalSince1970: 18 * 3600)  // 6:00 PM UTC
    let us = Locale(identifier: "en_US")
    XCTAssertEqual(
      PlaybackClock.endsAt(remaining: 52 * 60, now: now, locale: us, timeZone: utc).replacingOccurrences(of: "\u{202F}", with: " "),
      "Ends at 6:52 PM")
    // At 2× the film ends sooner.
    XCTAssertEqual(
      PlaybackClock.endsAt(remaining: 60 * 60, speed: 2, now: now, locale: us, timeZone: utc)
        .replacingOccurrences(of: "\u{202F}", with: " "),
      "Ends at 6:30 PM")
  }

  func testChaptersFromMpv() {
    let chapters = PlayerChapter.list(from: [
      ["title": "Opening", "time": 0.0] as [String: Any],
      ["time": 600.5] as [String: Any],
      ["title": "bad"] as [String: Any],
    ])
    XCTAssertEqual(chapters.map(\.title), ["Opening", "Chapter 2"])
    XCTAssertEqual(chapters[1].start, 600.5)
  }
}
