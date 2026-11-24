import Foundation

/// An intro or credits marker that Plex Media Server detected in a file
/// (`Marker` on `/library/metadata/<id>?includeMarkers=1`). Offsets are in ms.
public struct PlexMarker: Decodable, Sendable, Hashable {
  public enum Kind: String, Sendable { case intro, credits }

  public var kind: Kind
  public var start: Double
  public var end: Double
  /// Plex marks the credits that run to the end of the file as `final`.
  public var isFinal: Bool

  public init(kind: Kind, start: Double, end: Double, isFinal: Bool = false) {
    self.kind = kind
    self.start = start
    self.end = end
    self.isFinal = isFinal
  }

  enum CodingKeys: String, CodingKey { case type, startTimeOffset, endTimeOffset, final }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let type = try c.decodeLenientString(.type) ?? ""
    guard let kind = Kind(rawValue: type.lowercased()) else {
      throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Not an intro or credits marker")
    }
    self.kind = kind
    start = Double(try c.decodeLenientInt(.startTimeOffset) ?? 0) / 1000
    end = Double(try c.decodeLenientInt(.endTimeOffset) ?? 0) / 1000
    isFinal = try c.decodeLenientBool(.final) ?? false
  }
}

/// The skip button the player shows at a given moment (KP, 2026-11-24).
public enum SkipPrompt: Equatable, Sendable {
  /// "Skip Intro": jumps to the end of the intro.
  case intro(to: Double)
  /// "Skip Credits": jumps to the end of the credits (a movie, or an episode with no next one).
  case credits(to: Double)
  /// "Next Episode": tap-only, never plays on its own. Shown from the start of
  /// an episode's final credits, or in its last `nextEpisodeLead` seconds.
  case nextEpisode

  /// Which prompt shows at `position`. `hasNext` is true when there is a next
  /// episode and Settings → Playback → Next Episode is on.
  public static func at(
    _ position: Double, duration: Double, markers: [PlexMarker], hasNext: Bool, nextEpisodeLead: Double = 15
  ) -> SkipPrompt? {
    guard duration > 0, position >= 0 else { return nil }
    let left = duration - position
    if hasNext, left > 0, left <= nextEpisodeLead { return .nextEpisode }
    // Not in the last second of a marker, so the button doesn't flash up as it ends.
    guard let marker = markers.first(where: { $0.end - $0.start > 1 && position >= $0.start && position < $0.end - 1 })
    else { return nil }
    switch marker.kind {
    case .intro:
      return .intro(to: marker.end)
    case .credits:
      // Credits mid-episode (with a scene after) skip to that scene instead.
      let runsToEnd = marker.isFinal || marker.end >= duration - 2
      if hasNext, runsToEnd { return .nextEpisode }
      return .credits(to: min(marker.end, duration))
    }
  }
}

struct MarkersBody: Decodable {
  struct Item: Decodable {
    var markers: [PlexMarker]
    enum CodingKeys: String, CodingKey { case Marker }
    init(from decoder: Decoder) throws {
      let c = try decoder.container(keyedBy: CodingKeys.self)
      // One unknown marker type (Plex also has "commercial") never drops the rest.
      markers = (try? c.decode([Lossy].self, forKey: .Marker))?.compactMap(\.marker) ?? []
    }
  }
  struct Lossy: Decodable {
    var marker: PlexMarker?
    init(from decoder: Decoder) throws { marker = try? PlexMarker(from: decoder) }
  }
  var Metadata: [Item]?
}

extension SkipPrompt {
  public var title: String {
    switch self {
    case .intro: "Skip Intro"
    case .credits: "Skip Credits"
    case .nextEpisode: "Next Episode"
    }
  }

  /// SF Symbol after the title.
  public var symbol: String {
    switch self {
    case .intro, .credits: "forward.fill"
    case .nextEpisode: "forward.end.fill"
    }
  }
}
