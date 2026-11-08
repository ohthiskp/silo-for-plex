import Foundation

/// Astra 4.0 (KP, 2026-11-08: "Watchlist takes too long to load"): the Plex
/// Watchlist saved on the device, so the page shows at once and refreshes
/// behind. One file per signed-in account isn't needed: it is cleared on sign-out.
public struct WatchlistSnapshot: Codable, Sendable {
  public var savedAt: Date
  public var items: [PlexMetadata]

  public init(savedAt: Date, items: [PlexMetadata]) {
    self.savedAt = savedAt
    self.items = items
  }

  public static func load(from url: URL) -> WatchlistSnapshot? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(WatchlistSnapshot.self, from: data)
  }

  public func save(to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONEncoder().encode(self).write(to: url, options: .atomic)
  }
}

public enum WatchlistMatch {
  /// Each Watchlist title as the server's copy when the library index has it
  /// (so Play works), else as a TMDB-only title (`tmdb:` key, Play greyed).
  /// Titles without a TMDB id are dropped; each title appears once.
  public static func match(_ items: [PlexMetadata], index: [String: PlexMetadata]) -> [PlexMetadata] {
    var seen = Set<String>()
    return items.compactMap { item in
      guard let key = item.tmdbKey, seen.insert(key).inserted else { return nil }
      if let onServer = index[key] { return onServer }
      var catalog = item
      catalog.ratingKey = "tmdb:\(key)"
      return catalog
    }
  }

  /// The list after the + / ✓ button: added at the front, or taken off.
  public static func toggled(_ items: [PlexMetadata], _ item: PlexMetadata, adding: Bool) -> [PlexMetadata] {
    guard let key = item.tmdbKey else { return items }
    let rest = items.filter { $0.tmdbKey != key }
    return adding ? [item] + rest : rest
  }
}
