import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// A streaming service in Home's top switcher, with its TMDB watch-provider
/// ids for the US. Same list as the Flutter app (lib/astra/streaming_services.dart).
///
/// Browsing a service shows what TMDB says streams there. That is catalog
/// data only: a title plays in Astra only when it is on the Plex server.
public struct StreamingService: Sendable, Hashable, Identifiable {
  public var id: String
  public var label: String
  /// Asset catalog image name of the monochrome logo.
  public var logo: String
  public var providerIds: [Int]
  /// Visual height of the logo in the switcher, tuned per wordmark.
  public var logoHeight: Double
  /// The brand's own colour (RGB), used for its logo and Home's accent when chosen.
  public var accent: UInt32

  public var providerFilter: String { providerIds.map(String.init).joined(separator: "|") }

  public static let all: [StreamingService] = [
    // Astra: the main services only (KP, 2026-11-07), in KP's order, each with its brand colour.
    .init(id: "netflix", label: "Netflix", logo: "provider-netflix", providerIds: [8], logoHeight: 15, accent: 0xE50914),
    .init(id: "appletv", label: "Apple TV+", logo: "provider-appletv", providerIds: [350], logoHeight: 17, accent: 0xF5F5F7),
    .init(id: "prime", label: "Prime Video", logo: "provider-prime", providerIds: [9], logoHeight: 20, accent: 0x00A8E1),
    .init(id: "disney", label: "Disney+", logo: "provider-disney", providerIds: [337], logoHeight: 24, accent: 0x1F80E0),
    .init(id: "max", label: "HBO Max", logo: "provider-max", providerIds: [1899], logoHeight: 22, accent: 0x0046FF),
    .init(id: "hulu", label: "Hulu", logo: "provider-hulu", providerIds: [15], logoHeight: 15, accent: 0x1CE783),
  ]

  public static func byID(_ id: String?) -> StreamingService? {
    all.first { $0.id == id }
  }
}

/// A person from TMDB search: Search's People rows.
public struct TMDBPerson: Sendable, Hashable, Identifiable {
  public var id: Int
  public var name: String
  /// "Acting", "Directing"…
  public var department: String?
  public var profilePath: String?
  /// Their best-known titles, for the row's second line.
  public var knownFor: [String]

  public var profileURL: URL? { TMDBArtwork.url(profilePath, size: "w185") }

  /// "Actor", "Director"…
  public var role: String {
    switch department {
    case "Acting": "Actor"
    case "Directing": "Director"
    case "Writing": "Writer"
    case "Production": "Producer"
    case let other?: other
    case nil: "Person"
    }
  }
}

/// One TMDB search/discover result.
public struct TMDBItem: Sendable, Hashable, Identifiable, Codable {
  public enum Kind: String, Sendable, Codable { case movie, tv }

  public var tmdbID: Int
  public var kind: Kind
  public var title: String
  public var year: Int?
  public var overview: String?
  public var rating: Double?
  public var posterPath: String?
  public var backdropPath: String?
  /// The original language (ISO 639-1, "en", "hi"), for Search's language filter.
  public var language: String?

  public var id: String { "\(kind.rawValue):\(tmdbID)" }

  static func image(_ path: String?, size: String) -> String? {
    guard let path, !path.isEmpty else { return nil }
    return "https://image.tmdb.org/t/p/\(size)\(path)"
  }

  /// The item as a catalog-only `PlexMetadata`, so Home's cards and hero can
  /// show it. Its rating key starts with `tmdb:`; opening or playing it first
  /// looks the title up on the Plex server.
  public var asMetadata: PlexMetadata {
    var item = PlexMetadata(
      ratingKey: "tmdb:\(id)", type: kind == .movie ? .movie : .show, title: title, summary: overview, year: year,
      thumb: Self.image(posterPath, size: "w342"), art: Self.image(backdropPath, size: "w1280"))
    item.guids = [PlexGuid(id: "tmdb://\(tmdbID)")]
    item.audienceRating = rating
    return item
  }
}

extension PlexMetadata {
  /// True for a TMDB title shown on Home that hasn't been matched to the server yet.
  public var isCatalogOnly: Bool { ratingKey.hasPrefix("tmdb:") }
}

/// TMDB artwork paths for one title.
public struct TMDBArtwork: Sendable, Hashable {
  public var posterPath: String?
  public var backdropPath: String?
  public var logoPath: String?

