import Foundation

/// Settings → Playback → Audio Language and Subtitle Language (KP,
/// 2026-11-16: "it should be able to make a default to English"). The
/// chosen language wins over the file's own default track whenever the file
/// has a track in it; otherwise the file and Plex decide as before.
public struct PlaybackLanguage: Hashable, Sendable, Identifiable {
  /// ISO 639-1 code ("en"), or "" for Automatic (the file's / Plex's choice).
  public var code: String

  public init(code: String) { self.code = code.lowercased() }

  public static let automatic = PlaybackLanguage(code: "")
  public static let audioKey = "astra.playback.audioLanguage"
  public static let subtitleKey = "astra.playback.subtitleLanguage"

  public var id: String { code }
  public var isAutomatic: Bool { code.isEmpty }

  /// The choices in Settings: Automatic, then the common languages.
  public static let choices: [PlaybackLanguage] =
    [.automatic] + ["en", "hi", "es", "fr", "de", "it", "pt", "ja", "ko", "zh", "ta", "te", "ar", "ru"].map(PlaybackLanguage.init)

  public var title: String {
    if isAutomatic { return "Automatic" }
    return Locale(identifier: "en").localizedString(forLanguageCode: code) ?? code.uppercased()
  }

  /// Every spelling of this language a file may carry ("en", "eng").
  public var codes: [String] {
    guard !isAutomatic else { return [] }
    return [code] + (Self.threeLetter[code] ?? [])
  }

  /// Whether a track tagged `language` ("eng", "en", "en-US", "English") is in this language.
  public func matches(_ language: String?) -> Bool {
    guard !isAutomatic, let raw = language?.lowercased(), !raw.isEmpty else { return false }
    let base = String(raw.prefix { $0 != "-" && $0 != "_" })
    if codes.contains(base) { return true }
    return raw == title.lowercased()
  }

  /// mpv's alang / slang value: "en,eng".
  public var mpvValue: String { codes.joined(separator: ",") }

  public static func audio(_ defaults: UserDefaults = .standard) -> PlaybackLanguage {
    PlaybackLanguage(code: defaults.string(forKey: audioKey) ?? "")
  }

  public static func subtitle(_ defaults: UserDefaults = .standard) -> PlaybackLanguage {
    PlaybackLanguage(code: defaults.string(forKey: subtitleKey) ?? "")
  }

  /// ISO 639-2 (bibliographic and terminology) codes files use.
  private static let threeLetter: [String: [String]] = [
    "en": ["eng"], "hi": ["hin"], "es": ["spa"], "fr": ["fre", "fra"], "de": ["ger", "deu"],
    "it": ["ita"], "pt": ["por"], "ja": ["jpn"], "ko": ["kor"], "zh": ["chi", "zho"],
    "ta": ["tam"], "te": ["tel"], "ar": ["ara"], "ru": ["rus"],
  ]
}

extension PlaybackLanguage {
  /// Of the tracks given as (id, language), the one to pick: the first in this
  /// language, or nil when there is none (or the setting is Automatic).
  public func pick(from tracks: [(id: Int, language: String?)]) -> Int? {
    tracks.first { matches($0.language) }?.id
  }
}
