import Foundation

/// The player's audio track names, "English · Dolby Atmos 7.1" (KP's player
/// mockups, 2026-11-10): the language, then the format and the channel layout.
public enum AudioTrackLabel {
  /// - Parameters:
  ///   - language: the track's language as shown to the viewer ("English").
  ///   - codec: mpv's codec name ("truehd", "eac3", "dts", "aac"…).
  ///   - channels: the channel count (mpv's `demux-channel-count`).
  ///   - profile: mpv's `codec-profile` ("Dolby TrueHD + Dolby Atmos", "DTS-HD MA").
  ///   - plexTitle: Plex's name for the stream ("English (TrueHD 7.1 Atmos)"),
  ///     which knows about Atmos when mpv's codec profile doesn't say.
  ///   - trackTitle: the title in the file ("Director's Commentary").
  public static func make(
    language: String?, codec: String?, channels: Int?, profile: String? = nil, plexTitle: String? = nil,
    trackTitle: String? = nil
  ) -> String {
    var parts: [String] = []
    if let language, !language.isEmpty { parts.append(language) }
    let format = [formatName(codec: codec, profile: profile, plexTitle: plexTitle), channelLayout(channels)]
      .compactMap { $0 }.joined(separator: " ")
    if !format.isEmpty { parts.append(format) }
    // A commentary or descriptive track keeps its own name at the end.
    if let trackTitle = trackTitle?.trimmingCharacters(in: .whitespaces), !trackTitle.isEmpty,
      !parts.contains(where: { trackTitle.localizedCaseInsensitiveContains($0) }),
      isDescriptive(trackTitle)
    {
      parts.append(trackTitle)
    }
    if parts.isEmpty { return trackTitle.flatMap { $0.isEmpty ? nil : $0 } ?? "Unknown" }
    return parts.joined(separator: " · ")
  }

  /// "Dolby Atmos", "Dolby TrueHD", "Dolby Digital Plus", "DTS-HD MA", "AAC"…
  static func formatName(codec: String?, profile: String?, plexTitle: String?) -> String? {
    let profile = profile?.lowercased() ?? ""
    let plex = plexTitle?.lowercased() ?? ""
    if profile.contains("atmos") || plex.contains("atmos") { return "Dolby Atmos" }
    switch codec?.lowercased() {
    case "truehd", "mlp": return "Dolby TrueHD"
    case "eac3": return "Dolby Digital Plus"
    case "ac3": return "Dolby Digital"
    case "dts", "dca":
      if profile.contains("ma") || plex.contains("dts-hd ma") { return "DTS-HD MA" }
      if profile.contains("dts:x") || profile.contains("dts-x") || plex.contains("dts:x") { return "DTS:X" }
      if profile.contains("hd") { return "DTS-HD" }
      return "DTS"
    case "aac": return "AAC"
    case "flac": return "FLAC"
    case "opus": return "Opus"
    case "mp3": return "MP3"
    case "vorbis": return "Vorbis"
    case let codec? where codec.hasPrefix("pcm"): return "PCM"
    case let codec? where !codec.isEmpty: return codec.uppercased()
    default: return nil
    }
  }

  /// 8 → "7.1", 6 → "5.1", 2 → "Stereo", 1 → "Mono".
  static func channelLayout(_ channels: Int?) -> String? {
    switch channels {
    case nil, 0?: return nil
    case 1?: return "Mono"
    case 2?: return "Stereo"
    case 3?: return "2.1"
    case 6?: return "5.1"
    case 7?: return "6.1"
    case 8?: return "7.1"
    case let n?: return "\(n)ch"
    }
  }

  private static func isDescriptive(_ title: String) -> Bool {
    let lower = title.lowercased()
    return ["commentary", "descriptive", "description", "director", "isolated", "score"].contains { lower.contains($0) }
  }
}

/// Subtitles → Size (Apple TV top menu; saved per device).
public enum SubtitleSize: String, CaseIterable, Sendable, Identifiable {
  case small, medium, large, extraLarge

  public static let storageKey = "astra.subtitles.size"
  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .small: "Small"
    case .medium: "Medium"
    case .large: "Large"
    case .extraLarge: "Extra Large"
    }
  }

  /// mpv's `sub-scale`.
  public var scale: Double {
    switch self {
    case .small: 0.8
    case .medium: 1
    case .large: 1.25
    case .extraLarge: 1.5
    }
  }

  public static func current(_ defaults: UserDefaults = .standard) -> SubtitleSize {
    defaults.string(forKey: storageKey).flatMap(SubtitleSize.init(rawValue:)) ?? .medium
  }

  public func save(_ defaults: UserDefaults = .standard) { defaults.set(rawValue, forKey: Self.storageKey) }
}

