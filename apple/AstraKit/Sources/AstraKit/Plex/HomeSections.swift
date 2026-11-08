import Foundation

/// Astra 4.0 (KP, 2026-11-08): one Home layout for For You and every service:
/// Hero, Continue Watching, Top 10, Recently Released, All-Time Greats. The
/// last three each have Movies | Series. Everything listed is on the Plex server.
public struct HomeShelf: Sendable, Equatable {
  public var movies: [PlexMetadata]
  public var shows: [PlexMetadata]

  public init(movies: [PlexMetadata] = [], shows: [PlexMetadata] = []) {
    self.movies = movies
    self.shows = shows
  }

  public static let empty = HomeShelf()

  public var isEmpty: Bool { movies.isEmpty && shows.isEmpty }

  public func items(series: Bool) -> [PlexMetadata] { series ? shows : movies }
}

public enum HomeSections {
  /// Only titles on the server (no TMDB-only titles on Home), each once.
  public static func playable(_ items: [PlexMetadata]) -> [PlexMetadata] {
    var seen = Set<String>()
    return items.filter { !$0.isCatalogOnly && seen.insert($0.tmdbKey ?? $0.ratingKey).inserted }
  }

  /// Every title once, Plex or not (KP, 2026-11-08: "bring back cineby"):
  /// streaming pages list the service's whole popular catalogue.
  public static func unique(_ items: [PlexMetadata]) -> [PlexMetadata] {
    var seen = Set<String>()
    return items.filter { seen.insert($0.tmdbKey ?? $0.ratingKey).inserted }
  }

  /// A ranked TMDB list in its own order, each title once: the server's item
  /// when it has it (so it plays), else the TMDB title (Play greyed).
  public static func catalog(_ ranked: [TMDBItem], index: [String: PlexMetadata], limit: Int = 20) -> [PlexMetadata] {
    var seen = Set<String>()
    var out: [PlexMetadata] = []
    for item in ranked where out.count < limit {
      guard seen.insert(item.id).inserted else { continue }
      out.append(index.match(item) ?? item.asMetadata)
    }
    return out
  }

  /// A release date: Plex's `originallyAvailableAt` (a movie's release, a
  /// show's first air date), else 1 January of its year. Nil with neither.
  public static func releaseDate(_ item: PlexMetadata) -> Date? {
    if let text = item.originallyAvailableAt, let date = day.date(from: String(text.prefix(10))) { return date }
    guard let year = item.year else { return nil }
    return day.date(from: String(format: "%04d-01-01", year))
  }

  /// Recently Released: titles released in the last `windowDays` (by release
  /// or first-air date, never date added), newest first. With fewer than
  /// `minimum`, the window widens to three times as long. Titles with no
  /// date or a future date are left out.
  public static func recentlyReleased(
    _ items: [PlexMetadata], now: Date = Date(), windowDays: Int = 365, minimum: Int = 6, limit: Int = 20
  ) -> [PlexMetadata] {
    let dated = playable(items).compactMap { item in releaseDate(item).map { (item, $0) } }
      .filter { $0.1 <= now }
    func within(_ days: Int) -> [(PlexMetadata, Date)] {
      let start = now.addingTimeInterval(-Double(days) * 86_400)
      return dated.filter { $0.1 >= start }
    }
    var picked = within(windowDays)
    if picked.count < minimum { picked = within(windowDays * 3) }
    return picked
      .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.displayTitle < $1.0.displayTitle }
      .prefix(limit)
      .map(\.0)
  }

  /// A ranked TMDB list (trending, top rated, a service's newest) kept in
  /// its own order, but only the titles on the server (`index`), each once.
  public static func ranked(_ ranked: [TMDBItem], index: [String: PlexMetadata], limit: Int = 20) -> [PlexMetadata] {
    var seen = Set<String>()
    var out: [PlexMetadata] = []
    for item in ranked where out.count < limit {
      guard let match = index.match(item), seen.insert(item.id).inserted else { continue }
      out.append(match)
    }
    return out
  }

  /// All-Time Greats without TMDB: the library's best rated titles (audience
  /// rating, else critic rating, at least `minimumRating`), highest first;
  /// ties go to the older, more established title, then by name. Stable.
  public static func greatsFromLibrary(
    _ items: [PlexMetadata], minimumRating: Double = 7.5, limit: Int = 20
  ) -> [PlexMetadata] {
    playable(items)
      .compactMap { item in (item.audienceRating ?? item.rating).map { (item, $0) } }
      .filter { $0.1 >= minimumRating }
      .sorted { a, b in
        if a.1 != b.1 { return a.1 > b.1 }
        if (a.0.year ?? 0) != (b.0.year ?? 0) { return (a.0.year ?? 0) < (b.0.year ?? 0) }
        return a.0.displayTitle < b.0.displayTitle
      }
      .prefix(limit)
      .map(\.0)
  }

  /// Splits into Movies and Series.
  public static func shelf(_ items: [PlexMetadata]) -> HomeShelf {
    HomeShelf(movies: items.filter { $0.type == .movie }, shows: items.filter { $0.type == .show })
  }

  static let day: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(identifier: "UTC")
    f.dateFormat = "yyyy-MM-dd"
    return f
  }()
}
