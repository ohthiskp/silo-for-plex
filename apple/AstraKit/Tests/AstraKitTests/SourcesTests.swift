import XCTest

@testable import AstraKit

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// A share in memory: path → bytes; folders are implied by the paths.
final class MemoryShare: FileShare, @unchecked Sendable {
  let files: [String: Data]
  let modified: Date

  init(_ files: [String: Data], modified: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
    self.files = files
    self.modified = modified
  }

  func list(_ path: String) async throws -> [ShareEntry] {
    let prefix = path.isEmpty ? "" : path + "/"
    var folders = Set<String>()
    var entries: [ShareEntry] = []
    for (file, data) in files where file.hasPrefix(prefix) {
      let rest = file.dropFirst(prefix.count)
      if let slash = rest.firstIndex(of: "/") {
        folders.insert(String(rest[..<slash]))
      } else {
        entries.append(ShareEntry(name: String(rest), path: file, isDirectory: false, size: Int64(data.count), modified: modified))
      }
    }
    if entries.isEmpty && folders.isEmpty && !path.isEmpty { throw SourceError.notFound }
    return entries + folders.map { ShareEntry(name: $0, path: prefix + $0, isDirectory: true) }
  }

  func size(of path: String) async throws -> Int64 {
    guard let data = files[path] else { throw SourceError.notFound }
    return Int64(data.count)
  }

  func read(_ path: String, offset: Int64, length: Int) async throws -> Data {
    guard let data = files[path] else { throw SourceError.notFound }
    let start = Int(min(Int64(data.count), offset))
    return data.subdata(in: start..<min(data.count, start + length))
  }
}

struct TableMatcher: TitleMatcher {
  func movie(_ title: String, year: Int?) async throws -> ShareTitle? {
    title == "Dune" ? ShareTitle(tmdbID: 438631, title: "Dune", year: 2021, posterPath: "/dune.jpg") : nil
  }

  func show(_ title: String, year: Int?) async throws -> ShareTitle? {
    title == "Severance" ? ShareTitle(tmdbID: 95396, title: "Severance", year: 2022, posterPath: "/sev.jpg") : nil
  }

  func season(show tmdbID: Int, number: Int) async throws -> ShareSeason? {
    ShareSeason(posterPath: "/s\(number).jpg", episodes: ["1": ShareEpisode(title: "Good News About Hell", stillPath: "/e1.jpg")])
  }
}

final class ShareSourceTests: XCTestCase {
  let movies = SourceFolder(id: "fm", share: "Media", path: "Movies", content: .movies, title: "NAS Movies")
  let shows = SourceFolder(id: "fs", share: "Media", path: "TV", content: .shows, title: "NAS Shows")

  func makeClient() async throws -> ShareClient {
    let share = MemoryShare([
      "Movies/Dune (2021)/Dune (2021) 2160p.mkv": Data(count: 40),
      "Movies/Dune (2021)/Dune (2021) 1080p.mkv": Data(count: 20),
      "Movies/Dune (2021)/Extras/Behind.mkv": Data(count: 5),
      "Movies/Unknown Film (1999).mp4": Data(count: 10),
      "Movies/notes.txt": Data(count: 1),
      "TV/Severance/Season 1/Severance.S01E01.mkv": Data(count: 10),
      "TV/Severance/Season 1/Severance.S01E02.mkv": Data(count: 10),
    ])
    let config = SourceConfig(id: "nas1", kind: .smb, name: "NAS", address: "nas.local", folders: [movies, shows])
    var index = try await ShareScanner.scan(movies, share: share, into: ShareIndex(), matcher: TableMatcher())
    index = try await ShareScanner.scan(shows, share: share, into: index, matcher: TableMatcher())
    let state = ShareLibraryState(index: index)
    return ShareClient(
      config: config, state: state, streamBase: { URL(string: "http://127.0.0.1:9/secret/nas1/") },
      now: { Date(timeIntervalSince1970: 1_800_000_000) })
  }

  func testScanFindsVideosSkipsExtrasAndMatchesTMDB() async throws {
    let client = try await makeClient()
    let items = try await client.items(library: "fm", sort: "titleSort", start: 0, size: 50, filters: [])
    XCTAssertEqual(items.map(\.title), ["Dune", "Unknown Film"])
    let dune = items[0]
    XCTAssertEqual(dune.tmdbKey, "movie:438631")
    XCTAssertEqual(dune.thumb, "https://image.tmdb.org/t/p/w500/dune.jpg")
    // Two files are two versions, 4K first.
    XCTAssertEqual(dune.media.count, 2)
    XCTAssertEqual(dune.media.first?.tier, 2160)
    XCTAssertEqual(dune.sourceID, "nas1")
    XCTAssertEqual(dune.librarySectionID, SourceKey.number(SourceKey.make("nas1", "fm")))
    XCTAssertEqual(items[1].year, 1999)
    XCTAssertTrue(items[1].guids.isEmpty)
  }