  public init(posterPath: String?, backdropPath: String?, logoPath: String?) {
    self.posterPath = posterPath
    self.backdropPath = backdropPath
    self.logoPath = logoPath
  }

  /// A full image URL. Sizes: poster w342/w500/w780, backdrop w780/w1280/original, logo w300/w500.
  public static func url(_ path: String?, size: String) -> URL? {
    TMDBItem.image(path, size: size).flatMap(URL.init(string:))
  }
}

extension PlexMetadata {
  /// "movie:603" / "tv:1399" for a movie or show with a TMDB guid; nil otherwise.
  public var tmdbKey: String? {
    let kind: String
    switch type {
    case .movie: kind = "movie"
    case .show: kind = "tv"
    default: return nil
    }
    guard let id = guids.lazy.compactMap({ $0.id.hasPrefix("tmdb://") ? Int($0.id.dropFirst(7)) : nil }).first
    else { return nil }
    return "\(kind):\(id)"
  }
}

/// A minimal TMDB v3 client for Home's discovery rows, with the same queries
/// as the Flutter app. The read token is injected at build time.
public struct TMDBClient: Sendable {
  public static let region = "US"

  let token: String
  let transport: HTTPTransport
  let base = URL(string: "https://api.themoviedb.org/3")!

  public init(token: String, transport: HTTPTransport = URLSessionTransport()) {
    self.token = token
    self.transport = transport
  }

  public func trendingWeek() async throws -> [TMDBItem] {
    try await list("/trending/all/week", [:], kind: nil)
  }

  /// What's trending on TMDB today or this week, movies and shows together. 20 per page.
  public func trending(_ window: TrendingWindow, page: Int = 1) async throws -> [TMDBItem] {
    try await list("/trending/all/\(window.rawValue)", ["page": String(page)], kind: nil)
  }

  public enum TrendingWindow: String, Sendable { case day, week }

  public func popular(_ kind: TMDBItem.Kind) async throws -> [TMDBItem] {
    try await list("/discover/\(kind.rawValue)", ["sort_by": "popularity.desc", "watch_region": Self.region], kind: kind)
  }

  public func topRatedMovies() async throws -> [TMDBItem] {
    try await list("/movie/top_rated", [:], kind: .movie)
  }

  /// What streams on `service` (subscription, US), by popularity or rating. 20 per page.
  public func onService(
    _ service: StreamingService, _ kind: TMDBItem.Kind, topRated: Bool = false, page: Int = 1
  ) async throws -> [TMDBItem] {
    var query = [
      "with_watch_providers": service.providerFilter,
      "watch_region": Self.region,
      "with_watch_monetization_types": "flatrate",
      "sort_by": topRated ? "vote_average.desc" : "popularity.desc",
      "page": String(page),
    ]
    if topRated { query["vote_count.gte"] = kind == .tv ? "200" : "500" }
    return try await list("/discover/\(kind.rawValue)", query, kind: kind)
  }

  /// One discover page for a service row (see `ServiceCatalog`).
  public func discover(_ request: DiscoverRequest, on service: StreamingService) async throws -> [TMDBItem] {
    try await list("/discover/\(request.kind.rawValue)", request.query(service: service), kind: request.kind)
  }

  /// Search: titles (with their languages) and people for `text`, best matches first.
  public func searchMulti(_ text: String) async throws -> (items: [TMDBItem], people: [TMDBPerson]) {
    let data = try await get("/search/multi", ["query": text, "include_adult": "false"])
    let page = try JSONDecoder().decode(MultiPage.self, from: data)
    var items: [TMDBItem] = []
    var people: [TMDBPerson] = []
    for result in page.results {
      if result.media_type == "person" {
        if let person = result.person { people.append(person) }
      } else if let item = result.raw.item(forcedKind: nil) {
        items.append(item)
      }
    }
    return (items, people)
  }

  /// Everything a person acted in or made, most popular first, each title once.
  public func credits(of person: Int) async throws -> [TMDBItem] {
    let data = try await get("/person/\(person)/combined_credits", [:])
    let credits = try JSONDecoder().decode(Credits.self, from: data)
    var seen = Set<String>()
    return ((credits.cast ?? []) + (credits.crew ?? []))
      .sorted { ($0.popularity ?? 0) > ($1.popularity ?? 0) }
      .compactMap { $0.raw.item(forcedKind: nil) }
      .filter { seen.insert($0.id).inserted }
  }

  struct MultiPage: Decodable {
    var results: [MultiResult]
  }

