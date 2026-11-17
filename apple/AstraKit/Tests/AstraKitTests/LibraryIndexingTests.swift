import Foundation
import XCTest

@testable import AstraKit

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// KP (2026-11-09): the Omega library index must survive a big remote
/// library and dropped connections, resume instead of restarting, and never
/// call a title missing just because the read hasn't finished.
final class LibraryIndexRunTests: XCTestCase {
  private var folder: URL!

  override func setUpWithError() throws {
    folder = FileManager.default.temporaryDirectory.appendingPathComponent("astra-index-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: folder)
  }

  private var checkpointURL: URL { folder.appendingPathComponent("server.checkpoint.json") }

  private func client(_ transport: FakeTransport) -> PlexServerClient {
    PlexServerClient(
      baseURL: URL(string: "https://server.test:32400")!, token: "tok", serverName: "Omega", info: testInfo,
      transport: transport)
  }

  private func section(_ key: String, _ type: String = "movie") throws -> PlexLibrarySection {
    try JSONDecoder().decode(
      PlexLibrarySection.self, from: Data(#"{"key":"\#(key)","title":"Library \#(key)","type":"\#(type)"}"#.utf8))
  }

  /// A fake Plex library of `sizes[section]` movies. `fail` decides, per
  /// request (section, start, attempt), whether the connection drops.
  private func server(
    sizes: [String: Int], fail: @escaping @Sendable (_ section: String, _ start: Int, _ attempt: Int) -> Bool = { _, _, _ in false }
  ) -> (FakeTransport, Attempts) {
    let attempts = Attempts()
    let transport = FakeTransport { request in
      let parts = request.url!.path.split(separator: "/")
      let key = String(parts[2])
      let total = sizes[key] ?? 0
      let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
      let start = Int(query.first { $0.name == "X-Plex-Container-Start" }?.value ?? "0") ?? 0
      let size = Int(query.first { $0.name == "X-Plex-Container-Size" }?.value ?? "0") ?? 0
      if size == 0 {
        return (200, Data(#"{"MediaContainer":{"size":0,"totalSize":\#(total)}}"#.utf8))
      }
      let attempt = attempts.next("\(key):\(start)")
      if fail(key, start, attempt) { throw URLError(.networkConnectionLost) }
      let range = start..<max(start, min(total, start + size))
      let items = range.map { n in
        let id = Int(key)! * 1_000_000 + n
        return #"{"ratingKey":"\#(id)","type":"movie","title":"M\#(id)","Guid":[{"id":"tmdb://\#(id)"}]}"#
      }
      return (200, Data(#"{"MediaContainer":{"Metadata":[\#(items.joined(separator: ","))]}}"#.utf8))
    }
    return (transport, attempts)
  }

  func testReadsEveryLibraryAndRemovesTheCheckpoint() async throws {
    let (transport, _) = server(sizes: ["1": 600, "2": 40])
    let index = try await LibraryIndexRun.run(
      client: client(transport), sections: [try section("1"), try section("2", "show"), try section("3", "artist")],
      checkpointURL: checkpointURL, pageSize: 100, retryDelays: [])
    XCTAssertEqual(index.count, 640)
    XCTAssertFalse(FileManager.default.fileExists(atPath: checkpointURL.path), "a finished read leaves no checkpoint")
    XCTAssertFalse(transport.requests.contains { $0.url!.path.contains("/sections/3/") }, "music is never read")
  }

  /// A dropped page is asked for again after each delay, and counted.
  func testRetriesADroppedPage() async throws {
    let (transport, _) = server(sizes: ["1": 500]) { _, start, attempt in start == 200 && attempt <= 2 }
    let retries = LockedBox<Int>(0)
    let index = try await LibraryIndexRun.run(
      client: client(transport), sections: [try section("1")], checkpointURL: checkpointURL, pageSize: 100,
      retryDelays: [0, 0, 0], onProgress: { retries.value = $0.retries })
    XCTAssertEqual(index.count, 500)
    XCTAssertEqual(retries.value, 2)
  }

  /// The connection dies part-way: what arrived in order is saved, usable,
  /// and the next run carries on from that page instead of the start.
  func testInterruptedReadResumesFromTheCheckpoint() async throws {
    let down = LockedBox<Bool>(true)
    let (transport, _) = server(sizes: ["1": 1_000, "2": 300]) { section, start, _ in
      down.value && section == "1" && start >= 600
    }
    let partial = LockedBox<Int>(0)
    do {
      _ = try await LibraryIndexRun.run(
        client: client(transport), sections: [try section("1"), try section("2")], checkpointURL: checkpointURL,
        pageSize: 100, parallel: 3, retryDelays: [0], onProgress: { partial.value = $0.items.count })
      XCTFail("the read should fail while the server is down")
    } catch {}
    XCTAssertEqual(partial.value, 600, "the pages before the drop are usable at once")
    let saved = try XCTUnwrap(LibraryIndexCheckpoint.load(from: checkpointURL), "survives the app being closed")
    XCTAssertEqual(saved.libraries["1"]?.fetched, 600)
    XCTAssertEqual(saved.libraries["1"]?.total, 1_000)
    XCTAssertEqual(saved.libraries["1"]?.complete, false)

    down.value = false
    let before = transport.requests.count
    let index = try await LibraryIndexRun.run(
      client: client(transport), sections: [try section("1"), try section("2")], checkpointURL: checkpointURL,
      pageSize: 100, parallel: 3, retryDelays: [0])
    XCTAssertEqual(index.count, 1_300)
    let resumed = transport.requests[before...].compactMap { request -> Int? in
      guard request.url!.path.contains("/sections/1/") else { return nil }
      let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
      guard query.first(where: { $0.name == "X-Plex-Container-Size" })?.value != "0" else { return nil }
      return Int(query.first { $0.name == "X-Plex-Container-Start" }?.value ?? "")
    }
    XCTAssertFalse(resumed.contains { $0 < 600 && $0 > 0 }, "pages already read are not read again")
  }

  /// A checkpoint older than `maxAge` is not trusted: the read starts over.
  func testOldCheckpointIsNotResumed() async throws {
    var old = LibraryIndexCheckpoint(startedAt: .distantPast)
    old.libraries["1"] = .init(key: "1", title: "Old", total: 10, fetched: 5, items: [:], updatedAt: .distantPast)
    try old.save(to: checkpointURL)
    let (transport, _) = server(sizes: ["1": 50])
    let index = try await LibraryIndexRun.run(
      client: client(transport), sections: [try section("1")], checkpointURL: checkpointURL, pageSize: 100,
      retryDelays: [])
    XCTAssertEqual(index.count, 50)
  }

  /// A 20,000-title remote library whose connection drops every so often
  /// still finishes, over several runs, each resuming from the last.
  func testLargeLibraryWithFlakyConnectionCompletes() async throws {
    let (transport, _) = server(sizes: ["1": 14_000, "2": 6_000]) { _, start, attempt in
      // Every seventh page drops its first three tries (more than the retries).
      (start / 250) % 7 == 3 && attempt <= 3
    }
    var index: [String: PlexMetadata] = [:]
    var runs = 0
    while index.isEmpty && runs < 40 {
      runs += 1
      index = (try? await LibraryIndexRun.run(
        client: client(transport), sections: [try section("1"), try section("2")], checkpointURL: checkpointURL,
        retryDelays: [0, 0])) ?? [:]
    }
    XCTAssertEqual(index.count, 20_000)
    XCTAssertGreaterThan(runs, 1, "the drops really interrupted it")
    XCTAssertFalse(FileManager.default.fileExists(atPath: checkpointURL.path))
  }

  func testCancellationKeepsWhatWasRead() async throws {
    let (transport, _) = server(sizes: ["1": 400])
    let plex = client(transport)
    let sections = [try section("1")]
    let url = checkpointURL
    let task = Task {
      try await LibraryIndexRun.run(
        client: plex, sections: sections, checkpointURL: url, pageSize: 100, parallel: 1, retryDelays: [],
        onProgress: { p in
          if p.items.count >= 200 { withUnsafeCurrentTask { $0?.cancel() } }
        })
    }
    _ = try? await task.value
    let saved = LibraryIndexCheckpoint.load(from: url)
    XCTAssertGreaterThanOrEqual(saved?.libraries["1"]?.fetched ?? 0, 200, "what was read before closing is kept")
    XCTAssertEqual(saved?.libraries["1"]?.complete, false)
  }
}

final class LibraryIndexStateTests: XCTestCase {
  /// KP's requirement 5 and 6.
  func testAvailabilityStates() {
    XCTAssertEqual(LibraryAvailability.decide(inIndex: true, searchFound: nil, indexComplete: false), .available)
    XCTAssertEqual(LibraryAvailability.decide(inIndex: false, searchFound: true, indexComplete: true), .available)
    XCTAssertEqual(LibraryAvailability.decide(inIndex: false, searchFound: nil, indexComplete: true), .notFound)
    XCTAssertEqual(LibraryAvailability.decide(inIndex: false, searchFound: false, indexComplete: false), .notFound)
    XCTAssertEqual(
      LibraryAvailability.decide(inIndex: false, searchFound: nil, indexComplete: false), .unverified,
      "an unfinished index never says a title isn't on the server")
  }

  func testCheckpointAndSnapshotSurviveRelaunch() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("astra-relaunch-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: folder) }
    var item = PlexMetadata(ratingKey: "7", type: .movie, title: "Arrival", year: 2016)
    item.guids = [PlexGuid(id: "tmdb://329865")]
    var checkpoint = LibraryIndexCheckpoint(startedAt: Date())
    checkpoint.libraries["1"] = .init(
      key: "1", title: "Movies", total: 2, fetched: 1, items: ["movie:329865": item], updatedAt: Date())
    let checkpointURL = folder.appendingPathComponent("s.checkpoint.json")
    try checkpoint.save(to: checkpointURL)
    XCTAssertEqual(LibraryIndexCheckpoint.load(from: checkpointURL), checkpoint)

    let snapshotURL = LibraryIndexSnapshot.url(serverID: "omega", in: folder)
    try LibraryIndexSnapshot(savedAt: Date(), items: ["movie:329865": item], duration: 42).save(to: snapshotURL)
    let loaded = try XCTUnwrap(LibraryIndexSnapshot.load(from: snapshotURL))
    XCTAssertEqual(loaded.duration, 42)
    XCTAssertEqual(loaded.items["movie:329865"]?.ratingKey, "7")
    var catalog = PlexMetadata(ratingKey: "tmdb:movie:329865", type: .movie, title: "Arrival", year: 2016)
    catalog.guids = [PlexGuid(id: "tmdb://329865")]
    XCTAssertEqual(LibraryMatch.withAliases(loaded.items).match(catalog)?.ratingKey, "7", "known titles match with no search")
  }

  func testSnapshotsFromOlderBuildsStillLoad() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("astra-old-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }
    try Data(#"{"savedAt":0,"items":{}}"#.utf8).write(to: url)
    let loaded = try XCTUnwrap(LibraryIndexSnapshot.load(from: url))
    XCTAssertNil(loaded.duration)
  }

  func testPublishGate() {
    let clock = LockedBox<Date>(Date(timeIntervalSince1970: 0))
    let gate = PublishGate(eager: true, interval: 8, now: { clock.value })
    XCTAssertTrue(gate.shouldPublish(completed: 0, count: 250), "the first titles show at once")
    XCTAssertFalse(gate.shouldPublish(completed: 0, count: 500))
    clock.value = Date(timeIntervalSince1970: 9)
    XCTAssertTrue(gate.shouldPublish(completed: 0, count: 750))
    XCTAssertTrue(gate.shouldPublish(completed: 1, count: 760), "a finished library always shows")
    let refresh = PublishGate(eager: false, now: { clock.value })
    XCTAssertFalse(refresh.shouldPublish(completed: 0, count: 250), "a re-read keeps the old index until a library finishes")
    XCTAssertTrue(refresh.shouldPublish(completed: 1, count: 500))
  }

  func testOpenTimings() {
    var timings = OpenTimings()
    XCTAssertNil(timings.median)
    [8.2, 0.3, 0.4].forEach { timings.record($0) }
    XCTAssertEqual(timings.last, 0.4)
    XCTAssertEqual(timings.median, 0.4)
    timings.record(0.1)
    XCTAssertEqual(timings.median ?? 0, 0.35, accuracy: 0.0001)
    (0..<40).forEach { _ in timings.record(1) }
    XCTAssertEqual(timings.seconds.count, OpenTimings.keep)
    let defaults = UserDefaults(suiteName: "astra-open-\(UUID().uuidString)")!
    timings.save(defaults)
    XCTAssertEqual(OpenTimings.load(defaults), timings)
  }
}

/// Counts tries per key, from any thread.
final class Attempts: @unchecked Sendable {
  private let lock = NSLock()
  private var counts: [String: Int] = [:]
  func next(_ key: String) -> Int {
    lock.withLock {
      counts[key, default: 0] += 1
      return counts[key]!
    }
  }
}

final class LockedBox<Value>: @unchecked Sendable {
  private let lock = NSLock()
  private var stored: Value
  init(_ value: Value) { stored = value }
  var value: Value {
    get { lock.withLock { stored } }
    set { lock.withLock { stored = newValue } }
  }
}

/// KP (2026-11-09): Details gets a cinematic, scenic shot: TMDB's best-voted
/// backdrop with no text on it.
final class SceneryBackdropTests: XCTestCase {
  private func image(_ path: String, _ language: String?, vote: Double, count: Int = 10, width: Int = 3840)
    -> TMDBClient.ArtworkRaw.Images.Image
  {
    .init(file_path: path, iso_639_1: language, vote_average: vote, vote_count: count, width: width)
  }

  func testPicksTheBestVotedTextFreeBackdrop() {
    let pick = TMDBClient.bestScenery([
      image("/titled.jpg", "en", vote: 9.9),
      image("/small.jpg", nil, vote: 9.5, width: 780),
      image("/plain.jpg", nil, vote: 5.3),
      image("/scenic.jpg", nil, vote: 5.8),
      image("/scenic-fewer-votes.jpg", nil, vote: 5.8, count: 2),
    ])
    XCTAssertEqual(pick, "/scenic.jpg")
  }

  func testNoTextFreeBackdropFallsBack() {
    XCTAssertNil(TMDBClient.bestScenery([image("/titled.jpg", "en", vote: 8)]))
    let art = TMDBArtwork(posterPath: nil, backdropPath: "/main.jpg", logoPath: nil)
    XCTAssertNil(art.sceneryPath)
  }
}