  func testShowsHaveSeasonsAndEpisodesWithTMDBNames() async throws {
    let client = try await makeClient()
    let shows = try await client.items(library: "fs", sort: "titleSort", start: 0, size: 50, filters: [])
    XCTAssertEqual(shows.count, 1)
    XCTAssertEqual(shows[0].leafCount, 2)
    let seasons = try await client.children(try XCTUnwrap(SourceKey.split(shows[0].ratingKey)?.native))
    XCTAssertEqual(seasons.map(\.title), ["Season 1"])
    let episodes = try await client.children(try XCTUnwrap(SourceKey.split(seasons[0].ratingKey)?.native))
    XCTAssertEqual(episodes.map(\.title), ["Good News About Hell", "Episode 2"])
    XCTAssertEqual(episodes[0].grandparentTitle, "Severance")
    XCTAssertEqual(episodes[0].episodeLabel, "S1 · E1")
  }

  func testProgressAndWatchedStayOnDevice() async throws {
    let client = try await makeClient()
    let episodes = try await client.children(
      "n/fs/" + SourceKey.slug(MediaFileName.parse("Severance/Season 1/Severance.S01E01.mkv", content: .shows).matchKey) + "/1")
    let first = try XCTUnwrap(SourceKey.split(episodes[0].ratingKey)?.native)
    try await client.report(TimelineReport(ratingKey: episodes[0].ratingKey, key: "", state: .playing, timeMs: 60_000, durationMs: 3_000_000), id: first)
    var resumed = try await client.continueWatching(count: 10)
    XCTAssertEqual(resumed.map(\.ratingKey), [episodes[0].ratingKey])
    XCTAssertEqual(resumed.first?.viewOffset, 60_000)
    // Past 90% counts as watched and leaves Continue Watching.
    try await client.report(TimelineReport(ratingKey: episodes[0].ratingKey, key: "", state: .stopped, timeMs: 2_800_000, durationMs: 3_000_000), id: first)
    resumed = try await client.continueWatching(count: 10)
    XCTAssertTrue(resumed.isEmpty)
    let show = try await client.items(library: "fs", sort: "titleSort", start: 0, size: 5, filters: [])[0]
    XCTAssertEqual(show.viewedLeafCount, 1)
    // Marking the show watched marks every episode.
    try await client.setWatched(try XCTUnwrap(SourceKey.split(show.ratingKey)?.native), watched: true)
    let after = try await client.items(library: "fs", sort: "titleSort", start: 0, size: 5, filters: [])[0]
    XCTAssertTrue(after.isWatched)
  }

  func testStreamURLsGoThroughTheLocalServerEncoded() async throws {
    let client = try await makeClient()
    let dune = try await client.items(library: "fm", sort: "titleSort", start: 0, size: 1, filters: [])[0]
    let key = try XCTUnwrap(dune.media.first?.parts.first?.key)
    let router = SourceRouter([client])
    let plex = PlexServerClient(baseURL: URL(string: "https://p.test:32400")!, token: "t", serverName: "P", info: testInfo)
      .with(sources: router)
    let stream = try XCTUnwrap(plex.stream(forKey: key))
    XCTAssertEqual(stream.url.absoluteString, "http://127.0.0.1:9/secret/nas1/Movies/Dune%20(2021)/Dune%20(2021)%202160p.mkv")
    XCTAssertTrue(stream.headers.isEmpty)
    let source = try PlaybackResolver.directPlay(dune, client: plex)
    XCTAssertEqual(source.url, stream.url)
  }

  func testByteRanges() throws {
    XCTAssertNil(try ByteRange.parse(nil, size: 100))
    XCTAssertEqual(try ByteRange.parse("bytes=0-", size: 100), 0...99)
    XCTAssertEqual(try ByteRange.parse("bytes=10-19", size: 100), 10...19)
    XCTAssertEqual(try ByteRange.parse("bytes=90-500", size: 100), 90...99)
    XCTAssertEqual(try ByteRange.parse("bytes=-10", size: 100), 90...99)
    XCTAssertThrowsError(try ByteRange.parse("bytes=100-", size: 100))
  }

