import XCTest

@testable import AstraKit

final class MediaFileNameTests: XCTestCase {
  func testSceneMovieName() {
    let name = MediaFileName.parse("The.Matrix.1999.1080p.BluRay.x264-GROUP.mkv", content: .movies)
    XCTAssertEqual(name.kind, .movie)
    XCTAssertEqual(name.title, "The Matrix")
    XCTAssertEqual(name.year, 1999)
    XCTAssertEqual(name.height, 1080)
    XCTAssertEqual(name.matchKey, "movie:the matrix:1999")
  }

  func testPlexStyleMovieWithBracketsAndVersion() {
    let name = MediaFileName.parse("Dune Part Two (2024)/Dune Part Two (2024) [2160p DV] {tmdb-693134}.mkv", content: .movies)
    XCTAssertEqual(name.title, "Dune Part Two")
    XCTAssertEqual(name.year, 2024)
    XCTAssertEqual(name.dynamicRange, "Dolby Vision")
    XCTAssertEqual(name.height, 2160)
  }

  func testYearAsFirstWordStaysInTitle() {
    let name = MediaFileName.parse("2001 A Space Odyssey (1968).mp4", content: .movies)
    XCTAssertEqual(name.title, "2001 A Space Odyssey")
    XCTAssertEqual(name.year, 1968)
  }

  func testGenericFileTakesFolderName() {
    let name = MediaFileName.parse("Alien (1979)/movie.mkv", content: .movies)
    XCTAssertEqual(name.title, "Alien")
    XCTAssertEqual(name.year, 1979)
  }

  func testEpisodeInShowFolder() {
    let name = MediaFileName.parse("Breaking Bad (2008)/Season 2/Breaking.Bad.S02E05.720p.mkv", content: .shows)
    XCTAssertEqual(name.kind, .episode)
    XCTAssertEqual(name.title, "Breaking Bad")
    XCTAssertEqual(name.year, 2008)
    XCTAssertEqual(name.season, 2)
    XCTAssertEqual(name.episode, 5)
    XCTAssertEqual(name.height, 720)
  }

  func testEpisodeWithoutFolders() {
    let name = MediaFileName.parse("Severance.S01E01-E02.Good.News.About.Hell.mkv", content: .shows)
    XCTAssertEqual(name.title, "Severance")
    XCTAssertEqual(name.season, 1)
    XCTAssertEqual(name.episode, 1)
    XCTAssertEqual(name.episodeEnd, 2)
  }

  func testCrossFormatAndLooseNumbering() {
    XCTAssertEqual(MediaFileName.parse("Lost/Lost 1x04.avi", content: .shows).episode, 4)
    let loose = MediaFileName.parse("The Wire/Season 3/07 - Back Burners.mkv", content: .shows)
    XCTAssertEqual(loose.kind, .episode)
    XCTAssertEqual(loose.title, "The Wire")
    XCTAssertEqual(loose.season, 3)
    XCTAssertEqual(loose.episode, 7)
  }

  func testSourceKeysRoundTrip() {
    let key = SourceKey.make("ab12cd34", "e/f1/tv:lost:/1/4")
    XCTAssertEqual(SourceKey.split(key)?.source, "ab12cd34")
    XCTAssertEqual(SourceKey.split(key)?.native, "e/f1/tv:lost:/1/4")
    XCTAssertNil(SourceKey.split("12345"))
    XCTAssertNil(SourceKey.split("/library/metadata/1"))
    XCTAssertLessThan(SourceKey.number(key), 0)
    XCTAssertEqual(SourceKey.number(key), SourceKey.number(key))
  }
}
