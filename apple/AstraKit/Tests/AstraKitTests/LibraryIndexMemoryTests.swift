import Foundation
import XCTest

@testable import AstraKit

/// KP (2026-11-19): iOS closed Astra for memory (3.2 GB) while a
/// 125,491-title library index loaded. The saved index and the checkpoint
/// are now written a few thousand titles per file, a read in progress
/// writes only what each round added, and the index is built in place.
final class LibraryIndexMemoryTests: XCTestCase {
  private var folder: URL!

  override func setUpWithError() throws {
    folder = FileManager.default.temporaryDirectory.appendingPathComponent("astra-memory-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: folder)
  }

  private func movie(_ n: Int) -> PlexMetadata {
    var item = PlexMetadata(ratingKey: "\(n)", type: .movie, title: "Movie \(n)", year: 2000 + n % 20)
    item.guids = [PlexGuid(id: "tmdb://\(n)")]
    return item
  }

  private func index(_ count: Int) -> [String: PlexMetadata] {
    Dictionary(uniqueKeysWithValues: (0..<count).map { ("movie:\($0)", movie($0)) })
  }

  private func files(in url: URL) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []).sorted()
  }

  func testSnapshotIsSavedInPartsAndLoadsWhole() throws {
    let url = LibraryIndexSnapshot.url(serverID: "omega", in: folder)
    let items = index(IndexParts.size * 2 + 10)
    try LibraryIndexSnapshot(savedAt: Date(timeIntervalSince1970: 100), items: items, duration: 7, totals: ["1": 8_010])
      .save(to: url)
    let header = try XCTUnwrap(try? Data(contentsOf: url))
    XCTAssertLessThan(header.count, 4_096, "the header holds no titles")
    let partsFolders = files(in: folder).filter { $0.contains(".parts-") }
    XCTAssertEqual(partsFolders.count, 1)
    XCTAssertEqual(files(in: folder.appendingPathComponent(partsFolders[0])).count, 3)

    let loaded = try XCTUnwrap(LibraryIndexSnapshot.load(from: url))
    XCTAssertEqual(loaded.items, items)
    XCTAssertEqual(loaded.savedAt, Date(timeIntervalSince1970: 100))
    XCTAssertEqual(loaded.duration, 7)
    XCTAssertEqual(loaded.totals, ["1": 8_010])

    // Saving again replaces the parts; the old ones are removed.
    try LibraryIndexSnapshot(savedAt: Date(), items: index(5)).save(to: url)
    XCTAssertEqual(files(in: folder).filter { $0.contains(".parts-") }.count, 1)
    XCTAssertEqual(LibraryIndexSnapshot.load(from: url)?.items.count, 5)
  }

  func testSnapshotFromAnOlderBuildStillLoads() throws {
    let url = LibraryIndexSnapshot.url(serverID: "omega", in: folder)
    let old = LibraryIndexSnapshot(savedAt: Date(timeIntervalSince1970: 5), items: index(30), totals: ["1": 30])
    try JSONEncoder().encode(old).write(to: url)
    let loaded = try XCTUnwrap(LibraryIndexSnapshot.load(from: url))
    XCTAssertEqual(loaded.items.count, 30)
    XCTAssertEqual(loaded.totals, ["1": 30])
  }

  func testSnapshotWithAMissingPartIsNotUsed() throws {
    let url = LibraryIndexSnapshot.url(serverID: "omega", in: folder)
    try LibraryIndexSnapshot(savedAt: Date(), items: index(IndexParts.size + 1)).save(to: url)
    let parts = folder.appendingPathComponent(files(in: folder).first { $0.contains(".parts-") }!)
    try FileManager.default.removeItem(at: parts.appendingPathComponent("1.json"))
    XCTAssertNil(LibraryIndexSnapshot.load(from: url), "half an index is never mistaken for the whole one")
  }

  func testCheckpointFromAnOlderBuildLoads() throws {
    let url = folder.appendingPathComponent("s.checkpoint.json")
    var old = LibraryIndexCheckpoint(startedAt: Date(timeIntervalSince1970: 1))
    old.libraries["1"] = .init(
      key: "1", title: "Movies", total: 50, fetched: 20, items: index(20), updatedAt: Date(timeIntervalSince1970: 2))
    try JSONEncoder().encode(old).write(to: url)
    XCTAssertEqual(LibraryIndexCheckpoint.load(from: url), old)

    // And the parts format round-trips the same checkpoint.
    let url2 = folder.appendingPathComponent("t.checkpoint.json")
    try old.save(to: url2)
    XCTAssertEqual(LibraryIndexCheckpoint.load(from: url2), old)
    LibraryIndexCheckpoint.remove(at: url2)
    XCTAssertNil(LibraryIndexCheckpoint.load(from: url2))
    XCTAssertFalse(FileManager.default.fileExists(atPath: LibraryIndexCheckpoint.partsFolder(for: url2).path))
  }

  func testAddAliasesMatchesWithAliases() {
    var items = index(200)
    var odd = PlexMetadata(ratingKey: "x", type: .movie, title: "The Odd One", year: 1999)
    odd.guids = []
    items["title:movie:oddone:1999"] = odd
    let expected = LibraryMatch.withAliases(items)
    var inPlace = items
    LibraryMatch.addAliases(to: &inPlace)
    XCTAssertEqual(inPlace, expected)
  }

  func testAddPutsNewTitlesAndTheirAliasesInPlace() {
    var aliased = LibraryMatch.withAliases(index(10))
    var added = movie(500)
    added.title = "Project Hail Mary"
    added.year = 2026
    var newer = movie(3)
    newer.viewCount = 1
    LibraryMatch.add(LibraryIndexer.keyed([added, newer]), to: &aliased)
    var catalog = PlexMetadata(ratingKey: "tmdb:movie:999", type: .movie, title: "Project Hail Mary", year: 2026)
    catalog.guids = [PlexGuid(id: "tmdb://999")]
    XCTAssertEqual(aliased.match(catalog)?.ratingKey, "500", "found by title when the TMDB id differs")
    XCTAssertEqual(aliased["movie:3"]?.viewCount, 1)
    XCTAssertEqual(aliased[LibraryMatch.aliasPrefix + newer.titleMatchKey!]?.viewCount, 1, "the alias follows the newer copy")
  }

  func testIndexCopiesLeaveTheFilePathOut() {
    var item = movie(1)
    item.media = [PlexMedia(id: 1, parts: [PlexPart(id: 2, key: "/library/parts/2/file.mkv", file: "/mnt/movies/A/A.mkv")])]
    let slim = LibraryIndexer.keyed([item])["movie:1"]
    XCTAssertNil(slim?.media.first?.parts.first?.file)
    XCTAssertEqual(slim?.media.first?.parts.first?.key, "/library/parts/2/file.mkv", "what playback needs stays")
  }
}
