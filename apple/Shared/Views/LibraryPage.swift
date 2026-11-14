import AstraKit
import SwiftUI

/// Astra (KP, 2026-11-07): the Library tab on iPhone and the Library page
/// on the Mac share these: Libraries · Watchlist · Downloads, and inside
/// Libraries a smaller Movies | Shows switch.
enum LibrarySegment: String, CaseIterable, Identifiable {
  case libraries, watchlist, downloads
  var id: String { rawValue }
  var title: String {
    switch self {
    case .libraries: "Libraries"
    case .watchlist: "Watchlist"
    case .downloads: "Downloads"
    }
  }
  var symbol: String {
    switch self {
    case .libraries: "square.stack"
    case .watchlist: "bookmark"
    case .downloads: "arrow.down.circle"
    }
  }
}

enum LibraryKind: String, CaseIterable, Identifiable {
  case movie, show
  var id: String { rawValue }
  var title: String { self == .movie ? "Movies" : "Shows" }
}

/// Libraries · Watchlist · Downloads in one glass capsule; the chosen one is lit.
struct LibrarySegmentPill: View {
  @Binding var segment: LibrarySegment
  @Environment(AppModel.self) private var app
  @Namespace private var pill

  var body: some View {
    HStack(spacing: 0) {
      ForEach(Self.segments) { item in
        Button {
          astraWithAnimation(Astra.Motion.base) { segment = item }
        } label: {
          HStack(spacing: 6) {
            Label(item.title, systemImage: item.symbol).labelStyle(.titleAndIcon)
            // Astra: how many downloads are running or waiting.
            if item == .downloads, !app.downloads.jobs.isEmpty {
              CountBadge(count: app.downloads.jobs.count)
            }
          }
          .astraFont(size: 14, weight: .semibold)
          .foregroundStyle(segment == item ? Astra.Color.ink : Astra.Color.muted)
          .frame(maxWidth: .infinity)
          .frame(height: 38 * Astra.Layout.controlScale)
          .background {
            if segment == item {
              Capsule().fill(Astra.Color.ink.opacity(0.16)).matchedGeometryEffect(id: "segment", in: pill)
            }
          }
          .contentShape(Capsule())
          .tvFocusLift(1.06)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(segment == item ? .isSelected : [])
      }
    }
    .padding(4)
    .astraGlass(in: Capsule(), variant: .clear)
    .astraGlassEdge(Capsule(), strength: 0.6)
    .tvFocusSection()
  }

  /// Apple TV has no downloads (nothing to watch offline on a TV).
  #if os(tvOS)
    static let segments: [LibrarySegment] = LibrarySegment.allCases.filter { $0 != .downloads }
  #else
    static let segments = LibrarySegment.allCases
  #endif
}

/// The smaller Movies | Shows switch inside Libraries.
struct LibraryKindSwitch: View {
  @Binding var kind: LibraryKind
  @Namespace private var kindPill

  var body: some View {
    HStack(spacing: 6) {
      ForEach(LibraryKind.allCases) { item in
        Button {
          astraWithAnimation(Astra.Motion.fast) { kind = item }
        } label: {
          Text(item.title)
            .astraFont(size: 13, weight: .semibold)
            .foregroundStyle(kind == item ? Astra.Color.onSelection : Astra.Color.ink)
            .padding(.horizontal, 16 * Astra.Layout.controlScale)
            .frame(height: 30 * Astra.Layout.controlScale)
            .background {
              if kind == item { Capsule().fill(Astra.Color.selection).matchedGeometryEffect(id: "kind", in: kindPill) }
            }
            .astraGlass(in: Capsule(), variant: .clear, interactive: true)
            .contentShape(Capsule())
            .tvFocusLift(1.08)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(kind == item ? .isSelected : [])
      }
    }
  }
}

/// A small white count, like the badge on an app icon (white and grey only).
struct CountBadge: View {
  var count: Int

  var body: some View {
    Text("\(count)")
      .astraFont(size: 11, weight: .bold)
      .monospacedDigit()
      .foregroundStyle(.black)
      .padding(.horizontal, 5)
      .frame(minWidth: 18, minHeight: 18)
      .background(Capsule().fill(.white))
      .contentTransition(.numericText())
      .accessibilityLabel("\(count) downloading")
  }
}

/// The Plex Watchlist as a poster grid, without a page or title.
/// Astra 4.0 (KP, 2026-11-08): the saved list shows at once, matched to the
/// server from memory; plex.tv is asked behind it. A spinner only when there
/// is nothing saved yet, and it always ends (list, empty state or error).
struct WatchlistContent: View {
  var library: LibraryStore

  @Environment(AppModel.self) private var app

  var body: some View {
    Group {
      if let saved = app.watchlistItems {
        let items = library.matchWatchlist(saved)
        if items.isEmpty {
          EmptyState(
            symbol: "bookmark", title: "Your Watchlist is empty",
            message: "Use + on any title to add it to your Plex Watchlist.")
        } else {
          VStack(alignment: .leading, spacing: 12) {
            if let error = app.watchlistError {
              Text("Showing your saved Watchlist. \(error)")
                .astraFont(.meta)
                .foregroundStyle(Astra.Color.muted)
            }
            grid(items)
          }
        }
      } else if let error = app.watchlistError {
        EmptyState(
          symbol: "exclamationmark.triangle", title: "Couldn't load your Watchlist", message: error,
          action: ("Try Again", { Task { await app.refreshWatchlist(force: true) } }))
      } else {
        ProgressView().astraControlSize(.large).frame(maxWidth: .infinity).padding(.vertical, 60)
      }
    }
    // Once per appearance; the + / ✓ buttons update the list locally.
    .task {
      async let index: Void = library.warmLibraryIndex()
      await app.refreshWatchlist()
      await index
    }
  }

  @ViewBuilder private func grid(_ items: [PlexMetadata]) -> some View {
    // Big screens (Mac, Apple TV): adaptive columns sized by Astra.Layout.posterMinWidth.
    #if os(macOS) || os(tvOS)
      LazyVGrid(columns: posterColumns, alignment: .leading, spacing: 26) {
        ForEach(items) { PosterCard(library: library, item: $0) }
      }
    #else
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 14) {
        ForEach(items) { PosterCard(library: library, item: $0, width: 108) }
      }
    #endif
  }
}

#if os(macOS) || os(tvOS)
  /// The Mac (and Apple TV) Library page, laid out like the iPhone Library tab: a title,
  /// Libraries · Watchlist · Downloads, and Movies | Shows inside Libraries.
  struct LibraryPage: View {
    var library: LibraryStore

    @AppStorage("astra.library.segment") private var segment: LibrarySegment = .libraries
    @AppStorage("astra.library.kind") private var kind: LibraryKind = .movie

    var body: some View {
      AstraPage {
        AstraSectionHeader(title: "Library")
        LibrarySegmentPill(segment: $segment)
          .frame(maxWidth: 520 * Astra.Layout.controlScale)
        switch segment {
        case .libraries:
          LibraryKindSwitch(kind: $kind)
          LibraryGridContent(library: library, kind: kind.rawValue).id(kind.rawValue)
        case .watchlist:
          WatchlistContent(library: library)
        case .downloads:
          DownloadsContent()
        }
      }
      .astraAnimation(Astra.Motion.base, value: segment)
    }
  }
#endif
