import AstraKit
import SwiftUI

/// Astra: the iPhone Search tab (KP's mockup, 2026-11-07). A glass search
/// field, All / Movies / Shows / People, then
/// rich result rows and people. With nothing typed: recent searches and
/// what's popular (KP removed Explore, 2026-11-07).
struct PhoneSearchView: View {
  var library: LibraryStore

  enum Scope: String, CaseIterable, Identifiable {
    case all, movies, shows, people
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
  }



  @Environment(\.playItem) private var playItem
  @Environment(\.openItem) private var openItem
  @AppStorage("astra.search.recent") private var recentStore = ""
  @State private var query = Demo.query ?? ""
  @State private var scope: Scope = .all
  @State private var results: [PlexMetadata] = []
  @State private var people: [TMDBPerson] = []
  @State private var searched = false
  @State private var peopleSearched = false
  @State private var person: TMDBPerson?
  @FocusState private var focused: Bool
  @Namespace private var scopePill

  private var recent: [String] { recentStore.split(separator: "\n").map(String.init) }

  private var shownResults: [PlexMetadata] {
    results.filter { item in
      switch scope {
      case .movies: guard item.type == .movie else { return false }
      case .shows: guard item.type == .show || item.type == .episode else { return false }
      case .people: return false
      case .all: break
      }
      return true
    }
  }

  private var shownPeople: [TMDBPerson] { scope == .all || scope == .people ? people : [] }

  var body: some View {
    ScrollView(.vertical) {
      VStack(alignment: .leading, spacing: 16) {
        Text("Search")
          .astraFont(size: 34, weight: .bold)
          .foregroundStyle(Astra.Color.ink)
        field
        scopes
        if query.trimmingCharacters(in: .whitespaces).count < 2 {
          idle
        } else {
          resultsList
        }
      }
      .padding(.horizontal, 16)
      .padding(.top, 8)
      .padding(.bottom, 100)
    }
    .scrollIndicators(.never)
    .scrollDismissesKeyboard(.immediately)
    .background(Astra.Color.bg.ignoresSafeArea())
    .navigationDestination(item: $person) { PersonView(library: library, person: $0) }
    .task(id: query) { await runSearch() }
  }

  // MARK: Header

