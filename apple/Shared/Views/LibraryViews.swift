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
    .background(Astra.Color.bg.ignoresSafeArea())
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
      Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(Astra.Color.ink)
      Text(message).font(Astra.Font.meta).foregroundStyle(Astra.Color.muted).multilineTextAlignment(.center)
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

  @State private var sectionKey: String?
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
      HStack(spacing: Astra.Spacing.s) {
        if sections.count > 1 {
          Picker("Library", selection: Binding(get: { section?.key ?? "" }, set: { sectionKey = $0 })) {
            ForEach(sections) { Text($0.title).tag($0.key) }
          }
          .labelsHidden()
          .fixedSize()
        }
        Picker("Sort", selection: $sort) {
          Text("Recently Added").tag("addedAt:desc")
          Text("Title").tag("titleSort")
          Text("Release Date").tag("originallyAvailableAt:desc")
          Text("Rating").tag("audienceRating:desc")
        }
        .labelsHidden()
        .fixedSize()
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
    .task(id: "\(section?.key ?? "")|\(sort)") {
      items = []
      loaded = 0
      reachedEnd = false
      await loadMore()
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
  @AppStorage("astra.search.recent") private var recentStore = ""
  @FocusState private var focused: Bool
  @Namespace private var scopePill

  private var recent: [String] { recentStore.split(separator: "\n").map(String.init) }
  private var typed: Bool { query.trimmingCharacters(in: .whitespaces).count >= 2 }

  private var shownResults: [PlexMetadata] {
    switch scope {
    case .all: results
    case .movies: results.filter { $0.type == .movie }
    case .shows: results.filter { $0.type == .show || $0.type == .season || $0.type == .episode }
    case .people: []
    }
  }

  private var shownPeople: [TMDBPerson] { scope == .all || scope == .people ? people : [] }

  var body: some View {
    AstraPage {
      HStack(spacing: 12) {
        Image(systemName: "magnifyingglass").foregroundStyle(Astra.Color.muted)
        TextField("Movies, shows and people", text: $query)
          .textFieldStyle(.plain)
          .font(.system(size: 18))
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

      scopes

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
          withAnimation(Astra.Motion.fast) {
            scope = item
            person = nil
          }
        } label: {
          Text(item.title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(scope == item ? Color.black : Astra.Color.ink)
            .padding(.horizontal, 18)
            .frame(height: 32)
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
          .buttonStyle(.plain)
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(Astra.Color.muted)
      }
      .frame(maxWidth: 620)
      HStack(spacing: 8) {
        ForEach(recent.prefix(6), id: \.self) { text in
          Button {
            query = text
          } label: {
            Label(text, systemImage: "clock.arrow.circlepath")
              .font(.system(size: 13, weight: .medium))
              .foregroundStyle(Astra.Color.ink)
              .padding(.horizontal, 14)
              .frame(height: 30)
              .astraGlass(in: Capsule(), variant: .clear, interactive: true)
              .contentShape(Capsule())
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
    Text(text).font(Astra.Font.rowTitle).foregroundStyle(Astra.Color.ink).padding(.top, 6)
  }

  // MARK: Results

  @ViewBuilder private var resultsSection: some View {
    let titles = shownResults
    let found = shownPeople
    let done = searched && peopleSearched
    if !done && titles.isEmpty && found.isEmpty {
      ProgressView().controlSize(.large).frame(maxWidth: .infinity).padding(.vertical, 40)
    } else if titles.isEmpty && found.isEmpty {
      EmptyState(
        symbol: "magnifyingglass", title: "No results",
        message: scope == .people ? "No one matches “\(query)”." : "Nothing matches “\(query)”.")
    } else {
      if !found.isEmpty {
        if scope == .all { sectionTitle("People") }
        ScrollView(.horizontal) {
          LazyHStack(alignment: .top, spacing: 18) {
            ForEach(found) { candidate in
              Button {
                remember(query)
                withAnimation(Astra.Motion.base) { person = candidate }
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
        .animation(Astra.Motion.base, value: titles.map(\.id))
      }
    }
  }

  @ViewBuilder private func personPage(_ person: TMDBPerson) -> some View {
    HStack(spacing: 16) {
      Button {
        withAnimation(Astra.Motion.base) { self.person = nil }
      } label: {
        Image(systemName: "chevron.left")
      }
      .astraIconButton(size: 34, variant: .clear)
      .accessibilityLabel("Back to Results")
      RemoteImage(url: TMDBArtwork.url(person.profilePath, size: "w342"))
        .frame(width: 64, height: 80)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      VStack(alignment: .leading, spacing: 4) {
        Text(person.name).font(.system(size: 24, weight: .bold)).foregroundStyle(Astra.Color.ink)
        Text(person.role).font(.system(size: 14)).foregroundStyle(Astra.Color.muted)
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
    withAnimation(Astra.Motion.base) {
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
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Astra.Color.ink)
        .lineLimit(1)
      Text(person.role)
        .font(.system(size: 11))
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
    VStack(alignment: .leading, spacing: Astra.Spacing.m) {
      AstraSectionHeader(title: "Settings")
        .padding(.leading, leading)
      SettingsView()
        .frame(maxWidth: 600, alignment: .leading)
        // The form's own inset is ~20 pt; line its rows up with the title.
        .padding(.leading, max(0, leading - 20))
    }
    .padding(.top, Astra.Spacing.pageTop)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(Astra.Color.bg.ignoresSafeArea())
  }
}

struct SettingsView: View {
  @Environment(AppModel.self) private var app
  @Environment(\.checkForUpdates) private var checkForUpdates
  @AppStorage(PlaybackQuality.storageKey) private var quality: PlaybackQuality = .auto
  @AppStorage(SubtitlePreference.storageKey) private var subtitles: SubtitlePreference = .automatic
  @AppStorage(LibraryQuality.storageKey) private var libraryQuality: LibraryQuality = .deviceDefault
  @AppStorage(Preferences.serviceAccentsKey) private var serviceAccents = true
  @AppStorage(Preferences.qualityBadgesKey) private var qualityBadges = true
  @AppStorage(Preferences.ratingsKey) private var ratings = true
  @AppStorage(Preferences.wifiOnlyKey) private var wifiOnly = false

  // Astra 4.0 (KP, 2026-11-08): Appearance, Playback, Library, Sources,
  // Downloads, About.
  var body: some View {
    Form {
      Section {
        AccentPicker()
        Toggle("Streaming Service Accents", isOn: $serviceAccents).tint(Astra.Color.switchOn)
      } header: {
        Text("Appearance")
      } footer: {
        Text("The accent colours selection and progress. Service accents tint a streaming service's Home page in its colour.")
      }
      Section {
        Picker("Preferred Quality", selection: $quality) {
          ForEach(PlaybackQuality.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        Picker("Subtitles", selection: $subtitles) {
          ForEach(SubtitlePreference.allCases) { Text($0.title).tag($0) }
        }
      } header: {
        Text("Playback")
      } footer: {
        Text(
          "Astra always plays the original file. When a title has several versions, quality picks which one. "
            + "Automatic subtitles show what the file marks as forced or default; Always picks your language.")
      }
      // Astra: Library Quality, per device (KP, 2026-11-07).
      Section {
        Picker("Library Quality", selection: $libraryQuality) {
          ForEach(LibraryQuality.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .onChange(of: libraryQuality) { app.libraryQualityChanged() }
        Toggle("HD and 4K Badges", isOn: $qualityBadges).tint(Astra.Color.switchOn)
        Toggle("Age Ratings", isOn: $ratings).tint(Astra.Color.switchOn)
      } header: {
        Text("Library")
      } footer: {
        Text(
          libraryQuality == .hd
            ? "One copy of each title, in HD. 4K libraries are hidden on this device."
            : "One copy of each title: the 4K one when there is one, otherwise HD.")
      }
      // Astra 4.0 (KP, 2026-11-08): Sources, with each server's health.
      Section("Sources") {
        LabeledContent("Name", value: app.server?.serverName ?? "Not connected")
        LabeledContent("Type", value: "Plex Media Server")
        if let health = app.health {
          SourceHealthRow(health: health)
        }
        LabeledContent("Address", value: app.server?.baseURL.host() ?? "—")
        Button("Change Server…") { Task { await app.chooseServer() } }
        Button("Sign Out", role: .destructive) { app.signOut() }
      }
      Section {
        #if os(iOS)
          Toggle("Wi-Fi Only", isOn: $wifiOnly).tint(Astra.Color.switchOn)
        #endif
        LabeledContent(
          "Storage Used", value: ByteCountFormatter.string(fromByteCount: app.downloads.storageUsed, countStyle: .file))
      } header: {
        Text("Downloads")
      } footer: {
        Text("Manage downloads in Library → Downloads.")
      }
      Section {
        LabeledContent("Version", value: Self.versionText)
        if let checkForUpdates {
          Button("Check for Updates…", action: checkForUpdates)
        }
        DisclosureGroup("Licenses") {
          Text(
            "Astra is free software under the GNU General Public License, version 3. "
              + "Playback uses mpv and FFmpeg (LGPL/GPL); Mac updates use Sparkle (MIT).")
            .font(Astra.Font.meta)
            .foregroundStyle(Astra.Color.muted)
          if let url = URL(string: "https://www.gnu.org/licenses/gpl-3.0.html") {
            Link("GNU GPL v3", destination: url)
          }
        }
        NetworkDiagnosticsView()
      } header: {
        Text("About")
      } footer: {
        Text("Diagnostics list the last requests Astra made, newest first. Tokens are never shown or saved.")
      }
    }
    .formStyle(.grouped)
    .scrollContentBackground(.hidden)
  }

  /// "0.1.0 (202611070245)": the marketing version and the build that updates compare.
  static var versionText: String {
    let info = Bundle.main.infoDictionary ?? [:]
    let short = info["CFBundleShortVersionString"] as? String ?? ""
    let build = info["CFBundleVersion"] as? String ?? ""
    return build.isEmpty ? short : "\(short) (\(build))"
  }
}

/// Settings → Appearance → Accent: Astra's presets (no purple) and a picker.
struct AccentPicker: View {
  private var appearance: AstraAppearance { .shared }

  var body: some View {
    LabeledContent("Accent") {
      HStack(spacing: 8) {
        ForEach(AccentPreset.allCases) { preset in
          let selected = appearance.accentHex == preset.hex
          Button { appearance.setAccent(preset.hex) } label: {
            Circle()
              .fill(Color(hex: preset.hex.value))
              .frame(width: 20, height: 20)
              .overlay(Circle().stroke(Astra.Color.ink, lineWidth: selected ? 2 : 0).padding(-3))
              .overlay(Circle().stroke(Astra.Color.hairline, lineWidth: 1))
          }
          .buttonStyle(.plain)
          .accessibilityLabel(preset.title)
          .accessibilityAddTraits(selected ? .isSelected : [])
        }
        ColorPicker(
          "Custom Accent",
          selection: Binding(get: { appearance.accent }, set: { appearance.setAccent($0) }),
          supportsOpacity: false
        )
        .labelsHidden()
      }
    }
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
    DisclosureGroup("Diagnostics", isExpanded: $expanded) {
      if expanded {
        TimelineView(.periodic(from: .now, by: 2)) { _ in
          let events = Array(NetworkLog.shared.recent.suffix(60).reversed())
          if events.isEmpty {
            Text("No requests yet.").font(Astra.Font.meta).foregroundStyle(Astra.Color.muted)
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
            .textSelection(.enabled)
          }
        }
      }
    }
  }
}
