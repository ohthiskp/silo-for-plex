import AstraKit
import Foundation

/// Astra: a demo server for screenshots in CI. Launched with `-AstraDemo YES`,
/// the app skips sign-in and talks to a fake Plex server that answers from
/// the canned titles below (real TMDB ids, so TMDB artwork loads). Nothing
/// here runs in a normal launch.
///
/// Launch arguments:
/// - `-AstraDemo YES`: use the demo server.
/// - `-AstraDemoTab home|search|libraries`: the tab to open on.
/// - `-AstraDemoQuery <text>`: text typed into Search.
/// - `-AstraDemoOpen <ratingKey>`: open that title's details on Home.
/// - `-AstraDemoScroll <points>`: scroll Home down this far (rows below the hero).
enum Demo {
  static var isOn: Bool { UserDefaults.standard.bool(forKey: "AstraDemo") }
  static var tab: String? { isOn ? UserDefaults.standard.string(forKey: "AstraDemoTab") : nil }
  static var query: String? { isOn ? UserDefaults.standard.string(forKey: "AstraDemoQuery") : nil }
  static var openKey: String? { isOn ? UserDefaults.standard.string(forKey: "AstraDemoOpen") : nil }
  static var homeScroll: Double? {
    guard isOn, let text = UserDefaults.standard.string(forKey: "AstraDemoScroll") else { return nil }
    return Double(text)
  }
  /// `-AstraDemoPlay <path>`: a local video file to open in the player at launch (UI tests).
  static var videoPath: String? { isOn ? UserDefaults.standard.string(forKey: "AstraDemoPlay") : nil }
  /// `-AstraDemoPlayer <state>`: once the demo video plays, pause it and show a player state for a
  /// screenshot: `controls`, `more` (iPhone ⋯ menu), `scrub`, or the Apple TV top menu's
  /// `info`, `settings`, `subtitles`.
  static var playerShot: String? { isOn ? UserDefaults.standard.string(forKey: "AstraDemoPlayer") : nil }

  /// The demo movie and a source that plays `videoPath` from disk.
  static func playback() -> (PlexMetadata, PlaybackSource)? {
    guard let path = videoPath, let item = item("101") else { return nil }
    let json = #"{"ratingKey":"101","metadataKey":"/library/metadata/101","type":"movie","title":"Dune: Part Two","durationMs":60000,"fileName":"demo.mp4","addedAt":0}"#
    guard let record = try? JSONDecoder().decode(DownloadRecord.self, from: Data(json.utf8)) else { return nil }
    return (item, PlaybackResolver.local(record, fileURL: URL(fileURLWithPath: path), resumeMs: nil))
  }

  /// A session on the fake server.
  static func session(info: PlexClientInfo) -> ServerSession {
    let client = PlexServerClient(
      baseURL: URL(string: "https://demo.astra.invalid:32400")!, token: "demo", serverName: "Demo",
      info: info, transport: DemoTransport())
    let sections = [section("1", "Movies", "movie"), section("2", "TV Shows", "show")]
    return ServerSession(generation: 1, serverID: "astra-demo", client: client, sections: sections)
  }

  private static func section(_ key: String, _ title: String, _ type: String) -> PlexLibrarySection {
    let json = #"{"key":"\#(key)","title":"\#(title)","type":"\#(type)"}"#
    return try! JSONDecoder().decode(PlexLibrarySection.self, from: Data(json.utf8))
  }

  /// The demo item with this rating key, decoded.
  static func item(_ ratingKey: String) -> PlexMetadata? {
    guard let raw = (movies + shows + episodes).first(where: { $0["ratingKey"] as? String == ratingKey }),
      let data = try? JSONSerialization.data(withJSONObject: raw)
    else { return nil }
    return try? JSONDecoder().decode(PlexMetadata.self, from: data)
  }

  // MARK: - Titles

  typealias JSON = [String: Any]