/// Subtitles → Style (Apple TV top menu; saved per device). Applies to text
/// subtitles (SRT, and ASS through mpv's style override); picture subtitles
/// (PGS, VobSub) keep their own look.
public enum SubtitleLook: String, CaseIterable, Sendable, Identifiable {
  case whiteNoBackground, whiteOnBlack, yellow

  public static let storageKey = "astra.subtitles.style"
  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .whiteNoBackground: "White, no background"
    case .whiteOnBlack: "White on black"
    case .yellow: "Yellow"
    }
  }

  /// mpv properties for this look, set live while playing.
  public var mpvOptions: [(String, String)] {
    switch self {
    case .whiteNoBackground:
      [("sub-color", "#FFFFFFFF"), ("sub-border-style", "outline-and-shadow"), ("sub-border-size", "2.5"),
       ("sub-back-color", "#00000000"), ("sub-shadow-offset", "1")]
    case .whiteOnBlack:
      [("sub-color", "#FFFFFFFF"), ("sub-border-style", "background-box"), ("sub-border-size", "0"),
       ("sub-back-color", "#B3000000"), ("sub-shadow-offset", "0")]
    case .yellow:
      [("sub-color", "#FFFFD60A"), ("sub-border-style", "outline-and-shadow"), ("sub-border-size", "2.5"),
       ("sub-back-color", "#00000000"), ("sub-shadow-offset", "1")]
    }
  }

  /// Read from the saved `SubtitleStyle` (Settings → Subtitles), which owns colour and background now.
  public static func current(_ defaults: UserDefaults = .standard) -> SubtitleLook {
    SubtitleStyle.current(defaults).look
  }

  public func save(_ defaults: UserDefaults = .standard) {
    defaults.set(rawValue, forKey: Self.storageKey)
    SubtitleStyle.current(defaults).with(self).save(defaults)
  }
}

/// Subtitles → Sync: mpv's `sub-delay`, in 0.1 s steps between −10 and +10 s.
public enum SubtitleSync {
  public static let step = 0.1
  public static let range: ClosedRange<Double> = -10...10

  public static func adjusted(_ delay: Double, by steps: Int) -> Double {
    let value = ((delay + Double(steps) * step) * 10).rounded() / 10
    return min(range.upperBound, max(range.lowerBound, value))
  }

  /// "0.0s", "+0.3s", "−1.2s".
  public static func label(_ delay: Double) -> String {
    let rounded = (delay * 10).rounded() / 10
    if rounded == 0 { return "0.0s" }
    return (rounded > 0 ? "+" : "\u{2212}") + String(format: "%.1fs", abs(rounded))
  }
}

/// The player's clock: "18:14", "1:37:32"; "Ends at 6:52 PM".
public enum PlaybackClock {
  public static func format(_ seconds: Double) -> String {
    let total = seconds.isFinite ? Int(max(0, seconds).rounded(.down)) : 0
    let h = total / 3600, m = (total % 3600) / 60, s = total % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
  }

  /// When playback would end from `now` with `remaining` seconds left at `speed`.
  public static func endsAt(
    remaining: Double, speed: Double = 1, now: Date = Date(), locale: Locale = .current,
    timeZone: TimeZone = .current
  ) -> String {
    let left = max(0, remaining.isFinite ? remaining : 0) / max(0.1, speed)
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.timeZone = timeZone
    formatter.dateStyle = .none
    formatter.timeStyle = .short
    return "Ends at " + formatter.string(from: now.addingTimeInterval(left))
  }
}

/// One chapter from the file (mpv's `chapter-list`).
public struct PlayerChapter: Identifiable, Hashable, Sendable {
  public var id: Int
  public var title: String
  public var start: Double

  public init(id: Int, title: String, start: Double) {
    self.id = id
    self.title = title
    self.start = start
  }

  /// Chapters from mpv's `chapter-list` node; untitled ones become "Chapter 3".
  public static func list(from node: [Any]) -> [PlayerChapter] {
    var chapters: [PlayerChapter] = []
    for case let entry as [String: Any] in node {
      guard let time = (entry["time"] as? Double) ?? (entry["time"] as? Int).map(Double.init) else { continue }
      let index = chapters.count
      let title = (entry["title"] as? String)?.trimmingCharacters(in: .whitespaces)
      chapters.append(PlayerChapter(id: index, title: title?.isEmpty == false ? title! : "Chapter \(index + 1)", start: time))
    }
    return chapters
  }
}
