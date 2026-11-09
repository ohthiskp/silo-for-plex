import AstraKit
import SwiftUI

#if canImport(UIKit)
  import UIKit
#else
  import AppKit
#endif

/// Astra tokens from DESIGN_SYSTEM.md, in one place.
enum Astra {
  enum Color {
    // Whole-app themes (KP, 2026-11-09), Settings → Appearance: Frosted
    // Glass (the default: neutral greys, colour from the artwork), OLED,
    // Light and Violet. Every surface reads these, so a theme changes the
    // entire screen. Violet is the only purple, and only when KP picks it.
    @MainActor static var bg: SwiftUI.Color { AstraAppearance.shared.palette.bg }
    @MainActor static var surface: SwiftUI.Color { AstraAppearance.shared.palette.surface }
    @MainActor static var surface2: SwiftUI.Color { AstraAppearance.shared.palette.surface2 }
    @MainActor static var ink: SwiftUI.Color { AstraAppearance.shared.palette.ink }
    @MainActor static var muted: SwiftUI.Color { AstraAppearance.shared.palette.ink.opacity(0.62) }
    /// Selection, progress and focus: the theme's accent.
    @MainActor static var accent: SwiftUI.Color { AstraAppearance.shared.accent }
    /// Text and icons on an accent fill.
    @MainActor static var onAccent: SwiftUI.Color { AstraAppearance.shared.onAccent }
    /// An "on" switch: the accent, but grey when the accent is white so the
    /// white knob still shows (KP: "too white for switches").
    @MainActor static var switchOn: SwiftUI.Color { AstraAppearance.shared.switchOn }
    /// Icons, the tab bar and the sidebar.
    @MainActor static var theme: SwiftUI.Color { AstraAppearance.shared.accent }
    @MainActor static var onTheme: SwiftUI.Color { AstraAppearance.shared.onAccent }
    @MainActor static var hairline: SwiftUI.Color { AstraAppearance.shared.palette.hairline }
  }

  /// Fixed-size fonts. Text in views uses `.astraFont(_:)`, the same sizes
  /// scaled with Text Size; these stay for places that must not grow.
  enum Font {
    /// Large titles set as text: Apple's system font, bold (KP: no Didot).
    static func display(_ size: CGFloat) -> SwiftUI.Font {
      .system(size: size, weight: .bold)
    }
    #if os(tvOS)
      static let rowTitle = SwiftUI.Font.system(size: 30, weight: .bold)
      static let meta = SwiftUI.Font.system(size: 22, weight: .medium)
      static let card = SwiftUI.Font.system(size: 21, weight: .medium)
    #else
      static let rowTitle = SwiftUI.Font.system(size: 19, weight: .bold)
      static let meta = SwiftUI.Font.system(size: 14, weight: .medium)
      static let card = SwiftUI.Font.system(size: 13, weight: .medium)
    #endif
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
      /// Buttons and small controls; 1 on Mac and iPhone.
      static let controlScale: CGFloat = 1
      static let textScale: CGFloat = 1
    #elseif os(tvOS)
      // Apple TV (1920 × 1080 pt, seen from the sofa): about 1.5× the Mac. The
      // system safe area already keeps 60 pt top/bottom and 80 pt left/right.
      static let leading: CGFloat = 140
      static let heroHeight: CGFloat = 760
      static let detailHeaderHeight: CGFloat = 760
      static let heroShare: CGFloat = 0.8
      static let artCard = CGSize(width: 360, height: 203)
      static let continueCard = CGSize(width: 520, height: 293)
      static let episodeCard = CGSize(width: 420, height: 236)
      static let posterMinWidth: CGFloat = 230
      static let titleSize: CGFloat = 76
      static let pageTitleSize: CGFloat = 57
      /// Text in pages (`astraFont`) is this much larger than on the Mac and iPhone.
      static let textScale: CGFloat = 1.6
      /// Buttons, chips and small cards are this much larger, for focus from the sofa.
      static let controlScale: CGFloat = 1.5
      /// The TV's side safe area (80 pt on every Apple TV), which `tvFullBleed` runs past.
      static let tvSideSafeArea: CGFloat = 80
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
      static let controlScale: CGFloat = 1
      static let textScale: CGFloat = 1
      /// Space a scrolling page leaves at its bottom for the floating tab bar
      /// (52 pt bar + insets, `WideTabBar`) plus a little air.
      static let tabBarRoom: CGFloat = 80
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
    #elseif os(tvOS)
      static let pageTop: CGFloat = 30
      static let pageTrailing: CGFloat = 80
    #else
      static let pageTop: CGFloat = 8
      static let pageTrailing: CGFloat = 20
    #endif
  }