  private var field: some View {
    HStack(spacing: 12) {
      Image(systemName: "magnifyingglass").foregroundStyle(Astra.Color.muted)
      TextField("Movies, shows and people", text: $query)
        .textFieldStyle(.plain)
        .astraFont(size: 17)
        .focused($focused)
        .submitLabel(.search)
        .autocorrectionDisabled()
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
    .padding(.horizontal, 18)
    .frame(height: 50)
    .astraGlass(in: Capsule(), variant: .clear, interactive: true)
    .astraGlassEdge(Capsule(), strength: 0.6)
  }

  private var scopes: some View {
    HStack(spacing: 8) {
      ForEach(Scope.allCases) { item in
        Button {
          astraWithAnimation(Astra.Motion.fast) { scope = item }
        } label: {
          Text(item.title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(scope == item ? Color.black : Astra.Color.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background {
              if scope == item { Capsule().fill(.white).matchedGeometryEffect(id: "scope", in: scopePill) }
            }
            .astraGlass(in: Capsule(), variant: .clear, interactive: true)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(scope == item ? .isSelected : [])
      }
    }
  }

  // MARK: Nothing typed

  @ViewBuilder private var idle: some View {
    if !recent.isEmpty {
      HStack {
        sectionTitle("Recent Searches")
        Spacer()
        Button("Clear") { recentStore = "" }
          .font(.system(size: 14, weight: .medium))
          .foregroundStyle(Astra.Color.muted)
      }
      VStack(spacing: 0) {
        ForEach(recent.prefix(6), id: \.self) { text in
          Button {
            query = text
          } label: {
            HStack(spacing: 12) {
              Image(systemName: "clock.arrow.circlepath").foregroundStyle(Astra.Color.muted)
              Text(text).foregroundStyle(Astra.Color.ink)
              Spacer()
              Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Astra.Color.muted)
            }
            .font(.system(size: 15))
            .frame(height: 44)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          Divider().overlay(Astra.Color.hairline)
        }
      }
    }
    let popular = Array(LibraryStore.interleave(library.topTen.movies, library.topTen.shows).prefix(12))
    if !popular.isEmpty {
      sectionTitle("Popular Right Now")
      ScrollView(.horizontal) {
        LazyHStack(spacing: 12) {
          ForEach(popular) { PosterCard(library: library, item: $0, width: 120) }
        }
      }
      .scrollIndicators(.never)
      .scrollClipDisabled()
    }
  }

  private func sectionTitle(_ text: String) -> some View {
    Text(text).astraFont(size: 19, weight: .bold).foregroundStyle(Astra.Color.ink).padding(.top, 6)
  }

  // MARK: Results

  @ViewBuilder private var resultsList: some View {
    let titles = shownResults
    let people = shownPeople
    let done = searched && peopleSearched
    if !done && titles.isEmpty && people.isEmpty {
      ProgressView().controlSize(.large).frame(maxWidth: .infinity).padding(.vertical, 40)
    } else if titles.isEmpty && people.isEmpty {
      EmptyState(
        symbol: "magnifyingglass", title: "No results",
        message: scope == .people ? "No one matches “\(query)”." : "Nothing matches “\(query)”.")
    } else {
      Text("Results (\(titles.count + people.count))")
        .astraFont(size: 15, weight: .semibold)
        .foregroundStyle(Astra.Color.muted)
      VStack(spacing: 10) {
        ForEach(titles) { item in
          ResultRow(library: library, item: item) {
            remember(query)
            openItem(item)
          } play: {
            remember(query)
            playItem(item)
          }
        }
      }
      if !people.isEmpty {
        if scope == .all { sectionTitle("People") }
        VStack(spacing: 0) {
          ForEach(people) { candidate in
            Button {
              remember(query)
              person = candidate
            } label: {
              PersonRow(person: candidate)
            }
            .buttonStyle(.plain)
            Divider().overlay(Astra.Color.hairline)
          }
        }
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
      results = library.withServerNow(hit.items)
      people = hit.people
      searched = true
      peopleSearched = true
      return
    }
    searched = false
    peopleSearched = false
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
    astraWithAnimation(Astra.Motion.base) {
      results = library.withServerNow(found?.items ?? [])
      people = shownPeople
      searched = true
      peopleSearched = true
    }
  }

  private func remember(_ text: String) {
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    guard trimmed.count >= 2 else { return }
    let list = [trimmed] + recent.filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
    recentStore = list.prefix(10).joined(separator: "\n")
  }
}

extension View {
  /// Search's filter chips: clear glass, or solid white when on.
  fileprivate func searchChip(selected: Bool) -> some View {
    self
      .font(.system(size: 14, weight: .semibold))
      .foregroundStyle(selected ? Color.black : Astra.Color.ink)
      .padding(.horizontal, 16)
      .frame(height: 34)
      .background { if selected { Capsule().fill(.white) } }
      .astraGlass(in: Capsule(), variant: .clear, interactive: true)
      .contentShape(Capsule())
  }
}

/// A search result: poster, title, "Movie · 2023 · 3h 0m", quality badges,
/// genres, and a round play button.
private struct ResultRow: View {
  var library: LibraryStore
  var item: PlexMetadata
  var open: () -> Void
  var play: () -> Void

  private var kind: String {
    switch item.type {
    case .movie: "Movie"
    case .show: "Show"
    case .episode: "Episode"
    default: "Title"
    }
  }

  private var badges: [String] {
    let tiers = Set(item.media.compactMap(\.tier))
    var list: [String] = []
    if tiers.contains(where: { $0 >= 2160 }) { list.append("4K") }
    if tiers.contains(where: { $0 >= 720 && $0 < 2160 }) { list.append("HD") }
    return list
  }

  var body: some View {
    HStack(spacing: 14) {
      Button(action: open) {
        HStack(spacing: 14) {
          ArtworkImage(library: library, item: item, kind: .poster, width: 78, height: 117)
            .frame(width: 78, height: 117)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
          VStack(alignment: .leading, spacing: 6) {
            Text(item.displayTitle)
              .astraFont(size: 17, weight: .bold)
              .foregroundStyle(Astra.Color.ink)
              .lineLimit(2)
            Text([kind, item.episodeLabel, item.year.map(String.init), item.durationLabel].compactMap { $0 }
              .joined(separator: " · "))
              .astraFont(size: 13)
              .foregroundStyle(Astra.Color.muted)
              .lineLimit(1)
            if !badges.isEmpty {
              HStack(spacing: 6) {
                ForEach(badges, id: \.self) { badge in
                  Text(badge)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Astra.Color.ink)
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(Capsule().fill(.white.opacity(0.12)))
                    .overlay(Capsule().stroke(.white.opacity(0.18)))
                }
              }
            }
            if !item.genres.isEmpty {
              Text(item.genres.prefix(3).map(\.tag).joined(separator: " · "))
                .astraFont(size: 12)
                .foregroundStyle(Astra.Color.muted)
                .lineLimit(1)
            }
          }
          Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      Button(action: play) {
        Image(systemName: "play.fill")
      }
      .astraIconButton(size: 40, variant: .clear)
      // Not on the server: Play greyed out (KP).
      .disabled(library.availability(of: item) == .notOnServer)
      .opacity(library.availability(of: item) == .notOnServer ? 0.35 : 1)
      .accessibilityLabel("Play \(item.displayTitle)")
    }
    .padding(10)
    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.04)))
    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Astra.Color.hairline))
    .itemMenu(library: library, item: item)
  }
}

/// "Cillian Murphy / Actor · Oppenheimer" with a round photo.
private struct PersonRow: View {
  var person: TMDBPerson