  nonisolated(unsafe) static let movies: [JSON] = [
    // Filled out like a real title, so the Details screenshot shows every part
    // of KP's mockup: progress, two genres, a director, cast and a long synopsis.
    movie("101", "Dune: Part Two", 2024, 693134, "Science Fiction", 9960, "4k").merging([
      "viewOffset": 1_500_000,
      "Genre": [["tag": "Science Fiction"], ["tag": "Adventure"]],
      "summary": "Follow the mythic journey of Paul Atreides as he unites with Chani and the Fremen while on a "
        + "path of revenge against the conspirators who destroyed his family. Facing a choice between the love "
        + "of his life and the fate of the known universe, Paul endeavors to prevent a terrible future only he "
        + "can foresee.",
      "Director": [["tag": "Denis Villeneuve"]],
      "Role": [
        ["tag": "Timothée Chalamet", "role": "Paul Atreides"], ["tag": "Zendaya", "role": "Chani"],
        ["tag": "Rebecca Ferguson", "role": "Jessica"], ["tag": "Josh Brolin", "role": "Gurney Halleck"],
        ["tag": "Austin Butler", "role": "Feyd-Rautha"],
      ],
    ]) { $1 },
    movie("102", "Oppenheimer", 2023, 872585, "Drama", 10800, "4k"),
    movie("103", "Interstellar", 2014, 157336, "Science Fiction", 10140, "4k"),
    movie("104", "Inception", 2010, 27205, "Action", 8880, "1080"),
    movie("105", "The Dark Knight", 2008, 155, "Action", 9120, "4k"),
    movie("106", "Joker", 2019, 475557, "Drama", 7320, "1080"),
    movie("107", "The Matrix", 1999, 603, "Science Fiction", 8160, "1080"),
    movie("108", "Blade Runner 2049", 2017, 335984, "Science Fiction", 9840, "4k"),
    movie("109", "The Batman", 2022, 414906, "Action", 10560, "4k"),
    movie("110", "Barbie", 2023, 346698, "Comedy", 6840, "1080"),
  ]

  nonisolated(unsafe) static let shows: [JSON] = [
    show("201", "Breaking Bad", 2008, 1396, "Drama", 5),
    show("202", "Stranger Things", 2016, 66732, "Science Fiction", 4),
    show("203", "The Witcher", 2019, 71912, "Action", 3),
    show("204", "Ozark", 2017, 69740, "Drama", 4),
    show("205", "Severance", 2022, 95396, "Science Fiction", 2),
    show("206", "The Bear", 2022, 136315, "Comedy", 3),
  ]

  /// Season 1 episodes of Severance, two partly watched shows for Continue Watching.
  nonisolated(unsafe) static let episodes: [JSON] = (1...6).map { n in
    var e: JSON = [
      "ratingKey": "30\(n)", "key": "/library/metadata/30\(n)", "type": "episode",
      "title": "Episode \(n)", "index": n, "parentIndex": 1, "duration": 3_000_000,
      "grandparentTitle": "Severance", "grandparentRatingKey": "205", "parentRatingKey": "2051",
      "parentTitle": "Season 1", "librarySectionID": 2, "year": 2022,
      "summary": "Mark and his team at Lumon dig deeper into the mysteries of the severed floor.",
      "Media": [media(id: 300 + n, resolution: "1080", seconds: 3000)],
    ]
    if n == 3 { e["viewOffset"] = 1_400_000 }
    if n < 3 { e["viewCount"] = 1 }
    return e
  }

  private static func movie(
    _ key: String, _ title: String, _ year: Int, _ tmdb: Int, _ genre: String, _ seconds: Int, _ resolution: String
  ) -> JSON {
    [
      "ratingKey": key, "key": "/library/metadata/\(key)", "guid": "plex://movie/\(key)", "type": "movie",
      "title": title, "year": year, "duration": seconds * 1000, "librarySectionID": 1,
      "summary": "A demo copy of \(title) for screenshots.", "contentRating": "PG-13", "audienceRating": 8.4,
      "Guid": [["id": "tmdb://\(tmdb)"]], "Genre": [["tag": genre]],
      "Media": [media(id: Int(key)!, resolution: resolution, seconds: seconds)],
      "addedAt": 1_730_000_000 + Int(key)!,
    ]
  }

  private static func show(_ key: String, _ title: String, _ year: Int, _ tmdb: Int, _ genre: String, _ seasons: Int)
    -> JSON
  {
    [
      "ratingKey": key, "key": "/library/metadata/\(key)/children", "guid": "plex://show/\(key)", "type": "show",
      "title": title, "year": year, "librarySectionID": 2, "childCount": seasons, "leafCount": seasons * 9,
      "viewedLeafCount": 0, "summary": "A demo copy of \(title) for screenshots.", "contentRating": "TV-MA",
      "audienceRating": 8.7, "Guid": [["id": "tmdb://\(tmdb)"]], "Genre": [["tag": genre]],
    ]
  }

  private static func media(id: Int, resolution: String, seconds: Int) -> JSON {
    [
      "id": id, "duration": seconds * 1000, "videoResolution": resolution, "videoCodec": "hevc",
      "audioCodec": "eac3", "audioChannels": 6, "container": "mkv",
      "width": resolution == "4k" ? 3840 : 1920, "height": resolution == "4k" ? 2160 : 1080,
      "Part": [
        [
          "id": id, "key": "/library/parts/\(id)/file.mkv", "duration": seconds * 1000, "size": 8_000_000_000,
          // 4K demo files are Dolby Vision, so the badges show in screenshots.
          "Stream": [
            ["id": id * 10, "streamType": 1, "codec": "hevc", "colorTrc": resolution == "4k" ? "smpte2084" : "bt709",
             "DOVIPresent": resolution == "4k"],
            ["id": id * 10 + 1, "streamType": 2, "codec": resolution == "4k" ? "truehd" : "eac3",
             "extendedDisplayTitle": resolution == "4k" ? "English (TrueHD 7.1 Atmos)" : "English (EAC3 5.1)"],
          ],
        ]
      ],
    ]
  }

