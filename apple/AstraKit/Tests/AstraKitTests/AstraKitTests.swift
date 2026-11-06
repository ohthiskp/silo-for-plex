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
    XCTAssertEqual(episode.resolutionBadge, "HD")

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
