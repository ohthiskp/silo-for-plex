import AstraKit
import SwiftUI

/// A titled horizontal row, aligned to the page inset.
struct ContentRow<Content: View>: View {
  var title: String
  @ViewBuilder var content: () -> Content
  @Environment(\.contentLeading) private var leading

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(title)
        .font(Astra.Font.rowTitle)
        .foregroundStyle(Astra.Color.ink)
        .lineLimit(1)
        .padding(.leading, leading)
        .padding(.trailing, Astra.Spacing.pageTrailing)
      ScrollView(.horizontal) {
        LazyHStack(alignment: .top, spacing: 14) {
          content()
        }
        .padding(.horizontal, leading)
      }
      .scrollIndicators(.never)
      // Hover scale and shadow draw past the row instead of being clipped.
      .scrollClipDisabled()
    }
  }
}

/// Landscape art card with the title underneath.
struct ArtCard: View {
  var library: LibraryStore
  var item: PlexMetadata
  var width: CGFloat = Astra.Layout.artCard.width
  var height: CGFloat = Astra.Layout.artCard.height

  @Environment(\.openItem) private var openItem

  var body: some View {
    Button {
      openItem(item)
    } label: {
      VStack(alignment: .leading, spacing: 8) {
        Group {
          if item.type == .movie || item.type == .show {
            ArtworkImage(library: library, item: item, kind: .backdrop, width: width, height: height)
          } else {
            RemoteImage(url: library.imageURL(item.art ?? item.backdrop ?? item.thumb, width: width, height: height))
          }
        }
          .frame(width: width, height: height)
          .clipShape(RoundedRectangle(cornerRadius: Astra.Radius.card, style: .continuous))
          .overlay(alignment: .bottomLeading) {
            if let progress = item.progress { ProgressBar(value: progress).padding(10) }
          }
          .overlay(
            RoundedRectangle(cornerRadius: Astra.Radius.card, style: .continuous).stroke(Astra.Color.hairline))
          .pressable()
        Text(item.displayTitle)
          .font(Astra.Font.card)
          .foregroundStyle(Astra.Color.ink)
          .lineLimit(1)
        if let sub = item.episodeLabel ?? item.year.map(String.init) {
          Text(sub).font(.system(size: 12)).foregroundStyle(Astra.Color.muted).lineLimit(1)
        }
      }
      .frame(width: width, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(AstraCardButtonStyle())
    .itemMenu(library: library, item: item)
  }
}

/// Continue Watching: a wider card with the episode or title inside it and a progress line.
struct ContinueCard: View {
  var library: LibraryStore
  var item: PlexMetadata
  var width: CGFloat = Astra.Layout.continueCard.width
  var height: CGFloat = Astra.Layout.continueCard.height

  @Environment(\.playItem) private var playItem
  @Environment(\.openItem) private var openItem

  var body: some View {
    Button {
      playItem(item)
    } label: {
      ZStack(alignment: .bottomLeading) {
        if item.type == .episode {
          RemoteImage(url: library.imageURL(item.thumb, width: width, height: height))
        } else {
          ArtworkImage(library: library, item: item, kind: .backdrop, width: width, height: height)
        }
        LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .center, endPoint: .bottom)
        VStack(alignment: .leading, spacing: 6) {
          Text(item.displayTitle)
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(.white)
            .lineLimit(1)
          if let sub = [item.episodeLabel, item.type == .episode ? item.title : nil].compactMap({ $0 }).joined(
            separator: "  ·  "
          ).nilIfEmpty {
            Text(sub).font(.system(size: 13.5, weight: .medium)).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
          }
          ProgressBar(value: item.progress ?? 0)
        }
        .padding(14)
        Image(systemName: "play.fill")
          .font(.system(size: 18, weight: .bold))
          .foregroundStyle(.white)
          .frame(width: 48, height: 48)
          .background(.black.opacity(0.4), in: Circle())
          .overlay(Circle().stroke(.white.opacity(0.25)))
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      .frame(width: width, height: height)
      .clipShape(RoundedRectangle(cornerRadius: Astra.Radius.card, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: Astra.Radius.card, style: .continuous).stroke(Astra.Color.hairline))
      .contentShape(Rectangle())
      .pressable(hoverScale: 1.03)
    }
    .buttonStyle(AstraCardButtonStyle())
    .itemMenu(library: library, item: item)
  }
}

/// Poster card for library grids.
struct PosterCard: View {
  var library: LibraryStore
  var item: PlexMetadata
  var width: CGFloat = Astra.Layout.posterMinWidth + 10

  @Environment(\.openItem) private var openItem

  var body: some View {
    let height = width * 1.5
    Button {
      openItem(item)
    } label: {
      VStack(alignment: .leading, spacing: 8) {
        ArtworkImage(library: library, item: item, kind: .poster, width: width, height: height)
          .frame(width: width, height: height)
          .clipShape(RoundedRectangle(cornerRadius: Astra.Radius.card, style: .continuous))
          .overlay(alignment: .topTrailing) {
            if library.isWatched(item) {
              Image(systemName: "checkmark.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.black, .white)
                .font(.system(size: 18))
                .padding(8)
            }
          }
          .overlay(
            RoundedRectangle(cornerRadius: Astra.Radius.card, style: .continuous).stroke(Astra.Color.hairline))
          .pressable()
        Text(item.displayTitle).font(Astra.Font.card).foregroundStyle(Astra.Color.ink).lineLimit(1)
        if let year = item.year {
          Text(String(year)).font(.system(size: 12)).foregroundStyle(Astra.Color.muted)
        }
      }
      .frame(width: width, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(AstraCardButtonStyle())
    .itemMenu(library: library, item: item)
  }
}

struct ProgressBar: View {
  var value: Double

  var body: some View {
    Capsule()
      .fill(.white.opacity(0.25))
      .frame(height: 4)
      .overlay(alignment: .leading) {
        GeometryReader { geo in
          Capsule().fill(Astra.Color.accent).frame(width: max(4, geo.size.width * value))
        }
      }
  }
}

// MARK: - Long-press menu

extension View {
  /// Astra: the long-press (right-click on Mac) menu on every title card.
  func itemMenu(library: LibraryStore, item: PlexMetadata) -> some View {
    modifier(ItemMenu(library: library, item: item))
  }
}

/// Details, Play, Download, Mark Watched / Unwatched, and for episodes Go to
/// Season and Go to Show. TMDB-only titles get Details only.
struct ItemMenu: ViewModifier {
  var library: LibraryStore
  var item: PlexMetadata
  @Environment(AppModel.self) private var app
  @Environment(\.openItem) private var openItem
  @Environment(\.playItem) private var playItem

  func body(content: Content) -> some View {
    content.contextMenu {
      Button { openItem(item) } label: { Label("Details", systemImage: "info.circle") }
      if !item.isCatalogOnly {
        Button { playItem(item) } label: { Label("Play", systemImage: "play.fill") }
        let watched = library.isWatched(item)
        Button {
          Task { await library.setWatched(item, watched: !watched) }
        } label: {
          Label(watched ? "Mark Unwatched" : "Mark Watched", systemImage: watched ? "eye.slash" : "checkmark.circle")
        }
        let isGroup = item.type == .show || item.type == .season
        let downloadState = isGroup ? app.downloads.state(forEpisodesOf: item) : app.downloads.state(for: item.ratingKey)
        if item.type != .collection, downloadState == .none {
          Button { app.downloads.download(item) } label: { Label("Download", systemImage: "arrow.down.circle") }
        }
        if item.type == .episode {
          Divider()
          if let season = item.parentRatingKey {
            Button {
              openItem(PlexMetadata(ratingKey: season, type: .season, title: item.parentTitle ?? "Season"))
            } label: { Label("Go to Season", systemImage: "square.stack") }
          }
          if let show = item.grandparentRatingKey {
            Button {
              openItem(PlexMetadata(ratingKey: show, type: .show, title: item.grandparentTitle ?? "Show"))
            } label: { Label("Go to Show", systemImage: "tv") }
          }
        } else if item.type == .season, let show = item.parentRatingKey {
          Divider()
          Button {
            openItem(PlexMetadata(ratingKey: show, type: .show, title: item.parentTitle ?? "Show"))
          } label: { Label("Go to Show", systemImage: "tv") }
        }
      }
    }
  }
}
