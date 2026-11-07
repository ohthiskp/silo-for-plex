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

  public var providerFilter: String { providerIds.map(String.init).joined(separator: "|") }

  public static let all: [StreamingService] = [
    .init(id: "netflix", label: "Netflix", logo: "provider-netflix", providerIds: [8], logoHeight: 15),
    .init(id: "disney", label: "Disney+", logo: "provider-disney", providerIds: [337], logoHeight: 24),
    .init(id: "prime", label: "Prime Video", logo: "provider-prime", providerIds: [9], logoHeight: 20),
    .init(id: "appletv", label: "Apple TV+", logo: "provider-appletv", providerIds: [350], logoHeight: 17),
    .init(id: "max", label: "HBO Max", logo: "provider-max", providerIds: [1899], logoHeight: 22),
    .init(id: "hulu", label: "Hulu", logo: "provider-hulu", providerIds: [15], logoHeight: 15),
    .init(id: "paramount", label: "Paramount+", logo: "provider-paramount", providerIds: [531, 2303], logoHeight: 18),
    .init(id: "peacock", label: "Peacock", logo: "provider-peacock", providerIds: [386, 387], logoHeight: 17),
  ]

  public static func byID(_ id: String?) -> StreamingService? {
    all.first { $0.id == id }
  }
}

/// One TMDB search/discover result.
public struct TMDBItem: Sendable, Hashable, Identifiable {
  public enum Kind: String, Sendable { case movie, tv }

  public var tmdbID: Int
  public var kind: Kind
  public var title: String
  public var year: Int?
  public var overview: String?
  public var rating: Double?
  public var posterPath: String?
  public var backdropPath: String?

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

  /// Poster, backdrop and title logo for one title (English or text-free logo).
  public func artwork(id: Int, kind: TMDBItem.Kind) async throws -> TMDBArtwork {
    let data = try await get(
      "/\(kind.rawValue)/\(id)", ["append_to_response": "images", "include_image_language": "en,null"])
    let raw = try JSONDecoder().decode(ArtworkRaw.self, from: data)
    // Prefer PNG logos (transparent) over SVG, which the image pipeline can't decode.
    let logo = raw.images?.logos?.first { $0.file_path?.hasSuffix(".png") == true }?.file_path
    return TMDBArtwork(posterPath: raw.poster_path, backdropPath: raw.backdrop_path, logoPath: logo)
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
      struct Image: Decodable { var file_path: String? }
      var logos: [Image]?
    }
    var poster_path: String?
    var backdrop_path: String?
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

    func item(forcedKind: TMDBItem.Kind?) -> TMDBItem? {
      let kind = forcedKind ?? TMDBItem.Kind(rawValue: media_type ?? "")
      guard let kind, let id else { return nil }
      guard let title = (kind == .tv ? name : title), !title.isEmpty else { return nil }
      guard poster_path != nil || backdrop_path != nil else { return nil }
      let date = kind == .tv ? first_air_date : release_date
      return TMDBItem(
        tmdbID: id, kind: kind, title: title, year: date.flatMap { Int($0.prefix(4)) }, overview: overview,
        rating: (vote_average ?? 0) > 0 ? vote_average : nil, posterPath: poster_path, backdropPath: backdrop_path)
    }
  }
}
