import AstraKit
import SwiftUI

/// What the player shows from pressing Play until the first frame (KP,
/// 2026-11-16: "just the show or movie logo by itself"): the title's
/// artwork dimmed and frosted, and its logo in the middle, breathing softly
/// so it reads as loading. No spinner and no Astra mark. It fades into the
/// video. An episode shows its show's logo.
struct PlayLoadingCard: View {
  let player: PlayerController
  var library: LibraryStore?

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  /// The movie, or the episode's show once found.
  @State private var titleItem: PlexMetadata?
  @State private var logo: URL?
  @State private var resolved = false
  /// The logo's slow pulse while the title loads.
  @State private var breathing = false

  #if os(tvOS)
    private static let logoSize = CGSize(width: 800, height: 280)
  #else
    private static let logoSize = CGSize(width: 400, height: 140)
  #endif

  var body: some View {
    ZStack {
      // The artwork fills the screen as an overlay of it: laid out on its own,
      // a 16:9 backdrop filling a screen of another shape came out wider (Mac)
      // or taller (iPhone) than the screen and pushed the whole player with it,
      // so the logo sat off centre and the controls ran off the edges.
      Color.black
        .overlay {
          if let library, let item = titleItem ?? player.nowPlayingItem {
            ArtworkImage(library: library, item: item, kind: .backdrop, width: 640, height: 360, placeholder: Color.clear)
              .blur(radius: 50, opaque: true)
              .opacity(0.45)
          }
        }
        .clipped()
      title
        .opacity(breathing ? 0.78 : 1)
        .padding(.horizontal, 40)
    }
    .ignoresSafeArea()
    .allowsHitTesting(false)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Starting \(player.title)")
    .onAppear {
      guard !reduceMotion else { return }
      withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { breathing = true }
    }
    .task(id: player.nowPlayingItem?.ratingKey) {
      guard let library, let item = player.nowPlayingItem else { return }
      var shown = item
      if item.type == .episode, let key = item.grandparentRatingKey, let show = try? await library.details(key) {
        shown = show
      }
      guard !Task.isCancelled else { return }
      titleItem = shown
      logo = await library.artworkURL(for: shown, .logo, width: Self.logoSize.width * 2, height: Self.logoSize.height * 2)
      resolved = true
    }
  }

  @ViewBuilder private var title: some View {
    if let logo {
      RemoteImage(url: logo, contentMode: .fit, placeholder: Color.clear)
        .frame(maxWidth: Self.logoSize.width, maxHeight: Self.logoSize.height)
    } else if resolved || library == nil {
      // No logo for this title: its name.
      Text(player.nowPlayingItem?.grandparentTitle ?? player.title)
        .astraFont(size: 28, weight: .bold)
        .foregroundStyle(.white)
        .lineLimit(2)
        .multilineTextAlignment(.center)
        .frame(maxWidth: Self.logoSize.width * 1.4)
    } else {
      Color.clear.frame(width: 1, height: 1)
    }
  }
}
