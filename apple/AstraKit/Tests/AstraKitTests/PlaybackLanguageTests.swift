import XCTest

@testable import AstraKit

final class PlaybackLanguageTests: XCTestCase {
  func testMatchesTwoAndThreeLetterCodes() {
    let english = PlaybackLanguage(code: "en")
    XCTAssertTrue(english.matches("eng"))
    XCTAssertTrue(english.matches("en"))
    XCTAssertTrue(english.matches("en-US"))
    XCTAssertTrue(english.matches("English"))
    XCTAssertFalse(english.matches("hin"))
    XCTAssertFalse(english.matches(nil))
    XCTAssertTrue(PlaybackLanguage(code: "fr").matches("fre"))
    XCTAssertTrue(PlaybackLanguage(code: "fr").matches("fra"))
    XCTAssertFalse(PlaybackLanguage.automatic.matches("eng"))
  }

  func testPickFirstTrackInLanguage() {
    let tracks: [(id: Int, language: String?)] = [(1, "hin"), (2, nil), (3, "eng"), (4, "eng")]
    XCTAssertEqual(PlaybackLanguage(code: "en").pick(from: tracks), 3)
    XCTAssertNil(PlaybackLanguage(code: "ja").pick(from: tracks))
    XCTAssertNil(PlaybackLanguage.automatic.pick(from: tracks))
  }

  func testMpvValueAndStoredDefault() {
    XCTAssertEqual(PlaybackLanguage(code: "en").mpvValue, "en,eng")
    let defaults = UserDefaults(suiteName: "astra.tests.languages")!
    defaults.removePersistentDomain(forName: "astra.tests.languages")
    XCTAssertTrue(PlaybackLanguage.audio(defaults).isAutomatic)
    defaults.set("en", forKey: PlaybackLanguage.audioKey)
    XCTAssertEqual(PlaybackLanguage.audio(defaults).code, "en")
    XCTAssertEqual(PlaybackLanguage(code: "en").title, "English")
  }

  func testSubtitleLanguageReplacesDeviceLanguages() {
    let english = PlaybackLanguage(code: "en")
    let always = SubtitlePreference.always.mpvOptions(languages: ["fr-FR"], preferred: english)
    XCTAssertEqual(always.first { $0.0 == "slang" }?.1, "en,eng")
    let auto = SubtitlePreference.automatic.mpvOptions(languages: ["fr"], preferred: english)
    XCTAssertEqual(auto.first { $0.0 == "slang" }?.1, "en,eng")
    XCTAssertEqual(SubtitlePreference.off.mpvOptions(languages: ["en"], preferred: english).map(\.1), ["no"])
  }
}
