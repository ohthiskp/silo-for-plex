import Foundation

/// Astra 4.0 (KP, 2026-11-08): the settings the redesigned Settings page
/// saves, per device, in UserDefaults. Views read them with @AppStorage.
public enum Preferences {
  /// Appearance → Accent, as "RRGGBB". Missing means white (Astra's default).
  public static let accentKey = "astra.appearance.accent"
  /// Appearance → Streaming Service Accents: a provider's colour on its Home page.
  public static let serviceAccentsKey = "astra.appearance.serviceAccents"
  /// Library → HD / 4K badges.
  public static let qualityBadgesKey = "astra.library.qualityBadges"
  /// Library → age ratings (PG-13, TV-MA…).
  public static let ratingsKey = "astra.library.ratings"
  /// Downloads → Wi-Fi Only.
  public static let wifiOnlyKey = "astra.downloads.wifiOnly"
}

/// An sRGB colour as a 24-bit number, for saving a picked accent.
public struct RGBHex: Sendable, Equatable, Hashable {
  public var value: UInt32

  public init(_ value: UInt32) { self.value = value & 0xFFFFFF }

  /// "FF9F0A", "#ff9f0a" → the colour; anything else → nil.
  public init?(string: String) {
    var text = string.trimmingCharacters(in: .whitespaces)
    if text.hasPrefix("#") { text.removeFirst() }
    guard text.count == 6, let number = UInt32(text, radix: 16) else { return nil }
    self.init(number)
  }

  /// From 0…1 components (clamped), rounded to the nearest step.
  public init(red: Double, green: Double, blue: Double) {
    func byte(_ c: Double) -> UInt32 { UInt32((min(max(c, 0), 1) * 255).rounded()) }
    self.init(byte(red) << 16 | byte(green) << 8 | byte(blue))
  }

  public var string: String { String(format: "%06X", value) }
  public var red: Double { Double((value >> 16) & 0xFF) / 255 }
  public var green: Double { Double((value >> 8) & 0xFF) / 255 }
  public var blue: Double { Double(value & 0xFF) / 255 }

  /// WCAG relative luminance, 0 (black) … 1 (white).
  public var luminance: Double {
    func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
    return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
  }

  /// Text on a fill of this colour: black on light colours, white on dark ones,
  /// whichever has the higher contrast.
  public var prefersDarkText: Bool {
    let onBlack = (luminance + 0.05) / 0.05
    let onWhite = 1.05 / (luminance + 0.05)
    return onBlack >= onWhite
  }
}

/// Appearance → Accent presets. White is Astra's own; the rest are Apple's
/// system colours. No purple or violet (KP's standing rule).
public enum AccentPreset: String, CaseIterable, Sendable, Identifiable {
  case white, silver, red, orange, yellow, green, mint, blue

  public var id: String { rawValue }

  public var title: String { rawValue.capitalized }

  public var hex: RGBHex {
    switch self {
    case .white: RGBHex(0xFFFFFF)
    case .silver: RGBHex(0xAEAEB2)
    case .red: RGBHex(0xFF453A)
    case .orange: RGBHex(0xFF9F0A)
    case .yellow: RGBHex(0xFFD60A)
    case .green: RGBHex(0x30D158)
    case .mint: RGBHex(0x63E6E2)
    case .blue: RGBHex(0x0A84FF)
    }
  }

  /// The preset a saved accent is, if it is one.
  public static func matching(_ hex: RGBHex) -> AccentPreset? {
    allCases.first { $0.hex == hex }
  }
}

/// Settings → Playback → Subtitles.
public enum SubtitlePreference: String, CaseIterable, Sendable, Identifiable {
  /// What the file marks as default or forced (signs, foreign dialogue).
  case automatic
  /// Subtitles in the device's languages whenever the file has them.
  case always
  case off

  public static let storageKey = "astra.playback.subtitles"

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .automatic: "Automatic"
    case .always: "Always"
    case .off: "Off"
    }
  }

  /// mpv options to set before `loadfile`. `languages` are the device's
  /// preferred languages ("en-US", "fr"); only their language codes are used.
  public func mpvOptions(languages: [String]) -> [(String, String)] {
    switch self {
    case .off:
      return [("sid", "no")]
    case .automatic:
      return [("sid", "auto"), ("subs-with-matching-audio", "no")]
    case .always:
      var codes: [String] = []
      for language in languages {
        let code = String(language.prefix { $0 != "-" && $0 != "_" }).lowercased()
        if !code.isEmpty, !codes.contains(code) { codes.append(code) }
      }
      var options: [(String, String)] = [("sid", "auto"), ("subs-with-matching-audio", "yes")]
      if !codes.isEmpty { options.append(("slang", codes.joined(separator: ","))) }
      return options
    }
  }

  public static func current(_ defaults: UserDefaults = .standard) -> SubtitlePreference {
    defaults.string(forKey: storageKey).flatMap(SubtitlePreference.init(rawValue:)) ?? .automatic
  }
}

extension DownloadIndex {
  /// Downloads → Storage Used: the saved files' sizes, as recorded.
  public var totalBytes: Int64 { records.compactMap(\.bytes).reduce(0, +) }
}