  /// One /search/multi or credits row: a title (Raw's fields) or a person.
  struct MultiResult: Decodable {
    var raw: Raw
    var media_type: String?
    var popularity: Double?
    var person: TMDBPerson?

    enum Keys: String, CodingKey { case id, name, media_type, popularity, profile_path, known_for_department, known_for }
    struct KnownFor: Decodable {
      var title: String?
      var name: String?
    }

    init(from decoder: Decoder) throws {
      raw = try Raw(from: decoder)
      let c = try decoder.container(keyedBy: Keys.self)
      media_type = try? c.decodeIfPresent(String.self, forKey: .media_type)
      popularity = try? c.decodeIfPresent(Double.self, forKey: .popularity)
      if media_type == "person", let id = try? c.decodeIfPresent(Int.self, forKey: .id),
        let name = try? c.decodeIfPresent(String.self, forKey: .name)
      {
        let known = (try? c.decodeIfPresent([KnownFor].self, forKey: .known_for)) ?? []
        person = TMDBPerson(
          id: id, name: name, department: (try? c.decodeIfPresent(String.self, forKey: .known_for_department)) ?? nil,
          profilePath: (try? c.decodeIfPresent(String.self, forKey: .profile_path)) ?? nil,
          knownFor: known.compactMap { $0.title ?? $0.name })
      }
    }
  }

  struct Credits: Decodable {
    var cast: [MultiResult]?
    var crew: [MultiResult]?
  }

  /// One title by its TMDB id, or nil when it has no title or artwork.
  public func item(id: Int, kind: TMDBItem.Kind) async throws -> TMDBItem? {
    let data = try await get("/\(kind.rawValue)/\(id)", [:])
    return try JSONDecoder().decode(Raw.self, from: data).item(forcedKind: kind)
  }

  /// Poster, backdrop and title logo for one title.
  public func artwork(id: Int, kind: TMDBItem.Kind) async throws -> TMDBArtwork {
    let data = try await get(
      "/\(kind.rawValue)/\(id)",
      ["append_to_response": "images", "include_image_language": "en,null,ja,ko,fr,es,de,it,pt,hi,zh,da,sv,no"])
    let raw = try JSONDecoder().decode(ArtworkRaw.self, from: data)
    return TMDBArtwork(
      posterPath: raw.poster_path, backdropPath: raw.backdrop_path,
      logoPath: Self.bestLogo(raw.images?.logos ?? [], original: raw.original_language))
  }

  /// Astra (KP, 2026-11-07: "a lot of them don't have the logo"): the best
  /// title logo, like the streaming sites show. PNG only (the image pipeline
  /// can't decode SVG); English first, then the title's own language, then
  /// text-free, then any; the best voted within each.
  static func bestLogo(_ logos: [ArtworkRaw.Images.Image], original: String?) -> String? {
    let png = logos.filter { $0.file_path?.hasSuffix(".png") == true }
    func rank(_ logo: ArtworkRaw.Images.Image) -> Int {
      switch logo.iso_639_1 {
      case "en": 0
      case let code? where code == original: 1
      case nil: 2
      default: 3
      }
    }
    return png.enumerated()
      .min { a, b in
        (rank(a.element), -(a.element.vote_average ?? 0), a.offset) < (rank(b.element), -(b.element.vote_average ?? 0), b.offset)
      }?.element.file_path
  }

