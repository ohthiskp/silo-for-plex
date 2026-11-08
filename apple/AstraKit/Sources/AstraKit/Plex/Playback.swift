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

/// Settings → Playback → Preferred Quality. Saved per device, default Auto.
///
/// It only chooses between original files the server already has. Astra
/// never transcodes, re-encodes or downscales: every choice plays an original
/// file as it is.
public enum PlaybackQuality: String, CaseIterable, Sendable, Identifiable {
  case auto
  case hd
  case uhd

  public static let storageKey = "astra.playback.preferredQuality"

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .auto: "Auto"
    case .hd: "HD"
    case .uhd: "4K"
    }
  }

  /// The saved choice, or Auto when nothing (or something unknown) is saved.
  public static func stored(in defaults: UserDefaults = .standard) -> PlaybackQuality {
    defaults.string(forKey: storageKey).flatMap(PlaybackQuality.init(rawValue:)) ?? .auto
  }

  public func save(in defaults: UserDefaults = .standard) {
    defaults.set(rawValue, forKey: Self.storageKey)
  }
}

/// Video resolution tiers (480, 576, 720, 1080, 1440, 2160, 4320).
public enum VideoTier {
  static let tiers = [480, 576, 720, 1080, 1440, 2160, 4320]

  /// The tier for a frame size: max(height, width × 9/16), snapped down to a
  /// tier with 4% slack. Width counts, so wide films keep their tier:
  /// 1920×800 is 1080, 3840×1600 is 2160. Same rule as the Flutter app
  /// (docs/playback-quality.md).
  public static func tier(width: Int?, height: Int?) -> Int? {
    let lines = max(Double(height ?? 0), (Double(width ?? 0) * 9 / 16).rounded())
    guard lines > 0 else { return nil }
    return tiers.last { Double($0) * 0.96 <= lines } ?? tiers[0]
  }

  /// "4K UHD" for 2160 and up, "HD" for 720 to 1440, nothing below.
  public static func badge(for tier: Int?) -> String? {
    guard let tier else { return nil }
    if tier >= 2160 { return "4K UHD" }
    if tier >= 720 { return "HD" }
    return nil
  }
}

extension PlexMedia {
  /// The tier from the version's size, or from Plex's `videoResolution` when the size is missing.
  public var tier: Int? {
    if let tier = VideoTier.tier(width: width, height: height) { return tier }
    switch videoResolution?.lowercased() {
    case "4k": return 2160
    case "1080": return 1080
    case "720": return 720
    case "576": return 576
    case "480", "sd": return 480
    default: return nil
    }
  }
}

public enum PlaybackResolver {
  /// The tallest tier each preference aims for. Auto has no ceiling.
  static func ceiling(_ quality: PlaybackQuality) -> Int {
    switch quality {
    case .auto: Int.max
    case .hd: 1080
    case .uhd: 2160
    }
  }

  /// Chooses which existing original file to play. Nothing is ever converted.
  ///
  /// Among the versions at or under the preference's ceiling (none for Auto,
  /// 1080 for HD, 2160 for 4K) it takes the tallest tier, then the higher
  /// bitrate, then the earlier version. If every version is above the
  /// ceiling (HD with only 4K files) it plays the lowest one as it is. So 4K
  /// with no 4K file plays the best file there is, and a single file always
  /// plays. mpv decodes every Plex video codec (VideoToolbox in hardware
  /// where the chip supports it), so no version is dropped as incompatible.
  public static func preferredMedia(_ media: [PlexMedia], quality: PlaybackQuality = .auto) -> PlexMedia? {
    let playable = media.filter { $0.parts.first?.key != nil }
    guard playable.count > 1 else { return playable.first }
    let limit = ceiling(quality)
    let fits = playable.filter { ($0.tier ?? 0) <= limit }
    if !fits.isEmpty {
      // max(by:) and min(by:) keep the first of equal elements: the earlier version wins a tie.
      return fits.max { ($0.tier ?? 0, $0.bitrate ?? 0) < ($1.tier ?? 0, $1.bitrate ?? 0) }
    }
    return playable.min { ($0.tier ?? 0) < ($1.tier ?? 0) }
  }

  /// The original file is streamed as it is; Astra never asks Plex to transcode.
  public static func directPlay(
    _ item: PlexMetadata, client: PlexServerClient, quality: PlaybackQuality = .auto, resume: Bool = true
  ) throws -> PlaybackSource {
    guard let media = preferredMedia(item.media, quality: quality), let part = media.parts.first, let key = part.key else {
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
public struct TimelineReport: Sendable, Equatable, Codable {
  public enum State: String, Sendable, Codable { case playing, paused, stopped, buffering }

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

/// QA P2-6: progress watched while the server couldn't be reached (offline,
/// asleep, a download on a plane). The last stopped report per title and
/// server is kept, on disk, until the server answers again.
public struct PendingTimelines: Codable, Sendable, Equatable {
  public struct Entry: Codable, Sendable, Equatable {
    public var server: String
    public var report: TimelineReport
  }

  public private(set) var entries: [Entry] = []

  public init() {}

  /// Keeps `report` as the one to send for its title on `server`, replacing an older one.
  public mutating func record(_ report: TimelineReport, server: String) {
    var report = report
    report.state = .stopped
    entries.removeAll { $0.server == server && $0.report.ratingKey == report.ratingKey }
    entries.append(Entry(server: server, report: report))
  }

  /// A newer report for the title reached the server: the kept one is out of date.
  public mutating func superseded(ratingKey: String, server: String) {
    entries.removeAll { $0.server == server && $0.report.ratingKey == ratingKey }
  }

  /// The kept reports for `server`, oldest first.
  public func reports(for server: String) -> [TimelineReport] {
    entries.filter { $0.server == server }.map(\.report)
  }

  public var isEmpty: Bool { entries.isEmpty }

  public static let defaultsKey = "astra.playback.pendingTimelines"

  public static func load(from defaults: UserDefaults = .standard) -> PendingTimelines {
    guard let data = defaults.data(forKey: defaultsKey),
      let saved = try? JSONDecoder().decode(PendingTimelines.self, from: data)
    else { return PendingTimelines() }
    return saved
  }

  public func save(to defaults: UserDefaults = .standard) {
    if entries.isEmpty {
      defaults.removeObject(forKey: Self.defaultsKey)
    } else if let data = try? JSONEncoder().encode(self) {
      defaults.set(data, forKey: Self.defaultsKey)
    }
  }
}