  /// The docked Mac sidebar's geometry; pages start to the right of it.
  enum Sidebar {
    #if os(tvOS)
      // Apple TV: the same sidebar, sized for the remote's focus (KP, 2026-11-08).
      static let margin: CGFloat = 20
      static let collapsedWidth: CGFloat = 96
    #else
      static let margin: CGFloat = 14
      static let collapsedWidth: CGFloat = 62
    #endif
    /// While the pointer is over it (icons plus names, KP 2026-11-08). Pages keep
    /// `contentInset`: the expanded sidebar floats over them.
    #if os(tvOS)
      static let expandedWidth: CGFloat = 300
    #else
      static let expandedWidth: CGFloat = 190
    #endif
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
/// Settings → Appearance → Theme: how the whole app looks (KP, 2026-11-09).
enum AppTheme: String, CaseIterable, Identifiable, Sendable {
  case frosted, oled, light, violet

  var id: String { rawValue }

  var title: String {
    switch self {
    case .frosted: "Frosted Glass"
    case .oled: "OLED"
    case .light: "Light"
    case .violet: "Violet"
    }
  }

  var subtitle: String {
    switch self {
    case .frosted: "Liquid Glass over the artwork"
    case .oled: "Pure black, no blur"
    case .light: "Bright glass and dark text"
    case .violet: "Deep purple glass"
    }
  }

  var palette: ThemePalette {
    switch self {
    case .frosted:
      ThemePalette(
        bg: 0x0A0A0B, surface: 0x161618, surface2: 0x1E1E21, ink: 0xF5F5F7, accent: 0xFFFFFF,
        isLight: false, ambient: 0.7, wash: 0.45, glassTint: nil)
    case .oled:
      ThemePalette(
        bg: 0x000000, surface: 0x0E0E0F, surface2: 0x161617, ink: 0xF5F5F7, accent: 0xFFFFFF,
        isLight: false, ambient: 0, wash: 0, glassTint: nil)
    case .light:
      ThemePalette(
        bg: 0xF2F2F7, surface: 0xFFFFFF, surface2: 0xE5E5EA, ink: 0x1C1C1E, accent: 0x1C1C1E,
        isLight: true, ambient: 0.55, wash: 0.55, glassTint: nil)
    case .violet:
      ThemePalette(
        bg: 0x110A1F, surface: 0x1C1230, surface2: 0x261A40, ink: 0xF4F0FF, accent: 0xB69CFF,
        isLight: false, ambient: 0.55, wash: 0.5, glassTint: 0x6E4BD8)
    }
  }
}

/// One theme's colours. `ambient` is how strongly the blurred artwork shows
/// behind pages (0 = none, OLED); `wash` the theme colour laid over it.
struct ThemePalette {
  let bg: SwiftUI.Color
  let surface: SwiftUI.Color
  let surface2: SwiftUI.Color
  let ink: SwiftUI.Color
  let accentHex: RGBHex
  let isLight: Bool
  let ambient: Double
  let wash: Double
  let glassTint: SwiftUI.Color?

  init(
    bg: UInt32, surface: UInt32, surface2: UInt32, ink: UInt32, accent: UInt32,
    isLight: Bool, ambient: Double, wash: Double, glassTint: UInt32?
  ) {
    self.bg = SwiftUI.Color(hex: bg)
    self.surface = SwiftUI.Color(hex: surface)
    self.surface2 = SwiftUI.Color(hex: surface2)
    self.ink = SwiftUI.Color(hex: ink)
    accentHex = RGBHex(accent)
    self.isLight = isLight
    self.ambient = ambient
    self.wash = wash
    self.glassTint = glassTint.map { SwiftUI.Color(hex: $0).opacity(0.35) }
  }

  var hairline: SwiftUI.Color { isLight ? .black.opacity(0.1) : .white.opacity(0.09) }
  var colorScheme: ColorScheme { isLight ? .light : .dark }
}

@MainActor @Observable final class AstraAppearance {
  static let shared = AstraAppearance()
  static let themeKey = "astra.appearance.appTheme"

  private let defaults: UserDefaults
  private(set) var appTheme: AppTheme

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    appTheme = defaults.string(forKey: Self.themeKey).flatMap(AppTheme.init(rawValue:)) ?? .frosted
  }

