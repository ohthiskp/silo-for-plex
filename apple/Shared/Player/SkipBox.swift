import AstraKit
import SwiftUI

/// The skip button's look (KP, 2026-11-25: option D in Liquid Glass): the
/// prompt in capitals in a glass box with a light edge. With auto-skip on, a
/// white fill grows across it as the countdown runs, and it skips when full.
/// Used on iPhone, Mac and Apple TV for Skip Intro, Skip Credits and Next Episode.
struct SkipBox: View {
  let prompt: SkipPrompt
  /// Auto-skip countdown, 0…1; nil when it isn't counting down.
  var progress: Double?
  /// Apple TV: the box has focus (brighter, larger, lifted).
  var focused = false
  var tv = false

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: tv ? 16 : 12, style: .continuous)
    Text(prompt.title.uppercased())
      .font(.system(size: tv ? 22 : 13, weight: .bold))
      .tracking(tv ? 2.6 : 1.8)
      .foregroundStyle(Color.white)
      .lineLimit(1)
      .fixedSize()
      .padding(.horizontal, tv ? 30 : 20)
      .frame(height: tv ? 64 : 42)
      .background(alignment: .leading) {
        if let progress {
          GeometryReader { geo in
            Rectangle()
              .fill(Color.white.opacity(focused ? 0.5 : 0.32))
              .frame(width: geo.size.width * progress)
          }
          .transition(.opacity)
        }
      }
      .astraAnimation(.linear(duration: 0.25), value: progress)
      .clipShape(shape)
      .astraGlass(in: shape, variant: .regular, interactive: !tv, tint: focused ? Color.white.opacity(0.22) : nil)
      .overlay(shape.strokeBorder(Color.white.opacity(focused ? 0.7 : 0.34), lineWidth: tv ? 2 : 1.5).allowsHitTesting(false))
      .scaleEffect(focused ? 1.08 : 1, anchor: .bottomTrailing)
      .shadow(color: .black.opacity(focused ? 0.45 : 0.25), radius: focused ? 22 : 12, y: focused ? 12 : 6)
      .accessibilityLabel(prompt.title)
  }
}
