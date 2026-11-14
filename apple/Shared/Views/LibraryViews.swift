import AstraKit
import SwiftUI

/// A page title in Didot, aligned to the page inset.
struct AstraSectionHeader<Trailing: View>: View {
  var title: String
  @ViewBuilder var trailing: () -> Trailing

  var body: some View {
    // Wraps under the title when the window is too narrow for one line.
    ViewThatFits(in: .horizontal) {
      HStack(alignment: .firstTextBaseline, spacing: Astra.Spacing.l) {
        titleText
        Spacer(minLength: Astra.Spacing.l)
        trailing()
      }
      VStack(alignment: .leading, spacing: Astra.Spacing.m) {
        titleText
        trailing()
      }
    }
  }

  private var titleText: some View {
    Text(title).astraDisplay(Astra.Layout.pageTitleSize, tracking: 6).lineLimit(1)
  }
}

extension AstraSectionHeader where Trailing == EmptyView {
  init(title: String) {
    self.init(title: title) { EmptyView() }
  }
}

/// A scrolling page that respects the safe area (title bar, status bar) and
/// aligns to the sidebar-aware page inset.
struct AstraPage<Content: View>: View {
  @ViewBuilder var content: () -> Content
  @Environment(\.contentLeading) private var leading

  var body: some View {
    ScrollView(.vertical) {
      VStack(alignment: .leading, spacing: Astra.Spacing.l) {
        content()
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.leading, leading)
      .padding(.trailing, Astra.Spacing.pageTrailing)
      .padding(.top, Astra.Spacing.pageTop)
      .padding(.bottom, 60)
    }
    .scrollIndicators(.never)
    .astraScrollEdges()
    .astraPageBackground()
  }
}

/// Sort for Movies and Shows: one glass capsule of four choices. The chosen
/// one is a white pill with an arrow for its order; clicking it again flips
/// the order (newest/oldest, A–Z/Z–A, highest/lowest).
struct SortControl: View {
  /// The Plex sort key, "field:desc" or "field" (ascending).
  @Binding var sort: String

  /// Plex field, name, icon, and the order it starts in.
  private static let fields: [(String, String, String, Bool)] = [
    ("addedAt", "Recently Added", "clock", true),
    ("titleSort", "Title", "textformat", false),
    ("originallyAvailableAt", "Release Date", "calendar", true),
    ("audienceRating", "Rating", "star", true),
  ]

  private var field: String { String(sort.split(separator: ":").first ?? "addedAt") }
  private var descending: Bool { sort.hasSuffix(":desc") }

  var body: some View {
    HStack(spacing: 2) {
      ForEach(Self.fields, id: \.0) { item in
        let chosen = field == item.0
        GlassChoice(
          title: item.1, symbol: item.2, selected: chosen,
          trailingSymbol: chosen ? (descending ? "arrow.down" : "arrow.up") : nil
        ) {
          let flip = chosen ? !descending : item.3
          sort = flip ? "\(item.0):desc" : item.0
        }
        .help(chosen ? "Click again to reverse the order" : "Sort by \(item.1)")
      }
    }
    .padding(4)
    .astraGlass(in: Capsule(), variant: .clear)
    .astraGlassEdge(Capsule(), strength: 0.6)
    .fixedSize()
    .transaction(value: sort) { $0.animation = nil }
  }
}

/// A row of choices on one clear glass capsule: the chosen one is a white
/// pill with dark text, the rest muted until the pointer is over them.
struct GlassChoices: View {
  /// (tag, title, SF Symbol).
  var options: [(String, String, String?)]
  @Binding var selection: String

  var body: some View {
    HStack(spacing: 2) {
      ForEach(options, id: \.0) { option in
        GlassChoice(title: option.1, symbol: option.2, selected: selection == option.0) { selection = option.0 }
      }
    }
    .padding(4)
    .astraGlass(in: Capsule(), variant: .clear)
    .astraGlassEdge(Capsule(), strength: 0.6)
    .fixedSize()
    .transaction(value: selection) { $0.animation = nil }
  }
}

