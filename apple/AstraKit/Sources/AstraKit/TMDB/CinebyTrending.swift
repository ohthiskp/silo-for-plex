import Foundation

/// The "Trending on Cineby" list from cineby.tech's home page, as TMDB ids
/// in the site's order (KP chose this source for the For You hero and Top 10,
/// 2026-11-07). Only the public page's links are read; nothing is played
/// from the site. If the page can't be read or its layout changes, callers
/// fall back to TMDB's trending list.
public enum CinebyTrending {
  public static let pageURL = URL(string: "https://cineby.tech/")!

  public struct Entry: Sendable, Hashable {
    public var kind: TMDBItem.Kind
    public var tmdbID: Int
    /// The card's title and poster as the page shows them, when it does.
    public var title: String?
    public var posterPath: String?
    public var id: String { "\(kind.rawValue):\(tmdbID)" }

    public init(kind: TMDBItem.Kind, tmdbID: Int, title: String? = nil, posterPath: String? = nil) {
      self.kind = kind
      self.tmdbID = tmdbID
      self.title = title
      self.posterPath = posterPath
    }

    /// A card straight from the page (no backdrop), used until TMDB answers.
    public var item: TMDBItem? {
      guard let title, !title.isEmpty else { return nil }
      return TMDBItem(
        tmdbID: tmdbID, kind: kind, title: title, year: nil, overview: nil, rating: nil, posterPath: posterPath,
        backdropPath: nil)
    }
  }

