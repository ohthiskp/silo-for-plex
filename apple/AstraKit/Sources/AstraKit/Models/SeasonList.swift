import Foundation

/// A show's seasons as Details lists them (KP, 2026-11-16): Specials (season 0)
/// stay hidden unless Settings → Library → Show Specials is on.
public enum SeasonList {
  /// Plex's Specials season is season 0.
  public static func isSpecials(_ season: PlexMetadata) -> Bool {
    season.type == .season && season.index == 0
  }

  /// `seasons` without Specials, unless `showSpecials` is on or `keeping` names
  /// the Specials season (an episode from it was opened, e.g. from Continue Watching).
  public static func visible(_ seasons: [PlexMetadata], showSpecials: Bool, keeping key: String? = nil) -> [PlexMetadata] {
    if showSpecials { return seasons }
    return seasons.filter { !isSpecials($0) || ($0.ratingKey == key && key != nil) }
  }
}
