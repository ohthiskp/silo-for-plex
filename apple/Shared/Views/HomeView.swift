import AstraKit
import SwiftUI

struct HomeView: View {
  var library: LibraryStore
  @Environment(\.contentLeading) private var leading

  var body: some View {
    ScrollView(.vertical) {
      // A plain VStack: a lazy one guesses row heights and makes the page jump while scrolling.
      VStack(alignment: .leading, spacing: Astra.Spacing.xl) {
        if library.hero.isEmpty {
          Color.clear.frame(height: 110)
        } else {
          HeroCarousel(library: library, items: library.hero)
        }

        if !library.continueWatching.isEmpty {
          ContentRow(title: "Continue Watching") {
            ForEach(library.continueWatching) { item in
              ContinueCard(library: library, item: item)
            }
          }
        }

        ForEach(library.hubs) { hub in
          ContentRow(title: hub.title) {
            // Movies and shows as posters; episodes keep landscape stills.
            if hub.items.contains(where: { $0.type == .episode || $0.type == .clip }) {
              ForEach(hub.items) { ArtCard(library: library, item: $0) }
            } else {
              ForEach(hub.items) { PosterCard(library: library, item: $0) }
            }
          }
        }

        if let error = library.homeError {
          Text(error)
            .font(Astra.Font.meta)
            .foregroundStyle(Astra.Color.muted)
            .padding(.leading, leading)
        }
      }
      .padding(.bottom, 80)
    }
    .scrollIndicators(.never)
    .astraScrollEdges()
    .overlay {
      if library.isLoadingHome {
        ProgressView().controlSize(.large).transition(.opacity)
      }
    }
    .animation(Astra.Motion.base, value: library.isLoadingHome)
    .refreshable { await library.loadHome() }
    // Artwork runs under the title bar / status bar; the hero's controls sit
    // well below it, at the bottom of the hero.
    .ignoresSafeArea(edges: .top)
    .background(Astra.Color.bg.ignoresSafeArea())
  }
}

// MARK: - Hero

/// One featured title at a time. Backdrops crossfade; the title block fades
/// out completely before the next one fades in, so two titles never overlap.
struct HeroCarousel: View {
  var library: LibraryStore
  var items: [PlexMetadata]

