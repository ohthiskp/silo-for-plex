import Foundation

/// What the player needs to open an item: the stream URL, the headers that
/// authenticate it, and where to resume.
///
/// The token travels in a header, not the URL, so it never shows up in mpv's
/// logs or in a URL someone copies out of the player.
public struct PlaybackSource: Sendable, Equatable {
  public var url: URL
  public var headers: [String: String]
  public var startSeconds: Double
  public var ratingKey: String
  public var metadataKey: String
  public var durationMs: Int
  public var title: String
  public var subtitle: String?
  public var media: PlexMedia
  public var part: PlexPart
}

public enum PlaybackResolver {
  /// Chooses the media version to play: the highest resolution the Mac can
  /// decode (mpv with VideoToolbox decodes every Plex video codec except
  /// VC-1 in hardware, and the rest in software), so this keeps it simple
  /// and picks by size. The video-quality setting will refine this choice.
  public static func preferredMedia(_ media: [PlexMedia]) -> PlexMedia? {
    media
      .filter { !$0.parts.isEmpty && $0.parts.first?.key != nil }
      .max { ($0.width ?? 0, $0.bitrate ?? 0) < ($1.width ?? 0, $1.bitrate ?? 0) }
  }

  /// A direct-play source for `item` (a movie or an episode with full metadata).
  /// - Parameter resume: start at the saved position when there is one.
  public static func directPlay(
    _ item: PlexMetadata, client: PlexServerClient, resume: Bool = true
  ) throws -> PlaybackSource {
    guard let media = preferredMedia(item.media), let part = media.parts.first, let key = part.key else {
      throw PlexError.nothingToPlay
    }
    let url = client.baseURL.appending(plexPath: key)
    let offset = resume ? Double(item.viewOffset ?? 0) / 1000 : 0
    var headers = [
      "X-Plex-Token": client.token,
      "X-Plex-Client-Identifier": client.info.clientIdentifier,
      "X-Plex-Product": client.info.product,
    ]
    headers["X-Plex-Platform"] = client.info.platform
    return PlaybackSource(
      url: url,
      headers: headers,
      // Plex keeps a position in the last few seconds of a watched item; start over instead.
      startSeconds: offset > 0 && Double(item.duration ?? 0) / 1000 - offset > 30 ? offset : 0,
      ratingKey: item.ratingKey,
      metadataKey: item.key ?? "/library/metadata/\(item.ratingKey)",
      durationMs: item.duration ?? part.duration ?? media.duration ?? 0,
      title: item.displayTitle,
      subtitle: item.type == .episode ? [item.episodeLabel, item.title].compactMap { $0 }.joined(separator: "  ") : nil,
      media: media,
      part: part
    )
  }

  /// mpv's `http-header-fields` value. Header values never contain commas here
  /// (tokens and identifiers are alphanumeric), which mpv would split on.
  public static func mpvHeaderFields(_ headers: [String: String]) -> String {
    headers.sorted { $0.key < $1.key }
      .map { "\($0.key): \($0.value.replacingOccurrences(of: ",", with: ""))" }
      .joined(separator: ",")
  }
}

/// One `/:/timeline` report.
public struct TimelineReport: Sendable, Equatable {
  public enum State: String, Sendable { case playing, paused, stopped, buffering }

  public var ratingKey: String
  public var key: String
  public var state: State
  public var timeMs: Int
  public var durationMs: Int

  public init(ratingKey: String, key: String, state: State, timeMs: Int, durationMs: Int) {
    self.ratingKey = ratingKey
    self.key = key
    self.state = state
    self.timeMs = timeMs
    self.durationMs = durationMs
  }

  var queryItems: [URLQueryItem] {
    [
      .init(name: "ratingKey", value: ratingKey),
      .init(name: "key", value: key),
      .init(name: "state", value: state.rawValue),
      .init(name: "time", value: String(max(0, timeMs))),
      .init(name: "duration", value: String(max(0, durationMs))),
      .init(name: "hasMDE", value: "1"),
    ]
  }
}
