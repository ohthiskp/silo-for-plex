// Movies, Shows and Watchlist on Apple TV, laid out like Silo Apple's tvOS
// library grid (https://github.com/Silo-Server/silo-apple, AGPL-3.0-or-later,
// Copyright (C) 2026 Silo Media L.L.C. and contributors).

import AstraKit
import SwiftUI

/// The poster width for `columns` posters across the screen inside Silo's
/// 88 pt side margins, so nothing runs off the edge (KP, 2026-11-09).
private func gridPosterWidth(screen: CGFloat, columns: Int = TVMetrics.gridColumns) -> CGFloat {
  let usable = screen - TVMetrics.safeAreaX * 2 - TVMetrics.gridColumnSpacing * CGFloat(columns - 1)
  return floor(usable / CGFloat(columns))
}

/// A grid of posters under the top bar: a row of chips (library, sort) and
/// six posters across.
private struct TVPosterGrid<Header: View>: View {
  var library: LibraryStore
  var items: [PlexMetadata]
  var onLast: (() -> Void)? = nil
  @ViewBuilder var header: Header

  var body: some View {
    GeometryReader { proxy in
      let width = gridPosterWidth(screen: proxy.size.width)
      ScrollView(.vertical, showsIndicators: false) {
        VStack(alignment: .leading, spacing: 32) {
          header
          LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(width), spacing: TVMetrics.gridColumnSpacing), count: TVMetrics.gridColumns),
            alignment: .leading,
            spacing: TVMetrics.gridRowSpacing
          ) {
            ForEach(items) { item in
              TVPosterCard(library: library, item: item, width: width)
                .onAppear { if item.id == items.last?.id { onLast?() } }
            }
          }
        }
        .padding(.horizontal, TVMetrics.safeAreaX)
        .padding(.top, TVMetrics.pageTopInset)
        .padding(.bottom, 120)
      }
      .scrollClipDisabled()
    }
    .ignoresSafeArea()
  }
}

/// Movies or Shows: every title in the library, newest first, loaded a page at a time.
struct TVLibraryGrid: View {
  var library: LibraryStore
  /// "movie" or "show".
  var kind: String

  @State private var sectionKey: String?
  @State private var items: [PlexMetadata] = []
  @State private var reachedEnd = false
  @State private var loaded = 0
  @State private var loading = false
  @AppStorage("astra.tv.librarySort") private var sort = "addedAt:desc"

  private var sections: [PlexLibrarySection] { library.sections.filter { $0.type == kind } }
  private var section: PlexLibrarySection? { sections.first { $0.key == sectionKey } ?? sections.first }

  private static let sorts: [(String, String)] = [
    ("addedAt:desc", "Recently Added"),
    ("titleSort", "A–Z"),
    ("originallyAvailableAt:desc", "Release Date"),
    ("audienceRating:desc", "Rating"),
  ]

  var body: some View {
    TVPosterGrid(library: library, items: items, onLast: { Task { await loadMore() } }) {
      VStack(alignment: .leading, spacing: 18) {
        HStack(spacing: 12) {
          if sections.count > 1 {
            ForEach(sections) { item in
              TVFilterChip(title: item.title, selected: item.key == section?.key) { sectionKey = item.key }
            }
            Divider().frame(height: 40).padding(.horizontal, 8)
          }
          ForEach(Self.sorts, id: \.0) { value, title in
            TVFilterChip(title: title, selected: sort == value) { sort = value }
          }
        }
        .focusSection()
        if sections.isEmpty {
          message("This Plex server has no \(kind == "show" ? "shows" : "movies") library.")
        } else if items.isEmpty && reachedEnd {
          message("This library is empty.")
        } else if items.isEmpty {
          ProgressView().frame(maxWidth: .infinity).padding(.top, 80)
        }
      }
    }
    .task(id: "\(section?.key ?? "")|\(sort)") {
      items = []
      loaded = 0
      reachedEnd = false
      await loadMore()
    }
  }

  private func message(_ text: String) -> some View {
    Text(text)
      .font(.system(size: 26, weight: .medium))
      .foregroundStyle(TVColor.secondaryText)
      .padding(.top, 60)
  }

  private func loadMore() async {
    guard let section, !loading, !reachedEnd else { return }
    loading = true
    defer { loading = false }
    let raw = (try? await library.client.libraryItems(sectionKey: section.key, sort: sort, start: loaded)) ?? []
    reachedEnd = raw.isEmpty
    loaded += raw.count
    let page = library.shown(raw)
    items += page.filter { new in !items.contains { $0.id == new.id } }
  }
}

/// The Plex Watchlist as a poster grid.
struct TVWatchlistGrid: View {
  var library: LibraryStore
  @Environment(AppModel.self) private var app

  var body: some View {
    let items = library.matchWatchlist(app.watchlistItems ?? [])
    TVPosterGrid(library: library, items: items) {
      if items.isEmpty {
        Text(app.watchlistItems == nil ? "Loading your Watchlist…" : "Your Watchlist is empty. Press + on any title to add it.")
          .font(.system(size: 26, weight: .medium))
          .foregroundStyle(TVColor.secondaryText)
          .padding(.top, 60)
      }
    }
    .task { await app.refreshWatchlist() }
  }
}

/// A chip in the grid's header row: focused white, chosen grey.
private struct TVFilterChip: View {
  var title: String
  var selected: Bool
  var action: () -> Void

  var body: some View {
    Button(action: action) { TVFilterChipLabel(title: title, selected: selected) }
      .buttonStyle(TVPlainButtonStyle())
      .accessibilityAddTraits(selected ? .isSelected : [])
  }
}

private struct TVFilterChipLabel: View {
  var title: String
  var selected: Bool
  @Environment(\.isFocused) private var focused

  var body: some View {
    Text(title)
      .font(.system(size: 22, weight: .semibold))
      .foregroundStyle(focused ? Color.black : (selected ? Color.white : Color.white.opacity(0.62)))
      .padding(.horizontal, 22)
      .padding(.vertical, 10)
      .background(Capsule().fill(focused ? Color.white : (selected ? TVColor.selectedFill : TVColor.restingFill)))
      .scaleEffect(focused ? 1.04 : 1)
      .animation(.easeOut(duration: 0.15), value: focused)
  }
}
