import XCTest

@testable import AstraKit

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Answers requests from a table keyed by host + path; unknown requests fail.
final class FakeTransport: HTTPTransport, @unchecked Sendable {
  typealias Handler = (URLRequest) async throws -> (Int, Data)
  private let handler: Handler
  private let lock = NSLock()
  private(set) var requests: [URLRequest] = []

  init(_ handler: @escaping Handler) { self.handler = handler }

  func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    lock.withLock { requests.append(request) }
    let (status, data) = try await handler(request)
    let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
    return (data, response)
  }
}

let testInfo = PlexClientInfo(
  version: "1.0", platform: "macOS", platformVersion: "26.0", device: "Mac", deviceName: "Test Mac",
  clientIdentifier: "test-client")

final class DecodingTests: XCTestCase {
  func testHubsDecodeWithLooseTypes() throws {
    // ratingKey as a number, librarySectionID as a string, videoResolution as a number.
    let json = """
      {"MediaContainer":{"Hub":[
        {"hubIdentifier":"home.continue","title":"Continue Watching","Metadata":[
          {"ratingKey":101,"type":"episode","title":"Pilot","grandparentTitle":"Show","grandparentRatingKey":"7",
           "parentIndex":1,"index":1,"duration":3000000,"viewOffset":1500000,"librarySectionID":"2",
           "Media":[{"id":"5","videoResolution":1080,"width":1920,"Part":[{"id":9,"key":"/library/parts/9/file.mkv"}]}]}
        ]},
        {"hubIdentifier":"movie.recentlyadded","title":"Recently Added Movies","Metadata":[
          {"ratingKey":"202","type":"movie","title":"Film","year":"2024","audienceRating":8.1,
           "Image":[{"type":"clearLogo","url":"/library/metadata/202/clearLogo/1"}]},
          {"ratingKey":"203","type":"somethingNew","title":"Odd"}
        ]},
        {"hubIdentifier":"empty","title":"Empty"}
      ]}}
      """
    let body = try JSONDecoder().decode(MediaContainerEnvelope<HubBody>.self, from: Data(json.utf8)).MediaContainer
    let hubs = try XCTUnwrap(body.Hub)
    XCTAssertEqual(hubs.count, 3)
    XCTAssertTrue(hubs[0].isContinueWatching)

    let episode = hubs[0].items[0]
    XCTAssertEqual(episode.ratingKey, "101")
    XCTAssertEqual(episode.librarySectionID, 2)
    XCTAssertEqual(episode.displayTitle, "Show")
    XCTAssertEqual(episode.episodeLabel, "S1 · E1")
    XCTAssertEqual(episode.progress ?? 0, 0.5, accuracy: 0.001)
    XCTAssertEqual(episode.media.first?.videoResolution, "1080")
    XCTAssertEqual(episode.resolutionBadge(), "HD")

    let movie = hubs[1].items[0]
    XCTAssertEqual(movie.year, 2024)
    XCTAssertEqual(movie.clearLogo, "/library/metadata/202/clearLogo/1")
    XCTAssertEqual(hubs[1].items[1].type, .other)
    XCTAssertTrue(hubs[2].items.isEmpty)
  }

  func testDurationLabel() {
    XCTAssertEqual(PlexMetadata(ratingKey: "1", type: .movie, title: "", duration: 8_040_000).durationLabel, "2h 14m")
    XCTAssertEqual(PlexMetadata(ratingKey: "1", type: .movie, title: "", duration: 2_880_000).durationLabel, "48m")
    XCTAssertEqual(PlexMetadata(ratingKey: "1", type: .movie, title: "", duration: 7_200_000).durationLabel, "2h")
    XCTAssertNil(PlexMetadata(ratingKey: "1", type: .movie, title: "").durationLabel)
  }
}

final class ConnectionPickerTests: XCTestCase {
  typealias C = PlexServerResource.Connection

