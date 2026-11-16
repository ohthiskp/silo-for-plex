import AstraKit
import SwiftUI

/// What the player shows from pressing Play until the first frame (KP,
/// 2026-11-16, mockup A "title card"): the title's artwork dimmed and
/// frosted, its logo in the middle and the small orange Astra arrow moving
/// underneath. It fades into the video. An episode shows its show's logo.
struct PlayLoadingCard: View {
  let player: PlayerController
  var library: LibraryStore?

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  /// The movie, or the episode's show once found.
  @State private var titleItem: PlexMetadata?
  @State private var logo: URL?
  @State private var resolved = false
  @State private var start = Date()

  #if os(tvOS)
    private static let markSize: CGFloat = 110
    private static let logoSize = CGSize(width: 640, height: 220)
    private static let gap: CGFloat = 34
  #else
    private static let markSize: CGFloat = 64
    private static let logoSize = CGSize(width: 320, height: 110)
    private static let gap: CGFloat = 18
  #endif

  var body: some View {
    ZStack {
      Color.black
      if let library, let item = titleItem ?? player.nowPlayingItem {
        ArtworkImage(library: library, item: item, kind: .backdrop, width: 640, height: 360, placeholder: Color.clear)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .clipped()
          .blur(radius: 50, opaque: true)
          .opacity(0.45)
      }
      VStack(spacing: Self.gap) {
        title
        TimelineView(.animation(minimumInterval: 1 / 60, paused: reduceMotion)) { context in
          AstraLoadingMark(time: context.date.timeIntervalSince(start), settled: reduceMotion)
        }
        .frame(width: Self.markSize, height: Self.markSize)
      }
      .padding(.horizontal, 40)
    }
    .ignoresSafeArea()
    .allowsHitTesting(false)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Starting \(player.title)")
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
      // Keeps the arrow in place while the logo is looked up.
      Color.clear.frame(width: Self.logoSize.width, height: Self.logoSize.height * 0.5)
    }
  }
}
