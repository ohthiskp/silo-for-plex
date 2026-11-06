import SwiftUI

/// Astra tokens from DESIGN_SYSTEM.md, in one place.
enum Astra {
  enum Color {
    static let bg = SwiftUI.Color(hex: 0x07060B)
    static let surface = SwiftUI.Color(hex: 0x15131D)
    static let surface2 = SwiftUI.Color(hex: 0x1C1A26)
    static let ink = SwiftUI.Color(hex: 0xF2F0F7)
    static let muted = SwiftUI.Color(hex: 0xF2F0F7).opacity(0.66)
    static let purple = SwiftUI.Color(hex: 0x7C4DFF)
    static let purpleLight = SwiftUI.Color(hex: 0x9B74FF)
    static let hairline = SwiftUI.Color.white.opacity(0.09)
    static let playGradient = LinearGradient(
      colors: [SwiftUI.Color(hex: 0x8A5CFF), SwiftUI.Color(hex: 0x7246F5)], startPoint: .top, endPoint: .bottom)
  }

  enum Font {
    /// Didot display type with wide tracking, for titles set as text.
    static func display(_ size: CGFloat) -> SwiftUI.Font {
      .custom("Didot", size: size)
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
      /// Left inset of page content, clear of the docked sidebar.
      static let leading: CGFloat = 104
      static let heroHeight: CGFloat = 620
      static let detailHeaderHeight: CGFloat = 640
      static let artCard = CGSize(width: 240, height: 135)
      static let continueCard = CGSize(width: 360, height: 202)
      static let episodeCard = CGSize(width: 300, height: 169)
      static let posterMinWidth: CGFloat = 160
      static let titleSize: CGFloat = 52
    #else
      static let leading: CGFloat = 20
      static let heroHeight: CGFloat = 560
      static let detailHeaderHeight: CGFloat = 560
      static let artCard = CGSize(width: 168, height: 95)
      static let continueCard = CGSize(width: 270, height: 152)
      static let episodeCard = CGSize(width: 240, height: 135)
      static let posterMinWidth: CGFloat = 104
      static let titleSize: CGFloat = 38
    #endif
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
  /// Didot title styling: wide tracking and a soft shadow.
  func astraDisplay(_ size: CGFloat, tracking: CGFloat = 9) -> some View {
    font(Astra.Font.display(size))
      .tracking(tracking)
      .foregroundStyle(Astra.Color.ink)
      .shadow(color: .black.opacity(0.45), radius: 12, y: 4)
  }
}
