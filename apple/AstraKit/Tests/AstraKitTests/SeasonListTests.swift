import XCTest

@testable import AstraKit

final class SeasonListTests: XCTestCase {
  private func season(_ key: String, _ index: Int?) -> PlexMetadata {
    var s = PlexMetadata(ratingKey: key, type: .season, title: index == 0 ? "Specials" : "Season \(index ?? -1)")
    s.index = index
    return s
  }

  private lazy var seasons = [season("10", 0), season("11", 1), season("12", 2)]

  func testSpecialsHiddenByDefault() {
    XCTAssertEqual(SeasonList.visible(seasons, showSpecials: false).map(\.ratingKey), ["11", "12"])
  }

  func testSpecialsShownWhenTurnedOn() {
    XCTAssertEqual(SeasonList.visible(seasons, showSpecials: true).map(\.ratingKey), ["10", "11", "12"])
  }

  func testSpecialsKeptWhenOpenedFromOne() {
    XCTAssertEqual(SeasonList.visible(seasons, showSpecials: false, keeping: "10").map(\.ratingKey), ["10", "11", "12"])
    XCTAssertEqual(SeasonList.visible(seasons, showSpecials: false, keeping: "11").map(\.ratingKey), ["11", "12"])
  }

  func testSeasonWithoutIndexIsNotSpecials() {
    XCTAssertFalse(SeasonList.isSpecials(season("13", nil)))
  }
}
