import AppKit
import AstraKit
import SwiftUI

struct HomeView: View {
  var library: LibraryStore

  var body: some View {
    ScrollView(.vertical) {
      LazyVStack(alignment: .leading, spacing: 34) {
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
            ForEach(hub.items) { item in
              ArtCard(library: library, item: item)
            }
          }
        }

        if let error = library.homeError {
          Text(error)
            .font(Astra.Font.meta)
            .foregroundStyle(Astra.Color.muted)
            .padding(.leading, Astra.Layout.leading)
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
    .ignoresSafeArea(edges: .top)
  }
}

// MARK: - Hero

struct HeroCarousel: View {
  var library: LibraryStore
  var items: [PlexMetadata]

  @State private var index = 0
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.openItem) private var openItem
  @Environment(\.playItem) private var playItem

  var body: some View {
    let item = items[min(index, items.count - 1)]
    GeometryReader { geo in
      ZStack(alignment: .bottomLeading) {
        // Backdrops crossfade in place: opacity only, nothing slides or relayouts.
        ZStack {
          ForEach(Array(items.enumerated()), id: \.element.id) { offset, entry in
            RemoteImage(url: library.imageURL(entry.backdrop, width: geo.size.width, height: geo.size.height, scale: 1.5))
              .frame(width: geo.size.width, height: geo.size.height)
              .clipped()
              .opacity(offset == index ? 1 : 0)
          }
        }
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
          PageDots(count: items.count, index: index)
            .padding(.top, 10)
        }
        .id(item.id)
        .transition(.opacity)
        .padding(.leading, Astra.Layout.leading)
        .padding(.bottom, 40)
      }
    }
    .frame(height: 620)
    .animation(Astra.Motion.resolved(Astra.Motion.hero, reduceMotion: reduceMotion), value: index)
    .task(id: items.count) {
      // Auto-advance every 8 s; stops when the view goes away.
      while !Task.isCancelled && items.count > 1 {
        try? await Task.sleep(for: .seconds(8))
        guard !Task.isCancelled else { break }
        index = (index + 1) % items.count
      }
    }
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
        .astraDisplay(52, tracking: 10)
        .lineLimit(2)
        .minimumScaleFactor(0.6)
        .frame(maxWidth: 640, alignment: .leading)
    }
  }
}

/// A logo, fitted, with no placeholder box behind it.
struct LogoImage: View {
  var url: URL?
  @State private var image: NSImage?

  var body: some View {
    ZStack(alignment: .bottomLeading) {
      if let image {
        Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
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

  var body: some View {
    HStack(spacing: 10) {
      let parts = [
        item.year.map(String.init),
        item.type == .show ? item.childCount.map { "\($0) Season\($0 == 1 ? "" : "s")" } : item.durationLabel,
        item.genres.prefix(2).map(\.tag).joined(separator: ", ").nilIfEmpty,
      ].compactMap { $0 }
      Text(parts.joined(separator: "  •  "))
        .font(.system(size: fontSize, weight: .medium))
        .foregroundStyle(Astra.Color.ink.opacity(0.9))
      if let rating = item.contentRating { Badge(text: rating) }
      if let badge = item.resolutionBadge { Badge(text: badge) }
      if let score = item.audienceRating {
        Label(String(format: "%.1f", score), systemImage: "star.fill")
          .font(.system(size: fontSize - 1, weight: .semibold))
          .foregroundStyle(Astra.Color.ink.opacity(0.9))
      }
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
