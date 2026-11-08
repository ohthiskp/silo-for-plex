import SwiftUI

// Astra uses Apple's own Liquid Glass (macOS 26): the system glass button
// styles, `glassEffect` for custom floating shapes, and `GlassEffectContainer`
// so neighbouring glass blends and morphs as one surface. Before macOS 26 the
// same calls fall back to translucent materials.
//
// Rules (Apple's Liquid Glass guidance):
// - Glass is for the floating navigation layer only: sidebar, buttons, player
//   controls, search field. Never on artwork, cards or rows.
// - No glass on glass. Things that sit on glass use fills or vibrancy.
// - Regular glass everywhere except the player, which uses clear glass
//   consistently: it floats over video, under a dimming scrim, with bold white glyphs.
// - Only the primary action is tinted.

/// Which Liquid Glass variant a surface uses.
enum AstraGlassVariant {
  case regular
  /// Over video only, with a dimming scrim behind it.
  case clear
}

struct AstraGlass<S: Shape>: ViewModifier {
  var shape: S
  var variant: AstraGlassVariant = .regular
  var interactive = false
  var tint: Color?

  func body(content: Content) -> some View {
    if #available(macOS 26.0, iOS 26.0, *) {
      var glass: Glass = variant == .clear ? .clear : .regular
      if let tint { glass = glass.tint(tint) }
      if interactive { glass = glass.interactive() }
      return AnyView(content.glassEffect(glass, in: shape))
    } else {
      return AnyView(
        content
          .background(variant == .clear ? .ultraThinMaterial : .regularMaterial, in: shape)
          .overlay(shape.stroke(Astra.Color.hairline, lineWidth: 1)))
    }
  }
}

extension View {
  /// Liquid Glass in `shape` for a custom floating element.
  func astraGlass<S: Shape>(
    in shape: S, variant: AstraGlassVariant = .regular, interactive: Bool = false, tint: Color? = nil
  ) -> some View {
    modifier(AstraGlass(shape: shape, variant: variant, interactive: interactive, tint: tint))
  }

  /// The primary action (Play, Sign in): clear Liquid Glass with a light
  /// white tint and a bright edge, white text (KP, 2026-11-07: Play and
  /// Details as see-through glass, not a solid white pill).
  func astraPrimaryButton() -> some View {
    buttonStyle(ClearGlassButtonStyle(prominent: true))
  }

  /// Secondary actions (Details, Watched, Cancel): clear Liquid Glass.
  func astraSecondaryButton() -> some View {
    buttonStyle(ClearGlassButtonStyle(prominent: false))
  }

  /// A thin edge of light around `shape`, brightest top-left, as on the
  /// glass card KP chose as the reference.
  func astraGlassEdge<S: InsettableShape>(_ shape: S, strength: Double = 1) -> some View {
    overlay {
      shape
        .strokeBorder(
          LinearGradient(
            colors: [.white.opacity(0.6 * strength), .white.opacity(0.08 * strength), .white.opacity(0.22 * strength)],
            startPoint: .topLeading, endPoint: .bottomTrailing),
          lineWidth: 1
        )
        .allowsHitTesting(false)
    }
  }

  /// A round glass icon button (back, close, player transport).
  func astraIconButton(size: CGFloat = 44, variant: AstraGlassVariant = .regular) -> some View {
    buttonStyle(GlassIconButtonStyle(size: size, variant: variant))
  }
}

/// Groups glass elements so they render as one surface and morph into each
/// other when they move or appear (`GlassEffectContainer` on macOS 26).
struct AstraGlassGroup<Content: View>: View {
  var spacing: CGFloat = 16
  @ViewBuilder var content: () -> Content

  var body: some View {
    if #available(macOS 26.0, iOS 26.0, *) {
      GlassEffectContainer(spacing: spacing, content: content)
    } else {
      content()
    }
  }
}

extension View {
  /// Wraps this view in an `AstraGlassGroup`.
  func astraGlassGroup(spacing: CGFloat = 16) -> some View {
    AstraGlassGroup(spacing: spacing) { self }
  }
}

