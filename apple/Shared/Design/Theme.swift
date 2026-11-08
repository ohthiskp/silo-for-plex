import AstraKit
import SwiftUI

/// Astra tokens from DESIGN_SYSTEM.md, in one place.
enum Astra {
  enum Color {
    // Neutral, cinematic greys. No purple accent anywhere (KP, 2026-11-06):
    // selection and progress are white; colour comes from the artwork.
    static let bg = SwiftUI.Color(hex: 0x0A0A0B)
    static let surface = SwiftUI.Color(hex: 0x161618)
    static let surface2 = SwiftUI.Color(hex: 0x1E1E21)
    static let ink = SwiftUI.Color(hex: 0xF5F5F7)
    static let muted = SwiftUI.Color(hex: 0xF5F5F7).opacity(0.62)
    /// Selection, progress and focus: white unless KP picks another accent
    /// in Settings → Appearance (Astra 4.0).
    @MainActor static var accent: SwiftUI.Color { AstraAppearance.shared.accent }
    /// Text and icons on an accent fill: black on light accents, white on dark ones.
    @MainActor static var onAccent: SwiftUI.Color { AstraAppearance.shared.onAccent }
    static let hairline = SwiftUI.Color.white.opacity(0.09)
  }

  enum Font {
    /// Large titles set as text: Apple's system font, bold (KP: no Didot).
    static func display(_ size: CGFloat) -> SwiftUI.Font {
      .system(size: size, weight: .bold)
    }
    static let rowTitle = SwiftUI.Font.system(size: 19, weight: .bold)
    static let meta = SwiftUI.Font.system(size: 14, weight: .medium)
    static let card = SwiftUI.Font.system(size: 13, weight: .medium)
  }

  /// Motion tokens. Everything animates opacity and transform, never layout.
  enum Motion {
    /// 150 ms ease-out cubic: press, focus.
    static let fast = Animation.timingCurve(0.215, 0.61, 0.355, 1, duration: 0.15)
    /// 250 ms ease-out cubic: hover, chips.
    static let base = Animation.timingCurve(0.215, 0.61, 0.355, 1, duration: 0.25)
    /// 380 ms ease-in-out cubic: pages, sheets, menus.
    static let page = Animation.timingCurve(0.645, 0.045, 0.355, 1, duration: 0.38)
    /// 600 ms ease-in-out cubic: hero crossfade, poster → details.
    static let hero = Animation.timingCurve(0.645, 0.045, 0.355, 1, duration: 0.6)

    /// Fades only, at `fast`, when the user asked for reduced motion.
    static func resolved(_ animation: Animation, reduceMotion: Bool) -> Animation {
      reduceMotion ? fast : animation
    }
  }

  /// Sizes that differ between the Mac (docked sidebar, big window) and iPhone.
  enum Layout {
    #if os(macOS)
      /// Left inset of page content, clear of the collapsed sidebar. Screens
      /// read `\.contentLeading`, which follows the sidebar's width.
      static let leading: CGFloat = 104
      /// The hero and details header take this share of the window's height, up to the cap.
      static let heroHeight: CGFloat = 620
      static let detailHeaderHeight: CGFloat = 640
      static let heroShare: CGFloat = 0.82
      static let artCard = CGSize(width: 240, height: 135)
      static let continueCard = CGSize(width: 360, height: 202)
      static let episodeCard = CGSize(width: 300, height: 169)
      static let posterMinWidth: CGFloat = 160
      static let titleSize: CGFloat = 52
      static let pageTitleSize: CGFloat = 38
    #else
      static let leading: CGFloat = 20
      static let heroHeight: CGFloat = 560
      static let detailHeaderHeight: CGFloat = 560
      static let heroShare: CGFloat = 0.72
      static let artCard = CGSize(width: 168, height: 95)
      static let continueCard = CGSize(width: 270, height: 152)
      static let episodeCard = CGSize(width: 240, height: 135)
      static let posterMinWidth: CGFloat = 104
      static let titleSize: CGFloat = 38
      static let pageTitleSize: CGFloat = 30
    #endif
  }

  /// Spacing scale. Screens use these instead of literals.
  enum Spacing {
    static let xs: CGFloat = 6
    static let s: CGFloat = 10
    static let m: CGFloat = 14
    static let l: CGFloat = 22
    static let xl: CGFloat = 34
    /// Space between the page's top safe-area edge and a page header.
    #if os(macOS)
      static let pageTop: CGFloat = 24
      static let pageTrailing: CGFloat = 40
    #else
      static let pageTop: CGFloat = 8
      static let pageTrailing: CGFloat = 20
    #endif
  }