  func get(_ path: String, _ query: [String: String]) async throws -> Data {
    var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
    components.queryItems = ([URLQueryItem(name: "language", value: "en-US")]
      + query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) })
    var request = URLRequest(url: components.url!)
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.timeoutInterval = 12
    let (data, response) = try await transport.send(request)
    guard response.statusCode == 200 else { throw PlexError.http(response.statusCode) }
    return data
  }

  struct ArtworkRaw: Decodable {
    struct Images: Decodable {
      struct Image: Decodable {
        var file_path: String?
        var iso_639_1: String?
        var vote_average: Double?
      }
      var logos: [Image]?
    }
    var poster_path: String?
    var backdrop_path: String?
    var original_language: String?
    var images: Images?
  }

  func list(_ path: String, _ query: [String: String], kind: TMDBItem.Kind?) async throws -> [TMDBItem] {
    let data = try await get(path, query)
    let page = try JSONDecoder().decode(Page.self, from: data)
    return page.results.compactMap { $0.item(forcedKind: kind) }
  }

  struct Page: Decodable {
    var results: [Raw]
  }

  struct Raw: Decodable {
    var id: Int?
    var media_type: String?
    var title: String?
    var name: String?
    var release_date: String?
    var first_air_date: String?
    var overview: String?
    var vote_average: Double?
    var poster_path: String?
    var backdrop_path: String?
    var original_language: String?

    func item(forcedKind: TMDBItem.Kind?) -> TMDBItem? {
      let kind = forcedKind ?? TMDBItem.Kind(rawValue: media_type ?? "")
      guard let kind, let id else { return nil }
      guard let title = (kind == .tv ? name : title), !title.isEmpty else { return nil }
      guard poster_path != nil || backdrop_path != nil else { return nil }
      let date = kind == .tv ? first_air_date : release_date
      return TMDBItem(
        tmdbID: id, kind: kind, title: title, year: date.flatMap { Int($0.prefix(4)) }, overview: overview,
        rating: (vote_average ?? 0) > 0 ? vote_average : nil, posterPath: poster_path, backdropPath: backdrop_path,
        language: original_language)
    }
  }
}

/// Picks the hero: what's trending right now, but only titles on the Plex server.
public enum TrendingHero {
  /// `trending` in TMDB's order (most trending first) mapped to the server's
  /// items through `index` ("movie:603" → item), each title once.
  public static func pick(
    trending: [TMDBItem], index: [String: PlexMetadata], limit: Int = 6
  ) -> [PlexMetadata] {
    var seen = Set<String>()
    var out: [PlexMetadata] = []
    for item in trending where out.count < limit {
      guard let match = index[item.id], seen.insert(item.id).inserted else { continue }
      out.append(match)
    }
    return out
  }

  /// The For You hero, like cineby's "Top content today": TMDB's trending
  /// titles in order, each once. Ones on the server come from `index` (so
  /// they play); the rest are TMDB-only and show a greyed-out Play.
  public static func today(
    trending: [TMDBItem], index: [String: PlexMetadata], limit: Int = 10
  ) -> [PlexMetadata] {
    var seen = Set<String>()
    var out: [PlexMetadata] = []
    for item in trending where out.count < limit {
      guard seen.insert(item.id).inserted else { continue }
      out.append(index[item.id] ?? item.asMetadata)
    }
    return out
  }

  /// The numbered Top 10 rows under Continue Watching: trending movies and
  /// trending shows, each in TMDB's order, each title once.
  public static func topTen(
    trending: [TMDBItem], index: [String: PlexMetadata], limit: Int = 10
  ) -> (movies: [PlexMetadata], shows: [PlexMetadata]) {
    func list(_ kind: TMDBItem.Kind) -> [PlexMetadata] {
      today(trending: trending.filter { $0.kind == kind }, index: index, limit: limit)
    }
    return (list(.movie), list(.tv))
  }

  /// A streaming service's Top 10 (KP, 2026-11-07: "if I go to Netflix…
  /// it'll just tell me what the trending thing is"): its titles trending
  /// now, in trending order, then its most popular titles, each once.
  public static func serviceTopTen(
    trending: [TMDBItem], service popular: [PlexMetadata], limit: Int = 10
  ) -> [PlexMetadata] {
    let byKey = Dictionary(popular.compactMap { item in item.tmdbKey.map { ($0, item) } }, uniquingKeysWith: { a, _ in a })
    var out = pick(trending: trending, index: byKey, limit: limit)
    var seen = Set(out.compactMap(\.tmdbKey))
    for item in popular where out.count < limit {
      guard let key = item.tmdbKey, seen.insert(key).inserted else { continue }
      out.append(item)
    }
    return out
  }

  /// For a streaming service: its titles that are trending, in trending
  /// order; then, if that's too few, its popular titles from the last two
  /// years. Never an old catalogue title.
  public static func pick(
    trending: [TMDBItem], service popular: [PlexMetadata], limit: Int = 6, currentYear: Int
  ) -> [PlexMetadata] {
    let byKey = Dictionary(popular.compactMap { item in item.tmdbKey.map { ($0, item) } }, uniquingKeysWith: { a, _ in a })
    var out = pick(trending: trending, index: byKey, limit: limit)
    var seen = Set(out.compactMap(\.tmdbKey))
    for item in popular where out.count < limit {
      guard let year = item.year, year >= currentYear - 2, let key = item.tmdbKey, seen.insert(key).inserted
      else { continue }
      out.append(item)
    }
    return out
  }
}

