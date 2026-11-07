import AstraKit
import SwiftUI

/// Astra: the iPhone Libraries tab (KP's mockups, 2026-11-07). A large title,
/// Settings at the top right, a Movies / Shows / Downloads switch, then the
/// chosen library with its filters, sort sheet and grid or list.
struct LibrariesView: View {
  var library: LibraryStore

  enum Segment: String, CaseIterable, Identifiable {
    case movies, shows, downloads
    var id: String { rawValue }
    var title: String {
      switch self {
      case .movies: "Movies"
      case .shows: "Shows"
      case .downloads: "Downloads"
      }
    }
    var symbol: String {
      switch self {
      case .movies: "film"
      case .shows: "tv"
      case .downloads: "arrow.down.circle"
      }
    }
  }

  @AppStorage("astra.libraries.segment") private var segment: Segment = .movies
  @State private var showSettings = false
  @Namespace private var pill

  var body: some View {
    ScrollView(.vertical) {
      VStack(alignment: .leading, spacing: 16) {
        HStack(alignment: .center) {
          Text(segment.title)
            .font(.system(size: 34, weight: .bold))
            .foregroundStyle(Astra.Color.ink)
            .contentTransition(.opacity)
          Spacer()
          Button {
            showSettings = true
          } label: {
            Image(systemName: "gearshape.fill")
          }
          .astraIconButton(size: 40)
          .accessibilityLabel("Settings")
        }
        segmentPill
        switch segment {
        case .movies:
          LibraryBrowser(library: library, kind: "movie").id("movie")
        case .shows:
          LibraryBrowser(library: library, kind: "show").id("show")
        case .downloads:
          DownloadsContent()
        }
      }
      .padding(.horizontal, 16)
      .padding(.top, 8)
      .padding(.bottom, 100)
    }
    .scrollIndicators(.never)
    .background(Astra.Color.bg.ignoresSafeArea())
    .animation(Astra.Motion.base, value: segment)
    .sheet(isPresented: $showSettings) {
      NavigationStack {
        SettingsView()
          .navigationTitle("Settings")
          .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { showSettings = false } }
          }
      }
    }
  }

  /// Movies · Shows · Downloads in one glass capsule; the chosen one is lit.
  private var segmentPill: some View {
    HStack(spacing: 0) {
      ForEach(Segment.allCases) { item in
        Button {
          withAnimation(Astra.Motion.base) { segment = item }
        } label: {
          Label(item.title, systemImage: item.symbol)
            .font(.system(size: 14, weight: .semibold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(segment == item ? Astra.Color.ink : Astra.Color.muted)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background {
              if segment == item {
                Capsule().fill(.white.opacity(0.16)).matchedGeometryEffect(id: "segment", in: pill)
              }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(segment == item ? .isSelected : [])
      }
    }
    .padding(4)
    .astraGlass(in: Capsule(), variant: .clear)
    .astraGlassEdge(Capsule(), strength: 0.6)
  }
}

/// How the library is sorted (the sort sheet's rows).
enum LibrarySort: String, CaseIterable, Identifiable {
  case title = "titleSort"
  case releaseNewest = "originallyAvailableAt:desc"
  case releaseOldest = "originallyAvailableAt"
  case addedNewest = "addedAt:desc"
  case addedOldest = "addedAt"
  case rating = "audienceRating:desc"
  case longest = "duration:desc"
  case shortest = "duration"

  var id: String { rawValue }

  var title: String {
    switch self {
    case .title: "Title (A–Z)"
    case .releaseNewest: "Release Date (Newest)"
    case .releaseOldest: "Release Date (Oldest)"
    case .addedNewest: "Date Added (Newest)"
    case .addedOldest: "Date Added (Oldest)"
    case .rating: "Rating"
    case .longest: "Runtime (Longest)"
    case .shortest: "Runtime (Shortest)"
    }
  }

  var symbol: String {
    switch self {
    case .title, .releaseNewest, .releaseOldest: "arrow.up.arrow.down"
    case .addedNewest, .addedOldest: "calendar"
    case .rating: "star"
    case .longest, .shortest: "clock"
    }
  }
}

/// One kind of library (movies or shows): filter chips, a count, and a poster
/// grid or list loaded a page at a time.
struct LibraryBrowser: View {
  var library: LibraryStore
  /// "movie" or "show".
  var kind: String

  @Environment(\.openItem) private var openItem
  @AppStorage("astra.libraries.sort") private var sort: LibrarySort = .addedNewest
  @AppStorage("astra.libraries.grid") private var grid = true
  @State private var sectionKey: String?
  @State private var genre: PlexFilterValue?
  @State private var genres: [PlexFilterValue] = []
  @State private var only4K = false
  @State private var onlyHDR = false
  @State private var unwatched = false
  @State private var showSort = false
  @State private var items: [PlexMetadata] = []
  @State private var total: Int?
  @State private var loaded = 0
  @State private var reachedEnd = false
  @State private var loading = false

  private var sections: [PlexLibrarySection] { library.sections.filter { $0.type == kind } }
  private var section: PlexLibrarySection? { sections.first { $0.key == sectionKey } ?? sections.first }
  private var isMovies: Bool { kind == "movie" }
  private var noun: String { isMovies ? "Movies" : "Shows" }

  private var filters: [URLQueryItem] {
    var query: [URLQueryItem] = []
    if let genre { query.append(.init(name: "genre", value: genre.key)) }
    if unwatched { query.append(.init(name: "unwatched", value: "1")) }
    if isMovies, only4K { query.append(.init(name: "resolution", value: "4k")) }
    if isMovies, onlyHDR { query.append(.init(name: "hdr", value: "1")) }
    return query
  }

  /// Everything that changes what's listed; a change reloads from the top.
  private var reloadKey: String {
    "\(section?.key ?? "")|\(sort.rawValue)|\(filters.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&"))"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      chips
      HStack {
        Text(total.map { "\($0.formatted()) \(noun)" } ?? noun)
          .font(.system(size: 15, weight: .medium))
          .foregroundStyle(Astra.Color.muted)
          .contentTransition(.numericText())
        Spacer()
        layoutToggle
      }

      if sections.isEmpty {
        EmptyState(
          symbol: isMovies ? "film" : "tv", title: "No \(noun.lowercased()) library",
          message: "This Plex server has no \(noun.lowercased()) library.")
      } else if items.isEmpty && reachedEnd {
        EmptyState(symbol: "line.3.horizontal.decrease", title: "Nothing matches", message: "Try other filters.")
      } else if grid {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 12) {
          ForEach(items) { item in
            GridPoster(library: library, item: item)
              .onAppear { if item.id == items.last?.id { Task { await loadMore() } } }
          }
        }
      } else {
        LazyVStack(spacing: 10) {
          ForEach(items) { item in
            ListRow(library: library, item: item)
              .onAppear { if item.id == items.last?.id { Task { await loadMore() } } }
          }
        }
      }
      if loading { ProgressView().frame(maxWidth: .infinity).padding(.vertical, 12) }
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
    .task(id: section?.key) {
      guard let key = section?.key else { return }
      genres = (try? await library.client.genres(sectionKey: key)) ?? []
    }
    .sheet(isPresented: $showSort) {
      SortSheet(sort: $sort) { showSort = false }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
  }

  // MARK: Filters

  private var chips: some View {
    ScrollView(.horizontal) {
      HStack(spacing: 8) {
        Menu {
          if sections.count > 1 {
            Picker("Library", selection: Binding(get: { section?.key ?? "" }, set: { sectionKey = $0 })) {
              ForEach(sections) { Text($0.title).tag($0.key) }
            }
          }
          Picker("Genre", selection: $genre) {
            Text("All").tag(PlexFilterValue?.none)
            ForEach(genres) { Text($0.title).tag(PlexFilterValue?.some($0)) }
          }
        } label: {
          HStack(spacing: 6) {
            Text(genre?.title ?? "All")
            Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold))
          }
          .chip(selected: genre != nil)
        }
        if isMovies {
          Button { only4K.toggle() } label: { Text("4K").chip(selected: only4K) }.buttonStyle(.plain)
          Button { onlyHDR.toggle() } label: { Text("HDR").chip(selected: onlyHDR) }.buttonStyle(.plain)
        }
        Button { unwatched.toggle() } label: { Text("Unwatched").chip(selected: unwatched) }.buttonStyle(.plain)
        Button {
          showSort = true
        } label: {
          Image(systemName: "arrow.up.arrow.down").chip(selected: false)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sort: \(sort.title)")
      }
      .padding(.vertical, 2)
    }
    .scrollIndicators(.never)
    .animation(Astra.Motion.fast, value: filters)
  }

  private var layoutToggle: some View {
    HStack(spacing: 2) {
      ForEach([true, false], id: \.self) { isGrid in
        Button {
          withAnimation(Astra.Motion.base) { grid = isGrid }
        } label: {
          Image(systemName: isGrid ? "square.grid.2x2" : "list.bullet")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(grid == isGrid ? Astra.Color.ink : Astra.Color.muted)
            .frame(width: 40, height: 32)
            .background { if grid == isGrid { Capsule().fill(.white.opacity(0.14)) } }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isGrid ? "Grid" : "List")
      }
    }
  }

  // MARK: Loading

  private func countItems() async -> Int? {
    guard let section else { return nil }
    return try? await library.client.libraryCount(sectionKey: section.key, filters: filters)
  }

  private func loadMore() async {
    guard let section, !loading, !reachedEnd else { return }
    loading = true
    defer { loading = false }
    let raw =
      (try? await library.client.libraryItems(
        sectionKey: section.key, sort: sort.rawValue, start: loaded, filters: filters)) ?? []
    reachedEnd = raw.isEmpty
    loaded += raw.count
    // Library Quality (4K swaps in a movie's 4K copy); paging counts the raw page.
    let page = library.shown(raw)
    items += page.filter { new in !items.contains { $0.id == new.id } }
  }
}

