import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Talks to one Plex Media Server over the address `ConnectionPicker` chose.
public struct PlexServerClient: Sendable {
  public let baseURL: URL
  public let token: String
  public let serverName: String
  let info: PlexClientInfo
  let transport: HTTPTransport

  public init(
    baseURL: URL, token: String, serverName: String, info: PlexClientInfo,
    transport: HTTPTransport = URLSessionTransport()
  ) {
    self.baseURL = baseURL
    self.token = token
    self.serverName = serverName
    self.info = info
    self.transport = transport
    // Image URLs carry no token; the image loader adds it as a header.
    PlexImageAuth.register(baseURL, token: token)
  }

  // MARK: - Browsing

  /// The home hubs (Continue Watching, Recently Added…), as Plex orders them.
  public func homeHubs(count: Int = 16) async throws -> [PlexHub] {
    let body: HubBody = try await get(
      "/hubs",
      query: [
        .init(name: "count", value: String(count)),
        .init(name: "includeGuids", value: "1"),
        .init(name: "excludeFields", value: "summary"),
      ])
    return (body.Hub ?? []).filter { !$0.items.isEmpty }
  }

  /// Continue Watching on its own (the Plex endpoint de-duplicates On Deck).
  public func continueWatching(count: Int = 20) async throws -> [PlexMetadata] {
    let body: HubBody = try await get(
      "/hubs/continueWatching",
      query: [.init(name: "count", value: String(count)), .init(name: "includeGuids", value: "1")])
    var seenShows = Set<String>()
    return (body.Hub ?? []).flatMap(\.items).filter { item in
      // One entry per show, like the Plex apps.
      guard let show = item.grandparentRatingKey else { return true }
      return seenShows.insert(show).inserted
    }
  }

  /// More items of a home hub (its `key`), for refilling a row after de-duplication.
  public func hubItems(key: String, start: Int, count: Int = 20) async throws -> [PlexMetadata] {
    let body: MetadataBody = try await get(
      key,
      query: [
        .init(name: "X-Plex-Container-Start", value: String(start)),
        .init(name: "X-Plex-Container-Size", value: String(count)),
        .init(name: "includeGuids", value: "1"),
      ])
    return body.Metadata ?? []
  }

  public func librarySections() async throws -> [PlexLibrarySection] {
    let body: DirectoryBody = try await get("/library/sections")
    return (body.Directory ?? []).filter { $0.type == "movie" || $0.type == "show" }
  }

  /// `filters` are Plex's own library filters, such as `unwatched=1`,
  /// `resolution=4k`, `hdr=1` or `genre=<key>`.
  public func libraryItems(
    sectionKey: String, sort: String = "addedAt:desc", start: Int = 0, size: Int = 60, filters: [URLQueryItem] = []
  ) async throws -> [PlexMetadata] {
    let body: MetadataBody = try await get(
      "/library/sections/\(sectionKey)/all",
      query: [
        .init(name: "sort", value: sort),
        .init(name: "X-Plex-Container-Start", value: String(start)),
        .init(name: "X-Plex-Container-Size", value: String(size)),
        .init(name: "includeGuids", value: "1"),
      ] + filters)
    return body.Metadata ?? []
  }

  /// How many items a library holds with `filters` applied (no items are sent).
  public func libraryCount(sectionKey: String, filters: [URLQueryItem] = []) async throws -> Int? {
    let body: CountBody = try await get(
      "/library/sections/\(sectionKey)/all",
      query: [
        .init(name: "X-Plex-Container-Start", value: "0"),
        .init(name: "X-Plex-Container-Size", value: "0"),
      ] + filters)
    return body.totalSize ?? body.size
  }

  /// A library's genres, for filtering (`genre=<key>`).
  public func genres(sectionKey: String) async throws -> [PlexFilterValue] {
    let body: FilterValuesBody = try await get("/library/sections/\(sectionKey)/genre")
    return body.Directory ?? []
  }

  /// Full metadata for one item, with images (clear logo), media versions and streams.
  public func metadata(ratingKey: String) async throws -> PlexMetadata {
    let body: MetadataBody = try await get(
      "/library/metadata/\(ratingKey)",
      query: [
        .init(name: "includeImages", value: "1"),
        .init(name: "includeOnDeck", value: "1"),
        .init(name: "includeGuids", value: "1"),
      ])
    guard let item = body.Metadata?.first else { throw PlexError.invalidResponse }
    return item
  }

  /// Seasons of a show, or episodes of a season.
  public func children(ratingKey: String) async throws -> [PlexMetadata] {
    let body: MetadataBody = try await get("/library/metadata/\(ratingKey)/children")
    return body.Metadata ?? []
  }

  /// "More like this" and collections for the details page.
  public func relatedHubs(ratingKey: String, count: Int = 12) async throws -> [PlexHub] {
    let body: HubBody = try await get(
      "/hubs/metadata/\(ratingKey)/related",
      query: [.init(name: "count", value: String(count)), .init(name: "includeGuids", value: "1")])
    return (body.Hub ?? []).filter { !$0.items.isEmpty }
  }

