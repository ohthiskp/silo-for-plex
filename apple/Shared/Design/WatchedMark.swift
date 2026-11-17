import SwiftUI

/// Watched titles (KP, 2026-11-17: "just check mark bottom right and dimmed"):
/// the art dims and a plain white tick sits in its bottom-right corner, so
/// unwatched and in-progress titles stand out.
struct WatchedMark: View {
  /// The tick's height.
  var size: CGFloat = 20

  var body: some View {
    Image(systemName: "checkmark")
      .font(.system(size: size, weight: .bold))
      .foregroundStyle(.white)
      .shadow(color: .black.opacity(0.6), radius: 3, y: 1)
      .accessibilityLabel("Watched")
  }
}

extension View {
  /// Dims watched art and puts the tick in its bottom-right corner. Apply to
  /// the clipped image, before any progress bar so a bar stays bright.
  func watchedLook(_ watched: Bool, corner: CGFloat = Astra.Radius.card, mark: CGFloat = 20, inset: CGFloat = 10) -> some View {
    self
      .overlay {
        if watched {
          RoundedRectangle(cornerRadius: corner, style: .continuous).fill(Color.black.opacity(0.45)).allowsHitTesting(false)
        }
      }
      .overlay(alignment: .bottomTrailing) {
        if watched { WatchedMark(size: mark).padding(inset) }
      }
  }
}