  var palette: ThemePalette { appTheme.palette }
  var colorScheme: ColorScheme { palette.colorScheme }
  var accentHex: RGBHex { palette.accentHex }
  var accent: SwiftUI.Color { SwiftUI.Color(hex: accentHex.value) }
  var onAccent: SwiftUI.Color { accentHex.prefersDarkText ? .black : .white }
  var switchOn: SwiftUI.Color {
    accentHex == AccentPreset.white.hex ? SwiftUI.Color(hex: 0x636366) : accent
  }

  func setTheme(_ theme: AppTheme) {
    appTheme = theme
    if theme == .frosted {
      defaults.removeObject(forKey: Self.themeKey)
    } else {
      defaults.set(theme.rawValue, forKey: Self.themeKey)
    }
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

extension EnvironmentValues {
  /// Astra: Home's accent, the chosen streaming service's brand colour (nil is
  /// the usual white). Tints the main button and progress bars on that page.
  @Entry var astraAccent: Color? = nil
}

// MARK: - Reduce Motion

/// The system's Reduce Motion setting, for code outside a view (`withAnimation`).
/// Views read `\.accessibilityReduceMotion` instead.
@MainActor private var systemReducesMotion: Bool {
  #if canImport(UIKit)
    UIAccessibility.isReduceMotionEnabled
  #else
    NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
  #endif
}

/// `withAnimation`, but quick and calm when Reduce Motion is on
/// (`Astra.Motion.resolved`). Nothing changes when the setting is off.
@MainActor @discardableResult
func astraWithAnimation<Result>(_ animation: Animation? = .default, _ body: () throws -> Result) rethrows -> Result {
  try withAnimation(animation.map { Astra.Motion.resolved($0, reduceMotion: systemReducesMotion) }, body)
}

private struct AstraAnimationModifier<Value: Equatable>: ViewModifier {
  var animation: Animation?
  var value: Value
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func body(content: Content) -> some View {
    content.animation(animation.map { Astra.Motion.resolved($0, reduceMotion: reduceMotion) }, value: value)
  }
}

private struct AstraTransitionModifier: ViewModifier {
  var transition: AnyTransition
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func body(content: Content) -> some View {
    content.transition(reduceMotion ? .opacity : transition)
  }
}

extension View {
  /// `.animation(_:value:)` that follows Reduce Motion (`Astra.Motion.resolved`).
  func astraAnimation<Value: Equatable>(_ animation: Animation?, value: Value) -> some View {
    modifier(AstraAnimationModifier(animation: animation, value: value))
  }

  /// `.transition(_:)` that becomes a plain fade when Reduce Motion is on.
  func astraTransition(_ transition: AnyTransition) -> some View {
    modifier(AstraTransitionModifier(transition: transition))
  }
}

// MARK: - Dynamic Type

/// A system font that grows with the iPhone's Text Size setting and is
/// exactly `size` at the default setting, so the default look never changes
/// (KP, 2026-11-08). The Mac has no Text Size setting and keeps `size`.
private struct ScaledSystemFont: ViewModifier {
  @ScaledMetric private var size: CGFloat
  private let weight: SwiftUI.Font.Weight
  private let design: SwiftUI.Font.Design

  init(size: CGFloat, weight: SwiftUI.Font.Weight, design: SwiftUI.Font.Design) {
    #if os(tvOS)
      _size = ScaledMetric(wrappedValue: size * Astra.Layout.textScale, relativeTo: .body)
    #else
      _size = ScaledMetric(wrappedValue: size, relativeTo: .body)
    #endif
    self.weight = weight
    self.design = design
  }

  func body(content: Content) -> some View {
    content.font(.system(size: size, weight: weight, design: design))
  }
}

/// `Astra.Font`'s text tokens, scaled with Text Size (`astraFont(_:)`).
enum AstraTextStyle {
  case rowTitle, meta, card
  case display(CGFloat)
}

extension View {
  /// Text that follows Text Size; the same as `.font(.system(size:weight:design:))` at the default.
  func astraFont(
    size: CGFloat, weight: SwiftUI.Font.Weight = .regular, design: SwiftUI.Font.Design = .default
  ) -> some View {
    modifier(ScaledSystemFont(size: size, weight: weight, design: design))
  }

  /// `Astra.Font.rowTitle` / `meta` / `card` / `display(_:)`, scaled with Text Size.
  func astraFont(_ style: AstraTextStyle) -> some View {
    switch style {
    case .rowTitle: astraFont(size: 19, weight: .bold)
    case .meta: astraFont(size: 14, weight: .medium)
    case .card: astraFont(size: 13, weight: .medium)
    case .display(let size): astraFont(size: size, weight: .bold)
    }
  }
}
