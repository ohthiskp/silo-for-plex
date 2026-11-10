import SwiftUI

/// The small outlined "HD" / "4K" badge beside the player's title (KP's
/// player mockups, 2026-11-10): bold text at 70% white in a 1 pt border at
/// 50%. `size` is the text size: 9 pt on iPhone, about 40% of the title's
/// height on Apple TV. Shown only when the real resolution is known.
struct ResolutionTag: View {
  var text: String
  var size: CGFloat = 9

  var body: some View {
    Text(text)
      .font(.system(size: size, weight: .bold))
      .foregroundStyle(.white.opacity(0.7))
      .padding(.horizontal, size * 0.4)
      .padding(.vertical, size * 0.12)
      .overlay(
        RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
          .strokeBorder(.white.opacity(0.5), lineWidth: 1)
      )
      .fixedSize()
      .accessibilityLabel(text)
  }
}