/// Apple TV-style hover: a slight lift with a soft shadow. Transform only, so
/// scrolling rows never relayout. Hover only: a gesture here would sit inside
/// a Button's label and swallow its clicks on the Mac. Press feedback comes
/// from `AstraCardButtonStyle`.
struct Pressable: ViewModifier {
  var hoverScale: CGFloat = 1.04
  @State private var hovering = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func body(content: Content) -> some View {
    content
      .shadow(color: .black.opacity(hovering ? 0.45 : 0), radius: 18, y: 10)
      .scaleEffect(reduceMotion ? 1 : (hovering ? hoverScale : 1))
      .astraAnimation(Astra.Motion.base, value: hovering)
      .onHover { hovering = $0 }
  }
}

/// Cards: plain label, a small press-in, and the whole card is the hit area.
struct AstraCardButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .contentShape(Rectangle())
      .scaleEffect(configuration.isPressed ? 0.97 : 1)
      .astraAnimation(Astra.Motion.fast, value: configuration.isPressed)
  }
}

extension View {
  func pressable(hoverScale: CGFloat = 1.04) -> some View {
    modifier(Pressable(hoverScale: hoverScale))
  }

  /// Soft scroll-edge effect under the floating controls (macOS 26).
  @ViewBuilder func astraScrollEdges() -> some View {
    if #available(macOS 26.0, iOS 26.0, *) {
      scrollEdgeEffectStyle(.soft, for: .top)
    } else {
      self
    }
  }
}

/// Round glass icon button. Interactive glass flexes and glows under the pointer on macOS 26.
struct GlassIconButtonStyle: ButtonStyle {
  var size: CGFloat = 44
  var variant: AstraGlassVariant = .regular

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: size * 0.42, weight: .semibold))
      .foregroundStyle(.white)
      .frame(width: size, height: size)
      .contentShape(Circle())
      .astraGlass(in: Circle(), variant: variant, interactive: true)
      .scaleEffect(configuration.isPressed ? 0.94 : 1)
      .astraAnimation(Astra.Motion.fast, value: configuration.isPressed)
  }
}

// MARK: - Before macOS 26

/// White pill for the primary action.
struct PlayButtonStyle: ButtonStyle {

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 15, weight: .semibold))
      .foregroundStyle(.black)
      .padding(.horizontal, 26)
      .frame(height: 48)
      .background(Capsule().fill(.white))
      .scaleEffect(configuration.isPressed ? 0.97 : 1)
      .astraAnimation(Astra.Motion.fast, value: configuration.isPressed)
      .contentShape(Capsule())
  }
}

/// Material pill for secondary actions.
struct FallbackGlassButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 15, weight: .semibold))
      .foregroundStyle(Astra.Color.ink)
      .padding(.horizontal, 22)
      .frame(height: 48)
      .astraGlass(in: Capsule())
      .scaleEffect(configuration.isPressed ? 0.97 : 1)
      .astraAnimation(Astra.Motion.fast, value: configuration.isPressed)
      .contentShape(Capsule())
  }
}

/// The small boxed badge: "4K", "HD", "PG-13".
struct Badge: View {
  var text: String

  var body: some View {
    Text(text)
      .font(.system(size: 11, weight: .bold))
      .foregroundStyle(Astra.Color.ink)
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .overlay(RoundedRectangle(cornerRadius: Astra.Radius.badge).stroke(.white.opacity(0.25), lineWidth: 1))
  }
}

/// Play / Details: a capsule of clear Liquid Glass (macOS 26: `.clear`,
/// interactive, so it reacts to the pointer and presses like Apple's).
/// `prominent` adds a soft white tint so the main action stands out.
struct ClearGlassButtonStyle: ButtonStyle {
  var prominent: Bool
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.astraAccent) private var accent

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 15, weight: .semibold))
      .foregroundStyle(.white)
      .labelStyle(.titleAndIcon)
      // A label never wraps onto two lines.
      .lineLimit(1)
      .fixedSize(horizontal: false, vertical: true)
      .padding(.horizontal, 22)
      .frame(height: 46)
      .contentShape(Capsule())
      .shadow(color: .black.opacity(0.35), radius: 3)
      .astraGlass(
        in: Capsule(), variant: .clear, interactive: true, tint: prominent ? (accent?.opacity(0.6) ?? .white.opacity(0.22)) : nil)
      .astraGlassEdge(Capsule(), strength: prominent ? 1 : 0.8)
      .scaleEffect(configuration.isPressed ? 0.96 : 1)
      .opacity(isEnabled ? 1 : 0.45)
      .astraAnimation(Astra.Motion.fast, value: configuration.isPressed)
  }
}