  /// The docked Mac sidebar's geometry; pages start to the right of it.
  enum Sidebar {
    static let margin: CGFloat = 14
    static let collapsedWidth: CGFloat = 62
    static let gap: CGFloat = 28
    static let contentInset: CGFloat = margin + collapsedWidth + gap
  }

  enum Radius {
    static let card: CGFloat = 14
    static let badge: CGFloat = 4
  }
}

extension Color {
  init(hex: UInt32, opacity: Double = 1) {
    self.init(
      .sRGB,
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255,
      opacity: opacity)
  }
}

extension View {
  /// Title styling: the system font, bold, tight like Apple's large titles,
  /// with a soft shadow. `tracking` is kept for callers but no longer spaced out.
  func astraDisplay(_ size: CGFloat, tracking: CGFloat = 0) -> some View {
    font(Astra.Font.display(size))
      .tracking(size >= 30 ? -0.4 : 0)
      .foregroundStyle(Astra.Color.ink)
      .shadow(color: .black.opacity(0.45), radius: 12, y: 4)
  }
}

// MARK: - Page inset

private struct ContentLeadingKey: EnvironmentKey {
  static let defaultValue: CGFloat = Astra.Layout.leading
}

/// Settings → Appearance, read wherever a view uses `Astra.Color.accent`;
/// views redraw when it changes because it is observed.
@MainActor @Observable final class AstraAppearance {
  static let shared = AstraAppearance()

  private let defaults: UserDefaults
  private(set) var accentHex: RGBHex

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    accentHex = defaults.string(forKey: Preferences.accentKey).flatMap(RGBHex.init(string:)) ?? AccentPreset.white.hex
  }

  var accent: SwiftUI.Color { SwiftUI.Color(hex: accentHex.value) }
  var onAccent: SwiftUI.Color { accentHex.prefersDarkText ? .black : .white }

  func setAccent(_ hex: RGBHex) {
    accentHex = hex
    if hex == AccentPreset.white.hex {
      defaults.removeObject(forKey: Preferences.accentKey)
    } else {
      defaults.set(hex.string, forKey: Preferences.accentKey)
    }
  }

  /// The accent from a ColorPicker, in sRGB.
  func setAccent(_ color: SwiftUI.Color) {
    let resolved = color.resolve(in: EnvironmentValues())
    setAccent(RGBHex(red: Double(resolved.red), green: Double(resolved.green), blue: Double(resolved.blue)))
  }
}

extension EnvironmentValues {
  /// The left inset every page aligns its titles, rows and buttons to.
  var contentLeading: CGFloat {
    get { self[ContentLeadingKey.self] }
    set { self[ContentLeadingKey.self] = newValue }
  }
}

extension View {
  /// A header height that fits the window: `share` of the visible height, capped at `cap`.
  func astraHeaderHeight(cap: CGFloat) -> some View {
    containerRelativeFrame(.vertical) { length, _ in min(cap, max(360, length * Astra.Layout.heroShare)) }
  }
}

/// Settings → Appearance, read wherever a view uses `Astra.Color.accent`;
/// views redraw when it changes because it is observed.
@MainActor @Observable final class AstraAppearance {
  static let shared = AstraAppearance()

  private let defaults: UserDefaults
  private(set) var accentHex: RGBHex

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    accentHex = defaults.string(forKey: Preferences.accentKey).flatMap(RGBHex.init(string:)) ?? AccentPreset.white.hex
  }

  var accent: SwiftUI.Color { SwiftUI.Color(hex: accentHex.value) }
  var onAccent: SwiftUI.Color { accentHex.prefersDarkText ? .black : .white }

  func setAccent(_ hex: RGBHex) {
    accentHex = hex
    if hex == AccentPreset.white.hex {
      defaults.removeObject(forKey: Preferences.accentKey)
    } else {
      defaults.set(hex.string, forKey: Preferences.accentKey)
    }
  }

  /// The accent from a ColorPicker, in sRGB.
  func setAccent(_ color: SwiftUI.Color) {
    let resolved = color.resolve(in: EnvironmentValues())
    setAccent(RGBHex(red: Double(resolved.red), green: Double(resolved.green), blue: Double(resolved.blue)))
  }
}

extension EnvironmentValues {
  /// Astra: Home's accent, the chosen streaming service's brand colour (nil is
  /// the usual white). Tints the main button and progress bars on that page.
  @Entry var astraAccent: Color? = nil
}
