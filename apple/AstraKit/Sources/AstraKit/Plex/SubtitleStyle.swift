import Foundation

/// Settings → Subtitles (KP, 2026-11-13): the font, colour, background and
/// size of text subtitles (SRT, and ASS through mpv's style override).
/// Picture subtitles (PGS, VobSub) keep their own look. Saved per device.
public enum SubtitleFont: String, CaseIterable, Sendable, Identifiable {
  case standard, rounded, serif, condensed

  public static let storageKey = "astra.subtitles.font"
  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .standard: "Standard"
    case .rounded: "Rounded"
    case .serif: "Serif"
    case .condensed: "Condensed"
    }
  }

  /// The family mpv asks Core Text for; the Settings sample uses the same one.
  public var family: String {
    switch self {
    case .standard: "Helvetica Neue"
    case .rounded: "Arial Rounded MT Bold"
    case .serif: "Georgia"
    case .condensed: "Avenir Next Condensed"
    }
  }
}

public enum SubtitleColor: String, CaseIterable, Sendable, Identifiable {
  case white, yellow, cyan, green, grey

  public static let storageKey = "astra.subtitles.color"
  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .white: "White"
    case .yellow: "Yellow"
    case .cyan: "Cyan"
    case .green: "Green"
    case .grey: "Grey"
    }
  }

  /// 0xRRGGBB.
  public var rgb: UInt32 {
    switch self {
    case .white: 0xFFFFFF
    case .yellow: 0xFFD60A
    case .cyan: 0x64D2FF
    case .green: 0x30D158
    case .grey: 0xC7C7CC
    }
  }

  /// mpv's `#AARRGGBB`, fully opaque.
  public var mpvColor: String { String(format: "#FF%06X", rgb) }
}

public enum SubtitleBackground: String, CaseIterable, Sendable, Identifiable {
  case outline, box

  public static let storageKey = "astra.subtitles.background"
  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .outline: "Outline"
    case .box: "Box"
    }
  }
}

/// Everything about how text subtitles look, read and saved together.
public struct SubtitleStyle: Equatable, Sendable {
  public var font: SubtitleFont
  public var color: SubtitleColor
  public var background: SubtitleBackground
  public var size: SubtitleSize

  public init(
    font: SubtitleFont = .standard, color: SubtitleColor = .white, background: SubtitleBackground = .outline,
    size: SubtitleSize = .medium
  ) {
    self.font = font
    self.color = color
    self.background = background
    self.size = size
  }

  /// The saved style. Before 2026-11-13 the colour and background were one
  /// "look" (Apple TV menu); a saved look still counts until a new choice is made.
  public static func current(_ defaults: UserDefaults = .standard) -> SubtitleStyle {
    let legacy = defaults.string(forKey: SubtitleLook.storageKey).flatMap(SubtitleLook.init(rawValue:))
    let color = defaults.string(forKey: SubtitleColor.storageKey).flatMap(SubtitleColor.init(rawValue:))
      ?? (legacy == .yellow ? .yellow : .white)
    let background = defaults.string(forKey: SubtitleBackground.storageKey).flatMap(SubtitleBackground.init(rawValue:))
      ?? (legacy == .whiteOnBlack ? .box : .outline)
    let font = defaults.string(forKey: SubtitleFont.storageKey).flatMap(SubtitleFont.init(rawValue:)) ?? .standard
    return SubtitleStyle(font: font, color: color, background: background, size: .current(defaults))
  }

  public func save(_ defaults: UserDefaults = .standard) {
    defaults.set(font.rawValue, forKey: SubtitleFont.storageKey)
    defaults.set(color.rawValue, forKey: SubtitleColor.storageKey)
    defaults.set(background.rawValue, forKey: SubtitleBackground.storageKey)
    size.save(defaults)
  }

  /// mpv properties, set before a file loads and live while it plays.
  public var mpvOptions: [(String, String)] {
    var options: [(String, String)] = [("sub-font", font.family), ("sub-color", color.mpvColor)]
    switch background {
    case .outline:
      options += [
        ("sub-border-style", "outline-and-shadow"), ("sub-border-size", "2.5"),
        ("sub-back-color", "#00000000"), ("sub-shadow-offset", "1"),
      ]
    case .box:
      options += [
        ("sub-border-style", "background-box"), ("sub-border-size", "0"),
        ("sub-back-color", "#B3000000"), ("sub-shadow-offset", "0"),
      ]
    }
    options.append(("sub-scale", String(size.scale)))
    return options
  }

  /// The Apple TV menu's three looks, read from this style.
  public var look: SubtitleLook {
    if background == .box { return .whiteOnBlack }
    return color == .yellow ? .yellow : .whiteNoBackground
  }

  /// A look picked in the Apple TV menu sets the colour and background; the font stays.
  public func with(_ look: SubtitleLook) -> SubtitleStyle {
    var style = self
    switch look {
    case .whiteNoBackground: style.color = .white; style.background = .outline
    case .whiteOnBlack: style.color = .white; style.background = .box
    case .yellow: style.color = .yellow; style.background = .outline
    }
    return style
  }
}
