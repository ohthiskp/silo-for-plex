import Foundation

/// Search's filter chips (KP, 2026-11-09): 4K, HD, Dolby Atmos, Dolby Vision
/// and Bollywood. With chips on, results keep only titles that pass every
/// chip. Formats need the server's copy (a title not on Plex has none), so
/// they only ever keep titles you can play.
public enum SearchFilter: String, CaseIterable, Identifiable, Sendable {
  case fourK, hd, atmos, dolbyVision, bollywood

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .fourK: "4K"
    case .hd: "HD"
    case .atmos: "Dolby Atmos"
    case .dolbyVision: "Dolby Vision"
    case .bollywood: "Bollywood"
    }
  }

  /// Whether the filter needs the title's audio and video tracks, which Plex
  /// sends with full details but not in lists or search.
  public var needsStreams: Bool { self == .atmos || self == .dolbyVision }

  /// Whether `item` passes. Nil when it can't tell yet: Atmos and Dolby
  /// Vision for a server title whose tracks haven't been read.
  /// `language` is TMDB's original language ("hi" for Bollywood).
  public func matches(_ item: PlexMetadata, language: String?) -> Bool? {
    switch self {
    case .bollywood:
      return language == "hi"
    case .fourK:
      return item.media.contains { VideoTier.badge(for: $0.tier) == "4K UHD" }
    case .hd:
      return item.media.contains { VideoTier.badge(for: $0.tier) == "HD" }
    case .atmos, .dolbyVision:
      guard !item.media.isEmpty else { return false }
      let streams = item.media.flatMap(\.parts).flatMap(\.streams)
      guard !streams.isEmpty else { return nil }
      return self == .atmos
        ? item.media.contains(where: \.hasAtmos)
        : item.media.contains { $0.dynamicRange == .dolbyVision }
    }
  }

  /// Every filter in `filters` at once: false as soon as one fails, nil when
  /// none fails but one can't tell yet.
  public static func matches(_ item: PlexMetadata, language: String?, all filters: Set<SearchFilter>) -> Bool? {
    var unknown = false
    for filter in filters {
      switch filter.matches(item, language: language) {
      case false?: return false
      case nil: unknown = true
      case true?: break
      }
    }
    return unknown ? nil : true
  }
}
