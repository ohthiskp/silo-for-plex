import AstraKit
import SwiftUI

/// Movies or Shows from the top bar: the filter chips, the count and six
/// posters across, under the bar.
struct TVLibraryGridPage: View {
  var library: LibraryStore
  /// "movie" or "show".
  var kind: String
  @Environment(\.tvScrolledDown) private var scrolledDown

  var body: some View {
    ScrollView(.vertical, showsIndicators: false) {
      TVLibraryBrowser(library: library, kind: kind)
        .padding(.horizontal, TVLayout.leading)
        .padding(.top, TVLayout.barSpace)
        .padding(.bottom, 120)
    }
    .scrollClipDisabled()
    .onScrollGeometryChange(for: Bool.self, of: { $0.contentOffset.y > 60 }) { _, down in scrolledDown(down) }
    .ignoresSafeArea(edges: .top)
    .astraPageBackground()
  }
}

/// The Plex Watchlist from the top bar.
struct TVWatchlistPage: View {
  var library: LibraryStore
  @Environment(\.tvScrolledDown) private var scrolledDown

  var body: some View {
    ScrollView(.vertical, showsIndicators: false) {
      TVWatchlistContent(library: library)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, TVLayout.leading)
        .padding(.top, TVLayout.barSpace)
        .padding(.bottom, 120)
    }
    .scrollClipDisabled()
    .onScrollGeometryChange(for: Bool.self, of: { $0.contentOffset.y > 60 }) { _, down in scrolledDown(down) }
    .ignoresSafeArea(edges: .top)
    .astraPageBackground()
  }
}

/// Six posters across inside the TV's 80 pt safe area and the page margins
/// (1920 pt wide on every Apple TV).
private enum TVGrid {
  static let columns = 6
  static let spacing: CGFloat = 40
  static let posterWidth: CGFloat = floor(
    (1920 - 80 * 2 - TVLayout.leading * 2 - spacing * CGFloat(columns - 1)) / CGFloat(columns))
  static var layout: [GridItem] { Array(repeating: GridItem(.fixed(posterWidth), spacing: spacing), count: columns) }
}

/// One kind of library: library, Unwatched and sort chips, the count, and the
/// poster grid loaded a page at a time.
private struct TVLibraryBrowser: View {
  var library: LibraryStore
  /// "movie" or "show".
  var kind: String

  @AppStorage("astra.tv.librarySort") private var sort = "addedAt:desc"
  @State private var sectionKey: String?
  @State private var unwatched = false
  @State private var items: [PlexMetadata] = []
  @State private var total: Int?
  @State private var loaded = 0
  @State private var reachedEnd = false
  @State private var loading = false

  private var sections: [PlexLibrarySection] { library.sections.filter { $0.type == kind } }
  private var section: PlexLibrarySection? { sections.first { $0.key == sectionKey } ?? sections.first }
  private var noun: String { kind == "show" ? "Shows" : "Movies" }

  private static let sorts: [(String, String)] = [
    ("addedAt:desc", "Recently Added"),
    ("titleSort", "Title (A–Z)"),
    ("originallyAvailableAt:desc", "Release Date"),
    ("audienceRating:desc", "Rating"),
    ("duration:desc", "Runtime"),
  ]

  private var sortTitle: String { Self.sorts.first { $0.0 == sort }?.1 ?? "Sort" }

  private var filters: [URLQueryItem] {
    unwatched ? [URLQueryItem(name: "unwatched", value: "1")] : []
  }

  private var reloadKey: String { "\(section?.key ?? "")|\(sort)|\(unwatched)" }

  var body: some View {
    VStack(alignment: .leading, spacing: 26) {
      HStack(spacing: 12) {
        if sections.count > 1 {
          ForEach(sections) { item in
            chip(item.title, selected: item.key == section?.key) { sectionKey = item.key }
          }
        }
        chip("All", selected: !unwatched) { unwatched = false }
        chip("Unwatched", selected: unwatched) { unwatched = true }
        Menu {
          Picker("Sort", selection: $sort) {
            ForEach(Self.sorts, id: \.0) { value, title in Text(title).tag(value) }
          }
        } label: {
          Label(sortTitle, systemImage: "arrow.up.arrow.down")
            .font(.system(size: 22, weight: .semibold))
            .padding(.horizontal, 24)
            .frame(height: 50)
        }
        .buttonStyle(TVGlassButtonStyle(chip: true))
      }
      .focusSection()

      Text(total.map { "\($0.formatted()) \(noun)" } ?? noun)
        .font(.system(size: 24, weight: .medium))
        .foregroundStyle(Astra.Color.muted)
        .contentTransition(.numericText())

      if sections.isEmpty {
        message("This Plex server has no \(noun.lowercased()) library.")
      } else if items.isEmpty && reachedEnd {
        message(unwatched ? "You've watched everything here." : "This library is empty.")
      } else if items.isEmpty {
        ProgressView().frame(maxWidth: .infinity).padding(.top, 80)
      } else {
        LazyVGrid(columns: TVGrid.layout, alignment: .leading, spacing: 56) {
          ForEach(items) { item in
            TVPosterCard(library: library, item: item, width: TVGrid.posterWidth)
              .onAppear { if item.id == items.last?.id { Task { await loadMore() } } }
          }
        }
      }
    }
    .task(id: reloadKey) {
      items = []
      loaded = 0
      reachedEnd = false
      total = nil
      async let count = countItems()
      await loadMore()
      total = await count
    }
  }

  private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(title)
        .font(.system(size: 22, weight: .semibold))
        .padding(.horizontal, 24)
        .frame(height: 50)
    }
    .buttonStyle(TVGlassButtonStyle(chip: true, selected: selected))
    .accessibilityAddTraits(selected ? .isSelected : [])
  }

  private func message(_ text: String) -> some View {
    Text(text)
      .font(.system(size: 26, weight: .medium))
      .foregroundStyle(Astra.Color.muted)
      .padding(.top, 40)
  }

  private func countItems() async -> Int? {
    guard let section else { return nil }
    return try? await library.client.libraryCount(sectionKey: section.key, filters: filters)
  }

  private func loadMore() async {
    guard let section, !loading, !reachedEnd else { return }
    loading = true
    defer { loading = false }
    let raw =
      (try? await library.client.libraryItems(sectionKey: section.key, sort: sort, start: loaded, filters: filters))
      ?? []
    reachedEnd = raw.isEmpty
    loaded += raw.count
    let page = library.shown(raw)
    items += page.filter { new in !items.contains { $0.id == new.id } }
  }
}

/// The Plex Watchlist as the same poster grid.
private struct TVWatchlistContent: View {
  var library: LibraryStore
  @Environment(AppModel.self) private var app

  var body: some View {
    let items = library.matchWatchlist(app.watchlistItems ?? [])
    VStack(alignment: .leading, spacing: 26) {
      if items.isEmpty {
        Text(app.watchlistItems == nil ? "Loading your Watchlist…" : "Your Watchlist is empty. Press + on any title to add it.")
          .font(.system(size: 26, weight: .medium))
          .foregroundStyle(Astra.Color.muted)
          .padding(.top, 40)
      } else {
        Text("\(items.count.formatted()) \(items.count == 1 ? "Title" : "Titles")")
          .font(.system(size: 24, weight: .medium))
          .foregroundStyle(Astra.Color.muted)
        LazyVGrid(columns: TVGrid.layout, alignment: .leading, spacing: 56) {
          ForEach(items) { TVPosterCard(library: library, item: $0, width: TVGrid.posterWidth) }
        }
      }
    }
    .task { await app.refreshWatchlist() }
  }
}
