import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// A Jellyfin or Emby server (KP, 2026-11-17). Emby and Jellyfin share one
/// API (Jellyfin began as a fork of Emby); they differ in how a request
/// carries its sign-in. Everything is answered in Plex's models, and the
/// player gets the original file (`/Videos/<id>/stream?static=true`),
/// never a transcode.
public struct JellyfinClient: MediaSourceClient {
  public let config: SourceConfig
  let baseURL: URL
  let token: String
  let info: PlexClientInfo
  let transport: HTTPTransport

  public init(config: SourceConfig, token: String, info: PlexClientInfo, transport: HTTPTransport = URLSessionTransport()) throws {
    guard let url = JellyfinClient.normalizedURL(config.address) else { throw SourceError.badAddress }
    self.config = config
    self.baseURL = url
    self.token = token
    self.info = info
    self.transport = transport
  }

  var userID: String { config.userID ?? "" }

  // MARK: - Signing in

  /// What signing in learned: the token and the user, plus the server's own name.
  public struct SignIn: Sendable, Equatable {
    public var token: String
    public var userID: String
    public var serverName: String?
  }

  /// "nas:8096" → "http://nas:8096"; a trailing slash or "/web" is dropped.
  public static func normalizedURL(_ address: String) -> URL? {
    var text = address.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return nil }
    if !text.contains("://") { text = "http://" + text }
    while text.hasSuffix("/") { text.removeLast() }
    if text.lowercased().hasSuffix("/web") { text.removeLast(4) }
    guard let url = URL(string: text), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
      url.host != nil
    else { return nil }
    return url
  }

  /// Signs in with a username and password (`/Users/AuthenticateByName`).
  public static func signIn(
    kind: SourceKind, address: String, username: String, password: String, info: PlexClientInfo,
    transport: HTTPTransport = URLSessionTransport()
  ) async throws -> SignIn {
    guard let base = normalizedURL(address) else { throw SourceError.badAddress }
    var serverName: String?
    var publicInfo = URLRequest(url: base.appending(plexPath: "/System/Info/Public"))
    publicInfo.timeoutInterval = 8
    publicInfo.setValue("application/json", forHTTPHeaderField: "Accept")
    if let (data, response) = try? await transport.send(publicInfo), response.statusCode == 200 {
      serverName = (try? JSONDecoder().decode(PublicInfo.self, from: data))?.ServerName
    }
    var request = URLRequest(url: base.appending(plexPath: "/Users/AuthenticateByName"))
    request.httpMethod = "POST"
    request.timeoutInterval = 15
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    for (name, value) in authHeaders(kind: kind, token: nil, info: info) { request.setValue(value, forHTTPHeaderField: name) }
    request.httpBody = try JSONEncoder().encode(["Username": username, "Pw": password])
    let data: Data
    let response: HTTPURLResponse
    do {
      (data, response) = try await transport.send(request)
    } catch {
      throw SourceError.unreachable
    }
    switch response.statusCode {
    case 200..<300: break
    case 401, 403: throw SourceError.wrongLogin
    default: throw SourceError.http(response.statusCode)
    }
    guard let body = try? JSONDecoder().decode(AuthResult.self, from: data), let token = body.AccessToken,
      let user = body.User?.Id
    else { throw SourceError.notAServer }
    return SignIn(token: token, userID: user, serverName: serverName)
  }

  /// The headers that say who is asking. Jellyfin 12 accepts only the
  /// `Authorization: MediaBrowser …` form; Emby reads `X-Emby-Authorization`
  /// and `X-Emby-Token`.
  static func authHeaders(kind: SourceKind, token: String?, info: PlexClientInfo) -> [String: String] {
    func quoted(_ value: String) -> String { value.replacingOccurrences(of: "\"", with: "'") }
    var fields = [
      "Client=\"Astra\"", "Device=\"\(quoted(info.deviceName))\"", "DeviceId=\"\(quoted(info.clientIdentifier))\"",
      "Version=\"\(quoted(info.version))\"",
    ]
    switch kind {
    case .emby:
      var headers = ["X-Emby-Authorization": "MediaBrowser " + fields.joined(separator: ", ")]
      if let token { headers["X-Emby-Token"] = token }
      return headers
    default:
      if let token { fields.append("Token=\"\(token)\"") }
      return ["Authorization": "MediaBrowser " + fields.joined(separator: ", ")]
    }
  }

  /// The headers mpv and downloads send with a file: the token alone. mpv
  /// splits its header list on commas, so this form has none.
  var streamHeaders: [String: String] {
    config.kind == .emby ? ["X-Emby-Token": token] : ["Authorization": "MediaBrowser Token=\"\(token)\""]
  }

  // MARK: - MediaSourceClient

  public func libraries() async throws -> [SourceLibrary] {
    let body: ItemsBody = try await get("/Users/\(userID)/Views")
    return (body.Items ?? []).compactMap { view in
      guard let id = view.Id else { return nil }
      switch view.CollectionType?.lowercased() {
      case "movies": return SourceLibrary(id: id, title: view.Name ?? "Movies", type: "movie")
      case "tvshows": return SourceLibrary(id: id, title: view.Name ?? "TV Shows", type: "show")
      default: return nil
      }
    }
  }

  public func items(library: String, sort: String, start: Int, size: Int, filters: [URLQueryItem]) async throws -> [PlexMetadata] {
    let body: ItemsBody = try await get(
      "/Users/\(userID)/Items", query: listQuery(library: library, filters: filters) + Self.sortQuery(sort) + [
        .init(name: "StartIndex", value: String(start)), .init(name: "Limit", value: String(size)),
        .init(name: "EnableTotalRecordCount", value: "false"),
      ])
    let sectionID = PlexLibrarySection(key: key(library), title: "", type: "").numericID
    return (body.Items ?? []).compactMap {
      var item = map($0)
      item?.librarySectionID = sectionID
      return item
    }
  }

  public func count(library: String, filters: [URLQueryItem]) async throws -> Int? {
    let body: ItemsBody = try await get(
      "/Users/\(userID)/Items", query: listQuery(library: library, filters: filters) + [.init(name: "Limit", value: "0")])
    return body.TotalRecordCount
  }

  public func genres(library: String) async throws -> [PlexFilterValue] {
    let body: ItemsBody = try await get(
      "/Genres", query: [.init(name: "ParentId", value: library), .init(name: "UserId", value: userID)])
    return (body.Items ?? []).compactMap { $0.Name.map { PlexFilterValue(key: $0, title: $0) } }
  }

  public func metadata(_ id: String) async throws -> PlexMetadata {
    let item: Item = try await get("/Users/\(userID)/Items/\(id)", query: [.init(name: "Fields", value: Self.detailFields)])
    guard let mapped = map(item) else { throw SourceError.notFound }
    return mapped
  }

  public func children(_ id: String) async throws -> [PlexMetadata] {
    let parent: Item = try await get("/Users/\(userID)/Items/\(id)", query: [.init(name: "Fields", value: "ProviderIds")])
    let body: ItemsBody
    if parent.ItemType == "Series" {
      body = try await get(
        "/Shows/\(id)/Seasons",
        query: [.init(name: "UserId", value: userID), .init(name: "Fields", value: Self.listFields)])
    } else {
      body = try await get(
        "/Shows/\(parent.SeriesId ?? id)/Episodes",
        query: [
          .init(name: "UserId", value: userID), .init(name: "SeasonId", value: id),
          .init(name: "Fields", value: Self.listFields + ",MediaSources"),
        ])
    }
    return (body.Items ?? []).compactMap(map)
  }

  public func search(_ text: String, limit: Int) async throws -> [PlexMetadata] {
    let body: ItemsBody = try await get(
      "/Users/\(userID)/Items",
      query: [
        .init(name: "SearchTerm", value: text), .init(name: "Recursive", value: "true"),
        .init(name: "IncludeItemTypes", value: "Movie,Series,Episode"), .init(name: "Limit", value: String(limit)),
        .init(name: "Fields", value: Self.listFields),
      ])
    return (body.Items ?? []).compactMap(map)
  }

  public func continueWatching(count: Int) async throws -> [PlexMetadata] {
    let body: ItemsBody = try await get(
      "/Users/\(userID)/Items/Resume",
      query: [
        .init(name: "Limit", value: String(count)), .init(name: "MediaTypes", value: "Video"),
        .init(name: "Fields", value: Self.listFields),
      ])
    return (body.Items ?? []).compactMap(map)
  }

  public func setWatched(_ id: String, watched: Bool) async throws {
    try await send("/Users/\(userID)/PlayedItems/\(id)", method: watched ? "POST" : "DELETE")
  }

  public func removeFromContinueWatching(_ id: String) async throws {
    // Jellyfin and Emby list what has a resume point: clearing it takes the title off.
    try await send(
      "/Users/\(userID)/Items/\(id)/UserData", method: "POST", json: ["PlaybackPositionTicks": 0])
  }

  public func report(_ report: TimelineReport, id: String) async throws {
    let ticks = Int64(max(0, report.timeMs)) * 10_000
    let body: [String: Any] = [
      "ItemId": id, "PositionTicks": ticks, "IsPaused": report.state == .paused, "CanSeek": true,
      "PlayMethod": "DirectPlay",
    ]
    switch report.state {
    case .stopped: try await send("/Sessions/Playing/Stopped", method: "POST", json: body)
    default: try await send("/Sessions/Playing/Progress", method: "POST", json: body)
    }
  }

  /// "stream/<item>/<media source>/<container>" → the original file;
  /// "sub/<item>/<media source>/<index>/<codec>" → a sidecar subtitle.
  public func stream(_ key: String) -> StreamRequest? {
    let parts = key.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    switch parts.first {
    case "stream" where parts.count >= 3:
      let url = baseURL.appending(
        plexPath: "/Videos/\(parts[1])/stream",
        query: [.init(name: "static", value: "true"), .init(name: "mediaSourceId", value: parts[2])])
      return StreamRequest(url: url, headers: streamHeaders)
    case "sub" where parts.count >= 5:
      let url = baseURL.appending(
        plexPath: "/Videos/\(parts[1])/\(parts[2])/Subtitles/\(parts[3])/0/Stream.\(parts[4])")
      return StreamRequest(url: url, headers: streamHeaders)
    default:
      return nil
    }
  }

  /// "img/<item>/<type>/<tag>" → that image, scaled by the server.
  public func imageURL(_ path: String, width: Int, height: Int) -> URL? {
    let parts = path.split(separator: "/").map(String.init)
    guard parts.count >= 3, parts[0] == "img" else { return nil }
    var query: [URLQueryItem] = [.init(name: "quality", value: "90")]
    if parts[2] != "Logo" { query.append(.init(name: "fillWidth", value: String(width))) }
    query.append(.init(name: parts[2] == "Logo" ? "maxWidth" : "fillHeight", value: String(parts[2] == "Logo" ? width : height)))
    if parts.count >= 4 { query.append(.init(name: "tag", value: parts[3])) }
    return baseURL.appending(plexPath: "/Items/\(parts[1])/Images/\(parts[2])", query: query)
  }

  // MARK: - Queries

  static let listFields = "ProviderIds,Overview,Genres,DateCreated,PremiereDate,ProductionYear,ChildCount,RecursiveItemCount"
  static let detailFields = listFields + ",MediaSources,MediaStreams,People,Studios,Taglines,OfficialRating,Path"

  func listQuery(library: String, filters: [URLQueryItem]) -> [URLQueryItem] {
    var query: [URLQueryItem] = [
      .init(name: "ParentId", value: library), .init(name: "Recursive", value: "true"),
      .init(name: "IncludeItemTypes", value: "Movie,Series"), .init(name: "Fields", value: Self.listFields),
      .init(name: "EnableImageTypes", value: "Primary,Backdrop,Logo"),
    ]
    for filter in filters {
      switch filter.name {
      case "unwatched" where filter.value == "1": query.append(.init(name: "Filters", value: "IsUnplayed"))
      case "genre": if let genre = filter.value { query.append(.init(name: "Genres", value: genre)) }
      case "guid":
        // Plex's "is this title on the server" lookup: match by TMDB id.
        if let value = filter.value, value.hasPrefix("tmdb://") {
          query.append(.init(name: "AnyProviderIdEquals", value: "Tmdb." + value.dropFirst(7)))
        }
      default: break
      }
    }
    return query
  }

  /// Plex's sort ("titleSort", "addedAt:desc") in Jellyfin's terms.
  static func sortQuery(_ sort: String) -> [URLQueryItem] {
    let parts = sort.split(separator: ":")
    let field: String
    switch parts.first.map(String.init) ?? "" {
    case "addedAt": field = "DateCreated,SortName"
    case "originallyAvailableAt": field = "PremiereDate,SortName"
    case "year": field = "ProductionYear,SortName"
    case "audienceRating", "rating": field = "CommunityRating,SortName"
    case "duration": field = "Runtime,SortName"
    case "lastViewedAt": field = "DatePlayed,SortName"
    default: field = "SortName"
    }
    let order = parts.count > 1 && parts[1] == "desc" ? "Descending" : "Ascending"
    return [.init(name: "SortBy", value: field), .init(name: "SortOrder", value: order)]
  }

  // MARK: - Mapping

  /// A Jellyfin/Emby item as a Plex item, every key made a source key.
  func map(_ item: Item) -> PlexMetadata? {
    guard let id = item.Id else { return nil }
    let type: PlexItemType
    switch item.ItemType {
    case "Movie": type = .movie
    case "Series": type = .show
    case "Season": type = .season
    case "Episode": type = .episode
    default: return nil
    }
    var out = PlexMetadata(ratingKey: key(id), type: type, title: item.Name ?? "")
    out.key = key(id)
    out.guid = "\(config.kind.rawValue)://\(id)"
    out.titleSort = item.SortName
    out.summary = item.Overview
    out.tagline = item.Taglines?.first
    out.year = item.ProductionYear
    out.originallyAvailableAt = item.PremiereDate.map { String($0.prefix(10)) }
    out.contentRating = item.OfficialRating
    out.audienceRating = item.CommunityRating
    out.studio = item.Studios?.first?.Name
    out.duration = item.RunTimeTicks.map { Int($0 / 10_000) }
    out.index = item.IndexNumber
    out.parentIndex = item.ParentIndexNumber
    out.childCount = item.ChildCount
    out.genres = (item.Genres ?? []).map { PlexTag(tag: $0) }
    out.guids = Self.guids(item.ProviderIds)

    // Watched state and progress.
    let user = item.UserData
    if let ticks = user?.PlaybackPositionTicks, ticks > 0, user?.Played != true {
      out.viewOffset = Int(ticks / 10_000)
    }
    if user?.Played == true { out.viewCount = max(1, user?.PlayCount ?? 1) }
    out.lastViewedAt = user?.LastPlayedDate.flatMap(Self.epochSeconds)
    if type == .show || type == .season, let total = item.RecursiveItemCount ?? item.ChildCount {
      out.leafCount = total
      if let unplayed = user?.UnplayedItemCount { out.viewedLeafCount = max(0, total - unplayed) }
      else if user?.Played == true { out.viewedLeafCount = total }
    }

    // Artwork.
    if let tag = item.ImageTags?["Primary"] { out.thumb = key("img/\(id)/Primary/\(tag)") }
    if let tag = item.BackdropImageTags?.first {
      out.art = key("img/\(id)/Backdrop/\(tag)")
    } else if let parent = item.ParentBackdropItemId, let tag = item.ParentBackdropImageTags?.first {
      out.art = key("img/\(parent)/Backdrop/\(tag)")
    }
    if let tag = item.ImageTags?["Logo"] {
      out.images = [PlexImage(type: "clearLogo", url: key("img/\(id)/Logo/\(tag)"))]
    } else if let parent = item.ParentLogoItemId, let tag = item.ParentLogoImageTag {
      out.images = [PlexImage(type: "clearLogo", url: key("img/\(parent)/Logo/\(tag)"))]
    }

    // Show, season and episode links.
    switch type {
    case .season:
      out.parentRatingKey = optionalKey(item.SeriesId)
      out.parentTitle = item.SeriesName
      out.parentGuid = item.SeriesId.map { "\(config.kind.rawValue)://\($0)" }
      out.parentThumb = item.SeriesId.flatMap { series in item.SeriesPrimaryImageTag.map { key("img/\(series)/Primary/\($0)") } }
      if out.thumb == nil { out.thumb = out.parentThumb }
    case .episode:
      out.parentRatingKey = optionalKey(item.SeasonId)
      out.parentTitle = item.SeasonName
      out.grandparentRatingKey = optionalKey(item.SeriesId)
      out.grandparentTitle = item.SeriesName
      out.grandparentGuid = item.SeriesId.map { "\(config.kind.rawValue)://\($0)" }
      out.grandparentThumb = item.SeriesId.flatMap { series in item.SeriesPrimaryImageTag.map { key("img/\(series)/Primary/\($0)") } }
      out.grandparentArt = out.art
    default:
      break
    }

    out.directors = (item.People ?? []).filter { $0.PersonType == "Director" }.compactMap { person in
      person.Name.map { PlexTag(tag: $0) }
    }
    out.roles = (item.People ?? []).filter { $0.PersonType == "Actor" }.compactMap { person in
      person.Name.map { name in
        PlexTag(
          tag: name, role: person.Role,
          thumb: person.Id.flatMap { pid in person.PrimaryImageTag.map { key("img/\(pid)/Primary/\($0)") } })
      }
    }
    out.media = (item.MediaSources ?? []).compactMap { mapMedia($0, item: id, duration: out.duration) }
    return out
  }

  func mapMedia(_ source: MediaSource, item: String, duration: Int?) -> PlexMedia? {
    guard let sourceID = source.Id else { return nil }
    let streams = source.MediaStreams ?? []
    let video = streams.first { $0.StreamType == "Video" }
    let audio = streams.first { $0.StreamType == "Audio" && $0.IsDefault == true } ?? streams.first { $0.StreamType == "Audio" }
    let container = source.Container?.split(separator: ",").first.map(String.init)
    let partKey = key("stream/\(item)/\(sourceID)/\(container ?? "mkv")")
    var media = PlexMedia(
      id: SourceKey.number(partKey + "#media"), duration: source.RunTimeTicks.map { Int($0 / 10_000) } ?? duration,
      bitrate: source.Bitrate.map { $0 / 1000 }, width: video?.Width, height: video?.Height, container: container)
    media.videoCodec = video?.Codec
    media.videoProfile = video?.Profile
    media.audioCodec = audio?.Codec
    media.audioChannels = audio?.Channels
    var part = PlexPart(
      id: SourceKey.number(partKey), key: partKey, duration: media.duration, file: source.Path, size: source.Size,
      container: container)
    part.streams = streams.compactMap { stream in mapStream(stream, item: item, source: sourceID) }
    media.parts = [part]
    return media
  }

  func mapStream(_ stream: MediaStream, item: String, source: String) -> PlexStream? {
    let type: Int
    switch stream.StreamType {
    case "Video": type = 1
    case "Audio": type = 2
    case "Subtitle": type = 3
    default: return nil
    }
    let index = stream.Index ?? 0
    let external = stream.IsExternal == true
    var out = PlexStream(
      id: SourceKey.number(key("\(item)/\(source)/\(index)")), streamType: type, codec: stream.Codec?.lowercased(),
      displayTitle: stream.DisplayTitle, language: stream.Language.flatMap(Self.languageName),
      languageCode: stream.Language, selected: stream.IsDefault, forced: stream.IsForced,
      key: external && type == 3 ? key("sub/\(item)/\(source)/\(index)/\(Self.subtitleFormat(stream.Codec))") : nil,
      index: external ? nil : index)
    out.default = stream.IsDefault
    out.extendedDisplayTitle = [stream.Title, stream.Profile, stream.VideoRangeType].compactMap { $0 }.joined(separator: " ")
    if type == 1 {
      switch stream.VideoRangeType?.uppercased() ?? stream.VideoRange?.uppercased() ?? "" {
      case let range where range.contains("DOVI"): out.DOVIPresent = true
      case "HDR10PLUS": out.displayTitle = (stream.DisplayTitle ?? "") + " HDR10+"
      case "HDR10", "HDR": out.colorTrc = "smpte2084"
      case "HLG": out.colorTrc = "arib-std-b67"
      default: break
      }
    }
    return out
  }

  /// Sidecar subtitle codecs as the file extension the server converts to.
  static func subtitleFormat(_ codec: String?) -> String {
    switch codec?.lowercased() {
    case "subrip", "srt": "srt"
    case "ass": "ass"
    case "ssa": "ssa"
    case "webvtt", "vtt": "vtt"
    default: codec?.lowercased() ?? "srt"
    }
  }

  static func languageName(_ code: String) -> String? {
    Locale(identifier: "en").localizedString(forLanguageCode: code)
  }

  static func guids(_ ids: [String: String]?) -> [PlexGuid] {
    guard let ids else { return [] }
    var out: [PlexGuid] = []
    for (name, value) in ids.sorted(by: { $0.key < $1.key }) where !value.isEmpty {
      switch name.lowercased() {
      case "tmdb": out.insert(PlexGuid(id: "tmdb://\(value)"), at: 0)
      case "imdb": out.append(PlexGuid(id: "imdb://\(value)"))
      case "tvdb": out.append(PlexGuid(id: "tvdb://\(value)"))
      default: break
      }
    }
    return out
  }

  /// "2026-11-17T19:48:57.1234567Z" → seconds since 1970.
  static func epochSeconds(_ text: String) -> Int? {
    let trimmed = text.count > 19 ? String(text.prefix(19)) + "Z" : text
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: trimmed).map { Int($0.timeIntervalSince1970) }
  }

  // MARK: - Plumbing

  func request(_ path: String, query: [URLQueryItem] = [], method: String = "GET") -> URLRequest {
    var request = URLRequest(url: baseURL.appending(plexPath: path, query: query))
    request.httpMethod = method
    request.timeoutInterval = 30
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    for (name, value) in Self.authHeaders(kind: config.kind, token: token, info: info) {
      request.setValue(value, forHTTPHeaderField: name)
    }
    return request
  }

  @discardableResult
  func send(_ path: String, query: [URLQueryItem] = [], method: String = "GET", json: [String: Any]? = nil) async throws -> Data {
    var request = request(path, query: query, method: method)
    if let json {
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try JSONSerialization.data(withJSONObject: json)
    }
    let (data, response) = try await transport.send(request)
    switch response.statusCode {
    case 200..<300: return data
    case 401, 403: throw SourceError.wrongLogin
    case 404: throw SourceError.notFound
    default: throw SourceError.http(response.statusCode)
    }
  }

  func get<Body: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> Body {
    let data = try await send(path, query: query)
    do {
      return try JSONDecoder().decode(Body.self, from: data)
    } catch {
      throw SourceError.notAServer
    }
  }

  // MARK: - JSON

  struct PublicInfo: Decodable {
    var ServerName: String?
  }

  struct AuthResult: Decodable {
    struct User: Decodable { var Id: String? }
    var AccessToken: String?
    var User: User?
  }

  struct ItemsBody: Decodable {
    var Items: [Item]?
    var TotalRecordCount: Int?
  }

  struct Item: Decodable {
    struct UserState: Decodable {
      var PlaybackPositionTicks: Int64?
      var PlayCount: Int?
      var Played: Bool?
      var LastPlayedDate: String?
      var UnplayedItemCount: Int?
    }
    struct Person: Decodable {
      var Name: String?
      var Id: String?
      var Role: String?
      var PersonType: String?
      var PrimaryImageTag: String?
      enum CodingKeys: String, CodingKey {
        case Name, Id, Role, PrimaryImageTag
        case PersonType = "Type"
      }
    }
    struct Studio: Decodable { var Name: String? }

    var Id: String?
    var Name: String?
    var SortName: String?
    var ItemType: String?
    var CollectionType: String?
    var Overview: String?
    var Taglines: [String]?
    var ProductionYear: Int?
    var PremiereDate: String?
    var OfficialRating: String?
    var CommunityRating: Double?
    var RunTimeTicks: Int64?
    var IndexNumber: Int?
    var ParentIndexNumber: Int?
    var ChildCount: Int?
    var RecursiveItemCount: Int?
    var Genres: [String]?
    var Studios: [Studio]?
    var People: [Person]?
    var ProviderIds: [String: String]?
    var UserData: UserState?
    var ImageTags: [String: String]?
    var BackdropImageTags: [String]?
    var ParentBackdropItemId: String?
    var ParentBackdropImageTags: [String]?
    var ParentLogoItemId: String?
    var ParentLogoImageTag: String?
    var SeriesId: String?
    var SeriesName: String?
    var SeriesPrimaryImageTag: String?
    var SeasonId: String?
    var SeasonName: String?
    var MediaSources: [MediaSource]?

    enum CodingKeys: String, CodingKey {
      case Id, Name, SortName, CollectionType, Overview, Taglines, ProductionYear, PremiereDate, OfficialRating,
        CommunityRating, RunTimeTicks, IndexNumber, ParentIndexNumber, ChildCount, RecursiveItemCount, Genres, Studios,
        People, ProviderIds, UserData, ImageTags, BackdropImageTags, ParentBackdropItemId, ParentBackdropImageTags,
        ParentLogoItemId, ParentLogoImageTag, SeriesId, SeriesName, SeriesPrimaryImageTag, SeasonId, SeasonName,
        MediaSources
      case ItemType = "Type"
    }

    init(from decoder: Decoder) throws {
      let c = try decoder.container(keyedBy: CodingKeys.self)
      func value<T: Decodable>(_ key: CodingKeys) -> T? { (try? c.decodeIfPresent(T.self, forKey: key)) ?? nil }
      Id = value(.Id)
      Name = value(.Name)
      SortName = value(.SortName)
      ItemType = value(.ItemType)
      CollectionType = value(.CollectionType)
      Overview = value(.Overview)
      Taglines = value(.Taglines)
      ProductionYear = value(.ProductionYear)
      PremiereDate = value(.PremiereDate)
      OfficialRating = value(.OfficialRating)
      CommunityRating = value(.CommunityRating)
      RunTimeTicks = value(.RunTimeTicks)
      IndexNumber = value(.IndexNumber)
      ParentIndexNumber = value(.ParentIndexNumber)
      ChildCount = value(.ChildCount)
      RecursiveItemCount = value(.RecursiveItemCount)
      Genres = value(.Genres)
      Studios = value(.Studios)
      People = value(.People)
      // Provider ids can be null-valued in some server versions.
      ProviderIds = (value(.ProviderIds) as [String: String?]?)?.compactMapValues { $0 }
      UserData = value(.UserData)
      ImageTags = value(.ImageTags)
      BackdropImageTags = value(.BackdropImageTags)
      ParentBackdropItemId = value(.ParentBackdropItemId)
      ParentBackdropImageTags = value(.ParentBackdropImageTags)
      ParentLogoItemId = value(.ParentLogoItemId)
      ParentLogoImageTag = value(.ParentLogoImageTag)
      SeriesId = value(.SeriesId)
      SeriesName = value(.SeriesName)
      SeriesPrimaryImageTag = value(.SeriesPrimaryImageTag)
      SeasonId = value(.SeasonId)
      SeasonName = value(.SeasonName)
      MediaSources = value(.MediaSources)
    }
  }

  struct MediaSource: Decodable {
    var Id: String?
    var Container: String?
    var Path: String?
    var Size: Int64?
    var Bitrate: Int?
    var RunTimeTicks: Int64?
    var MediaStreams: [MediaStream]?
  }

  struct MediaStream: Decodable {
    var StreamType: String?
    var Codec: String?
    var Index: Int?
    var Language: String?
    var DisplayTitle: String?
    var Title: String?
    var Profile: String?
    var IsDefault: Bool?
    var IsForced: Bool?
    var IsExternal: Bool?
    var Width: Int?
    var Height: Int?
    var Channels: Int?
    var VideoRange: String?
    var VideoRangeType: String?

    enum CodingKeys: String, CodingKey {
      case Codec, Index, Language, DisplayTitle, Title, Profile, IsDefault, IsForced, IsExternal, Width, Height,
        Channels, VideoRange, VideoRangeType
      case StreamType = "Type"
    }
  }
}

/// Why a source couldn't be added or read, in words for Settings.
public enum SourceError: Error, LocalizedError, Equatable, Sendable {
  case badAddress
  case unreachable
  case wrongLogin
  case notAServer
  case notFound
  case http(Int)
  case share(String)

  public var errorDescription: String? {
    switch self {
    case .badAddress: "That address doesn't look right. Try something like 192.168.1.20:8096."
    case .unreachable: "Astra couldn't reach that address. Check it's on and on this network."
    case .wrongLogin: "The username or password wasn't accepted."
    case .notAServer: "Something answered, but it isn't a Jellyfin or Emby server."
    case .notFound: "That title is no longer on the server."
    case .http(let code): "The server answered with an error (\(code))."
    case .share(let reason): reason
    }
  }
}