  func testSourceStoreRoundTrip() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = SourceStore(directory: dir)
    let config = SourceConfig(kind: .jellyfin, name: "JF", address: "http://jf:8096", username: "kp", userID: "u1",
      libraries: [SourceLibrary(id: "lib", title: "Movies", type: "movie")])
    store.save([config])
    XCTAssertEqual(store.load(), [config])
    XCTAssertEqual(config.sections.map(\.key), [SourceKey.make(config.id, "lib")])
  }
}

final class JellyfinSourceTests: XCTestCase {
  func config(_ kind: SourceKind = .jellyfin) -> SourceConfig {
    SourceConfig(
      id: "jf1", kind: kind, name: "Home", address: "jf.local:8096", username: "kp", userID: "user1",
      libraries: [SourceLibrary(id: "movies1", title: "Movies", type: "movie")])
  }

  static let movieJSON = """
    {"Id":"m1","Name":"Dune","SortName":"dune","Type":"Movie","ProductionYear":2021,"PremiereDate":"2021-10-22T00:00:00.0000000Z",
     "OfficialRating":"PG-13","CommunityRating":7.8,"RunTimeTicks":93550000000,"Overview":"Paul.",
     "Genres":["Science Fiction"],"ProviderIds":{"Tmdb":"438631","Imdb":"tt1160419","Custom":null},
     "UserData":{"PlaybackPositionTicks":6000000000,"PlayCount":0,"Played":false,"LastPlayedDate":"2026-11-16T20:00:00.1234567Z"},
     "ImageTags":{"Primary":"p1","Logo":"l1"},"BackdropImageTags":["b1"],
     "People":[{"Name":"Denis Villeneuve","Type":"Director"},{"Name":"Timothée Chalamet","Id":"pp1","Role":"Paul","Type":"Actor","PrimaryImageTag":"pt"}],
     "MediaSources":[{"Id":"ms1","Container":"mkv","Path":"/media/Dune.mkv","Size":60000000000,"Bitrate":60000000,
       "MediaStreams":[
         {"Type":"Video","Codec":"hevc","Index":0,"Width":3840,"Height":2160,"VideoRange":"HDR","VideoRangeType":"DOVIWithHDR10"},
         {"Type":"Audio","Codec":"truehd","Index":1,"Language":"eng","DisplayTitle":"English - Dolby TrueHD + Dolby Atmos - 7.1","IsDefault":true,"Channels":8},
         {"Type":"Subtitle","Codec":"subrip","Index":3,"Language":"spa","DisplayTitle":"Spanish","IsExternal":true}
       ]}]}
    """

  func testMovieMapsToPlexModels() throws {
    let client = try JellyfinClient(config: config(), token: "tok", info: testInfo)
    let item = try JSONDecoder().decode(JellyfinClient.Item.self, from: Data(Self.movieJSON.utf8))
    let movie = try XCTUnwrap(client.map(item))
    XCTAssertEqual(movie.ratingKey, "src~jf1~m1")
    XCTAssertEqual(movie.type, .movie)
    XCTAssertEqual(movie.tmdbKey, "movie:438631")
    XCTAssertEqual(movie.duration, 9_355_000)
    XCTAssertEqual(movie.viewOffset, 600_000)
    XCTAssertEqual(movie.officialRating, "PG-13")
    XCTAssertEqual(movie.thumb, "src~jf1~img/m1/Primary/p1")
    XCTAssertEqual(movie.clearLogo, "src~jf1~img/m1/Logo/l1")
    XCTAssertEqual(movie.directors.map(\.tag), ["Denis Villeneuve"])
    XCTAssertEqual(movie.roles.first?.role, "Paul")
    XCTAssertEqual(movie.dynamicRange(), .dolbyVision)
    XCTAssertTrue(movie.hasAtmos())
    XCTAssertEqual(movie.media.first?.tier, 2160)
    let part = try XCTUnwrap(movie.media.first?.parts.first)
    XCTAssertLessThan(part.id, 0)
    let subtitle = try XCTUnwrap(part.streams.first { $0.streamType == 3 })
    XCTAssertNil(subtitle.index)
    XCTAssertEqual(subtitle.key, "src~jf1~sub/m1/ms1/3/srt")
    XCTAssertEqual(part.streams.first { $0.streamType == 2 }?.index, 1)
    XCTAssertNotNil(movie.lastViewedAt)
  }

