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
        .astraFont(.rowTitle)
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
      .tvFocusSection()
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
          .astraFont(.card)
          .foregroundStyle(Astra.Color.ink)
          .lineLimit(1)
        if let sub = item.episodeLabel ?? item.year.map(String.init) {
          Text(sub).astraFont(size: 12).foregroundStyle(Astra.Color.muted).lineLimit(1)
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
    // Astra: the card opens the details page; only the play button on the
    // thumbnail starts playback (KP, 2026-11-07).
    Button {
      openItem(item)
    } label: {
      ZStack(alignment: .bottomLeading) {
        if item.type == .episode, item.thumb != nil {
          RemoteImage(url: library.imageURL(item.thumb, width: width, height: height))
        } else {
          // Movies, and an episode without its own still: the (show's) backdrop.
          ArtworkImage(library: library, item: item, kind: .backdrop, width: width, height: height)
        }
        LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .center, endPoint: .bottom)
        VStack(alignment: .leading, spacing: 6) {
          Text(item.displayTitle)
            .astraFont(size: 17, weight: .bold)
            .foregroundStyle(.white)
            .lineLimit(1)
          if let sub = [item.episodeLabel, item.type == .episode ? item.title : nil].compactMap({ $0 }).joined(
            separator: "  ·  "
          ).nilIfEmpty {
            Text(sub).astraFont(size: 13.5, weight: .medium).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
          }
          ProgressBar(value: item.progress ?? 0)
        }
        .padding(14)
      }
      .frame(width: width, height: height)
      .clipShape(RoundedRectangle(cornerRadius: Astra.Radius.card, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: Astra.Radius.card, style: .continuous).stroke(Astra.Color.hairline))
      .contentShape(Rectangle())
      .pressable(hoverScale: 1.03)
    }
    .buttonStyle(AstraCardButtonStyle())
    .overlay {
      // Its own button, above the card, so a tap on it plays instead of opening details.
      Button {
        playItem(item)
      } label: {
        Image(systemName: "play.fill")
          .font(.system(size: 18, weight: .bold))
          .foregroundStyle(.white)
          .frame(width: 48, height: 48)
          .background(.black.opacity(0.4), in: Circle())
          .overlay(Circle().stroke(.white.opacity(0.25)))
          .contentShape(Circle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Play \(item.displayTitle)")
    }
    .itemMenu(library: library, item: item, inContinueWatching: true)
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
        Text(item.displayTitle).astraFont(.card).foregroundStyle(Astra.Color.ink).lineLimit(1)
        if let year = item.year {
          Text(String(year)).astraFont(size: 12).foregroundStyle(Astra.Color.muted)
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
  @Environment(\.astraAccent) private var accent

  var body: some View {
    Capsule()
      .fill(.white.opacity(0.25))
      .frame(height: 4)
      .overlay(alignment: .leading) {
        GeometryReader { geo in
          Capsule().fill(accent ?? Astra.Color.accent).frame(width: max(4, geo.size.width * value))
        }
      }
  }
}

// MARK: - Long-press menu

extension View {
  /// Astra: the long-press (right-click on Mac) menu on every title card.
  func itemMenu(library: LibraryStore, item: PlexMetadata, inContinueWatching: Bool = false) -> some View {
    modifier(ItemMenu(library: library, item: item, inContinueWatching: inContinueWatching))
  }
}

/// Details, Play, Download, Mark Watched / Unwatched, and for episodes Go to
/// Season and Go to Show. TMDB-only titles get Details only.
struct ItemMenu: ViewModifier {
  var library: LibraryStore
  var item: PlexMetadata
  /// Continue Watching cards end the menu with a short red Remove (KP, 2026-11-08: less cluttered).
  var inContinueWatching = false

  func body(content: Content) -> some View {
    content.contextMenu {
      ItemMenuItems(library: library, item: item, inContinueWatching: inContinueWatching)
    }
  }
}

/// The title menu's buttons, shared by the long-press menu and the ••• menu on Details.
struct ItemMenuItems: View {
  var library: LibraryStore
  var item: PlexMetadata
  #if os(tvOS)
    private static let isTV = true
  #else
    private static let isTV = false
  #endif
  var inContinueWatching = false
  /// Details and Play are left out on the Details page itself (it has its own Play).
  var onDetails = false
  @Environment(AppModel.self) private var app
  @Environment(\.openItem) private var openItem
  @Environment(\.playItem) private var playItem

  var body: some View {
    if !onDetails {
      Button { openItem(item) } label: { Label("Details", systemImage: "info.circle") }
    }
    if !item.isCatalogOnly {
      if !onDetails {
        Button { playItem(item) } label: { Label("Play", systemImage: "play.fill") }
      }
      if onDetails {
        // KP (2026-11-08): Details' ••• always offers both.
        Button { Task { await library.setWatched(item, watched: true) } } label: {
          Label("Mark as Watched", systemImage: "checkmark.circle")
        }
        Button { Task { await library.setWatched(item, watched: false) } } label: {
          Label("Mark as Unwatched", systemImage: "eye.slash")
        }
      } else {
        let watched = library.isWatched(item)
        Button {
          Task { await library.setWatched(item, watched: !watched) }
        } label: {
          Label(watched ? "Mark Unwatched" : "Mark Watched", systemImage: watched ? "eye.slash" : "checkmark.circle")
        }
      }
      let isGroup = item.type == .show || item.type == .season
      let downloadState = isGroup ? app.downloads.state(forEpisodesOf: item) : app.downloads.state(for: item.ratingKey)
      // Apple TV has no downloads (KP, 2026-11-08).
      if !Self.isTV, item.type != .collection, downloadState == .none {
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
    if inContinueWatching, !item.isCatalogOnly {
      Divider()
      Button(role: .destructive) {
        Task { await library.removeFromContinueWatching(item) }
      } label: {
        Label("Remove", systemImage: "minus.circle")
      }
    }
  }
}