extension View {
  /// A filter chip: clear glass, or solid white with black text when on.
  fileprivate func chip(selected: Bool) -> some View {
    self
      .font(.system(size: 14, weight: .semibold))
      .foregroundStyle(selected ? Color.black : Astra.Color.ink)
      .padding(.horizontal, 16)
      .frame(height: 36)
      .background { if selected { Capsule().fill(.white) } }
      .astraGlass(in: Capsule(), variant: .clear, interactive: true)
      .contentShape(Capsule())
  }
}

/// A poster filling its grid column (2:3), opening details, with the long-press menu.
private struct GridPoster: View {
  var library: LibraryStore
  var item: PlexMetadata
  @Environment(\.openItem) private var openItem

  var body: some View {
    Button {
      openItem(item)
    } label: {
      Color.clear
        .aspectRatio(2 / 3, contentMode: .fit)
        .overlay {
          GeometryReader { geo in
            ArtworkImage(library: library, item: item, kind: .poster, width: geo.size.width, height: geo.size.height)
              .frame(width: geo.size.width, height: geo.size.height)
          }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Astra.Color.hairline))
        .overlay(alignment: .topTrailing) {
          if library.isWatched(item) {
            Image(systemName: "checkmark.circle.fill")
              .font(.system(size: 16, weight: .semibold))
              .foregroundStyle(.white, .black.opacity(0.5))
              .padding(6)
          }
        }
        .contentShape(Rectangle())
    }
    .buttonStyle(AstraCardButtonStyle())
    .accessibilityLabel(item.displayTitle)
    .itemMenu(library: library, item: item)
  }
}