  // MARK: - Responses

  static func response(path: String, query: [String: String]) -> JSON {
    let all = movies + shows
    switch path {
    case "/library/sections":
      return [
        "Directory": [
          ["key": "1", "title": "Movies", "type": "movie"], ["key": "2", "title": "TV Shows", "type": "show"],
        ]
      ]
    case "/hubs/continueWatching":
      let items: [JSON] = [episodes[2], movies[2].merging(["viewOffset": 4_200_000]) { $1 }]
      return ["Hub": [["hubIdentifier": "home.continue", "title": "Continue Watching", "Metadata": items]]]
    case "/hubs":
      return [
        "Hub": [
          ["hubIdentifier": "movie.recentlyadded.1", "title": "Recently Added Movies", "key": "/hubs/home/1",
           "Metadata": movies],
          ["hubIdentifier": "tv.recentlyadded.2", "title": "Recently Added TV", "key": "/hubs/home/2",
           "Metadata": shows],
        ]
      ]
    case "/hubs/search":
      let text = (query["query"] ?? "").lowercased()
      let hits = all.filter { ($0["title"] as? String ?? "").lowercased().contains(text) }
      return ["Hub": [["hubIdentifier": "search", "title": "Results", "Metadata": hits]]]
    default: break
    }
    let parts = path.split(separator: "/").map(String.init)
    if parts.count == 4, parts[0] == "library", parts[1] == "sections", parts[3] == "all" {
      var items = parts[2] == "1" ? movies : shows
      if query["resolution"] == "4k" { items = items.filter { isUHD($0) } }
      if let genre = query["genre"] {
        items = items.filter { (($0["Genre"] as? [JSON])?.first?["tag"] as? String) == genre }
      }
      if query["X-Plex-Container-Size"] == "0" { return ["size": 0, "totalSize": items.count] }
      let start = Int(query["X-Plex-Container-Start"] ?? "0") ?? 0
      let page = start < items.count ? Array(items[start...]) : []
      return ["size": page.count, "totalSize": items.count, "Metadata": page]
    }
    if parts.count == 4, parts[0] == "library", parts[1] == "sections", parts[3] == "genre" {
      let names = Set((parts[2] == "1" ? movies : shows).compactMap {
        ($0["Genre"] as? [JSON])?.first?["tag"] as? String
      })
      return ["Directory": names.sorted().map { ["key": $0, "title": $0] }]
    }
    if parts.count >= 3, parts[0] == "library", parts[1] == "metadata" {
      let key = parts[2]
      if parts.count == 4, parts[3] == "children" {
        if key == "205" {
          return [
            "Metadata": [
              ["ratingKey": "2051", "key": "/library/metadata/2051/children", "type": "season", "title": "Season 1",
               "index": 1, "parentRatingKey": "205", "parentTitle": "Severance", "leafCount": 6,
               "viewedLeafCount": 2]
            ]
          ]
        }
        if key == "2051" { return ["Metadata": episodes] }
        return ["Metadata": []]
      }
      if let raw = (all + episodes).first(where: { $0["ratingKey"] as? String == key }) {
        return ["Metadata": [raw]]
      }
    }
    if parts.count == 4, parts[0] == "hubs", parts[1] == "metadata", parts[3] == "related" {
      let key = parts[2]
      let pool = movies.contains { $0["ratingKey"] as? String == key } ? movies : shows
      return [
        "Hub": [["hubIdentifier": "related", "title": "More Like This",
                 "Metadata": pool.filter { $0["ratingKey"] as? String != key }]]
      ]
    }
    if parts.count == 3, parts[0] == "hubs", parts[1] == "home" {
      return ["Metadata": parts[2] == "1" ? movies : shows]
    }
    return [:]
  }

  private static func isUHD(_ item: JSON) -> Bool {
    ((item["Media"] as? [JSON])?.first?["videoResolution"] as? String) == "4k"
  }
}

/// Answers every request from `Demo.response`.
struct DemoTransport: HTTPTransport {
  /// `-AstraDemoLatency <ms>`: each answer waits this long, like a remote server.
  static let latency = Double(UserDefaults.standard.integer(forKey: "AstraDemoLatency")) / 1000

  func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let started = Date()
    if Self.latency > 0 { try await Task.pause(Self.latency) }
    let url = request.url!
    defer { NetworkLog.shared.record(request, status: 200, started: started, error: nil) }
    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    var query: [String: String] = [:]
    for item in components?.queryItems ?? [] { query[item.name] = item.value ?? "" }
    let body = Demo.response(path: url.path, query: query)
    let data = try JSONSerialization.data(withJSONObject: ["MediaContainer": body])
    let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
    return (data, response)
  }
}