  public func search(_ text: String, limit: Int = 30) async throws -> [PlexMetadata] {
    let body: HubBody = try await get(
      "/hubs/search",
      query: [
        .init(name: "query", value: text), .init(name: "limit", value: String(limit)),
        .init(name: "includeGuids", value: "1"),
      ])
    return (body.Hub ?? []).flatMap(\.items).filter {
      [.movie, .show, .episode].contains($0.type)
    }
  }

  // MARK: - Watch state

  public func markWatched(ratingKey: String) async throws {
    try await send(
      "/:/scrobble",
      query: [.init(name: "identifier", value: "com.plexapp.plugins.library"), .init(name: "key", value: ratingKey)])
  }

  /// Takes a title off Continue Watching without changing its watched state
  /// (Plex's own "Remove from Continue Watching").
  public func removeFromContinueWatching(ratingKey: String) async throws {
    try await send(
      "/actions/removeFromContinueWatching", query: [.init(name: "ratingKey", value: ratingKey)], method: "PUT")
  }

  public func markUnwatched(ratingKey: String) async throws {
    try await send(
      "/:/unscrobble",
      query: [.init(name: "identifier", value: "com.plexapp.plugins.library"), .init(name: "key", value: ratingKey)])
  }

  /// Reports playback progress. Plex marks the item watched itself once the
  /// reported time passes its watched threshold (90% by default).
  /// Saves the audio and subtitle choice for a file on the server (Plex's
  /// own per-file selection, which every Plex app then uses). Subtitle 0 is
  /// "none"; nil leaves that kind as it is.
  public func setStreams(partID: Int, audio: Int? = nil, subtitle: Int? = nil) async throws {
    var query: [URLQueryItem] = [.init(name: "allParts", value: "1")]
    if let audio { query.append(.init(name: "audioStreamID", value: String(audio))) }
    if let subtitle { query.append(.init(name: "subtitleStreamID", value: String(subtitle))) }
    try await send("/library/parts/\(partID)", query: query, method: "PUT")
  }

  /// The server URL for a Plex path such as a sidecar subtitle's
  /// "/library/streams/<id>" (no token: it travels in headers).
  public func url(forKey key: String) -> URL { baseURL.appending(plexPath: key) }

  public func reportTimeline(_ report: TimelineReport) async throws {
    try await send("/:/timeline", query: report.queryItems)
  }

  // MARK: - URLs

  /// A server image resized by Plex, so a 300 pt card never downloads a 4K poster.
  /// No token in the URL (it is a cache key on disk): fetch it with
  /// `PlexImageAuth.request(_:)`, which adds the token as a header.
  public func imageURL(_ path: String?, width: Int, height: Int) -> URL? {
    guard let path, !path.isEmpty else { return nil }
    return baseURL.appending(
      plexPath: "/photo/:/transcode",
      query: [
        .init(name: "url", value: path),
        .init(name: "width", value: String(width)),
        .init(name: "height", value: String(height)),
        .init(name: "minSize", value: "1"),
        .init(name: "upscale", value: "1"),
      ])
  }

  // MARK: - Plumbing

  func request(_ path: String, query: [URLQueryItem] = [], method: String = "GET") -> URLRequest {
    var request = URLRequest(url: baseURL.appending(plexPath: path, query: query))
    request.httpMethod = method
    request.apply(headers: info.headers(token: token))
    return request
  }

  @discardableResult
  func send(_ path: String, query: [URLQueryItem] = [], method: String = "GET") async throws -> Data {
    let (data, response) = try await transport.send(request(path, query: query, method: method))
    switch response.statusCode {
    case 200..<300: return data
    case 401, 403: throw PlexError.unauthorized
    default: throw PlexError.http(response.statusCode)
    }
  }

  func get<Body: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> Body {
    let data = try await send(path, query: query)
    do {
      return try JSONDecoder().decode(MediaContainerEnvelope<Body>.self, from: data).MediaContainer
    } catch {
      throw PlexError.invalidResponse
    }
  }
}

/// Artwork pixel sizes, rounded up to fixed steps.
public enum ImageSize {
  /// Rounds the width up to a multiple of `step` and keeps the aspect ratio.
  /// Frames that differ by a few points then share one URL, so artwork is not
  /// refetched (and does not flicker) while a window resizes or a layout animates.
  /// Returns nil for an empty frame, which happens on a view's first layout pass.
  public static func bucketed(width: Double, height: Double, step: Double = 160) -> (width: Int, height: Int)? {
    guard width >= 1, height >= 1, width.isFinite, height.isFinite else { return nil }
    let w = max(step, (width / step).rounded(.up) * step)
    return (Int(w), Int((height * w / width).rounded()))
  }
}
