import Foundation

/// Astra (KP, 2026-11-07): continuous playback. Which episode follows the one
/// that just finished: the next in its season, else the first episode of the
/// next season (specials, season 0, are skipped).
public enum UpNext {
  /// The episode after `current` among its season's `episodes`, by index.
  public static func nextInSeason(after current: PlexMetadata, episodes: [PlexMetadata]) -> PlexMetadata? {
    let list = episodes.filter { $0.type == .episode }.sorted { ($0.index ?? 0) < ($1.index ?? 0) }
    if let i = list.firstIndex(where: { $0.ratingKey == current.ratingKey }) {
      return i + 1 < list.count ? list[i + 1] : nil
    }
    guard let index = current.index else { return nil }
    return list.first { ($0.index ?? 0) > index }
  }

  /// The season after `seasonIndex` among a show's `seasons` (season 0 never follows).
  public static func nextSeason(after seasonIndex: Int, seasons: [PlexMetadata]) -> PlexMetadata? {
    seasons
      .filter { $0.type == .season && ($0.index ?? 0) > max(seasonIndex, 0) }
      .min { ($0.index ?? 0) < ($1.index ?? 0) }
  }

  /// The first real episode of a season's `episodes`.
  public static func first(of episodes: [PlexMetadata]) -> PlexMetadata? {
    episodes.filter { $0.type == .episode }.min { ($0.index ?? 0) < ($1.index ?? 0) }
  }
}
