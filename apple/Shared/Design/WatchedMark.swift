import SwiftUI

/// Watched titles (KP, 2026-11-17: option 5, "make the artwork dimmed"):
/// the art dims and a thin white ring with a white tick sits in its top-right
/// corner, so unwatched and in-progress titles stand out.
struct WatchedMark: View {
  /// The ring's diameter.
  var size: CGFloat = 26

  var body: some View {
    ZStack {
      Circle().strokeBorder(.white, lineWidth: max(1.5, size / 13))
      Image(systemName: "checkmark")
        .font(.system(size: size * 0.46, weight: .bold))
        .foregroundStyle(.white)
    }
    .frame(width: size, height: size)
    .shadow(color: .black.opacity(0.6), radius: 3, y: 1)
    .accessibilityElement()
    .accessibilityLabel("Watched")
  }
}

extension View {
  /// Dims watched art and puts the ringed tick in its top-right corner. Apply
  /// to the clipped image, before any progress bar so a bar stays bright.
  func watchedLook(_ watched: Bool, corner: CGFloat = Astra.Radius.card, mark: CGFloat = 26, inset: CGFloat = 8) -> some View {
    self
      .overlay {
        if watched {
          RoundedRectangle(cornerRadius: corner, style: .continuous).fill(Color.black.opacity(0.5)).allowsHitTesting(false)
        }
      }
      .overlay(alignment: .topTrailing) {
        if watched { WatchedMark(size: mark).padding(inset) }
      }
  }
}