  func testOrderPrefersLocalThenRemoteThenRelay() {
    let relay = C(uri: "https://relay.plex.direct:8443", local: false, relay: true)
    let remote = C(uri: "https://1-2-3-4.plex.direct:32400", local: false, relay: false)
    let localHttp = C(uri: "http://192.168.1.5:32400", local: true, relay: false)
    let localHttps = C(uri: "https://192-168-1-5.plex.direct:32400", local: true, relay: false)
    let ordered = ConnectionPicker.ordered([relay, remote, localHttp, localHttps]).map(\.uri)
    XCTAssertEqual(ordered, [localHttps.uri, localHttp.uri, remote.uri, relay.uri])
  }

  func testFastRelayWaitsForSlowerLocalAddress() async throws {
    let transport = FakeTransport { request in
      if request.url!.host == "local.test" {
        try await Task.sleep(for: .milliseconds(150))
        return (200, Data())
      }
      return (200, Data())
    }
    let server = PlexServerResource(
      name: "Home", clientIdentifier: "s1", accessToken: "server-token",
      connections: [
        C(uri: "https://relay.test", local: false, relay: true),
        C(uri: "https://local.test:32400", local: true, relay: false),
      ])
    let picker = ConnectionPicker(info: testInfo, transport: transport)
    let url = try await picker.pick(for: server, accountToken: "account")
    XCTAssertEqual(url.host, "local.test")
    // Probes authenticate with the server's own token.
    XCTAssertTrue(transport.requests.allSatisfy { $0.value(forHTTPHeaderField: "X-Plex-Token") == "server-token" })
  }

  func testFallsBackWhenBetterAddressesFail() async throws {
    let transport = FakeTransport { request in
      request.url!.host == "remote.test" ? (200, Data()) : (500, Data())
    }
    let server = PlexServerResource(
      name: "Home", clientIdentifier: "s1", accessToken: nil,
      connections: [
        C(uri: "https://local.test", local: true, relay: false),
        C(uri: "https://remote.test", local: false, relay: false),
      ])
    let url = try await ConnectionPicker(info: testInfo, transport: transport).pick(for: server, accountToken: "a")
    XCTAssertEqual(url.host, "remote.test")
  }

  func testNoReachableAddressThrows() async {
    let transport = FakeTransport { _ in (503, Data()) }
    let server = PlexServerResource(
      name: "Home", clientIdentifier: "s1", accessToken: nil,
      connections: [C(uri: "https://local.test", local: true, relay: false)])
    do {
      _ = try await ConnectionPicker(info: testInfo, transport: transport).pick(for: server, accountToken: "a")
      XCTFail("expected a throw")
    } catch {
      XCTAssertEqual(error as? PlexError, .noReachableConnection("Home"))
    }
  }
}

final class AccountTests: XCTestCase {
  func testServersKeepOnlyServersOwnedFirst() async throws {
    let json = """
      [{"name":"Friend","clientIdentifier":"f","provides":"server","owned":false,"connections":[]},
       {"name":"Phone","clientIdentifier":"p","provides":"client,player","connections":[]},
       {"name":"Mine","clientIdentifier":"m","provides":"server","owned":true,"accessToken":"t",
        "connections":[{"uri":"https://a.plex.direct:32400","local":true,"relay":false,"protocol":"https"}]}]
      """
    let transport = FakeTransport { _ in (200, Data(json.utf8)) }
    let servers = try await PlexAccountClient(info: testInfo, transport: transport).servers(token: "tok")
    XCTAssertEqual(servers.map(\.name), ["Mine", "Friend"])
    XCTAssertEqual(transport.requests.first?.value(forHTTPHeaderField: "X-Plex-Token"), "tok")
    XCTAssertEqual(transport.requests.first?.value(forHTTPHeaderField: "X-Plex-Product"), "Astra")
  }

  func testAuthURLCarriesClientAndCode() {
    let client = PlexAccountClient(info: testInfo, transport: FakeTransport { _ in (200, Data()) })
    let url = client.authURL(for: PlexPin(id: 1, code: "ABCD"))
    XCTAssertTrue(url.absoluteString.hasPrefix("https://app.plex.tv/auth#?"))
    XCTAssertTrue(url.absoluteString.contains("clientID=test-client"))
    XCTAssertTrue(url.absoluteString.contains("code=ABCD"))
  }