/// One TMDB discover query for a streaming service's row.
public struct DiscoverRequest: Sendable, Hashable {
  public enum Order: Sendable, Hashable { case popular, newest, topRated }

  public var kind: TMDBItem.Kind
  public var order: Order
  /// TMDB genre ids, any of them ("28|12").
  public var genres: String?
  public var page: Int

  public init(_ kind: TMDBItem.Kind, _ order: Order, genres: String? = nil, page: Int = 1) {
    self.kind = kind
    self.order = order
    self.genres = genres
    self.page = page
  }

  func query(service: StreamingService, today: Date = Date()) -> [String: String] {
    var query = [
      "with_watch_providers": service.providerFilter,
      "watch_region": TMDBClient.region,
      "with_watch_monetization_types": "flatrate",
      "page": String(page),
    ]
    let dateField = kind == .movie ? "primary_release_date" : "first_air_date"
    switch order {
    case .popular:
      query["sort_by"] = "popularity.desc"
    case .newest:
      query["sort_by"] = "\(dateField).desc"
      query["\(dateField).lte"] = Self.day.string(from: today)
      // Skips placeholders and obscure uploads with no audience yet.
      query["vote_count.gte"] = "15"
    case .topRated:
      query["sort_by"] = "vote_average.desc"
      query["vote_count.gte"] = kind == .tv ? "200" : "500"
    }
    if let genres { query["with_genres"] = genres }
    return query
  }

  static let day: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(identifier: "UTC")
    f.dateFormat = "yyyy-MM-dd"
    return f
  }()
}

/// The rows a streaming service's tab shows, all from that service only.
public enum ServiceCatalog {
  public struct Row: Sendable, Hashable {
    public var id: String
    public var title: String
    /// Movies and shows alternate in the row when both are asked for.
    public var requests: [DiscoverRequest]
  }

  /// Movie and TV genre ids differ on TMDB.
  static let genres: [(id: String, title: String, movie: String, tv: String)] = [
    ("action", "Action & Adventure", "28|12", "10759"),
    ("comedy", "Comedy", "35", "35"),
    ("drama", "Drama", "18", "18"),
    ("scifi", "Sci-Fi & Fantasy", "878|14", "10765"),
    ("crime", "Crime & Thrillers", "80|53", "80|9648"),
    ("animation", "Animation", "16", "16"),
    ("documentary", "Documentaries", "99", "99"),
  ]

  public static func rows(for service: StreamingService) -> [Row] {
    func both(_ order: DiscoverRequest.Order, pages: Int, genre: (movie: String, tv: String)? = nil) -> [DiscoverRequest] {
      (1...pages).flatMap { page in
        [
          DiscoverRequest(.tv, order, genres: genre?.tv, page: page),
          DiscoverRequest(.movie, order, genres: genre?.movie, page: page),
        ]
      }
    }
    let name = service.label
    var rows = [
      Row(id: "\(service.id).trending", title: "Trending on \(name)", requests: both(.popular, pages: 1)),
      Row(id: "\(service.id).new", title: "New on \(name)", requests: both(.newest, pages: 1)),
      Row(id: "\(service.id).shows", title: "Shows", requests: (1...3).map { DiscoverRequest(.tv, .popular, page: $0) }),
      Row(id: "\(service.id).movies", title: "Movies", requests: (1...3).map { DiscoverRequest(.movie, .popular, page: $0) }),
      Row(id: "\(service.id).top", title: "Top Rated", requests: both(.topRated, pages: 1)),
    ]
    rows += genres.map { genre in
      Row(id: "\(service.id).\(genre.id)", title: genre.title, requests: both(.popular, pages: 1, genre: (genre.movie, genre.tv)))
    }
    return rows
  }

  /// One row's results in page order; where a page was asked for both TV
  /// and movies, the two alternate. Each title once.
  public static func merge(_ results: [(request: DiscoverRequest, items: [TMDBItem])]) -> [TMDBItem] {
    var out: [TMDBItem] = []
    var seen = Set<String>()
    let pages = Set(results.map(\.request.page)).sorted()
    for page in pages {
      let lists = results.filter { $0.request.page == page }.map(\.items)
      let longest = lists.map(\.count).max() ?? 0
      for n in 0..<longest {
        for list in lists where n < list.count && seen.insert(list[n].id).inserted {
          out.append(list[n])
        }
      }
    }
    return out
  }
}