  func testStreamIsTheOriginalFileWithATokenHeaderWithoutCommas() throws {
    let client = try JellyfinClient(config: config(), token: "tok", info: testInfo)
    let stream = try XCTUnwrap(client.stream("stream/m1/ms1/mkv"))
    XCTAssertEqual(stream.url.absoluteString, "http://jf.local:8096/Videos/m1/stream?static=true&mediaSourceId=ms1")
    XCTAssertEqual(stream.headers, ["Authorization": "MediaBrowser Token=\"tok\""])
    XCTAssertFalse(PlaybackResolver.mpvHeaderFields(stream.headers).dropFirst(14).contains(","))
    let emby = try JellyfinClient(config: config(.emby), token: "tok", info: testInfo)
    XCTAssertEqual(emby.stream("stream/m1/ms1/mkv")?.headers, ["X-Emby-Token": "tok"])
    XCTAssertEqual(
      client.stream("sub/m1/ms1/3/srt")?.url.absoluteString, "http://jf.local:8096/Videos/m1/ms1/Subtitles/3/0/Stream.srt")
  }

  func testSignInSendsCredentialsAndReadsTheToken() async throws {
    let transport = FakeTransport { request in
      switch request.url?.path {
      case "/System/Info/Public": return (200, Data(#"{"ServerName":"Den"}"#.utf8))
      case "/Users/AuthenticateByName":
        XCTAssertTrue(request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("MediaBrowser Client=\"Astra\"") ?? false)
        return (200, Data(#"{"AccessToken":"abc","User":{"Id":"u9"}}"#.utf8))
      default: return (404, Data())
      }
    }
    let result = try await JellyfinClient.signIn(
      kind: .jellyfin, address: "jf.local:8096/web/", username: "kp", password: "pw", info: testInfo, transport: transport)
    XCTAssertEqual(result, .init(token: "abc", userID: "u9", serverName: "Den"))
    let bad = FakeTransport { request in request.url?.path == "/Users/AuthenticateByName" ? (401, Data()) : (404, Data()) }
    do {
      _ = try await JellyfinClient.signIn(kind: .jellyfin, address: "jf.local", username: "kp", password: "x", info: testInfo, transport: bad)
      XCTFail("expected wrong login")
    } catch {
      XCTAssertEqual(error as? SourceError, .wrongLogin)
    }
  }

  func testRouterSendsSourceKeysToTheSourceAndMergesLibraries() async throws {
    let transport = FakeTransport { request in
      let path = request.url?.path ?? ""
      if path == "/library/sections" {
        return (200, Data(#"{"MediaContainer":{"Directory":[{"key":"1","title":"Plex Movies","type":"movie"}]}}"#.utf8))
      }
      if path == "/Users/user1/Items" {
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(query.first { $0.name == "ParentId" }?.value, "movies1")
        XCTAssertEqual(query.first { $0.name == "SortBy" }?.value, "DateCreated,SortName")
        XCTAssertEqual(query.first { $0.name == "SortOrder" }?.value, "Descending")
        return (200, Data("{\"Items\":[\(Self.movieJSON)]}".utf8))
      }
      if path == "/Users/user1/PlayedItems/m1" {
        XCTAssertEqual(request.httpMethod, "POST")
        return (200, Data())
      }
      return (404, Data())
    }
    let jellyfin = try JellyfinClient(config: config(), token: "tok", info: testInfo, transport: transport)
    let plex = PlexServerClient(
      baseURL: URL(string: "https://p.test:32400")!, token: "t", serverName: "P", info: testInfo, transport: transport
    ).with(sources: SourceRouter([jellyfin]))
    let sections = try await plex.librarySections()
    XCTAssertEqual(sections.map(\.title), ["Plex Movies", "Movies"])
    let items = try await plex.libraryItems(sectionKey: sections[1].key, sort: "addedAt:desc")
    XCTAssertEqual(items.map(\.title), ["Dune"])
    XCTAssertEqual(items.first?.librarySectionID, sections[1].numericID)
    try await plex.markWatched(ratingKey: "src~jf1~m1")
    XCTAssertEqual(
      plex.imageURL("src~jf1~img/m1/Primary/p1", width: 300, height: 450)?.absoluteString,
      "http://jf.local:8096/Items/m1/Images/Primary?quality=90&fillWidth=300&fillHeight=450&tag=p1")
    XCTAssertEqual(plex.imageURL("https://image.tmdb.org/t/p/w500/x.jpg", width: 1, height: 1)?.host, "image.tmdb.org")
  }

  func testContinueWatchingMergesByMostRecent() {
    var a = PlexMetadata(ratingKey: "1", type: .movie, title: "Plex old")
    a.lastViewedAt = 100
    var b = PlexMetadata(ratingKey: "src~x~2", type: .movie, title: "Jellyfin new")
    b.lastViewedAt = 200
    XCTAssertEqual(PlexServerClient.mergeByRecent([a], [b], count: 20).map(\.title), ["Jellyfin new", "Plex old"])
  }
}