struct GlassChoice: View {
  var title: String
  var symbol: String?
  var selected: Bool
  /// The chosen sort's order arrow.
  var trailingSymbol: String? = nil
  var action: () -> Void
  @State private var hovering = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 6) {
        if let symbol { Image(systemName: symbol).font(.system(size: 12, weight: .semibold)) }
        Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
        if let trailingSymbol {
          Image(systemName: trailingSymbol)
            .font(.system(size: 11, weight: .bold))
            .contentTransition(.symbolEffect(.replace))
        }
      }
      .padding(.horizontal, 14)
      .frame(height: 30)
      .foregroundStyle(selected ? Astra.Color.onTheme : (hovering ? Astra.Color.ink : Astra.Color.muted))
      .background {
        if selected {
          Capsule().fill(Astra.Color.theme)
        } else if hovering {
          Capsule().fill(Astra.Color.ink.opacity(0.1))
        }
      }
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    #if os(macOS)
      .onHover { hovering = $0 }
    #endif
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}

/// A quiet centred message for empty and unavailable states.
struct EmptyState: View {
  var symbol: String
  var title: String
  var message: String
  /// An optional button under the message, such as Try Again.
  var action: (title: String, run: () -> Void)? = nil

  var body: some View {
    VStack(spacing: Astra.Spacing.s) {
      Image(systemName: symbol).font(.system(size: 34, weight: .light)).foregroundStyle(Astra.Color.muted)
      Text(title).astraFont(size: 17, weight: .semibold).foregroundStyle(Astra.Color.ink)
      Text(message).astraFont(.meta).foregroundStyle(Astra.Color.muted).multilineTextAlignment(.center)
        .frame(maxWidth: 380)
      if let action {
        Button(action.title, action: action.run)
          .astraSecondaryButton()
          .padding(.top, Astra.Spacing.s)
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 80)
  }
}

let posterColumns = [
  GridItem(
    .adaptive(minimum: Astra.Layout.posterMinWidth, maximum: Astra.Layout.posterMinWidth + 30), spacing: 18,
    alignment: .top)
]

/// Movies or Shows on the Mac Library page: every library of that kind as
/// one poster grid, loaded a page at a time. With several libraries a picker
/// chooses between them; a second picker sorts.
struct LibraryGridContent: View {
  var library: LibraryStore
  /// "movie" or "show".
  var kind: String
  /// The page title. Given, the title, the count and the sort share one
  /// header row (the Mac's Movies and Shows pages).
  var title: String? = nil

  @State private var sectionKey: String?
  @State private var total: Int?
  @State private var items: [PlexMetadata] = []
  @State private var reachedEnd = false
  /// Items read from the server so far (the next page starts here).
  @State private var loaded = 0
  @State private var loading = false
  @AppStorage("astra.libraries.macSort") private var sort = "addedAt:desc"

  private var sections: [PlexLibrarySection] { library.sections.filter { $0.type == kind } }
  private var section: PlexLibrarySection? {
    sections.first { $0.key == sectionKey } ?? sections.first
  }
  private var noun: String { kind == "show" ? "Shows" : "Movies" }

