import SwiftUI

/// Liquid Glass on macOS 26, a translucent material before it.
struct AstraGlass<S: Shape>: ViewModifier {
  var shape: S
  var interactive = false

  func body(content: Content) -> some View {
    if #available(macOS 26.0, *) {
      content.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
    } else {
      content
        .background(.ultraThinMaterial, in: shape)
        .overlay(shape.stroke(Astra.Color.hairline, lineWidth: 1))
    }
  }
}

extension View {
  func astraGlass<S: Shape>(in shape: S, interactive: Bool = false) -> some View {
    modifier(AstraGlass(shape: shape, interactive: interactive))
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
      .scaleEffect(reduceMotion ? 1 : (pressed ? 0.97 : (hovering ? hoverScale : 1)))
      .animation(pressed ? Astra.Motion.fast : Astra.Motion.base, value: hovering)
      .animation(Astra.Motion.fast, value: pressed)
      .onHover { hovering = $0 }
      .simultaneousGesture(
        DragGesture(minimumDistance: 0).updating($pressed) { _, state, _ in state = true })
  }
}

extension View {
  func pressable(hoverScale: CGFloat = 1.04) -> some View {
    modifier(Pressable(hoverScale: hoverScale))
  }
}

/// White Play pill, the primary action.
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

/// Glass secondary pill (Details, Watched…).
struct GlassButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 15, weight: .semibold))
      .foregroundStyle(Astra.Color.ink)
      .padding(.horizontal, 22)
      .frame(height: 48)
      .astraGlass(in: Capsule(), interactive: true)
      .scaleEffect(configuration.isPressed ? 0.97 : 1)
      .animation(Astra.Motion.fast, value: configuration.isPressed)
      .contentShape(Capsule())
  }
}

/// Round glass icon button (player transport, close).
struct GlassIconButtonStyle: ButtonStyle {
  var size: CGFloat = 44

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: size * 0.42, weight: .semibold))
      .foregroundStyle(.white)
      .frame(width: size, height: size)
      .astraGlass(in: Circle(), interactive: true)
      .scaleEffect(configuration.isPressed ? 0.94 : 1)
      .animation(Astra.Motion.fast, value: configuration.isPressed)
      .contentShape(Circle())
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
