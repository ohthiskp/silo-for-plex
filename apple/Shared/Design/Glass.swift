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

  /// The primary action (Play, Sign in): Apple's prominent glass button.
  /// White on the cinematic screens, violet for sign-in.
  @ViewBuilder func astraPrimaryButton(violet: Bool = false) -> some View {
    if #available(macOS 26.0, iOS 26.0, *) {
      self
        .buttonStyle(.glassProminent)
        .tint(violet ? Astra.Color.purple : .white)
        .foregroundStyle(violet ? Color.white : Color.black)
        .font(.system(size: 15, weight: .semibold))
        .controlSize(.extraLarge)
    } else {
      buttonStyle(PlayButtonStyle(violet: violet))
    }
  }

  /// Secondary actions (Details, Watched, Cancel): Apple's glass button.
  @ViewBuilder func astraSecondaryButton() -> some View {
    if #available(macOS 26.0, iOS 26.0, *) {
      self
        .buttonStyle(.glass)
        .foregroundStyle(Astra.Color.ink)
        .font(.system(size: 15, weight: .semibold))
        .controlSize(.extraLarge)
    } else {
      buttonStyle(FallbackGlassButtonStyle())
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

/// Scales slightly on hover and press. Transform only, so scrolling rows never relayout.
struct Pressable: ViewModifier {
  var hoverScale: CGFloat = 1.04
  @State private var hovering = false
  @GestureState private var pressed = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func body(content: Content) -> some View {
    content
      // Apple TV-style lift: scale plus a soft shadow under the pointer.
      .shadow(color: .black.opacity(hovering ? 0.45 : 0), radius: 18, y: 10)
      .scaleEffect(reduceMotion ? 1 : (pressed ? 0.97 : (hovering ? hoverScale : 1)))
      .animation(pressed ? Astra.Motion.fast : Astra.Motion.base, value: hovering)
      .animation(Astra.Motion.fast, value: pressed)
      .onHover { hovering = $0 }
      #if os(macOS)
        // A zero-distance drag would steal touches from scroll views on iPhone.
        .simultaneousGesture(
          DragGesture(minimumDistance: 0).updating($pressed) { _, state, _ in state = true })
      #endif
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
      .animation(Astra.Motion.fast, value: configuration.isPressed)
  }
}

// MARK: - Before macOS 26

/// White or violet pill for the primary action.
struct PlayButtonStyle: ButtonStyle {
  var violet = false

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 15, weight: .semibold))
      .foregroundStyle(violet ? .white : .black)
      .padding(.horizontal, 26)
      .frame(height: 48)
      .background {
        if violet {
          Capsule().fill(Astra.Color.playGradient)
        } else {
          Capsule().fill(.white)
        }
      }
      .scaleEffect(configuration.isPressed ? 0.97 : 1)
      .animation(Astra.Motion.fast, value: configuration.isPressed)
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
      .animation(Astra.Motion.fast, value: configuration.isPressed)
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