  var body: some View {
    VStack(alignment: .leading, spacing: Astra.Spacing.l) {
      // KP (2026-11-13): "make the sort by view way sleeker and modern",
      // then "still make it better": the title and how many titles on the
      // left, the sort on the right of the same row; a second click on the
      // chosen sort flips its order.
      if let title {
        ViewThatFits(in: .horizontal) {
          HStack(alignment: .bottom, spacing: Astra.Spacing.l) {
            titleBlock(title)
            Spacer(minLength: Astra.Spacing.l)
            SortControl(sort: $sort)
          }
          VStack(alignment: .leading, spacing: Astra.Spacing.m) {
            titleBlock(title)
            SortControl(sort: $sort)
          }
        }
      } else {
        SortControl(sort: $sort)
      }
      if sections.count > 1 {
        GlassChoices(
          options: sections.map { ($0.key, $0.title, nil) },
          selection: Binding(get: { section?.key ?? "" }, set: { sectionKey = $0 }))
      }

      if sections.isEmpty {
        EmptyState(
          symbol: kind == "show" ? "tv" : "film", title: "No \(noun.lowercased()) library",
          message: "This Plex server has no \(noun.lowercased()) library.")
      } else if items.isEmpty && reachedEnd {
        EmptyState(symbol: "square.stack", title: "Nothing here yet", message: "This library is empty.")
      } else {
        LazyVGrid(columns: posterColumns, alignment: .leading, spacing: 26) {
          ForEach(items) { item in
            PosterCard(library: library, item: item)
              .onAppear {
                if item.id == items.last?.id { Task { await loadMore() } }
              }
          }
        }
      }
      if loading { ProgressView().frame(maxWidth: .infinity) }
    }
    .task(id: section?.key) {
      total = nil
      guard let section else { return }
      total = try? await library.client.libraryCount(sectionKey: section.key)
    }
    .task(id: "\(section?.key ?? "")|\(sort)") {
      items = []
      loaded = 0
      reachedEnd = false
      await loadMore()
    }
  }

  private func titleBlock(_ title: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title).astraDisplay(Astra.Layout.pageTitleSize, tracking: 6).lineLimit(1)
      Text(total.map { "\($0) \($0 == 1 ? String(noun.dropLast()) : noun)" } ?? " ")
        .astraFont(size: 14, weight: .medium)
        .foregroundStyle(Astra.Color.muted)
        .monospacedDigit()
        .contentTransition(.numericText())
    }
  }

  private func loadMore() async {
    guard let section, !loading, !reachedEnd else { return }
    loading = true
    defer { loading = false }
    let raw = (try? await library.client.libraryItems(sectionKey: section.key, sort: sort, start: loaded)) ?? []
    reachedEnd = raw.isEmpty
    // Astra: Library Quality (4K swaps in a movie's 4K copy); paging counts the raw page.
    loaded += raw.count
    let page = library.shown(raw)
    items += page.filter { new in !items.contains { $0.id == new.id } }
  }
}

struct SearchView: View {
  var library: LibraryStore

  /// Astra (KP, 2026-11-07): the same search as the iPhone, laid out for
  /// the Mac window: All / Movies / Shows / People, titles from the library
  /// index at once, the server's answer added after, people from TMDB only.
  enum Scope: String, CaseIterable, Identifiable {
    case all, movies, shows, people
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
  }

  @State private var query = ""
  @State private var scope: Scope = .all
  @State private var results: [PlexMetadata] = []
  @State private var people: [TMDBPerson] = []
  @State private var searched = false
  @State private var peopleSearched = false
  /// A person picked from the results: their TMDB filmography replaces the results.
  @State private var person: TMDBPerson?
  @State private var credits: [PlexMetadata] = []
  @State private var creditsLoaded = false
  /// KP (2026-11-09): 4K, HD, Dolby Atmos, Dolby Vision and Bollywood chips.
  @State private var filters: Set<SearchFilter> = []
  @State private var languages: [String: String] = [:]
  @State private var fullCopies: [String: PlexMetadata] = [:]
  @State private var verifying = false
  @AppStorage("astra.search.recent") private var recentStore = ""
  @FocusState private var focused: Bool
  @Namespace private var scopePill

  private var recent: [String] { recentStore.split(separator: "\n").map(String.init) }
  private var typed: Bool { query.trimmingCharacters(in: .whitespaces).count >= 2 }

  private var shownResults: [PlexMetadata] {
    let scoped: [PlexMetadata] =
      switch scope {
      case .all: results
      case .movies: results.filter { $0.type == .movie }
      case .shows: results.filter { $0.type == .show || $0.type == .season || $0.type == .episode }
      case .people: []
      }
    guard !filters.isEmpty else { return scoped }
    return scoped.filter { item in
      SearchFilter.matches(
        fullCopies[item.ratingKey] ?? item, language: item.tmdbKey.flatMap { languages[$0] }, all: filters) == true
    }
  }

  private var verifyKey: String {
    "\(filters.map(\.rawValue).sorted())|\(results.map(\.ratingKey).joined(separator: ","))"
  }