  var body: some View {
    HStack(spacing: 14) {
      RemoteImage(url: person.profileURL)
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      VStack(alignment: .leading, spacing: 3) {
        Text(person.name).astraFont(size: 16, weight: .semibold).foregroundStyle(Astra.Color.ink)
        Text(([person.role] + person.knownFor.prefix(1)).joined(separator: " · "))
          .astraFont(size: 13)
          .foregroundStyle(Astra.Color.muted)
          .lineLimit(1)
      }
      Spacer()
      Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Astra.Color.muted)
    }
    .frame(height: 68)
    .contentShape(Rectangle())
  }
}

/// A person's page: their photo and name, then their movies and shows from TMDB.
struct PersonView: View {
  var library: LibraryStore
  var person: TMDBPerson

  @State private var items: [PlexMetadata] = []
  @State private var loaded = false

  var body: some View {
    ScrollView(.vertical) {
      VStack(alignment: .leading, spacing: 18) {
        HStack(spacing: 16) {
          RemoteImage(url: TMDBArtwork.url(person.profilePath, size: "w342"))
            .frame(width: 96, height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
          VStack(alignment: .leading, spacing: 6) {
            Text(person.name).astraFont(size: 26, weight: .bold).foregroundStyle(Astra.Color.ink)
            Text(person.role).astraFont(size: 15).foregroundStyle(Astra.Color.muted)
          }
        }
        Text("Movies & Shows").astraFont(size: 19, weight: .bold).foregroundStyle(Astra.Color.ink)
        if !loaded {
          ProgressView().frame(maxWidth: .infinity).padding(.vertical, 30)
        } else if items.isEmpty {
          EmptyState(
            symbol: "person.crop.rectangle", title: "Nothing here",
            message: "TMDB has no movies or shows for \(person.name).")
        } else {
          LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 14) {
            ForEach(items) { PosterCard(library: library, item: $0, width: 108) }
          }
        }
      }
      .padding(.horizontal, 16)
      .padding(.top, 8)
      .padding(.bottom, 100)
    }
    .scrollIndicators(.never)
    .background(Astra.Color.bg.ignoresSafeArea())
    .navigationTitle(person.name)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar(.visible, for: .navigationBar)
    .task {
      guard let tmdb = library.tmdb else {
        loaded = true
        return
      }
      let credits = (try? await tmdb.credits(of: person.id)) ?? []
      // Astra (KP): the actor's whole filmography from TMDB; titles on the
      // server play, the rest open with Play greyed out.
      items = await library.withServer(credits)
      loaded = true
    }
  }
}
