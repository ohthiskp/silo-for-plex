import Foundation

/// Astra (KP, 2026-11-07): the For You rows built from the user's own library.
/// After the hero, Continue Watching and the Top 10 come Recommended For You,
/// Because You Watched… and Hidden Gems. Each title shows once on the page:
/// callers pass what is already shown as `exclude` (rating keys and TMDB keys).
public enum ForYou {
  /// Never started: a movie with no plays and no progress, a show with no episode watched.
  public static func isUnwatched(_ item: PlexMetadata) -> Bool {
    switch item.type {
    case .show: (item.viewedLeafCount ?? 0) == 0
    default: (item.viewCount ?? 0) == 0 && (item.viewOffset ?? 0) == 0
    }
  }

  /// Watched at least once (a show: at least one episode).
  public static func isWatched(_ item: PlexMetadata) -> Bool {
    switch item.type {
    case .show: (item.viewedLeafCount ?? 0) > 0
    default: (item.viewCount ?? 0) > 0
    }
  }

  /// The keys that identify a title for de-duplication.
  public static func keys(_ item: PlexMetadata) -> [String] {
    [item.ratingKey, item.grandparentRatingKey, item.tmdbKey].compactMap { $0 }
  }

  static func isExcluded(_ item: PlexMetadata, _ exclude: Set<String>) -> Bool {
    keys(item).contains(where: exclude.contains)
  }

  /// How much the user likes each genre: every watched title adds to its
  /// genres, recent ones (and ones rated highly by the user) more.
  public static func genreTaste(_ library: [PlexMetadata]) -> [String: Double] {
    let watched = library.filter(isWatched).sorted { ($0.lastViewedAt ?? 0) > ($1.lastViewedAt ?? 0) }
    var taste: [String: Double] = [:]
    for (rank, item) in watched.enumerated() {
      // The 20 most recent count fully, older ones fade to a quarter.
      let recency = rank < 20 ? 1.0 : 0.25
      // The user's own star rating (Plex `rating` on a 0–10 scale) when there is one.
      let liked = item.rating.map { $0 >= 7 ? 1.5 : ($0 <= 4 ? 0.3 : 1) } ?? 1
      for genre in item.genres { taste[genre.tag, default: 0] += recency * liked }
    }
    let top = taste.values.max() ?? 1
    return taste.mapValues { $0 / max(top, 1) }
  }

  /// Unwatched titles scored by the user's favourite genres and their
  /// audience rating, movies and series alternating.
  public static func recommended(
    library: [PlexMetadata], exclude: Set<String>, limit: Int = 20
  ) -> [PlexMetadata] {
    let taste = genreTaste(library)
    func score(_ item: PlexMetadata) -> Double {
      let genres = item.genres.map { taste[$0.tag] ?? 0 }
      let genreScore = genres.isEmpty ? 0 : genres.reduce(0, +) / Double(genres.count) + (genres.max() ?? 0)
      let rating = (item.audienceRating ?? 6) / 10
      return genreScore * 2 + rating
    }
    let pool = unique(library.filter { isUnwatched($0) && !isExcluded($0, exclude) })
      .map { ($0, score($0)) }
      .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.title < $1.0.title }
      .map(\.0)
    return interleave(pool, limit: limit)
  }

  /// Well-reviewed titles nobody has started that aren't trending
  /// (`popular` is the trending titles' TMDB keys), best rated first.
  public static func hiddenGems(
    library: [PlexMetadata], exclude: Set<String>, popular: Set<String>, minimumRating: Double = 7.2,
    limit: Int = 20
  ) -> [PlexMetadata] {
    let pool = unique(
      library.filter { item in
        guard isUnwatched(item), !isExcluded(item, exclude), let rating = item.audienceRating,
          rating >= minimumRating
        else { return false }
        return item.tmdbKey.map { !popular.contains($0) } ?? true
      }
    )
    .sorted { ($0.audienceRating ?? 0, $1.title) > ($1.audienceRating ?? 0, $0.title) }
    return interleave(pool, limit: limit)
  }

  /// The title for "Because You Watched…": the movie or show watched most
  /// recently, from the library or (for a show) Continue Watching's episodes.
  public static func becauseSeed(library: [PlexMetadata], continueWatching: [PlexMetadata]) -> PlexMetadata? {
    let byKey = Dictionary(library.map { ($0.ratingKey, $0) }, uniquingKeysWith: { a, _ in a })
    var candidates = library.filter { isWatched($0) && $0.lastViewedAt != nil }
    for item in continueWatching {
      if let show = item.grandparentRatingKey.flatMap({ byKey[$0] }) {
        var show = show
        show.lastViewedAt = max(show.lastViewedAt ?? 0, item.lastViewedAt ?? 0)
        candidates.append(show)
      } else if let movie = byKey[item.ratingKey] {
        candidates.append(movie)
      }
    }
    return candidates.max { ($0.lastViewedAt ?? 0) < ($1.lastViewedAt ?? 0) }
  }

  /// One copy per title (two libraries can hold the same TMDB title).
  static func unique(_ items: [PlexMetadata]) -> [PlexMetadata] {
    var seen = Set<String>()
    return items.filter { seen.insert($0.tmdbKey ?? $0.ratingKey).inserted }
  }

  /// Movies and series alternating, each list keeping its order.
  static func interleave(_ items: [PlexMetadata], limit: Int) -> [PlexMetadata] {
    var movies = items.filter { $0.type != .show }[...]
    var shows = items.filter { $0.type == .show }[...]
    var out: [PlexMetadata] = []
    while out.count < limit, !(movies.isEmpty && shows.isEmpty) {
      if let m = movies.popFirst() { out.append(m) }
      if out.count < limit, let s = shows.popFirst() { out.append(s) }
    }
    return out
  }
}

/// Astra: instant title search over the library index on the device.
public enum LocalSearch {
  /// Titles matching `text` (case- and accent-insensitive): those starting
  /// with it first, then those with a word starting with it, then any that
  /// contain it; ties by title.
  public static func rank(_ items: [PlexMetadata], text: String, limit: Int = 30) -> [PlexMetadata] {
    let needle = fold(text)
    guard !needle.isEmpty else { return [] }
    var scored: [(Int, PlexMetadata)] = []
    for item in items {
      let title = fold(item.title)
      let score: Int
      if title.hasPrefix(needle) {
        score = 0
      } else if title.contains(" " + needle) {
        score = 1
      } else if title.contains(needle) {
        score = 2
      } else {
        continue
      }
      scored.append((score, item))
    }
    return scored.sorted { ($0.0, $0.1.title) < ($1.0, $1.1.title) }.prefix(limit).map(\.1)
  }

  static func fold(_ text: String) -> String {
    text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
      .replacingOccurrences(of: ":", with: "")
      .trimmingCharacters(in: .whitespaces)
  }
}
