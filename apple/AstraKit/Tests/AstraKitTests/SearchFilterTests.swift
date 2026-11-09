import Foundation
import XCTest

@testable import AstraKit

/// KP (2026-11-09): Search's 4K, HD, Dolby Atmos, Dolby Vision and Bollywood chips.
final class SearchFilterTests: XCTestCase {
  private func movie(_ media: String) throws -> PlexMetadata {
    try JSONDecoder().decode(
      PlexMetadata.self, from: Data(#"{"ratingKey":"1","type":"movie","title":"T","Media":[\#(media)]}"#.utf8))
  }

  private let uhdListed = #"{"id":1,"width":3840,"height":2160,"Part":[{"id":1}]}"#
  private let hdListed = #"{"id":2,"width":1920,"height":800,"Part":[{"id":2}]}"#
  private let uhdFull = #"""
    {"id":3,"width":3840,"height":2160,"Part":[{"id":3,"Stream":[
      {"id":1,"streamType":1,"codec":"hevc","DOVIPresent":true},
      {"id":2,"streamType":2,"codec":"truehd","displayTitle":"English (TrueHD 7.1 Atmos)"}]}]}
    """#

  func testResolutionChipsUseTheListedVersions() throws {
    let both = try movie(uhdListed + "," + hdListed)
    XCTAssertEqual(SearchFilter.fourK.matches(both, language: nil), true)
    XCTAssertEqual(SearchFilter.hd.matches(both, language: nil), true)
    let hdOnly = try movie(hdListed)
    XCTAssertEqual(SearchFilter.fourK.matches(hdOnly, language: nil), false)
  }

  func testAtmosAndDolbyVisionNeedTheTracks() throws {
    let listed = try movie(uhdListed)
    XCTAssertNil(SearchFilter.atmos.matches(listed, language: nil), "a list copy can't tell")
    let full = try movie(uhdFull)
    XCTAssertEqual(SearchFilter.atmos.matches(full, language: nil), true)
    XCTAssertEqual(SearchFilter.dolbyVision.matches(full, language: nil), true)
    let plain = try movie(hdListed.replacingOccurrences(
      of: #""Part":[{"id":2}]"#, with: #""Part":[{"id":2,"Stream":[{"id":9,"streamType":1,"codec":"h264"}]}]"#))
    XCTAssertEqual(SearchFilter.dolbyVision.matches(plain, language: nil), false)
  }

  func testTitlesNotOnTheServerNeverPassAFormatChip() {
    let catalog = PlexMetadata(ratingKey: "tmdb:movie:1", type: .movie, title: "T")
    for filter in [SearchFilter.fourK, .hd, .atmos, .dolbyVision] {
      XCTAssertEqual(filter.matches(catalog, language: "en"), false, filter.title)
    }
  }

  func testBollywoodIsHindi() {
    let item = PlexMetadata(ratingKey: "tmdb:movie:1", type: .movie, title: "RRR")
    XCTAssertEqual(SearchFilter.bollywood.matches(item, language: "hi"), true)
    XCTAssertEqual(SearchFilter.bollywood.matches(item, language: "te"), false)
  }

  func testEveryChipAtOnce() throws {
    let full = try movie(uhdFull)
    XCTAssertEqual(SearchFilter.matches(full, language: "hi", all: [.fourK, .atmos, .bollywood]), true)
    XCTAssertEqual(SearchFilter.matches(full, language: "en", all: [.fourK, .bollywood]), false)
    XCTAssertNil(SearchFilter.matches(try movie(uhdListed), language: nil, all: [.fourK, .atmos]))
    XCTAssertEqual(SearchFilter.matches(try movie(hdListed), language: nil, all: [.fourK, .atmos]), false)
  }
}