  func testPinCheckReturnsTokenOnceApproved() async throws {
    var approved = false
    let transport = FakeTransport { _ in
      defer { approved = true }
      let token = approved ? "\"secret\"" : "null"
      return (200, Data(#"{"id":1,"code":"ABCD","authToken":\#(token)}"#.utf8))
    }
    let client = PlexAccountClient(info: testInfo, transport: transport)
    let token = try await client.waitForToken(PlexPin(id: 1, code: "ABCD"), every: .milliseconds(10))
    XCTAssertEqual(token, "secret")
  }

  func testExpiredPinThrows() async {
    let client = PlexAccountClient(info: testInfo, transport: FakeTransport { _ in (404, Data()) })
    do {
      _ = try await client.checkPin(PlexPin(id: 1, code: "X"))
      XCTFail("expected a throw")
    } catch {
      XCTAssertEqual(error as? PlexError, .pinExpired)
    }
  }
}

final class PlaybackTests: XCTestCase {
  func makeItem(_ json: String) throws -> PlexMetadata {
    try JSONDecoder().decode(PlexMetadata.self, from: Data(json.utf8))
  }

  let client = PlexServerClient(
    baseURL: URL(string: "https://server.test:32400")!, token: "tok", serverName: "Home", info: testInfo,
    transport: FakeTransport { _ in (200, Data()) })

  func testPicksHighestResolutionVersionAndKeepsTokenOutOfURL() throws {
    let item = try makeItem(
      """
      {"ratingKey":"1","type":"movie","title":"Film","duration":7200000,"viewOffset":600000,"Media":[
        {"id":1,"width":1920,"bitrate":8000,"Part":[{"id":11,"key":"/library/parts/11/1/file.mkv"}]},
        {"id":2,"width":3840,"bitrate":40000,"Part":[{"id":22,"key":"/library/parts/22/1/file.mkv"}]},
        {"id":3,"width":7680,"Part":[]}
      ]}
      """)
    let source = try PlaybackResolver.directPlay(item, client: client)
    XCTAssertEqual(source.media.id, 2)
    XCTAssertEqual(source.url.absoluteString, "https://server.test:32400/library/parts/22/1/file.mkv")
    XCTAssertFalse(source.url.absoluteString.contains("tok"))
    XCTAssertEqual(source.headers["X-Plex-Token"], "tok")
    XCTAssertEqual(source.startSeconds, 600)
    XCTAssertEqual(source.metadataKey, "/library/metadata/1")
  }

  func testNearlyFinishedItemStartsOver() throws {
    let item = try makeItem(
      """
      {"ratingKey":"1","type":"movie","title":"Film","duration":100000,"viewOffset":90000,
       "Media":[{"id":1,"Part":[{"id":1,"key":"/p"}]}]}
      """)
    XCTAssertEqual(try PlaybackResolver.directPlay(item, client: client).startSeconds, 0)
    XCTAssertEqual(try PlaybackResolver.directPlay(item, client: client, resume: false).startSeconds, 0)
  }

  func testNoPartThrows() throws {
    let item = try makeItem(#"{"ratingKey":"1","type":"movie","title":"Film"}"#)
    XCTAssertThrowsError(try PlaybackResolver.directPlay(item, client: client)) {
      XCTAssertEqual($0 as? PlexError, .nothingToPlay)
    }
  }

  func testMpvHeaderFieldsAreSortedAndCommaFree() {
    let fields = PlaybackResolver.mpvHeaderFields(["X-B": "2,3", "X-A": "1"])
    XCTAssertEqual(fields, "X-A: 1,X-B: 23")
  }

  func testImageURLIsResizedByServer() throws {
    let url = try XCTUnwrap(client.imageURL("/library/metadata/1/thumb/9", width: 300, height: 450))
    let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
    XCTAssertEqual(components.path, "/photo/:/transcode")
    let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    XCTAssertEqual(query["url"], "/library/metadata/1/thumb/9")
    XCTAssertEqual(query["width"], "300")
    XCTAssertNil(client.imageURL(nil, width: 1, height: 1))
  }

  func testTimelineReportQuery() async throws {
    let transport = FakeTransport { _ in (200, Data()) }
    let client = PlexServerClient(
      baseURL: URL(string: "https://server.test")!, token: "tok", serverName: "Home", info: testInfo,
      transport: transport)
    try await client.reportTimeline(
      TimelineReport(ratingKey: "5", key: "/library/metadata/5", state: .paused, timeMs: 1234, durationMs: 5000))
    let request = try XCTUnwrap(transport.requests.first)
    let components = try XCTUnwrap(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))
    XCTAssertEqual(components.path, "/:/timeline")
    XCTAssertTrue(components.queryItems!.contains(.init(name: "state", value: "paused")))
    XCTAssertTrue(components.queryItems!.contains(.init(name: "time", value: "1234")))
    XCTAssertEqual(request.value(forHTTPHeaderField: "X-Plex-Client-Identifier"), "test-client")
  }

  func testPlexPathKeepsExistingQuery() {
    let url = URL(string: "https://s.test/")!.appending(
      plexPath: "/library/sections/1/all?type=1", query: [.init(name: "sort", value: "addedAt:desc")])
    XCTAssertEqual(url.absoluteString, "https://s.test/library/sections/1/all?type=1&sort=addedAt:desc")
  }

  func testImageSizeBucketsNearbyFramesTogether() throws {
    let a = try XCTUnwrap(ImageSize.bucketed(width: 1201, height: 675))
    let b = try XCTUnwrap(ImageSize.bucketed(width: 1279, height: 719))
    XCTAssertEqual(a.width, 1280)
    XCTAssertEqual(b.width, 1280)
    XCTAssertEqual(ImageSize.bucketed(width: 480, height: 270)?.width, 480)
    XCTAssertEqual(ImageSize.bucketed(width: 480, height: 270)?.height, 270)
    XCTAssertEqual(ImageSize.bucketed(width: 20, height: 30)?.width, 160)
    XCTAssertEqual(ImageSize.bucketed(width: 20, height: 30)?.height, 240)
  }

  func testImageSizeIsNilForAnEmptyFrame() {
    XCTAssertNil(ImageSize.bucketed(width: 0, height: 0))
    XCTAssertNil(ImageSize.bucketed(width: 300, height: 0))
  }
}

// MARK: - Preferred quality: original files only

final class PreferredQualityTests: XCTestCase {
  func media(_ json: String) throws -> [PlexMedia] {
    try JSONDecoder().decode([PlexMedia].self, from: Data(json.utf8))
  }

  /// A 4K file, a 1080p file and a 720p file of one title.
  lazy var versions: [PlexMedia] = try! media(
    """
    [{"id":1,"width":1920,"height":800,"bitrate":10000,"Part":[{"id":1,"key":"/p/1"}]},
     {"id":2,"width":3840,"height":1600,"bitrate":50000,"Part":[{"id":2,"key":"/p/2"}]},
     {"id":3,"width":1280,"height":720,"bitrate":4000,"Part":[{"id":3,"key":"/p/3"}]},
     {"id":4,"width":7680,"height":4320,"Part":[]}]
    """)

  func testAutoPicksBestOriginal() {
    XCTAssertEqual(PlaybackResolver.preferredMedia(versions, quality: .auto)?.id, 2)
  }

  func testHDPicksBestOriginalAtOrBelow1080() {
    XCTAssertEqual(PlaybackResolver.preferredMedia(versions, quality: .hd)?.id, 1)
  }

  func test4KPicks4KOriginal() {
    XCTAssertEqual(PlaybackResolver.preferredMedia(versions, quality: .uhd)?.id, 2)
  }

  func testHDFallsBackToClosestOriginalWhenOnly4KExists() throws {
    let only4K = try media(
      """
      [{"id":7,"width":3840,"height":2160,"bitrate":60000,"Part":[{"id":7,"key":"/p/7"}]},
       {"id":8,"width":4096,"height":2160,"bitrate":40000,"Part":[{"id":8,"key":"/p/8"}]}]
      """)
    // No conversion: the lowest version above the ceiling plays as it is (the earlier one on a tie).
    XCTAssertEqual(PlaybackResolver.preferredMedia(only4K, quality: .hd)?.id, 7)
  }

  func test4KSkips8KWhenA4KFileExists() throws {
    let list = try media(
      """
      [{"id":1,"width":7680,"height":4320,"Part":[{"id":1,"key":"/p/1"}]},
       {"id":2,"width":3840,"height":2160,"Part":[{"id":2,"key":"/p/2"}]}]
      """)
    XCTAssertEqual(PlaybackResolver.preferredMedia(list, quality: .uhd)?.id, 2)
    XCTAssertEqual(PlaybackResolver.preferredMedia(list, quality: .auto)?.id, 1)
  }

  func test4KFallsBackToBestOriginalWhenNo4KExists() throws {
    let noUHD = try media(
      """
      [{"id":1,"width":1280,"height":720,"Part":[{"id":1,"key":"/p/1"}]},
       {"id":2,"width":1920,"height":1080,"Part":[{"id":2,"key":"/p/2"}]}]
      """)
    XCTAssertEqual(PlaybackResolver.preferredMedia(noUHD, quality: .uhd)?.id, 2)
  }

  func testSingleOriginalPlaysAtEveryPreference() throws {
    let single = try media(#"[{"id":5,"width":3840,"height":2160,"Part":[{"id":5,"key":"/p/5"}]}]"#)
    for quality in PlaybackQuality.allCases {
      XCTAssertEqual(PlaybackResolver.preferredMedia(single, quality: quality)?.id, 5, "\(quality)")
    }
  }

  func testDirectPlayStreamsTheOriginalFileForEveryPreference() throws {
    let client = PlexServerClient(
      baseURL: URL(string: "https://server.test:32400")!, token: "tok", serverName: "Home", info: testInfo,
      transport: FakeTransport { _ in (200, Data()) })
    var item = PlexMetadata(ratingKey: "1", type: .movie, title: "Film", duration: 7_200_000)
    item.media = versions
    for (quality, part) in [(PlaybackQuality.auto, "/p/2"), (.hd, "/p/1"), (.uhd, "/p/2")] {
      let source = try PlaybackResolver.directPlay(item, client: client, quality: quality)
      XCTAssertEqual(source.url.path, part)
      // The original file URL: no transcode endpoint and no resolution parameters.
      XCTAssertFalse(source.url.absoluteString.contains("transcode"))
      XCTAssertNil(source.url.query)
    }
  }

  func testTiersCountWideFilms() {
    XCTAssertEqual(VideoTier.tier(width: 1920, height: 800), 1080)
    XCTAssertEqual(VideoTier.tier(width: 3840, height: 1600), 2160)
    XCTAssertEqual(VideoTier.tier(width: 1916, height: 1036), 1080)
    XCTAssertEqual(VideoTier.tier(width: 720, height: 480), 480)
    XCTAssertNil(VideoTier.tier(width: nil, height: nil))
    XCTAssertEqual(VideoTier.badge(for: 2160), "4K UHD")
    XCTAssertEqual(VideoTier.badge(for: 1080), "HD")
    XCTAssertEqual(VideoTier.badge(for: 720), "HD")
    XCTAssertNil(VideoTier.badge(for: 576))
  }

  func testPreferenceDefaultsToAutoAndPersists() throws {
    let suite = "astra.tests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    XCTAssertEqual(PlaybackQuality.stored(in: defaults), .auto)
    for quality in PlaybackQuality.allCases {
      quality.save(in: defaults)
      // A fresh read, as after restarting Astra.
      XCTAssertEqual(PlaybackQuality.stored(in: UserDefaults(suiteName: suite)!), quality)
    }
    XCTAssertEqual(defaults.string(forKey: PlaybackQuality.storageKey), "uhd")
    defaults.set("8k", forKey: PlaybackQuality.storageKey)
    XCTAssertEqual(PlaybackQuality.stored(in: defaults), .auto)
    XCTAssertEqual(PlaybackQuality.allCases.map(\.title), ["Auto", "HD", "4K"])
  }
}

// MARK: - Home de-duplication

final class HomeDeduplicationTests: XCTestCase {
  func items(_ json: String) throws -> [PlexMetadata] {
    try JSONDecoder().decode([PlexMetadata].self, from: Data(json.utf8))
  }

  func testSameMovieInTwoLibrariesIsShownOnceByTMDBId() throws {
    let continueWatching = try items(
      #"[{"ratingKey":"10","type":"movie","title":"Dune","guid":"plex://movie/a","Guid":[{"id":"tmdb://438631"}]}]"#)
    let trending = try items(
      """
      [{"ratingKey":"99","type":"movie","title":"Dune (4K)","guid":"local://99","Guid":[{"id":"tmdb://438631"}]},
       {"ratingKey":"11","type":"movie","title":"Arrival","guid":"plex://movie/b","Guid":[{"id":"tmdb://329865"}]}]
      """)
    var dedup = HomeDeduplicator()
    XCTAssertEqual(dedup.filter(continueWatching).map(\.ratingKey), ["10"])
    XCTAssertEqual(dedup.filter(trending).map(\.ratingKey), ["11"])
  }

  func testSameTitleDifferentFilmsAreBothKept() throws {
    let list = try items(
      """
      [{"ratingKey":"1","type":"movie","title":"Dune","year":1984,"Guid":[{"id":"tmdb://841"}]},
       {"ratingKey":"2","type":"movie","title":"Dune","year":2021,"Guid":[{"id":"tmdb://438631"}]}]
      """)
    var dedup = HomeDeduplicator()
    XCTAssertEqual(dedup.filter(list).count, 2)
  }

  func testEpisodeInContinueWatchingHidesItsShowElsewhere() throws {
    let continueWatching = try items(
      #"[{"ratingKey":"501","type":"episode","title":"Pilot","grandparentRatingKey":"50","grandparentGuid":"plex://show/s"}]"#)
    let shows = try items(
      """
      [{"ratingKey":"50","type":"show","title":"Severance","guid":"plex://show/s"},
       {"ratingKey":"60","type":"show","title":"Andor","guid":"plex://show/t"}]
      """)
    var dedup = HomeDeduplicator()
    _ = dedup.filter(continueWatching)
    XCTAssertEqual(dedup.filter(shows).map(\.ratingKey), ["60"])
  }

  func testOrderIsKeptWithinARow() throws {
    let row = try items(
      """
      [{"ratingKey":"3","type":"movie","title":"C"},{"ratingKey":"1","type":"movie","title":"A"},
       {"ratingKey":"3","type":"movie","title":"C"},{"ratingKey":"2","type":"movie","title":"B"}]
      """)
    var dedup = HomeDeduplicator()
    XCTAssertEqual(dedup.filter(row).map(\.ratingKey), ["3", "1", "2"])
  }

  func testHubItemsPagesFromTheHubKey() async throws {
    let transport = FakeTransport { request in
      XCTAssertEqual(request.url?.path, "/hubs/home/recentlyAdded")
      let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
      XCTAssertTrue(query.contains(.init(name: "type", value: "1")))
      XCTAssertTrue(query.contains(.init(name: "X-Plex-Container-Start", value: "16")))
      return (200, Data(#"{"MediaContainer":{"Metadata":[{"ratingKey":"77","type":"movie","title":"More"}]}}"#.utf8))
    }
    let client = PlexServerClient(
      baseURL: URL(string: "https://server.test:32400")!, token: "tok", serverName: "Home", info: testInfo,
      transport: transport)
    let more = try await client.hubItems(key: "/hubs/home/recentlyAdded?type=1", start: 16)
    XCTAssertEqual(more.map(\.ratingKey), ["77"])
  }
}

// MARK: - Downloads

final class DownloadTests: XCTestCase {
  func makeItem(_ json: String) throws -> PlexMetadata {
    try JSONDecoder().decode(PlexMetadata.self, from: Data(json.utf8))
  }

  let client = PlexServerClient(
    baseURL: URL(string: "https://server.test:32400")!, token: "tok", serverName: "Home", info: testInfo,
    transport: FakeTransport { _ in (200, Data()) })

  func testRecordSavesTheVersionThePreferencePicksAsTheOriginalFile() throws {
    let item = try makeItem(
      """
      {"ratingKey":"7","type":"movie","title":"Film","year":2024,"duration":7200000,"Media":[
        {"id":1,"width":1920,"height":1080,"Part":[{"id":11,"key":"/library/parts/11/1/file.mkv","container":"mkv","size":"4000"}]},
        {"id":2,"width":3840,"height":2160,"Part":[{"id":22,"key":"/library/parts/22/1/file.mp4","container":"mp4","size":9000}]}
      ]}
      """)
    let hd = try XCTUnwrap(DownloadRecord.make(for: item, quality: .hd))
    XCTAssertEqual(hd.partKey, "/library/parts/11/1/file.mkv")
    XCTAssertEqual(hd.record.fileName, "7.mkv")
    XCTAssertEqual(hd.record.bytes, 4000)
    XCTAssertEqual(hd.record.resolutionBadge, "HD")

    let uhd = try XCTUnwrap(DownloadRecord.make(for: item, quality: .auto))
    XCTAssertEqual(uhd.partKey, "/library/parts/22/1/file.mp4")
    XCTAssertEqual(uhd.record.fileName, "7.mp4")
    XCTAssertEqual(uhd.record.resolutionBadge, "4K UHD")
  }

  func testShowsAndItemsWithoutFilesCannotBeRecorded() throws {
    XCTAssertNil(DownloadRecord.make(for: try makeItem(#"{"ratingKey":"1","type":"show","title":"S"}"#), quality: .auto))
    XCTAssertNil(DownloadRecord.make(for: try makeItem(#"{"ratingKey":"1","type":"movie","title":"M"}"#), quality: .auto))
  }

  func testRatingKeyCannotEscapeTheFolder() {
    XCTAssertEqual(DownloadRecord.safeName("../../etc"), "etc")
    XCTAssertEqual(DownloadRecord.safeName("/"), "item")
  }

  func testDownloadRequestAsksForTheOriginalWithTokenInHeader() {
    let request = PlaybackResolver.downloadRequest(partKey: "/library/parts/22/1/file.mkv", client: client)
    XCTAssertEqual(request.url?.absoluteString, "https://server.test:32400/library/parts/22/1/file.mkv?download=1")
    XCTAssertEqual(request.value(forHTTPHeaderField: "X-Plex-Token"), "tok")
  }

  func testEpisodesGroupByShowInOrderAndIndexRoundTrips() throws {
    func episode(_ key: String, _ show: String, _ s: Int, _ e: Int) throws -> DownloadRecord {
      try XCTUnwrap(
        DownloadRecord.make(
          for: try makeItem(
            """
            {"ratingKey":"\(key)","type":"episode","title":"Ep","grandparentTitle":"\(show)","parentIndex":\(s),"index":\(e),
             "Media":[{"id":1,"Part":[{"id":1,"key":"/p/\(key)","container":"mkv"}]}]}
            """), quality: .auto)?.record)
    }
    var index = DownloadIndex()
    index.upsert(try episode("3", "Severance", 2, 1))
    index.upsert(try episode("1", "Severance", 1, 2))
    index.upsert(try episode("2", "Andor", 1, 1))
    index.upsert(try episode("1", "Severance", 1, 2))
    XCTAssertEqual(index.records.count, 3)
    XCTAssertEqual(index.shows.map(\.title), ["Andor", "Severance"])
    XCTAssertEqual(index.shows[1].episodes.map(\.ratingKey), ["1", "3"])
    XCTAssertEqual(index.shows[1].episodes[0].episodeLabel, "S1 · E2")

    let url = FileManager.default.temporaryDirectory.appendingPathComponent("astra-index-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: url) }
    try index.save(to: url)
    let loaded = DownloadIndex.load(from: url)
    XCTAssertEqual(loaded.records.map(\.ratingKey).sorted(), ["1", "2", "3"])
    XCTAssertEqual(loaded.record("3")?.showTitle, "Severance")

    index.remove("3")
    XCTAssertNil(index.record("3"))
  }

  func testLocalPlaybackUsesTheFileAndResumes() throws {
    let record = try XCTUnwrap(
      DownloadRecord.make(
        for: try makeItem(
          #"{"ratingKey":"9","type":"movie","title":"Film","duration":7200000,"Media":[{"id":1,"width":1920,"height":1080,"Part":[{"id":1,"key":"/p","container":"mkv"}]}]}"#
        ), quality: .auto)?.record)
    let file = URL(fileURLWithPath: "/tmp/9.mkv")
    let source = PlaybackResolver.local(record, fileURL: file, resumeMs: 600_000)
    XCTAssertEqual(source.url, file)
    XCTAssertTrue(source.headers.isEmpty)
    XCTAssertEqual(source.startSeconds, 600)
    XCTAssertEqual(source.ratingKey, "9")
    XCTAssertEqual(PlaybackResolver.local(record, fileURL: file, resumeMs: 7_190_000).startSeconds, 0)
  }
}

// MARK: - TMDB

final class TMDBTests: XCTestCase {
  func testDiscoverOnServiceDecodesAndFiltersByProvider() async throws {
    let transport = FakeTransport { request in
      XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer t")
      return (
        200,
        Data(
          """
          {"results":[
            {"id":1399,"name":"Game of Thrones","first_air_date":"2011-04-17","poster_path":"/p.jpg","vote_average":8.4},
            {"id":5,"name":"No Art"},
            {"id":6,"name":""}
          ]}
          """.utf8)
      )
    }
    let tmdb = TMDBClient(token: "t", transport: transport)
    let items = try await tmdb.onService(StreamingService.byID("max")!, .tv)
    XCTAssertEqual(items.map(\.id), ["tv:1399"])
    XCTAssertEqual(items[0].year, 2011)
    let query = URLComponents(url: try XCTUnwrap(transport.requests.first?.url), resolvingAgainstBaseURL: false)!
    XCTAssertEqual(query.path, "/3/discover/tv")
    XCTAssertEqual(query.queryItems?.first { $0.name == "with_watch_providers" }?.value, "1899")
    XCTAssertEqual(query.queryItems?.first { $0.name == "watch_region" }?.value, "US")
  }

  func testArtworkPrefersPngLogo() async throws {
    let tmdb = TMDBClient(
      token: "t",
      transport: FakeTransport { _ in
        (
          200,
          Data(
            #"{"poster_path":"/p.jpg","backdrop_path":"/b.jpg","images":{"logos":[{"file_path":"/l.svg"},{"file_path":"/l.png"}]}}"#
              .utf8)
        )
      })
    let art = try await tmdb.artwork(id: 603, kind: .movie)
    XCTAssertEqual(art.logoPath, "/l.png")
    XCTAssertEqual(TMDBArtwork.url(art.posterPath, size: "w500")?.absoluteString, "https://image.tmdb.org/t/p/w500/p.jpg")
    XCTAssertNil(TMDBArtwork.url(nil, size: "w500"))
  }

  func testTmdbKeyFromPlexGuids() throws {
    let movie = try JSONDecoder().decode(
      PlexMetadata.self,
      from: Data(#"{"ratingKey":"1","type":"movie","title":"M","Guid":[{"id":"imdb://tt1"},{"id":"tmdb://603"}]}"#.utf8))
    XCTAssertEqual(movie.tmdbKey, "movie:603")
    let show = try JSONDecoder().decode(
      PlexMetadata.self, from: Data(#"{"ratingKey":"2","type":"show","title":"S","Guid":[{"id":"tmdb://1399"}]}"#.utf8))
    XCTAssertEqual(show.tmdbKey, "tv:1399")
    let episode = try JSONDecoder().decode(
      PlexMetadata.self, from: Data(#"{"ratingKey":"3","type":"episode","title":"E","Guid":[{"id":"tmdb://9"}]}"#.utf8))
    XCTAssertNil(episode.tmdbKey)
  }
}