  private var shownPeople: [TMDBPerson] { scope == .all || scope == .people ? people : [] }

  var body: some View {
    AstraPage {
      #if os(tvOS)
        // Apple TV: the system's own search field (it opens the TV keyboard
        // and draws its own focus), without a glass capsule around it.
        TextField("Movies, shows and people", text: $query)
          .astraFont(size: 18)
          .focused($focused)
          .submitLabel(.search)
          .onSubmit { remember(query) }
          .frame(maxWidth: 620 * Astra.Layout.controlScale)
      #else
        HStack(spacing: 12) {
          Image(systemName: "magnifyingglass").foregroundStyle(Astra.Color.muted)
          TextField("Movies, shows and people", text: $query)
            .textFieldStyle(.plain)
            .astraFont(size: 18)
            .focused($focused)
            .submitLabel(.search)
            .onSubmit { remember(query) }
          if !query.isEmpty {
            Button {
              query = ""
            } label: {
              Image(systemName: "xmark.circle.fill").foregroundStyle(Astra.Color.muted)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Clear Search")
          }
        }
        .padding(.horizontal, 20)
        .frame(height: 52)
        .frame(maxWidth: 620)
        .astraGlass(in: Capsule())
      #endif

      scopes
      filterChips

      if let person {
        personPage(person)
      } else if typed {
        resultsSection
      } else {
        idle
      }
    }
    .onAppear { focused = true }
    .task(id: query) {
      person = nil
      await runSearch()
    }
    .task(id: verifyKey) { await readTracks() }
    .task(id: person?.id) {
      credits = []
      creditsLoaded = false
      guard let person else { return }
      let found = (try? await library.tmdb?.credits(of: person.id)) ?? []
      guard !Task.isCancelled else { return }
      credits = await library.withServer(found)
      creditsLoaded = true
    }
  }

  private var scopes: some View {
    HStack(spacing: 8) {
      ForEach(Scope.allCases) { item in
        Button {
          astraWithAnimation(Astra.Motion.fast) {
            scope = item
            person = nil
          }
        } label: {
          Text(item.title)
            .astraFont(size: 13, weight: .semibold)
            .foregroundStyle(scope == item ? Color.black : Astra.Color.ink)
            .padding(.horizontal, 18 * Astra.Layout.controlScale)
            .frame(height: 32 * Astra.Layout.controlScale)
            .background {
              if scope == item { Capsule().fill(.white).matchedGeometryEffect(id: "scope", in: scopePill) }
            }
            .astraGlass(in: Capsule(), variant: .clear, interactive: true)
            .contentShape(Capsule())
            .tvFocusLift()
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(scope == item ? .isSelected : [])
      }
    }
    .tvFocusSection()
  }

  private var filterChips: some View {
    HStack(spacing: 8) {
      ForEach(SearchFilter.allCases) { filter in
        let on = filters.contains(filter)
        Button {
          astraWithAnimation(Astra.Motion.fast) {
            if on { filters.remove(filter) } else { filters.insert(filter) }
          }
        } label: {
          Text(filter.title)
            .astraFont(size: 13, weight: .semibold)
            .foregroundStyle(on ? Color.black : Astra.Color.ink)
            .padding(.horizontal, 16 * Astra.Layout.controlScale)
            .frame(height: 30 * Astra.Layout.controlScale)
            .background { if on { Capsule().fill(.white) } }
            .astraGlass(in: Capsule(), variant: .clear, interactive: true)
            .contentShape(Capsule())
            .tvFocusLift()
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
      }
    }
    .tvFocusSection()
  }

  // MARK: Nothing typed

  @ViewBuilder private var idle: some View {
    if !recent.isEmpty {
      HStack {
        sectionTitle("Recent Searches")
        Spacer()
        Button("Clear") { recentStore = "" }
          .buttonStyle(.plain)
          .astraFont(size: 13, weight: .medium)
          .foregroundStyle(Astra.Color.muted)
      }
      .frame(maxWidth: 620)
      HStack(spacing: 8) {
        ForEach(recent.prefix(6), id: \.self) { text in
          Button {
            query = text
          } label: {
            Label(text, systemImage: "clock.arrow.circlepath")
              .astraFont(size: 13, weight: .medium)
              .foregroundStyle(Astra.Color.ink)
              .padding(.horizontal, 14 * Astra.Layout.controlScale)
              .frame(height: 30 * Astra.Layout.controlScale)
              .astraGlass(in: Capsule(), variant: .clear, interactive: true)
              .contentShape(Capsule())
              .tvFocusLift()
          }
          .buttonStyle(.plain)
        }
      }
    }
    let popular = Array(library.topTenAll.prefix(12))
    if !popular.isEmpty {
      sectionTitle("Popular Right Now")
      LazyVGrid(columns: posterColumns, alignment: .leading, spacing: 26) {
        ForEach(popular) { PosterCard(library: library, item: $0) }
      }
    }
  }

  private func sectionTitle(_ text: String) -> some View {
    Text(text).astraFont(.rowTitle).foregroundStyle(Astra.Color.ink).padding(.top, 6)
  }

  // MARK: Results

  @ViewBuilder private var resultsSection: some View {
    let titles = shownResults
    let found = shownPeople
    let done = searched && peopleSearched && !verifying
    if !done && titles.isEmpty && found.isEmpty {
      ProgressView().astraControlSize(.large).frame(maxWidth: .infinity).padding(.vertical, 40)
    } else if titles.isEmpty && found.isEmpty {
      EmptyState(
        symbol: "magnifyingglass", title: "No results",
        message: scope == .people
          ? "No one matches “\(query)”."
          : filters.isEmpty
            ? "Nothing matches “\(query)”."
            : "Nothing on your server matches “\(query)” with these filters.")
    } else {
      if !found.isEmpty {
        if scope == .all { sectionTitle("People") }
        ScrollView(.horizontal) {
          LazyHStack(alignment: .top, spacing: 18) {
            ForEach(found) { candidate in
              Button {
                remember(query)
                astraWithAnimation(Astra.Motion.base) { person = candidate }
              } label: {
                PersonCircle(person: candidate)
              }
              .buttonStyle(.plain)
            }
          }
        }
        .scrollIndicators(.never)
        .scrollClipDisabled()
      }
      if !titles.isEmpty {
        if scope == .all, !found.isEmpty { sectionTitle("Movies & Shows") }
        LazyVGrid(columns: posterColumns, alignment: .leading, spacing: 26) {
          ForEach(titles) { PosterCard(library: library, item: $0) }
        }
        .astraAnimation(Astra.Motion.base, value: titles.map(\.id))
      }
    }
  }

  @ViewBuilder private func personPage(_ person: TMDBPerson) -> some View {
    HStack(spacing: 16) {
      Button {
        astraWithAnimation(Astra.Motion.base) { self.person = nil }
      } label: {
        Image(systemName: "chevron.left")
      }
      .astraIconButton(size: 34, variant: .clear)
      .accessibilityLabel("Back to Results")
      RemoteImage(url: TMDBArtwork.url(person.profilePath, size: "w342"))
        .frame(width: 64, height: 80)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      VStack(alignment: .leading, spacing: 4) {
        Text(person.name).astraFont(size: 24, weight: .bold).foregroundStyle(Astra.Color.ink)
        Text(person.role).astraFont(size: 14).foregroundStyle(Astra.Color.muted)
      }
    }
    if !creditsLoaded {
      ProgressView().frame(maxWidth: .infinity).padding(.vertical, 30)
    } else if credits.isEmpty {
      EmptyState(
        symbol: "person.crop.rectangle", title: "Nothing here", message: "TMDB has no movies or shows for \(person.name).")
    } else {
      // Astra (KP): their whole filmography from TMDB; titles on the server
      // play, the rest open with Play greyed out.
      LazyVGrid(columns: posterColumns, alignment: .leading, spacing: 26) {
        ForEach(credits) { PosterCard(library: library, item: $0) }
      }
    }
  }

  // MARK: Searching

  /// Astra (KP, 2026-11-07: "just use TMDB… don't load anything from
  /// Plex"): one TMDB search for titles and people, ranked exact match and
  /// most popular first (`SearchRank`). Titles on the server are matched with
  /// the library index on the device and play; the rest open with Play
  /// greyed out. A spinner shows until TMDB answers, never "No results".
  private func runSearch() async {
    let text = query.trimmingCharacters(in: .whitespaces)
    guard text.count >= 2 else {
      results = []
      people = []
      searched = false
      peopleSearched = false
      return
    }
    if let hit = SearchCache.shared[text] {
      remember(languagesOf: hit.items)
      results = library.searchResults(hit.items, text: text)
      people = hit.people
      searched = true
      peopleSearched = true
      return
    }
    searched = false
    peopleSearched = false
    // Like Netflix: titles on the server that match show at once, as you
    // type, and TMDB's ranked list replaces them a moment later.
    results = library.localSearch(text, limit: 20)
    // A short pause so each keystroke doesn't send a request.
    try? await Task.pause(0.15)
    guard !Task.isCancelled, let tmdb = library.tmdb else {
      searched = true
      peopleSearched = true
      return
    }
    let found = try? await tmdb.searchMulti(text)
    guard !Task.isCancelled else { return }
    let shownPeople = Array((found?.people ?? []).filter { $0.profilePath != nil }.prefix(12))
    if let found { SearchCache.shared[text] = (found.items, shownPeople) }
    remember(languagesOf: found?.items ?? [])
    astraWithAnimation(Astra.Motion.base) {
      results = library.searchResults(found?.items ?? [], text: text)
      people = shownPeople
      searched = true
      peopleSearched = true
    }
  }

  private func remember(languagesOf items: [TMDBItem]) {
    for item in items { if let language = item.language { languages[item.id] = language } }
  }

  /// Atmos and Dolby Vision are in a title's tracks, which only its full
  /// details have: read them for the server's results (cached, four at a time).
  private func readTracks() async {
    // Bollywood: the language of server titles TMDB's search didn't return.
    let unknown = filters.contains(.bollywood) ? results.filter { $0.tmdbKey.map { languages[$0] == nil } ?? false } : []
    if !unknown.isEmpty {
      verifying = true
      defer { verifying = false }
      let found = await withTaskGroup(of: (String, String)?.self) { group in
        for item in unknown {
          group.addTask {
            guard let key = item.tmdbKey, let language = await library.language(of: item) else { return nil }
            return (key, language)
          }
        }
        var out: [(String, String)] = []
        for await pair in group { if let pair { out.append(pair) } }
        return out
      }
      guard !Task.isCancelled else { return }
      for (key, language) in found { languages[key] = language }
    }
    guard filters.contains(where: \.needsStreams) else { return }
    let pending = results.filter { item in
      !item.isCatalogOnly && fullCopies[item.ratingKey] == nil
        && SearchFilter.matches(item, language: item.tmdbKey.flatMap { languages[$0] }, all: filters) == nil
    }
    guard !pending.isEmpty else { return }
    verifying = true
    defer { verifying = false }
    for start in stride(from: 0, to: pending.count, by: 4) {
      let batch = pending[start..<min(pending.count, start + 4)]
      let found = await withTaskGroup(of: PlexMetadata?.self) { group in
        for item in batch { group.addTask { try? await library.details(item.ratingKey) } }
        var out: [PlexMetadata] = []
        for await item in group { if let item { out.append(item) } }
        return out
      }
      guard !Task.isCancelled else { return }
      for item in found { fullCopies[item.ratingKey] = item }
    }
  }

  private func remember(_ text: String) {
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    guard trimmed.count >= 2 else { return }
    let list = [trimmed] + recent.filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
    recentStore = list.prefix(10).joined(separator: "\n")
  }
}

/// A person in Mac search results: round photo, name, what they're known for.
private struct PersonCircle: View {
  var person: TMDBPerson

  var body: some View {
    VStack(spacing: 8) {
      RemoteImage(url: TMDBArtwork.url(person.profilePath, size: "w185"))
        .frame(width: 96, height: 96)
        .clipShape(Circle())
        .overlay(Circle().stroke(Astra.Color.hairline))
      Text(person.name)
        .astraFont(size: 13, weight: .semibold)
        .foregroundStyle(Astra.Color.ink)
        .lineLimit(1)
      Text(person.role)
        .astraFont(size: 11)
        .foregroundStyle(Astra.Color.muted)
        .lineLimit(1)
    }
    .frame(width: 110)
    .pressable()
    .contentShape(Rectangle())
  }
}

/// Settings inside the main window (the Mac sidebar's Settings item). The
/// form scrolls itself, so it isn't wrapped in another scroll view.
struct SettingsPage: View {
  @Environment(\.contentLeading) private var leading

  var body: some View {
    // KP (2026-11-13): the Mac's own Settings page (MacSettingsPage).
    #if os(macOS)
      MacSettingsPage()
    #else
      listPage
    #endif
  }

  private var listPage: some View {
    VStack(alignment: .leading, spacing: Astra.Spacing.m) {
      AstraSectionHeader(title: "Settings")
        .padding(.leading, leading)
      SettingsView()
        // The form's own inset is ~20 pt; line its rows up with the title.
        // Full width (KP, 2026-11-12): a 600 pt stack drew stray lines.
        .padding(.leading, max(0, leading - 20))
    }
    .padding(.top, Astra.Spacing.pageTop)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .astraPageBackground()
  }
}

/// Settings → Sources: connection status, when it was last checked, Retry.
struct SourceHealthRow: View {
  let health: ServerHealthMonitor

  var body: some View {
    LabeledContent("Status") {
      HStack(spacing: 6) {
        Circle()
          .fill(health.state == .connected ? Astra.Color.ink : Astra.Color.muted)
          .frame(width: 7, height: 7)
        Text(health.state.title)
      }
    }
    LabeledContent("Last Checked") {
      if let at = health.lastChecked {
        Text(at, style: .relative) + Text(" ago")
      } else {
        Text("—")
      }
    }
    Button("Retry Connection") { health.checkNow() }
      .disabled(health.state == .checking)
  }
}

/// Settings → Network: recent requests with their status and time, to see
/// why something is slow or failing. Refreshes every two seconds while open.
struct NetworkDiagnosticsView: View {
  @State private var expanded = false

  var body: some View {
    #if os(tvOS)
      // Apple TV has no disclosure groups: a button shows or hides the list.
      Button(expanded ? "Hide Requests" : "Show Requests") { expanded.toggle() }
      if expanded { requests }
    #else
      DisclosureGroup("Diagnostics", isExpanded: $expanded) {
        if expanded { requests }
      }
    #endif
  }

  private var requests: some View {
        TimelineView(.periodic(from: .now, by: 2)) { _ in
          let events = Array(NetworkLog.shared.recent.suffix(60).reversed())
          if events.isEmpty {
            Text("No requests yet.").astraFont(.meta).foregroundStyle(Astra.Color.muted)
          }
          ForEach(events) { event in
            VStack(alignment: .leading, spacing: 2) {
              HStack(spacing: 8) {
                Image(systemName: event.succeeded ? "checkmark.circle" : "exclamationmark.triangle")
                  .foregroundStyle(event.succeeded ? Astra.Color.muted : Astra.Color.ink)
                Text(event.status.map(String.init) ?? "—").monospacedDigit()
                Text("\(event.milliseconds) ms").monospacedDigit().foregroundStyle(Astra.Color.muted)
                Text(event.host).foregroundStyle(Astra.Color.muted).lineLimit(1)
              }
              Text(event.path).lineLimit(1).truncationMode(.middle).foregroundStyle(Astra.Color.muted)
              if let failure = event.failure {
                Text(failure).foregroundStyle(Astra.Color.ink)
              }
            }
            .font(.system(size: 11))
            #if !os(tvOS)
              .textSelection(.enabled)
            #endif
          }
        }
  }
}