/// The list layout: a small poster, the title, and year · runtime.
private struct ListRow: View {
  var library: LibraryStore
  var item: PlexMetadata
  @Environment(\.openItem) private var openItem

  var body: some View {
    Button {
      openItem(item)
    } label: {
      HStack(spacing: 14) {
        ArtworkImage(library: library, item: item, kind: .poster, width: 56, height: 84)
          .frame(width: 56, height: 84)
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        VStack(alignment: .leading, spacing: 4) {
          Text(item.displayTitle).font(.system(size: 16, weight: .semibold)).foregroundStyle(Astra.Color.ink)
            .lineLimit(2)
          Text([item.year.map(String.init), item.durationLabel].compactMap { $0 }.joined(separator: " · "))
            .font(.system(size: 13)).foregroundStyle(Astra.Color.muted)
        }
        Spacer(minLength: 8)
        if library.isWatched(item) {
          Image(systemName: "checkmark.circle.fill").foregroundStyle(Astra.Color.muted)
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .itemMenu(library: library, item: item)
  }
}

/// The sort sheet: one row per order, the chosen one ticked.
private struct SortSheet: View {
  @Binding var sort: LibrarySort
  var close: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("Sort By").font(.system(size: 22, weight: .bold)).foregroundStyle(Astra.Color.ink)
        Spacer()
        Button(action: close) { Image(systemName: "xmark") }
          .astraIconButton(size: 36)
          .accessibilityLabel("Close")
      }
      .padding(.bottom, 6)
      ScrollView {
        VStack(spacing: 2) {
          ForEach(LibrarySort.allCases) { option in
            Button {
              sort = option
              close()
            } label: {
              HStack(spacing: 14) {
                Image(systemName: option.symbol).frame(width: 22)
                Text(option.title)
                Spacer()
                if sort == option { Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)) }
              }
              .font(.system(size: 16, weight: .medium))
              .foregroundStyle(Astra.Color.ink)
              .padding(.horizontal, 14)
              .frame(height: 48)
              .background {
                if sort == option {
                  RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.1))
                }
              }
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
          }
        }
      }
      .scrollIndicators(.never)
    }
    .padding(20)
  }
}
