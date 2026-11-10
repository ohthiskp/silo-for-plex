import Foundation
import XCTest

@testable import AstraKit

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// KP's performance audit (2026-11-10). Each test checks that a
/// simplification keeps the old answer, and prints `ASTRA-METRIC` lines with
/// the cost before and after (request counts, milliseconds) for the report.
final class PerformanceAuditTests: XCTestCase {
  private func client(_ transport: FakeTransport) -> PlexServerClient {
    PlexServerClient(
      baseURL: URL(string: "https://server.test:32400")!, token: "tok", serverName: "Omega", info: testInfo,
      transport: transport)
  }

  private func section(_ key: String, _ type: String = "movie") throws -> PlexLibrarySection {
    try JSONDecoder().decode(
      PlexLibrarySection.self, from: Data(#"{"key":"\#(key)","title":"Library \#(key)","type":"\#(type)"}"#.utf8))
  }

  /// A fake Plex server with `sizes[section]` titles per library.
  private func server(_ sizes: LockedBox<[String: Int]>) -> FakeTransport {
    FakeTransport { request in
      let parts = request.url!.path.split(separator: "/")
      let key = String(parts[2])
      let total = sizes.value[key] ?? 0
      let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
      let start = Int(query.first { $0.name == "X-Plex-Container-Start" }?.value ?? "0") ?? 0
      let size = Int(query.first { $0.name == "X-Plex-Container-Size" }?.value ?? "0") ?? 0
      if size == 0 { return (200, Data(#"{"MediaContainer":{"size":0,"totalSize":\#(total)}}"#.utf8)) }
      let items = (start..<max(start, min(total, start + size))).map { n in
        let id = Int(key)! * 1_000_000 + n
        return #"{"ratingKey":"\#(id)","type":"movie","title":"M\#(id)","Guid":[{"id":"tmdb://\#(id)"}]}"#
      }
      return (200, Data(#"{"MediaContainer":{"Metadata":[\#(items.joined(separator: ","))]}}"#.utf8))
    }
  }

  // MARK: Library index (area 7)

  /// An unchanged library is confirmed with one count per library instead
  /// of being read again page by page.
  func testUnchangedLibraryIsCheckedWithOneCountPerLibrary() async throws {
    let sizes = LockedBox(["1": 6_000, "2": 1_500])
    let transport = server(sizes)
    let sections = [try section("1"), try section("2", "show")]
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("astra-perf-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: folder) }

    let readStart = Date()
    _ = try await LibraryIndexRun.run(
      client: client(transport), sections: sections, checkpointURL: folder.appendingPathComponent("c.json"),
      retryDelays: [])
    let full = transport.requests.count
    let fullMs = Int(Date().timeIntervalSince(readStart) * 1000)
    let saved = await LibraryIndexCheck.counts(client: client(transport), sections: sections)
    XCTAssertEqual(saved, ["1": 6_000, "2": 1_500])

    let before = transport.requests.count
    let checkStart = Date()
    let now = await LibraryIndexCheck.counts(client: client(transport), sections: sections)
    let checkMs = Int(Date().timeIntervalSince(checkStart) * 1000)
    let check = transport.requests.count - before
    XCTAssertTrue(LibraryIndexCheck.unchanged(saved: saved, now: now))
    XCTAssertEqual(check, 2)
    print("ASTRA-METRIC index.relaunch.requests before=\(full) after=\(check) (7,500 titles, 2 libraries)")
    print("ASTRA-METRIC index.relaunch.ms before=\(fullMs) after=\(checkMs) (in-process fake server, no network)")
  }

  /// Any added or removed title changes a count, and the index is read again.
  func testChangedOrUnknownCountsAreNotTrusted() async throws {
    let sizes = LockedBox(["1": 300])
    let transport = server(sizes)
    let sections = [try section("1")]
    let saved = await LibraryIndexCheck.counts(client: client(transport), sections: sections)
    sizes.value = ["1": 299]
    let removed = await LibraryIndexCheck.counts(client: client(transport), sections: sections)
    XCTAssertFalse(LibraryIndexCheck.unchanged(saved: saved, now: removed))
    sizes.value = ["1": 301]
    let added = await LibraryIndexCheck.counts(client: client(transport), sections: sections)
    XCTAssertFalse(LibraryIndexCheck.unchanged(saved: saved, now: added))
    XCTAssertFalse(LibraryIndexCheck.unchanged(saved: nil, now: added), "an index without counts is read in full")
    XCTAssertFalse(LibraryIndexCheck.unchanged(saved: saved, now: nil), "a library that didn't answer is read in full")

    let down = FakeTransport { _ in throw URLError(.timedOut) }
    let unreachable = await LibraryIndexCheck.counts(client: client(down), sections: sections)
    XCTAssertNil(unreachable)
  }

  /// Old saved indexes (no counts) still load, and a day-old one isn't trusted by counts.
  func testSnapshotWithoutCountsStillLoadsAndOldOnesAreReadAgain() throws {
    let old = #"{"savedAt":0,"items":{}}"#
    let snapshot = try JSONDecoder().decode(LibraryIndexSnapshot.self, from: Data(old.utf8))
    XCTAssertNil(snapshot.totals)
    XCTAssertFalse(LibraryIndexCheck.canVerify(snapshot))
    let recent = LibraryIndexSnapshot(savedAt: Date().addingTimeInterval(-3600), items: [:], totals: ["1": 5])
    XCTAssertTrue(LibraryIndexCheck.canVerify(recent))
    let stale = LibraryIndexSnapshot(savedAt: Date().addingTimeInterval(-25 * 3600), items: [:], totals: ["1": 5])
    XCTAssertFalse(LibraryIndexCheck.canVerify(stale))
    let data = try JSONEncoder().encode(recent)
    XCTAssertEqual(try JSONDecoder().decode(LibraryIndexSnapshot.self, from: data).totals, ["1": 5])
  }

  // MARK: Cineby (area 1)

  /// The hero list and the For You rows ask for cineby's page at the same
  /// time: one download serves both.
  func testCinebyPageIsReadOncePerSession() async throws {
    let transport = FakeTransport { _ in (200, Data("<html></html>".utf8)) }
    let page = CinebyPage(transport: transport)
    async let a = page.html()
    async let b = page.html()
    _ = try await (a, b)
    _ = try await page.html()
    XCTAssertEqual(transport.requests.count, 1)
    print("ASTRA-METRIC cineby.pageReads before=2 after=\(transport.requests.count) (per launch with stale saved copies)")
  }

  func testFailedCinebyReadIsTriedAgain() async throws {
    let fails = LockedBox(true)
    let transport = FakeTransport { _ in
      if fails.value { throw URLError(.timedOut) }
      return (200, Data("ok".utf8))
    }
    let page = CinebyPage(transport: transport)
    _ = try? await page.html()
    fails.value = false
    let html = try await page.html()
    XCTAssertEqual(html, "ok")
    XCTAssertEqual(transport.requests.count, 2)
  }

  func testCinebyPageIsReadAgainAfterMaxAge() async throws {
    let clock = LockedBox(Date())
    let transport = FakeTransport { _ in (200, Data("ok".utf8)) }
    let page = CinebyPage(transport: transport, maxAge: 60, now: { clock.value })
    _ = try await page.html()
    clock.value = clock.value.addingTimeInterval(61)
    _ = try await page.html()
    XCTAssertEqual(transport.requests.count, 2)
  }

  // MARK: Search (area 6)

  /// Search over the library index folds each title once per index, not on
  /// every keystroke; the results are the same.
  func testLocalSearchPreparedOnceGivesTheSameResultsFaster() {
    let words = ["the", "dune", "rocky", "star", "night", "river", "Amélie", "Avatar: Fire & Ash", "ocean", "king"]
    let items = (0..<20_000).map { n in
      PlexMetadata(
        ratingKey: "\(n)", type: n % 3 == 0 ? .show : .movie,
        title: "\(words[n % words.count]) \(words[(n / 7) % words.count]) \(n)")
    }
    let queries = ["d", "du", "dun", "dune", "dune ", "ro", "roc", "rocky", "am", "ame", "amelie", "avatar", "fire"]

    var start = Date()
    let before = queries.map { LocalSearch.rank(items, text: $0, limit: 20) }
    let perKeystrokeBefore = Date().timeIntervalSince(start) * 1000 / Double(queries.count)

    start = Date()
    let prepared = LocalSearch.Prepared(items)
    let prepareMs = Date().timeIntervalSince(start) * 1000
    start = Date()
    let after = queries.map { LocalSearch.rank(prepared, text: $0, limit: 20) }
    let perKeystrokeAfter = Date().timeIntervalSince(start) * 1000 / Double(queries.count)

    XCTAssertEqual(before.map { $0.map(\.ratingKey) }, after.map { $0.map(\.ratingKey) })
    XCTAssertFalse(after[3].isEmpty)
    print(
      "ASTRA-METRIC search.local.msPerKeystroke before=\(String(format: "%.1f", perKeystrokeBefore)) after=\(String(format: "%.1f", perKeystrokeAfter)) prepareOncePerIndex=\(String(format: "%.1f", prepareMs)) (20,000 titles)"
    )
  }
}
