import SwiftUI

/// Watched titles (KP, 2026-11-17, mockup "glass tick + dimmed"): the art dims
/// a little and a Liquid Glass circle with a white tick sits in its top-right
/// corner, so unwatched and in-progress titles stand out.
struct WatchedMark: View {
  /// The circle's diameter.
  var size: CGFloat = 28

  var body: some View {
    Image(systemName: "checkmark")
      .font(.system(size: size * 0.46, weight: .bold))
      .foregroundStyle(.white)
      .frame(width: size, height: size)
      .astraGlass(in: Circle(), variant: .clear)
      .environment(\.colorScheme, .dark)
      .accessibilityLabel("Watched")
  }
}

extension View {
  /// Dims watched art and puts the glass tick on it. Apply to the clipped image,
  /// before any progress bar so a bar stays bright.
  func watchedLook(_ watched: Bool, corner: CGFloat = Astra.Radius.card, mark: CGFloat = 28, inset: CGFloat = 8) -> some View {
    self
      .overlay { if watched {
          RoundedRectangle(cornerRadius: corner, style: .continuous).fill(Color.black.opacity(0.4)).allowsHitTesting(false)
        } }
      .overlay(alignment: .topTrailing) {
        if watched { WatchedMark(size: mark).padding(inset) }
      }
  }
}
