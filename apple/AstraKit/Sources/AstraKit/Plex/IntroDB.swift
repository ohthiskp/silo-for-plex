import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Community intro and end-credits times from IntroDB (introdb.app), used when
/// Plex has no markers for an item (KP, 2026-11-24: Skip Intro didn't show on
/// Entourage). Reads need no key or account. Keyed by IMDb id, plus season and
/// episode for TV (the show's IMDb id, not the episode's).
public struct IntroDBClient: Sendable {
  public static let baseURL = URL(string: "https://api.introdb.app")!
  let transport: HTTPTransport

  public init(transport: HTTPTransport = URLSessionTransport()) {
    self.transport = transport
  }

  /// The intro and end credits for an episode (season and episode set) or a
  /// movie (both nil). Empty when nobody has timed them.
  public func markers(imdbID: String, season: Int?, episode: Int?) async throws -> [PlexMarker] {
    var components = URLComponents(url: Self.baseURL.appendingPathComponent("segments"), resolvingAgainstBaseURL: false)!
    var query = [URLQueryItem(name: "imdb_id", value: imdbID)]
    if let season, let episode {
      query += [.init(name: "season", value: String(season)), .init(name: "episode", value: String(episode))]
    } else {
      query.append(.init(name: "is_movie", value: "true"))
    }
    components.queryItems = query
    var request = URLRequest(url: components.url!)
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.timeoutInterval = 10
    let (data, response) = try await transport.send(request)
    guard (200..<300).contains(response.statusCode) else { throw PlexError.http(response.statusCode) }
    let body = try JSONDecoder().decode(Segments.self, from: data)
    var markers: [PlexMarker] = []
    if let intro = body.intro, intro.end_sec > intro.start_sec {
      markers.append(PlexMarker(kind: .intro, start: intro.start_sec, end: intro.end_sec))
    }
    if let outro = body.outro, outro.end_sec > outro.start_sec {
      // A scene after the credits means they don't run to the end of the file.
      markers.append(PlexMarker(kind: .credits, start: outro.start_sec, end: outro.end_sec, isFinal: body.post_credits == nil))
    }
    return markers
  }

  struct Segment: Decodable {
    var start_sec: Double
    var end_sec: Double
  }

  struct Segments: Decodable {
    var intro: Segment?
    var outro: Segment?
    var post_credits: Segment?
  }
}

extension PlexMetadata {
  /// The IMDb id among `guids` ("imdb://tt0387199" → "tt0387199").
  public var imdbID: String? {
    guids.lazy.map(\.id).first { $0.hasPrefix("imdb://") }.map { String($0.dropFirst("imdb://".count)) }
  }
}

extension PlexMarker {
  /// Plex's own markers first; IntroDB fills in an intro or credits Plex doesn't have.
  public static func merged(plex: [PlexMarker], introDB: [PlexMarker]) -> [PlexMarker] {
    let kinds = Set(plex.map(\.kind))
    return (plex + introDB.filter { !kinds.contains($0.kind) }).sorted { $0.start < $1.start }
  }
}
