import SwiftUI

/// The "HD" / "4K" label beside the player's title. Plain bold text with no
/// border, like the quality label in the badge row on Details and the hero
/// (KP, 2026-11-17: "make the hd badge match the rest of the app, no
/// border"). `size` is the text size, about the subtitle line's size on each
/// platform. Shown only when the real resolution is known.
struct ResolutionTag: View {
  var text: String
  var size: CGFloat = 13

  var body: some View {
    Text(text)
      .font(.system(size: size, weight: .bold))
      .foregroundStyle(.white.opacity(0.95))
      .fixedSize()
      .accessibilityLabel(text)
  }
}
