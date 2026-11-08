import Foundation

/// Matching a TMDB title to the server's copy (KP, 2026-11-08: "it says
/// Project Hail Mary is not on the Plex server; it's there"). The library
/// index is keyed by TMDB id, but a Plex item can lack a TMDB guid (matched
/// by IMDb only, or not matched) or carry a different TMDB id. Then the
/// title and year find it: `alias:` keys added in memory point at the same
/// items, and items with no TMDB id are indexed under `title:`.
public enum LibraryMatch {
  public static let aliasPrefix = "alias:"
  public static let titlePrefix = "title:"

  /// "movie:projecthailmary:2026": kind, letters and digits only (a leading
  /// "the" and accents dropped), year. Nil without a title.
  public static func titleKey(kind: String, title: String, year: Int?) -> String? {
    var folded = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
      .replacingOccurrences(of: "&", with: "and")
    if folded.hasPrefix("the ") { folded.removeFirst(4) }
    let letters = String(folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    guard !letters.isEmpty else { return nil }
    return "\(kind):\(letters):\(year.map(String.init) ?? "")"
  }

  /// The index with an `alias:` key for every title, so `match` finds titles
  /// whose TMDB id is missing or different. The first item per key wins.
  public static func withAliases(_ index: [String: PlexMetadata]) -> [String: PlexMetadata] {
    var out = index
    for (key, item) in index.sorted(by: { $0.key < $1.key }) where !key.hasPrefix(aliasPrefix) {
      guard let title = item.titleMatchKey else { continue }
      if out[aliasPrefix + title] == nil { out[aliasPrefix + title] = item }
    }
    return out
  }
}

extension PlexMetadata {
  /// See `LibraryMatch.titleKey`; nil for anything but movies and shows.
  public var titleMatchKey: String? {
    switch type {
    case .movie: LibraryMatch.titleKey(kind: "movie", title: title, year: year)
    case .show: LibraryMatch.titleKey(kind: "tv", title: title, year: year)
    default: nil
    }
  }
}

extension TMDBItem {
  public var titleMatchKey: String? {
    LibraryMatch.titleKey(kind: kind == .movie ? "movie" : "tv", title: title, year: year)
  }
}

extension Dictionary where Key == String, Value == PlexMetadata {
  /// The server's copy of a TMDB title: by TMDB id, else by title and year
  /// (a year either side too, release dates differ by region).
  public func match(_ item: TMDBItem) -> PlexMetadata? {
    if let byID = self[item.id] { return byID }
    return matchTitle(kind: item.kind == .movie ? "movie" : "tv", title: item.title, year: item.year)
  }

  /// The same for a catalog-only (`tmdb:`) item.
  public func match(_ item: PlexMetadata) -> PlexMetadata? {
    if let key = item.tmdbKey, let byID = self[key] { return byID }
    switch item.type {
    case .movie: return matchTitle(kind: "movie", title: item.title, year: item.year)
    case .show: return matchTitle(kind: "tv", title: item.title, year: item.year)
    default: return nil
    }
  }

  private func matchTitle(kind: String, title: String, year: Int?) -> PlexMetadata? {
    let years: [Int?] = year.map { [$0, $0 - 1, $0 + 1] } ?? [nil]
    for y in years {
      guard let key = LibraryMatch.titleKey(kind: kind, title: title, year: y) else { return nil }
      if let hit = self[LibraryMatch.aliasPrefix + key] ?? self[LibraryMatch.titlePrefix + key] { return hit }
    }
    return nil
  }

  /// The library's titles, without the in-memory `alias:` entries.
  public var libraryItems: [PlexMetadata] {
    compactMap { $0.key.hasPrefix(LibraryMatch.aliasPrefix) ? nil : $0.value }
  }
}