  /// Each link's card: `<a href=".../movie/1/watch"><img src="https://image.tmdb.org/t/p/w185/x.jpg" alt="Title">`.
  private static let card = try! NSRegularExpression(
    pattern: #"href="[^"]*/(movie|tv)/([0-9]{1,9})/[^"]*"[^>]*>\s*<img[^>]*?src="https://image\.tmdb\.org/t/p/[a-z0-9]+(/[^"]+)"[^>]*?alt="([^"]*)""#)

  /// `/movie/123` and `/tv/456` links in page order, each title once.
  public static func parse(_ html: String) -> [Entry] {
    let pattern = try! NSRegularExpression(pattern: #"/(movie|tv)/([0-9]{1,9})(?=[/"'?#])"#)
    let range = NSRange(html.startIndex..., in: html)
    var seen = Set<String>()
    var out: [Entry] = []
    for match in pattern.matches(in: html, range: range) {
      guard let kindRange = Range(match.range(at: 1), in: html), let idRange = Range(match.range(at: 2), in: html),
        let kind = TMDBItem.Kind(rawValue: String(html[kindRange])), let id = Int(html[idRange])
      else { continue }
      let entry = Entry(kind: kind, tmdbID: id)
      if seen.insert(entry.id).inserted { out.append(entry) }
    }
    // Titles and posters where the page has them.
    var cards: [String: (title: String, poster: String)] = [:]
    for match in card.matches(in: html, range: range) {
      guard let k = Range(match.range(at: 1), in: html), let i = Range(match.range(at: 2), in: html),
        let p = Range(match.range(at: 3), in: html), let t = Range(match.range(at: 4), in: html)
      else { continue }
      cards["\(html[k]):\(html[i])"] = (decodeEntities(String(html[t])), String(html[p]))
    }
    return out.map { entry in
      var entry = entry
      if let card = cards[entry.id] {
        entry.title = card.title
        entry.posterPath = card.poster
      }
      return entry
    }
  }

  static func decodeEntities(_ text: String) -> String {
    text.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&#39;", with: "'")
      .replacingOccurrences(of: "&#x27;", with: "'").replacingOccurrences(of: "&quot;", with: "\"")
      .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
  }

  /// Reads the page. Throws on a network error or a non-200 answer.
  public static func fetch(transport: HTTPTransport = URLSessionTransport()) async throws -> [Entry] {
    parse(try await fetchHTML(transport: transport))
  }

  /// The page's rows by their headings ("Trending", "Top Rated"…), each with
  /// its titles in order. Links before the first heading are left out.
  public static func sections(_ html: String) -> [(title: String, entries: [Entry])] {
    let heading = try! NSRegularExpression(
      pattern: #"<h[1-6][^>]*>(.*?)</h[1-6]>"#, options: [.dotMatchesLineSeparators, .caseInsensitive])
    let tags = try! NSRegularExpression(pattern: #"<[^>]+>"#)
    let full = NSRange(html.startIndex..., in: html)
    let matches = heading.matches(in: html, range: full)
    var out: [(String, [Entry])] = []
    for (i, match) in matches.enumerated() {
      guard let inner = Range(match.range(at: 1), in: html) else { continue }
      let raw = String(html[inner])
      let title = decodeEntities(
        tags.stringByReplacingMatches(in: raw, range: NSRange(raw.startIndex..., in: raw), withTemplate: "")
      ).trimmingCharacters(in: .whitespacesAndNewlines)
      let start = match.range.location + match.range.length
      let end = i + 1 < matches.count ? matches[i + 1].range.location : full.length
      guard !title.isEmpty, end > start, let body = Range(NSRange(location: start, length: end - start), in: html)
      else { continue }
      let entries = parse(String(html[body]))
      if !entries.isEmpty { out.append((title, entries)) }
    }
    return out
  }

  /// The first row whose heading contains one of `keywords` (any case).
  /// A streaming service's own row ("New on Netflix", "Best of Prime Video")
  /// is never For You's: those titles belong to that service's tab.
  public static func section(_ sections: [(title: String, entries: [Entry])], matching keywords: [String]) -> [Entry]? {
    sections.first { section in
      let title = section.title.lowercased()
      guard !serviceWords.contains(where: { title.contains($0) }) else { return false }
      return keywords.contains { title.contains($0) }
    }?.entries
  }

  /// Words that mark a heading as one streaming service's row.
  static let serviceWords = [
    "netflix", "prime video", "amazon", "disney", "hbo", "max original", "hulu", "apple tv", "paramount", "peacock",
    "crunchyroll",
  ]

  /// Headings that mean Recently Released, and All-Time Greats.
  public static let recentKeywords = ["recent", "new release", "latest", "just released", "now playing", "in theater", "new movies", "new shows"]
  public static let greatsKeywords = ["top rated", "top-rated", "all-time", "all time", "greatest", "best of", "classic", "acclaimed", "highest rated"]

  public static func fetchHTML(transport: HTTPTransport = URLSessionTransport()) async throws -> String {
    var request = URLRequest(url: pageURL)
    request.timeoutInterval = 8
    // The page is served to browsers; a plain client gets a challenge page.
    request.setValue(
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
      forHTTPHeaderField: "User-Agent")
    request.setValue("text/html", forHTTPHeaderField: "Accept")
    let (data, response) = try await transport.send(request)
    guard response.statusCode == 200 else { throw PlexError.http(response.statusCode) }
    return String(decoding: data, as: UTF8.self)
  }

  /// Cineby's titles first, then `fill` (TMDB trending) for anything it
  /// doesn't list, each title once.
  public static func merge(_ cineby: [TMDBItem], fill: [TMDBItem]) -> [TMDBItem] {
    var seen = Set<String>()
    return (cineby + fill).filter { seen.insert($0.id).inserted }
  }
}

/// The For You trending list saved on disk, so Home shows it the moment the
/// app opens; it's refreshed in the background. `details` keeps every TMDB
/// lookup, so later refreshes only fetch titles that are new on cineby.
public struct TrendingSnapshot: Codable, Sendable {
  public var savedAt: Date
  public var items: [TMDBItem]
  public var details: [String: TMDBItem]

  public init(savedAt: Date, items: [TMDBItem], details: [String: TMDBItem]) {
    self.savedAt = savedAt
    self.items = items
    self.details = details
  }

  public static func url(in folder: URL) -> URL { folder.appendingPathComponent("Trending.json") }

  public static func load(from url: URL) -> TrendingSnapshot? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(TrendingSnapshot.self, from: data)
  }

  public func save(to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONEncoder().encode(self).write(to: url, options: .atomic)
  }

  /// Newer than this, no refresh is needed at all.
  public static let freshFor: TimeInterval = 3600
  public func isFresh(now: Date = Date()) -> Bool { now.timeIntervalSince(savedAt) < Self.freshFor }

  /// Keeps the lookup cache from growing without end: the newest 300.
  public static func trimmed(_ details: [String: TMDBItem], keeping ids: [String]) -> [String: TMDBItem] {
    guard details.count > 300 else { return details }
    let keep = Set(ids)
    return details.filter { keep.contains($0.key) }
  }
}