  /// The backdrop showing.
  @State private var index = 0
  /// The title block showing; it trails `index` by the fade-out.
  @State private var shownIndex = 0
  @State private var textVisible = true
  @State private var size: CGSize = .zero
  /// Bumped by manual navigation so the auto-advance timer restarts.
  @State private var interaction = 0
  @State private var swap: Task<Void, Never>?

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.openItem) private var openItem
  @Environment(\.playItem) private var playItem
  @Environment(\.contentLeading) private var leading

  var body: some View {
    let item = items[min(shownIndex, items.count - 1)]
    ZStack(alignment: .bottomLeading) {
      ZStack {
        ForEach(Array(items.enumerated()), id: \.element.id) { offset, entry in
          RemoteImage(url: library.imageURL(entry.backdrop, width: size.width, height: size.height, scale: 1.5))
            .opacity(offset == index ? 1 : 0)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .clipped()
      .onGeometryChange(for: CGSize.self, of: { $0.size }) { size = $0 }
      .animation(Astra.Motion.resolved(Astra.Motion.hero, reduceMotion: reduceMotion), value: index)

      HeroScrim()

      VStack(alignment: .leading, spacing: 16) {
        HeroTitle(library: library, item: item)
        MetaRow(item: item)
        if let summary = item.summary, !summary.isEmpty {
          Text(summary)
            .font(.system(size: 14.5))
            .lineSpacing(4)
            .foregroundStyle(Astra.Color.ink.opacity(0.82))
            .lineLimit(3)
            .frame(maxWidth: 560, alignment: .leading)
        }
        HStack(spacing: 14) {
          Button {
            playItem(item)
          } label: {
            Label(item.progress != nil ? "Resume" : "Play", systemImage: "play.fill")
          }
          .astraPrimaryButton()
          Button {
            openItem(item)
          } label: {
            Label("Details", systemImage: "info.circle")
          }
          .astraSecondaryButton()
        }
        .astraGlassGroup(spacing: 14)
        .padding(.top, 6)
      }
      .opacity(textVisible ? 1 : 0)
      .padding(.leading, leading)
      .padding(.trailing, Astra.Spacing.pageTrailing)
      .padding(.bottom, 64)

      if items.count > 1 {
        HeroPager(count: items.count, index: index, previous: { step(-1) }, next: { step(1) })
          .padding(.leading, leading)
          .padding(.bottom, 18)
      }
    }
    .frame(maxWidth: .infinity)
    .astraHeaderHeight(cap: Astra.Layout.heroHeight)
    .task(id: "\(items.map(\.id))|\(interaction)") {
      // New hero items (after a refresh) start from the first one.
      if index >= items.count { show(0) }
      // Auto-advance every 8 s; restarts after manual navigation, stops when the view goes away.
      while !Task.isCancelled && items.count > 1 {
        try? await Task.sleep(for: .seconds(8))
        guard !Task.isCancelled else { break }
        show((index + 1) % items.count)
      }
    }
    .onDisappear { swap?.cancel() }
  }

  private func step(_ delta: Int) {
    guard !items.isEmpty else { return }
    interaction += 1
    show((index + delta + items.count) % items.count)
  }

  private func show(_ next: Int) {
    guard next != index || next != shownIndex else { return }
    index = next
    swap?.cancel()
    let fade = reduceMotion ? 0.15 : 0.22
    withAnimation(.easeOut(duration: fade)) { textVisible = false }
    swap = Task {
      try? await Task.sleep(for: .seconds(fade))
      guard !Task.isCancelled else { return }
      shownIndex = next
      withAnimation(.easeOut(duration: fade + 0.08)) { textVisible = true }
    }
  }
}

/// Previous and next buttons around the page dots.
struct HeroPager: View {
  var count: Int
  var index: Int
  var previous: () -> Void
  var next: () -> Void

  var body: some View {
    HStack(spacing: Astra.Spacing.m) {
      Button(action: previous) { Image(systemName: "chevron.left") }
        .astraIconButton(size: 32)
        .accessibilityLabel("Previous Title")
      PageDots(count: count, index: index)
      Button(action: next) { Image(systemName: "chevron.right") }
        .astraIconButton(size: 32)
        .accessibilityLabel("Next Title")
    }
    .astraGlassGroup(spacing: Astra.Spacing.m)
    #if os(macOS)
      .onKeyPress(.leftArrow) {
        previous()
        return .handled
      }
      .onKeyPress(.rightArrow) {
        next()
        return .handled
      }
    #endif
  }
}

struct HeroScrim: View {
  var body: some View {
    ZStack {
      LinearGradient(
        stops: [
          .init(color: Astra.Color.bg.opacity(0.0), location: 0.35),
          .init(color: Astra.Color.bg.opacity(0.75), location: 0.8),
          .init(color: Astra.Color.bg, location: 1),
        ], startPoint: .top, endPoint: .bottom)
      LinearGradient(
        colors: [Astra.Color.bg.opacity(0.85), Astra.Color.bg.opacity(0)], startPoint: .leading,
        endPoint: .init(x: 0.6, y: 0.5))
    }
    .allowsHitTesting(false)
  }
}

/// The clear logo when Plex has one, else the title in Didot.
struct HeroTitle: View {
  var library: LibraryStore
  var item: PlexMetadata
  var maxWidth: CGFloat = 440
  var maxHeight: CGFloat = 150

  var body: some View {
    if let logo = item.clearLogo {
      LogoImage(url: library.imageURL(logo, width: maxWidth, height: maxHeight))
        .frame(maxWidth: maxWidth, maxHeight: maxHeight, alignment: .bottomLeading)
        .shadow(color: .black.opacity(0.5), radius: 14, y: 4)
    } else {
      Text(item.displayTitle.uppercased())
        .astraDisplay(Astra.Layout.titleSize, tracking: 10)
        .lineLimit(2)
        .minimumScaleFactor(0.6)
        .frame(maxWidth: 640, alignment: .leading)
    }
  }
}

/// A logo, fitted, with no placeholder box behind it.
struct LogoImage: View {
  var url: URL?
  @State private var image: PlatformImage?

  var body: some View {
    ZStack(alignment: .bottomLeading) {
      if let image {
        Image(platformImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
          .transition(.opacity)
      }
    }
    .task(id: url) {
      guard let url else { return }
      if let hit = ImagePipeline.shared.cached(url) { return image = hit }
      let loaded = await ImagePipeline.shared.image(for: url)
      withAnimation(Astra.Motion.base) { image = loaded }
    }
  }
}

struct MetaRow: View {
  var item: PlexMetadata
  var fontSize: CGFloat = 15
  @AppStorage(PlaybackQuality.storageKey) private var quality: PlaybackQuality = .auto

  var body: some View {
    HStack(spacing: 10) {
      let parts = [
        item.year.map(String.init),
        item.type == .show ? item.childCount.map { "\($0) Season\($0 == 1 ? "" : "s")" } : item.durationLabel,
        item.genres.prefix(2).map(\.tag).joined(separator: ", ").nilIfEmpty,
      ].compactMap { $0 }
      // The text truncates first; badges keep their size.
      Text(parts.joined(separator: "  •  "))
        .font(.system(size: fontSize, weight: .medium))
        .foregroundStyle(Astra.Color.ink.opacity(0.9))
        .lineLimit(1)
      Group {
        if let rating = item.contentRating { Badge(text: rating) }
        // The version this device would play, never a claim about HDR.
        if let badge = item.resolutionBadge(for: quality) { Badge(text: badge) }
        if let score = item.audienceRating {
          Label(String(format: "%.1f", score), systemImage: "star.fill")
            .font(.system(size: fontSize - 1, weight: .semibold))
            .foregroundStyle(Astra.Color.ink.opacity(0.9))
        }
      }
      .fixedSize()
    }
  }
}

struct PageDots: View {
  var count: Int
  var index: Int

  var body: some View {
    HStack(spacing: 6) {
      ForEach(0..<count, id: \.self) { i in
        Capsule()
          .fill(i == index ? Color.white : Color.white.opacity(0.35))
          .frame(width: 20, height: 6)
          // Width animates through scale, not layout.
          .scaleEffect(x: i == index ? 1 : 0.3, y: 1, anchor: .center)
          .frame(width: i == index ? 20 : 6)
      }
    }
    .animation(Astra.Motion.base, value: index)
  }
}

extension String {
  var nilIfEmpty: String? { isEmpty ? nil : self }
}
