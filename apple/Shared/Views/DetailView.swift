import AstraKit
import SwiftUI

/// Movie and TV details: backdrop header, actions, seasons and episodes, cast, related.
struct DetailView: View {
  var library: LibraryStore
  var seed: PlexMetadata
  @Binding var path: [Route]

  @State private var item: PlexMetadata?
  /// The show an episode or season belongs to, for the + Watchlist button.
  @State private var parentShow: PlexMetadata?
  @State private var seasons: [PlexMetadata] = []
  /// Settings → Library → Show Specials (off by default, KP 2026-11-16).
  @AppStorage(Preferences.showSpecialsKey) private var showSpecials = false
  @State private var selectedSeason: PlexMetadata?
  @State private var episodes: [PlexMetadata] = []
  /// A show's picked episode (KP, 2026-11-14): the header shows its details and
  /// Resume / Play plays it. Tapping an episode picks it; only Play or a
  /// double tap plays.
  @State private var focus: PlexMetadata?
  /// The episode the season row scrolls to once it loads (KP, 2026-11-26: a
  /// Continue Watching episode opens on that episode, not the season's start).
  @State private var revealEpisode: String?
  /// The season row's scroll position, by episode.
  @State private var rowPosition: String?
  @State private var related: [PlexHub] = []
  @State private var error: String?
  /// A TMDB title that isn't on the Plex server: shown, but nothing to play.
  @State private var notOnServer = false
  /// The visible height of the page; the header's backdrop is at least a share of it.
  @State private var viewport: CGFloat = 800
  /// How far the page has scrolled; the backdrop holds still against it.
  @State private var scrolled: CGFloat = 0
  /// The page's width: the iPhone layout scales its hero with it.
  @State private var pageWidth: CGFloat = 393
  /// iPhone: the synopsis opened past four lines with More.
  @State private var summaryExpanded = false
  /// iPhone: the full cast / related list from a row's chevron.
  @State private var showAllCast = false
  @State private var allRelated: PlexHub?

  @Environment(\.playItem) private var playItem
  @Environment(AppModel.self) private var app
  @Environment(\.contentLeading) private var leading
  @Environment(\.closeCard) private var closeCard
  /// False for a card under the top one: its keyboard shortcuts are off.
  @Environment(\.isPageActive) private var isActive
  #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// iPhone: a wide Play and round icon buttons, so no label ever wraps.
    private var narrow: Bool { sizeClass == .compact }
  #else
    private var narrow: Bool { false }
  #endif

  private var shown: PlexMetadata { item ?? seed }

  /// Whose logo, backdrop, meta line, cast and related titles the page shows:
  /// the show itself on an episode's or season's page.
  private var titleItem: PlexMetadata {
    if shown.type == .episode || shown.type == .season, let parentShow { return parentShow }
    // Genres and length from TMDB for titles that aren't on Plex.
    return library.filled(shown)
  }

  /// What the header describes and Play / Resume plays.
  private var playTarget: PlexMetadata { focus ?? shown }

  private var isSeries: Bool { shown.type == .show || shown.type == .season || shown.type == .episode }

  /// The picked episode's synopsis on a show, else the title's own.
  private var headerSummary: String? {
    if let text = focus?.summary, !text.isEmpty { return text }
    if let text = shown.summary, !text.isEmpty { return text }
    return titleItem.summary
  }

  /// Picks an episode without playing it. The page stays where it is
  /// (KP, 2026-11-16: "dont make it automatically go to top").
  private func pick(_ episode: PlexMetadata) {
    astraWithAnimation(Astra.Motion.base) {
      focus = episode
      summaryExpanded = false
    }
  }

  /// The picked episode's own still for the header, from the moment the page
  /// opens (KP, 2026-11-16: "each episode should have its own backdrop").
  private var episodeStill: URL? {
    guard let focus, focus.type == .episode, let thumb = focus.thumb else { return nil }
    // TMDB's full-size still once found (KP, 2026-11-25: some shows' server stills are blurry).
    return sharpStills[focus.ratingKey] ?? library.imageURL(thumb, width: 1920, height: 1080, scale: 1)
  }
  /// TMDB stills found for the picked episodes, by rating key.
  @State private var sharpStills: [String: URL] = [:]

  private static let headerID = "details.header"
  /// The header's text column on Mac and iPad.
  private static let textColumn: CGFloat = 580
  private static let episodesID = "details.episodes"

  var body: some View {
    // KP (2026-11-14): Details stays Frosted Glass, even on the Light theme.
    page.astraDetailsTheme()
      .task(id: focus?.ratingKey) {
        guard let focus, focus.type == .episode, sharpStills[focus.ratingKey] == nil,
          let url = await library.episodeStillURL(for: focus, width: 1920, height: 1080, scale: 1),
          url.host() == "image.tmdb.org", !Task.isCancelled
        else { return }
        sharpStills[focus.ratingKey] = url
      }
  }

  @ViewBuilder private var page: some View {
    ScrollViewReader { scroll in
      ScrollView(.vertical) {
        // A plain VStack: a lazy one guesses row heights and makes the page jump while scrolling.
        VStack(alignment: .leading, spacing: sectionSpacing) {
          deviceHeader
            .id(Self.headerID)
          // Astra (KP, 2026-11-07): the backdrop stays still while the page
          // scrolls, so everything below the header covers it as it rises.
          VStack(alignment: .leading, spacing: sectionSpacing) {
            if isSeries, !seasons.isEmpty || !episodes.isEmpty {
              episodesSection
                .id(Self.episodesID)
            }
            if !titleItem.roles.isEmpty {
              deviceCastRow
            }
            ForEach(related) { hub in
              deviceRelatedRow(hub)
            }
          }
          .padding(.bottom, bottomRoom)
          .frame(maxWidth: .infinity, alignment: .leading)
          // iPhone: no flat black under the rows; the frosted artwork shows through (KP, 2026-11-09).
          .background(narrow ? Color.clear : Astra.Color.bg)
        }
      }
      .scrollIndicators(.never)
      .modifier(ScrollOffsetReader(offset: $scrolled))
      .astraScrollEdges()
      // CI screenshots: `-AstraDemoOpen <show> -AstraDemoScroll 1` shows the season list.
      .task(id: episodes.count) {
        guard Demo.openKey != nil, Demo.homeScroll != nil, !episodes.isEmpty else { return }
        try? await Task.pause(1)
        scroll.scrollTo(Self.episodesID, anchor: .top)
      }
    }
    .onGeometryChange(for: CGSize.self, of: { $0.size }) {
      viewport = $0.height
      pageWidth = $0.width
    }
    // The backdrop runs under the title bar; the back button below stays inside the safe area.
    .ignoresSafeArea(edges: .top)
    .background { pageBackground }
    #if os(macOS)
      .overlay(alignment: .topLeading) {
        // KP (2026-11-16): X and ••• at the top left of the card.
        HStack(spacing: 10) {
          // Astra: details are a card on the Mac; X closes it (Esc too).
          Button {
            if let closeCard { closeCard() } else if !path.isEmpty { path.removeLast() }
          } label: {
            Image(systemName: "xmark")
          }
          .astraIconButton(size: 36, variant: .clear)
          #if !os(tvOS)
            .keyboardShortcut(isActive ? .cancelAction : nil)
          #endif
          .help("Close (Esc)")
          .accessibilityLabel("Close")
          // KP (2026-11-08): ••• beside the X with the title's actions.
          if !shown.isCatalogOnly {
            moreMenu
              .menuStyle(.button)
              .astraIconButton(size: 36, variant: .clear)
          }
        }
        .padding(.leading, 18)
        .padding(.top, 18)
      }
    #elseif os(iOS)
      // iPad keeps the system back button (Liquid Glass on iOS 26). The iPhone
      // card has its own X; swipe-back and drag-to-close come from the zoom.
      .toolbarBackground(.hidden, for: .navigationBar)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar(narrow ? .hidden : .automatic, for: .navigationBar)
      .toolbar {
        // KP (2026-11-08): ••• top right with the title's actions (the bar gives it its glass).
        // On iPhone it's More in the row of actions (KP, 2026-11-26, like Plex).
        if !shown.isCatalogOnly, !narrow {
          ToolbarItem(placement: .topBarTrailing) { moreMenu }
        }
      }
      // The floating tab bar gets a dark floor, so it never sits on top of the
      // cast or posters (KP's mockup, 2026-11-08).
      .overlay(alignment: .bottom) {
        if narrow { BottomEdgeBlur() }
      }
      // KP (2026-11-26): a card like Plex's, rounded at the top just under the
      // status bar, with a glass X.
      .modifier(PhoneDetailCard(enabled: narrow) { if !path.isEmpty { path.removeLast() } })
      .sheet(isPresented: $showAllCast) { PhoneCastList(roles: titleItem.roles) }
      .sheet(item: $allRelated) { hub in
        PhoneRelatedGrid(library: library, hub: hub) { picked in
          allRelated = nil
          path.append(.details(picked))
        }
      }
    #endif
    .task(id: seed.ratingKey) { await load() }
    .task(id: shown.ratingKey) {
      let key = shown.type == .episode ? shown.grandparentRatingKey : shown.type == .season ? shown.parentRatingKey : nil
      guard let key, parentShow?.ratingKey != key else { return }
      parentShow = try? await library.details(key)
    }
  }

  /// What + Watchlist adds: the title itself, or an episode's or season's show.
  private var watchlistTarget: PlexMetadata? {
    if shown.tmdbKey != nil, shown.type == .movie || shown.type == .show { return shown }
    if shown.type == .episode || shown.type == .season, let show = parentShow, show.tmdbKey != nil { return show }
    return nil
  }

  /// The ••• menu: Mark Watched / Unwatched, Download, Go to Season / Show,
  /// the same actions as a long-press on a title.
  private var moreMenu: some View {
    Menu {
      ItemMenuItems(library: library, item: playTarget, onDetails: true)
    } label: {
      Image(systemName: "ellipsis")
    }
    .menuIndicator(.hidden)
    .help("More")
    .accessibilityLabel("More")
  }

  // MARK: Per device

  /// Behind the whole page: a frosted blur of the title's artwork on iPhone
  /// (KP, 2026-11-09: "liquid frosted glass rather than just completely black"), plain dark elsewhere.
  @ViewBuilder private var pageBackground: some View {
    #if os(iOS)
      if narrow {
        // The same picture as the card's art, so the colour runs on from it (KP, 2026-11-26).
        PhoneFrostedBackground(library: library, item: titleItem, kind: .keyArt, imageURL: episodeStill)
      } else {
        Astra.Color.bg.ignoresSafeArea()
      }
    #else
      Astra.Color.bg.ignoresSafeArea()
    #endif
  }

  private var sectionSpacing: CGFloat {
    #if os(iOS)
      narrow ? PhoneDetail.sectionGap : Astra.Spacing.xl - 4
    #else
      Astra.Spacing.xl - 4
    #endif
  }

  private var bottomRoom: CGFloat {
    #if os(iOS)
      narrow ? Astra.Layout.tabBarRoom + 40 : 110
    #else
      110
    #endif
  }

  @ViewBuilder private var deviceHeader: some View {
    #if os(iOS)
      if narrow { phoneHeader } else { header }
    #else
      header
    #endif
  }

  @ViewBuilder private var deviceCastRow: some View {
    #if os(iOS)
      if narrow { phoneCastRow } else { castRow }
    #else
      castRow
    #endif
  }

  @ViewBuilder private func deviceRelatedRow(_ hub: PlexHub) -> some View {
    #if os(iOS)
      if narrow {
        phoneRelatedRow(hub)
      } else {
        ContentRow(title: hub.title) { ForEach(hub.items) { ArtCard(library: library, item: $0) } }
      }
    #else
      ContentRow(title: hub.title) { ForEach(hub.items) { ArtCard(library: library, item: $0) } }
    #endif
  }

  // MARK: Header

  /// The header grows with its text instead of squeezing it into a fixed
  /// frame, so the title, summary and buttons can never spill over the back
  /// button or the seasons below. The backdrop fills whatever height that is.
  private var header: some View {
    // Astra (KP's mockup, 2026-11-07): logo to the left over the artwork,
    // the meta line, a row of format badges (4K, HDR, Dolby Atmos, PG-13),
    // the tagline, the summary with More, then Resume and Download side by
    // side and the progress bar with the time left.
    VStack(alignment: .leading, spacing: 12) {
      HeroTitle(library: library, item: titleItem, maxWidth: narrow ? 250 : 380, maxHeight: narrow ? 92 : 120)
        .padding(.bottom, 4)
      // KP (2026-11-13): like the iPhone and Apple TV, one line of
      // "2024 • 2h 46m • [PG-13] [4K] [Dolby Atmos]" with the rating in a
      // grey box, and the genres on their own line under it.
      MetaBadgeRow(item: titleItem, playTarget: playTarget, library: library)
      if !titleItem.genres.isEmpty {
        Text(titleItem.genres.prefix(3).map(\.tag).joined(separator: " · "))
          .astraFont(size: 14)
          .foregroundStyle(Astra.Color.ink.opacity(0.62))
          .lineLimit(1)
      }
      episodeHeading
      if focus == nil, let tagline = titleItem.tagline, !tagline.isEmpty {
        Text(tagline)
          .astraFont(size: 15, weight: .semibold)
          .italic()
          .foregroundStyle(Astra.Color.ink.opacity(0.9))
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.top, 4)
      }
      if let summary = headerSummary, !summary.isEmpty {
        ExpandableSummary(text: summary)
          .id(playTarget.ratingKey)
      }
      HStack(spacing: 12) {
        Button {
          playItem(playTarget)
        } label: {
          Label(playLabel, systemImage: "play.fill")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(SolidCapsuleButtonStyle())
        #if !os(tvOS)
          .keyboardShortcut(isActive ? .defaultAction : nil)
        #endif
        .disabled(shown.isCatalogOnly || !app.canPlay(playTarget))

        if shown.type != .collection, !shown.isCatalogOnly {
          DownloadButton(item: shown, round: true)
        }

        // KP (2026-11-08): the round + Watchlist button next to Download, as on
        // the hero, and no Watched button here (Mark Watched / Unwatched are in
        // the ••• menu). On an episode or season the + adds its show.
        if let target = watchlistTarget {
          WatchlistButton(item: target, size: 46, variant: .clear)
        }
      }
      .frame(maxWidth: narrow ? .infinity : 560)
      .astraGlassGroup(spacing: 12)
      .padding(.top, 6)
      if let left = timeLeft, let progress = resumeProgress {
        VStack(alignment: .trailing, spacing: 6) {
          ProgressView(value: progress)
            .progressViewStyle(.linear)
            .tint(Astra.Color.ink)
          Text(left)
            .astraFont(size: 12, weight: .medium)
            .monospacedDigit()
            .foregroundStyle(Astra.Color.muted)
        }
        .frame(maxWidth: narrow ? .infinity : 560)
      }
      if !playTarget.directors.isEmpty {
        Text("Directed by \(playTarget.directors.map(\.tag).joined(separator: ", "))")
          .astraFont(size: 13).foregroundStyle(Astra.Color.muted).lineLimit(1)
      }
      if notOnServer {
        Text("Not on your Plex server.").astraFont(size: 13).foregroundStyle(Astra.Color.muted)
      }
      if let error {
        Text(error).astraFont(size: 13).foregroundStyle(Astra.Color.muted)
      }
    }
    // KP (2026-11-16, Dune): the text keeps to a column at the left, so
    // the faces in the art (framed to its right on the Mac) stay clear.
    .frame(maxWidth: narrow ? .infinity : Self.textColumn, alignment: .leading)
    .padding(.leading, leading)
    .padding(.trailing, Astra.Spacing.pageTrailing)
    // Room for the backdrop above the text, and for the back button.
    .padding(.top, max(140, viewport * 0.32))
    .padding(.bottom, 30)
    .frame(maxWidth: .infinity, minHeight: min(Astra.Layout.detailHeaderHeight, viewport * 0.72), alignment: .bottomLeading)
    .background {
      ZStack {
        Group {
          if let still = episodeStill {
            RemoteImage(url: still, placeholder: Color.clear)
          } else {
            #if os(macOS)
              // Faces found by Vision sit right of the text column (KP,
              // 2026-11-16: "the text is covering his face"), as on Apple TV.
              MacHeroArt(
                library: library, item: titleItem, clearX: leading + Self.textColumn + 40, kind: .scenery, push: 0.3)
            #else
              ArtworkImage(
                library: library, item: titleItem, kind: .scenery, width: 1920, height: 1080, placeholder: Color.clear)
            #endif
          }
        }
        .id(episodeStill)
        .transition(.opacity)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        // Darkens a little as the page rises over it.
        .overlay(Astra.Color.bg.opacity(min(0.55, max(0, scrolled) / 700)))
        HeroScrim()
      }
      .tvFullBleed()
      // Held in place: only the logo, text and buttons move with the scroll.
      .offset(y: max(0, scrolled))
    }
  }

  /// How far into the movie or the next episode, for the bar under the buttons.
  private var resumeTarget: PlexMetadata? {
    if let focus { return focus }
    if shown.type == .movie || shown.type == .episode { return shown }
    return episodes.first { ($0.viewOffset ?? 0) > 0 }
  }

  private var resumeProgress: Double? {
    guard let target = resumeTarget, let offset = target.viewOffset, offset > 0, let duration = target.duration,
      duration > 0
    else { return nil }
    return min(1, Double(offset) / Double(duration))
  }

  /// "1h 12m left".
  private var timeLeft: String? {
    guard let target = resumeTarget, let offset = target.viewOffset, offset > 0, let duration = target.duration,
      duration > offset
    else { return nil }
    let minutes = max(1, (duration - offset) / 60_000)
    let label = minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    return "\(label) left"
  }

  private var playLabel: String {
    if let focus {
      let verb = focus.progress != nil ? "Resume" : "Play"
      guard let label = focus.episodeLabel else { return verb }
      return "\(verb) \(label.replacingOccurrences(of: " · ", with: " "))"
    }
    if shown.type == .movie || shown.type == .episode { return shown.progress != nil ? "Resume" : "Play" }
    if let next = episodes.first(where: { ($0.viewOffset ?? 0) > 0 }) ?? episodes.first(where: { !$0.isWatched }),
      let label = next.episodeLabel
    {
      return "Play \(label.replacingOccurrences(of: " · ", with: " "))"
    }
    return "Play"
  }

  // MARK: Episodes

  /// "S1 · E3 · 52m" over the picked episode's title, above its synopsis.
  @ViewBuilder private var episodeHeading: some View {
    if let focus, focus.type == .episode {
      VStack(alignment: .leading, spacing: 3) {
        Text([focus.episodeLabel, focus.durationLabel].compactMap { $0 }.joined(separator: "  ·  "))
          .astraFont(size: 13, weight: .semibold)
          .foregroundStyle(Astra.Color.muted)
        Text(focus.title)
          .astraFont(size: narrow ? 20 : 22, weight: .bold)
          .foregroundStyle(Astra.Color.ink)
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityElement(children: .combine)
      .id(focus.ratingKey)
      .transition(.opacity)
    }
  }

  private var rowLeading: CGFloat {
    #if os(iOS)
      narrow ? PhoneDetail.margin : leading
    #else
      leading
    #endif
  }

  private var rowTrailing: CGFloat {
    #if os(iOS)
      narrow ? PhoneDetail.trailing : Astra.Spacing.pageTrailing
    #else
      Astra.Spacing.pageTrailing
    #endif
  }

  /// KP (2026-11-16, like Infuse): the seasons left to right with no dropdown,
  /// then the season's episodes left to right. Tapping an episode shows its
  /// details up top; Play / Resume or a double tap plays it.
  private var episodesSection: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(spacing: 12) {
        SeasonTabs(seasons: seasons, selected: selectedSeason, leading: rowLeading) { season in
          Task { await selectSeason(season) }
        }
      }
      .padding(.trailing, rowTrailing)
      episodeCardRow
    }
  }

  /// The season as a row of stills on every device. The row stays in place
  /// when the season changes; only its cards are replaced.
  private var episodeCardRow: some View {
    ScrollViewReader { proxy in
      ScrollView(.horizontal) {
        LazyHStack(alignment: .top, spacing: narrow ? 12 : 14) {
          ForEach(episodes) { episode in
            EpisodeCard(library: library, item: episode, selected: episode.ratingKey == focus?.ratingKey) {
              pick(episode)
            }
            .id(episode.ratingKey)
          }
        }
        .scrollTargetLayout()
        .padding(.leading, rowLeading)
        .padding(.trailing, rowTrailing)
      }
      .scrollIndicators(.never)
      .scrollClipDisabled()
      .scrollPosition(id: $rowPosition, anchor: .center)
      .task(id: revealEpisode) {
        guard let key = revealEpisode else { return }
        // Let the season's cards finish coming in, then bring the episode in.
        try? await Task.pause(0.4)
        rowPosition = key
        proxy.scrollTo(key, anchor: .center)
        revealEpisode = nil
      }
    }
  }

  private var castRow: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Cast").astraFont(.rowTitle).foregroundStyle(Astra.Color.ink).padding(.leading, leading)
      ScrollView(.horizontal) {
        LazyHStack(alignment: .top, spacing: 16) {
          ForEach(Array(titleItem.roles.prefix(20).enumerated()), id: \.offset) { _, role in
            VStack(spacing: 6) {
              RemoteImage(url: role.thumb.flatMap { URL(string: $0) })
                .frame(width: 84, height: 84)
                .clipShape(Circle())
                .overlay(Circle().stroke(Astra.Color.hairline))
              Text(role.tag).astraFont(size: 12, weight: .semibold).foregroundStyle(Astra.Color.ink)
                .lineLimit(1)
              if let character = role.role {
                Text(character).astraFont(size: 11).foregroundStyle(Astra.Color.muted).lineLimit(1)
              }
            }
            .frame(width: 96)
          }
        }
        .padding(.horizontal, leading)
      }
      .scrollIndicators(.never)
    }
  }

  // MARK: Loading

  private func load(refresh: Bool = false) async {
    // KP's requirement 14: how long a title takes to open, until its full
    // details show (Settings → Sources).
    let opened = Date()
    do {
      // A refresh reloads the title already shown; otherwise start from the seed.
      var key = refresh ? (item?.ratingKey ?? seed.ratingKey) : seed.ratingKey
      if key.hasPrefix("tmdb:") {
        // A title from a streaming tab: find it on the server, else show TMDB's details.
        // The library index usually knows at once: show the server's copy
        // (Play enabled) while its full details load (KP, 2026-11-08: 8 s
        // before a title on Plex could be played).
        if !refresh, let quick = library.indexMatch(seed) {
          astraWithAnimation(Astra.Motion.base) { item = quick }
        }
        do {
          key = try await library.resolve(seed).ratingKey
        } catch LibraryStore.CatalogError.notOnServer {
          notOnServer = true
          return
        }
      }
      let full = try await library.details(key, refresh: refresh)
      astraWithAnimation(Astra.Motion.base) { item = full }
      if !refresh {
        library.recordOpen(seconds: Date().timeIntervalSince(opened))
        PerfProbe.value("details.full.ms", Date().timeIntervalSince(opened) * 1000)
      }
      // KP (2026-11-14): a show, season or episode (Continue Watching) opens on
      // that episode's season with the episode picked.
      let keep = refresh ? focus?.ratingKey : nil
      switch full.type {
      case .show:
        try await loadSeasons(show: full.ratingKey, season: nil, episode: keep)
      case .season:
        if let show = full.parentRatingKey {
          try await loadSeasons(show: show, season: full.ratingKey, episode: keep)
        } else {
          selectedSeason = full
          episodes = try await library.children(of: full.ratingKey)
          pickDefaultEpisode(keep)
        }
      case .episode:
        if let show = full.grandparentRatingKey {
          try await loadSeasons(show: show, season: full.parentRatingKey, episode: keep ?? full.ratingKey)
        }
        if focus == nil { focus = full }
      default:
        break
      }
      let relatedKey =
        (full.type == .episode ? full.grandparentRatingKey : full.type == .season ? full.parentRatingKey : nil)
        ?? full.ratingKey
      related = await library.related(relatedKey)
      if !refresh { PerfProbe.value("details.complete.ms", Date().timeIntervalSince(opened) * 1000) }
    } catch {
      self.error = error.localizedDescription
    }
  }

  /// The show's seasons, opened on `season` (else the first one not watched
  /// yet) with `episode` picked (else the one to watch next).
  private func loadSeasons(show: String, season: String?, episode: String?) async throws {
    let all = try await library.children(of: show).filter { $0.type == .season }
    seasons = SeasonList.visible(all, showSpecials: showSpecials, keeping: season)
    let start =
      season.flatMap { key in seasons.first { $0.ratingKey == key } }
      ?? seasons.first { !$0.isWatched && ($0.index ?? 0) > 0 } ?? seasons.first
    if let start { await selectSeason(start) }
    pickDefaultEpisode(episode)
  }

  /// `key` when the season has it, else the episode in progress, else the first unwatched one.
  private func pickDefaultEpisode(_ key: String?) {
    let found =
      key.flatMap { key in episodes.first { $0.ratingKey == key } }
      ?? episodes.first { ($0.viewOffset ?? 0) > 0 } ?? episodes.first { !library.isWatched($0) } ?? episodes.first
    if let found {
      astraWithAnimation(Astra.Motion.base) { focus = found }
      revealEpisode = found.ratingKey
    }
  }

  private func selectSeason(_ season: PlexMetadata) async {
    selectedSeason = season
    let list = (try? await library.children(of: season.ratingKey)) ?? []
    astraWithAnimation(Astra.Motion.base) { episodes = list }
  }
}

/// The seasons left to right, like Infuse (KP, 2026-11-16: "no drop down").
/// The picked season is a glass capsule; the others are quiet text.
struct SeasonTabs: View {
  var seasons: [PlexMetadata]
  var selected: PlexMetadata?
  var leading: CGFloat
  var onPick: (PlexMetadata) -> Void

  var body: some View {
    if seasons.count > 1 {
      ScrollViewReader { proxy in
        ScrollView(.horizontal) {
          HStack(spacing: 6) {
            ForEach(seasons) { season in
              let isOn = season.id == (selected ?? seasons.first)?.id
              Button {
                onPick(season)
              } label: {
                Text(season.title)
                  .astraFont(size: 15, weight: isOn ? .semibold : .medium)
                  .foregroundStyle(isOn ? Astra.Color.ink : Astra.Color.muted)
                  .lineLimit(1)
                  .padding(.horizontal, 14)
                  .frame(height: 36)
                  .contentShape(Capsule())
                  .background {
                    if isOn { Color.clear.astraGlass(in: Capsule(), variant: .regular, interactive: true) }
                  }
              }
              .buttonStyle(.plain)
              .id(season.id)
              .accessibilityAddTraits(isOn ? [.isSelected] : [])
            }
          }
          .padding(.leading, leading - 14)
          .padding(.trailing, 8)
        }
        .scrollIndicators(.never)
        .scrollClipDisabled()
        .onAppear { if let selected { proxy.scrollTo(selected.id, anchor: .center) } }
        .onChange(of: selected?.id) { _, id in
          if let id { astraWithAnimation(Astra.Motion.base) { proxy.scrollTo(id, anchor: .center) } }
        }
      }
    } else {
      Text(selected?.title ?? seasons.first?.title ?? "Episodes")
        .astraFont(.rowTitle)
        .foregroundStyle(Astra.Color.ink)
        .lineLimit(1)
        .padding(.leading, leading)
      Spacer(minLength: 0)
    }
  }
}

/// One episode in a season's row (Mac, iPad). KP (2026-11-14): a tap picks it
/// and shows its details up top; a double tap or Play plays it.
struct EpisodeCard: View {
  var library: LibraryStore
  var item: PlexMetadata
  var selected = false
  var width: CGFloat = Astra.Layout.episodeCard.width
  var height: CGFloat = Astra.Layout.episodeCard.height
  var onSelect: () -> Void = {}

  @Environment(\.playItem) private var playItem

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      EpisodeStill(library: library, item: item, width: width, height: height)
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: Astra.Radius.card, style: .continuous))
        .watchedLook(library.isWatched(item))
        .overlay(alignment: .bottomLeading) {
          if let progress = item.progress { ProgressBar(value: progress).padding(10) }
        }
        .overlay {
          RoundedRectangle(cornerRadius: Astra.Radius.card, style: .continuous)
            .strokeBorder(selected ? Astra.Color.ink : Astra.Color.hairline, lineWidth: selected ? 2.5 : 1)
        }
        .pressable(hoverScale: 1.03)
      HStack(spacing: 8) {
        if let index = item.index {
          Text("\(index).").astraFont(size: 13, weight: .bold).foregroundStyle(Astra.Color.muted)
        }
        Text(item.title).astraFont(size: 13, weight: .semibold).foregroundStyle(Astra.Color.ink).lineLimit(1)
        Spacer(minLength: 0)
        if let duration = item.durationLabel {
          Text(duration).font(.system(size: 12)).foregroundStyle(Astra.Color.muted)
        }
        // Room for the download button drawn over this corner.
        Color.clear.frame(width: 30, height: 1)
      }
      if let summary = item.summary, !summary.isEmpty {
        Text(summary).astraFont(size: 12).foregroundStyle(Astra.Color.muted).lineLimit(2)
      }
    }
    .frame(width: width, alignment: .leading)
    .contentShape(Rectangle())
    .episodeTaps(item: item, selected: selected, onSelect: onSelect, play: playItem)
    .astraAnimation(Astra.Motion.fast, value: selected)
    .itemMenu(library: library, item: item)
    // Outside the card's taps, so it gets its own clicks.
    .overlay(alignment: .topTrailing) {
      DownloadButton(item: item, compact: true)
        .offset(x: 4, y: height + 1)
    }
  }
}

extension View {
  /// A single tap picks the episode at once; a double tap plays it (KP, 2026-11-14).
  func episodeTaps(
    item: PlexMetadata, selected: Bool, onSelect: @escaping () -> Void, play: @escaping (PlexMetadata) -> Void
  ) -> some View {
    self
      .onTapGesture(count: 2) { play(item) }
      .simultaneousGesture(TapGesture().onEnded { onSelect() })
      .accessibilityElement(children: .combine)
      .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
      .accessibilityHint("Shows this episode's details")
      .accessibilityAction { onSelect() }
      .accessibilityAction(named: "Play") { play(item) }
  }
}

/// Astra: on iPhone the secondary actions are round glass icons beside a wide Play.
struct ActionButtonShape: ViewModifier {
  var round: Bool
  func body(content: Content) -> some View {
    if round {
      content.astraIconButton(size: 46, variant: .clear)
    } else {
      content.astraSecondaryButton()
    }
  }
}

/// Reports how far a scroll view has scrolled (macOS 15 / iOS 18 and later;
/// older systems keep 0, so the backdrop simply scrolls with the page).
private struct ScrollOffsetReader: ViewModifier {
  @Binding var offset: CGFloat

  func body(content: Content) -> some View {
    if #available(macOS 15.0, iOS 18.0, *) {
      content.onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y + $0.contentInsets.top }) {
        offset = $1
      }
    } else {
      content
    }
  }
}

// MARK: - Details header pieces (KP's mockup, 2026-11-07)

/// "2014 • 2h 49m • Sci-Fi, Adventure"; a show gives its seasons instead of a length.
struct DetailMetaLine: View {
  var item: PlexMetadata
  /// For the official rating of titles Plex has none for (TMDB-only ones).
  var library: LibraryStore? = nil
  /// Details lists two genres; the hero doesn't (KP's mockup, 2026-11-08).
  var showsGenres = true
  var fontSize: CGFloat = 15
  var separator = "  ·  "
  /// How many genres; the hero shows one (KP's hero mockup, 2026-11-09).
  var genreLimit = 2
  /// The hero puts the rating box after the text: "2025 · 2h 8m · Sci-Fi [PG-13]".
  var ratingAfter = false
  /// iPhone hero and Details (KP, 2026-11-09): the rating in a grey filled box.
  var greyRating = false

  @State private var fetchedRating: String?
  @AppStorage(Preferences.ratingsKey) private var showRatings = true

  var body: some View {
    // KP (2026-11-09): the official rating sits in its own official-looking
    // box at the front of the line: "[PG-13]  2014 · 2h 49m".
    let parts = [
      item.year.map(String.init),
      item.type == .show ? item.childCount.map { "\($0) Season\($0 == 1 ? "" : "s")" } : item.durationLabel,
      showsGenres ? item.genres.prefix(genreLimit).map(\.tag).joined(separator: ", ").nilIfEmpty : nil,
    ].compactMap { $0 }
    let rating = showRatings ? item.officialRating ?? fetchedRating : nil
    HStack(spacing: fontSize * 0.6) {
      if !ratingAfter, let rating { RatingBox(text: rating, fontSize: fontSize * 0.8, grey: greyRating) }
      Text(parts.joined(separator: separator))
        .astraFont(size: fontSize, weight: .medium)
        .foregroundStyle(Astra.Color.ink.opacity(0.9))
        .lineLimit(1)
      if ratingAfter, let rating { RatingBox(text: rating, fontSize: fontSize * 0.8, grey: greyRating) }
    }
      .task(id: item.id) {
        fetchedRating = nil
        guard item.officialRating == nil, item.type == .movie || item.type == .show, let library else { return }
        fetchedRating = await library.tmdbArtwork(for: item)?.certification
      }
  }
}

/// KP's mockup (2026-11-16, Dune), on every platform:
/// "2024  [PG-13]  2h 46m  4K UHD  ◗◖Dolby Vision  ◗◖Dolby Atmos".
/// Only the rating sits in a thin outlined box; 4K UHD / 4K / HD is bold
/// text, and Dolby Vision and Dolby Atmos are Dolby's horizontal logos with
/// no background. HDR10, HDR10+ and HLG show a bold "HDR". It stays on one
/// line everywhere; on a narrow iPhone the gaps and type tighten slightly.
struct MetaBadgeRow: View {
  /// The movie or show: year, rating, length or seasons.
  var item: PlexMetadata
  /// The version that plays: resolution, HDR and Atmos.
  var playTarget: PlexMetadata
  /// For the official rating of titles Plex has none for (TMDB-only ones).
  var library: LibraryStore? = nil
  var fontSize: CGFloat = 15
  /// Kept for callers; the row is always a single line.
  var alignment: HorizontalAlignment = .leading

  /// TMDB's rating, genres and length, for what Plex didn't give (titles not on Plex).
  @State private var fetchedArt: TMDBArtwork?
  @AppStorage(Preferences.ratingsKey) private var showRatings = true
  @AppStorage(PlaybackQuality.storageKey) private var quality: PlaybackQuality = .auto
  @AppStorage(Preferences.qualityBadgesKey) private var showQuality = true
  @Environment(\.astraOnArt) private var onArt

  private var pick: PlaybackQuality { quality == .auto ? .current() : quality }
  private var gap: CGFloat { fontSize * 1.25 }

  var body: some View {
    // Always one line (KP, 2026-11-16: "it does fit"): the gaps tighten
    // first, then the type shrinks a little, before anything would clip.
    ViewThatFits(in: .horizontal) {
      line(gap: gap, size: fontSize)
      line(gap: fontSize * 0.8, size: fontSize)
      line(gap: fontSize * 0.6, size: fontSize * 0.9)
      line(gap: fontSize * 0.5, size: fontSize * 0.8)
    }
    .task(id: item.id) {
      fetchedArt = nil
      let missing = item.officialRating == nil || (item.type == .movie ? item.duration == nil : item.childCount == nil)
      guard missing, item.type == .movie || item.type == .show, let library else { return }
      fetchedArt = await library.tmdbArtwork(for: item)
    }
  }

  private func line(gap: CGFloat, size: CGFloat) -> some View {
    HStack(spacing: gap) {
      facts(size)
      badges(size)
    }
    .font(.system(size: size, weight: .regular))
    .foregroundStyle(Astra.Color.ink(onArt: onArt).opacity(0.95))
    .lineLimit(1)
  }

  @ViewBuilder private func facts(_ fontSize: CGFloat) -> some View {
    let item = item.filling(from: fetchedArt)
    if let year = item.year { Text(String(year)).fixedSize() }
    if showRatings, let rating = item.officialRating {
      Text(rating.uppercased())
        .font(.system(size: fontSize * 0.88, weight: .regular))
        .padding(.horizontal, fontSize * 0.32)
        .frame(height: fontSize * 1.32)
        .overlay(
          RoundedRectangle(cornerRadius: fontSize * 0.2, style: .continuous)
            .strokeBorder(Astra.Color.ink(onArt: onArt).opacity(0.85), lineWidth: max(1, fontSize * 0.06))
        )
        .fixedSize()
        .accessibilityLabel("Rated \(rating)")
    }
    let length = item.type == .show ? item.childCount.map { "\($0) Season\($0 == 1 ? "" : "s")" } : item.durationLabel
    if let length { Text(length).fixedSize() }
  }

  @ViewBuilder private func badges(_ fontSize: CGFloat) -> some View {
    if showQuality, let label = playTarget.qualityLabel(for: pick) {
      Text(label).fontWeight(.bold).fixedSize()
    }
    switch playTarget.dynamicRange(for: pick) {
    case .dolbyVision?: logo("format-dolby-vision-wide", fontSize).accessibilityLabel("Dolby Vision")
    case .hdr10Plus?, .hdr10?, .hlg?: Text("HDR").fontWeight(.bold).fixedSize()
    case nil: EmptyView()
    }
    if playTarget.hasAtmos(for: pick) {
      logo("format-dolby-atmos-wide", fontSize).accessibilityLabel("Dolby Atmos")
    }
  }

  private func logo(_ name: String, _ fontSize: CGFloat) -> some View {
    Image(name)
      .renderingMode(.template)
      .resizable()
      .scaledToFit()
      .frame(height: fontSize * 0.92)
      .fixedSize()
  }
}

/// Format badges are read from the sofa on Apple TV, so they grow more there
/// than other text does (the hub thread, 2026-11-08: they looked tiny at 1.6x).
#if os(tvOS)
  private let formatBadgeScale: CGFloat = 1.8
#else
  private let formatBadgeScale: CGFloat = 1
#endif

/// The format badges under the meta line: resolution, Dolby Atmos, then the
/// HDR format, each in a thin outlined pill (KP's Avatar mockup, 2026-11-08;
/// the hero uses the same row). Dolby Vision and Dolby Atmos use KP's official
/// logos (Formats.xcassets); HDR10, HDR10+ and HLG share a plain "HDR".
struct FormatBadges: View {
  var item: PlexMetadata

  @AppStorage(PlaybackQuality.storageKey) private var quality: PlaybackQuality = .auto
  @AppStorage(Preferences.qualityBadgesKey) private var showQuality = true

  private var pick: PlaybackQuality { quality == .auto ? .current() : quality }

  var body: some View {
    HStack(spacing: 10 * formatBadgeScale) {
      if showQuality, let badge = item.qualityLabel(for: pick) {
        FormatPill { Text(badge) }
      }
      if item.hasAtmos(for: pick) {
        FormatPill(logo: true) { logo("format-dolby-atmos", height: 16) }.accessibilityLabel("Dolby Atmos")
      }
      switch item.dynamicRange(for: pick) {
      case .dolbyVision?: FormatPill(logo: true) { logo("format-dolby-vision", height: 16) }.accessibilityLabel("Dolby Vision")
      // KP: one general HDR badge for HDR10, HDR10+ and HLG.
      case .hdr10Plus?, .hdr10?, .hlg?: FormatPill { Text("HDR") }
      case nil: EmptyView()
      }
    }
  }

  private func logo(_ name: String, height: CGFloat) -> some View {
    Image(name)
      .renderingMode(.template)
      .resizable()
      .scaledToFit()
      .frame(height: height * formatBadgeScale)
  }
}

/// One badge in the format row: clear, with a thin grey outline, rounded
/// corners and bold text (KP's Avatar mockup, 2026-11-08).
struct FormatPill<Content: View>: View {
  @Environment(\.astraOnArt) private var onArt
  /// A Dolby logo: tighter sides so the logo fills the pill and stays
  /// readable (badge audit, 2026-11-16: "VISION" was ~3 pt tall).
  var logo = false
  @ViewBuilder var content: Content

  var body: some View {
    content
      .font(.system(size: 13 * formatBadgeScale, weight: .bold))
      .foregroundStyle(Astra.Color.ink(onArt: onArt))
      .padding(.horizontal, (logo ? 7 : 10) * formatBadgeScale)
      .frame(height: 22 * formatBadgeScale)
      .overlay(
        RoundedRectangle(cornerRadius: 6 * formatBadgeScale, style: .continuous)
          .strokeBorder(Astra.Color.ink(onArt: onArt).opacity(0.5), lineWidth: 1)
      )
      .fixedSize()
  }
}

/// The official age rating (PG-13, R, TV-MA…) in a squared box with a solid
/// border and heavy condensed letters, like the rating box on a film's
/// poster or trailer (KP, 2026-11-09: "in a box… look very official"). The
/// same box on the hero, Details and Apple TV.
struct RatingBox: View {
  @Environment(\.astraOnArt) private var onArt
  var text: String
  var fontSize: CGFloat = 12
  /// A soft grey filled box instead of the outlined one (KP's iPhone mockup, 2026-11-09).
  var grey = false

  var body: some View {
    Text(text.uppercased())
      .font(.system(size: fontSize, weight: .heavy).width(.condensed))
      .tracking(fontSize * 0.05)
      .monospacedDigit()
      .foregroundStyle(Astra.Color.ink(onArt: onArt).opacity(grey ? 0.9 : 1))
      .padding(.horizontal, fontSize * 0.5)
      .frame(height: fontSize * 1.75)
      .background {
        if grey { RoundedRectangle(cornerRadius: fontSize * 0.3, style: .continuous).fill(Astra.Color.ink(onArt: onArt).opacity(0.22)) }
      }
      .overlay(
        RoundedRectangle(cornerRadius: fontSize * 0.16, style: .continuous)
          .strokeBorder(Astra.Color.ink(onArt: onArt), lineWidth: grey ? 0 : max(1.25, fontSize * 0.12))
      )
      .fixedSize()
      .accessibilityLabel("Rated \(text)")
  }
}

/// The summary, four lines with "More ⌄" to open the rest.
struct ExpandableSummary: View {
  var text: String
  @State private var expanded = false

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(text)
        .astraFont(size: 14.5)
        .lineSpacing(4)
        .foregroundStyle(Astra.Color.ink.opacity(0.85))
        .lineLimit(expanded ? nil : 4)
        .frame(maxWidth: 620, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
      if text.count > 160 {
        Button {
          astraWithAnimation(Astra.Motion.base) { expanded.toggle() }
        } label: {
          HStack(spacing: 4) {
            Text(expanded ? "Less" : "More")
            Image(systemName: "chevron.down")
              .astraFont(size: 10, weight: .bold)
              .rotationEffect(.degrees(expanded ? 180 : 0))
          }
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(Astra.Color.ink)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
    }
  }
}

/// Resume / Play on Details: a solid white capsule with black text (KP's mockup).
struct SolidCapsuleButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.astraOnArt) private var onArt

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 16 * Astra.Layout.controlScale, weight: .semibold))
      .foregroundStyle(Astra.Color.onSelection(onArt: onArt))
      .padding(.horizontal, 22 * Astra.Layout.controlScale)
      .frame(height: 50 * Astra.Layout.controlScale)
      .background(Capsule().fill(Astra.Color.ink(onArt: onArt).opacity(isEnabled ? 1 : 0.35)))
      .tvFocusLift(1.06)
      .scaleEffect(configuration.isPressed ? 0.97 : 1)
      .astraAnimation(.snappy(duration: 0.15), value: configuration.isPressed)
      .contentShape(Capsule())
  }
}

// MARK: - iPhone layout (KP's Avatar mockup, 2026-11-08)

#if os(iOS)
  /// Spacing and sizes for the iPhone Details page, measured off KP's mockup
  /// (drawn for a 393 pt wide iPhone; the hero scales with the width).
  enum PhoneDetail {
    static let margin: CGFloat = 24
    static let trailing: CGFloat = 22
    /// Where the logo starts, as a share of the width (175 pt on a 393 pt phone).
    static let logoTop: CGFloat = 0.6
    /// Where the logo sits on the card, as a share of the card's height (Plex's card, 2026-11-26).
    static let logoShare: CGFloat = 0.5
    /// How much slower than the page the card's art scrolls away (0 = with the page).
    static let artParallax: CGFloat = 0.4
    /// The card's logo box: smaller, like the Apple TV app's (KP, 2026-11-26).
    static let cardLogo = CGSize(width: 230, height: 96)
    /// The card's top corners (Plex's card, 2026-11-26).
    static let cardRadius: CGFloat = 34
    /// The X's distance from the card's top and leading edges.
    static let closeInset: CGFloat = 16
    /// The backdrop's height as a share of the width, fading into the page.
    /// Taller, and starting below the Dynamic Island so faces aren't cut
    /// off by it (KP, 2026-11-09: "the poster should be more down").
    static let backdropShare: CGFloat = 1.08
    static let backdropTop: CGFloat = 56
    /// The centred logo's box: as wide as the text column and 120 pt tall, so
    /// every logo grows until it meets one edge. Thin wide wordmarks (The
    /// Odyssey) fill the width and tall ones fill the height (KP, 2026-11-10:
    /// "Why is odyssey logo so small bro… make those logos way bigger").
    static let logoMaxWidth: CGFloat = 360
    static let logoHeight: CGFloat = 120
    static let sectionGap: CGFloat = 26
    static let actionColumn: CGFloat = 76
    static let actionCircle: CGFloat = 46
    static let resumeHeight: CGFloat = 48
    static let castPhoto = CGSize(width: 78, height: 62)
    /// Related rows are 2:3 posters (KP, 2026-11-09: "the posters below are way too small").
    static let relatedTile = CGSize(width: 120, height: 180)
    static let rowSpacing: CGFloat = 14

    /// A dark floor behind the floating tab bar: content fades out above it.
    @MainActor static var tabBarFloor: some View {
      LinearGradient(
        stops: [
          .init(color: Astra.Color.bg.opacity(0), location: 0),
          .init(color: Astra.Color.bg.opacity(0.5), location: 0.5),
          .init(color: Astra.Color.bg.opacity(0.72), location: 1),
        ], startPoint: .top, endPoint: .bottom
      )
      .frame(height: 120)
      .ignoresSafeArea(edges: .bottom)
      .allowsHitTesting(false)
    }
  }

  extension DetailView {
    /// KP (2026-11-26, "like the Plex card"): the artwork runs sharp to the
    /// card's top edge, then everything is centred under it: logo, the picked
    /// episode's name, the meta line, a full-width white Play / "Resume · 20m
    /// left", and a row of round actions with their names under them. The
    /// synopsis, director and the file's Video / Audio / Subtitles follow.
    var phoneHeader: some View {
      let width = max(pageWidth, 320)
      // The logo sits where the art starts to fade, a little over half way
      // down the card (Plex's card, 2026-11-26).
      let logoTop = min(470, max(320, viewport * PhoneDetail.logoShare))
      return VStack(alignment: .leading, spacing: 0) {
        // KP (2026-11-26, the Apple TV app): the title's own coloured logo,
        // smaller, sitting on the art just above the info.
        HeroTitle(
          library: library, item: titleItem,
          maxWidth: min(PhoneDetail.cardLogo.width, width - PhoneDetail.margin - PhoneDetail.trailing),
          maxHeight: PhoneDetail.cardLogo.height,
          alignment: .bottom, kind: .officialLogo
        )
        .frame(maxWidth: .infinity)
        .frame(height: PhoneDetail.cardLogo.height, alignment: .bottom)
        if let focus, focus.type == .episode {
          // "One Day in the Valley", then "S3 · E2 · 26m" (Plex's episode card).
          VStack(spacing: 4) {
            Text(focus.title)
              .astraFont(size: 19, weight: .semibold)
              .foregroundStyle(Astra.Color.ink.opacity(0.92))
              .lineLimit(1)
              .minimumScaleFactor(0.85)
            Text([focus.episodeLabel, focus.durationLabel].compactMap { $0 }.joined(separator: "  ·  "))
              .astraFont(size: 13.5, weight: .medium)
              .foregroundStyle(Astra.Color.muted)
          }
          .multilineTextAlignment(.center)
          .frame(maxWidth: .infinity)
          .padding(.top, 12)
          .id(focus.ratingKey)
          .transition(.opacity)
          .accessibilityElement(children: .combine)
        }
        // "2024 • 2h 46m • [PG-13] [HD] [Dolby Atmos]", the genres under it.
        MetaBadgeRow(item: titleItem, playTarget: playTarget, library: library, fontSize: 14, alignment: .center)
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
        if !titleItem.genres.isEmpty {
          Text(titleItem.genres.prefix(3).map(\.tag).joined(separator: " · "))
            .astraFont(size: 13.5)
            .foregroundStyle(Astra.Color.ink.opacity(0.62))
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .padding(.top, 6)
        }
        phonePlayButton
          .padding(.top, 18)
        phoneActions
          .padding(.top, 16)
        if let summary = headerSummary, !summary.isEmpty {
          Text(summary)
            .astraFont(size: 15)
            .lineSpacing(3)
            .foregroundStyle(Astra.Color.ink.opacity(0.86))
            .lineLimit(summaryExpanded ? nil : 3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 20)
            .contentShape(Rectangle())
            .onTapGesture {
              guard summary.count > 120 else { return }
              astraWithAnimation(Astra.Motion.base) { summaryExpanded.toggle() }
            }
            .accessibilityHint(summary.count > 120 ? "Shows the whole synopsis" : "")
        }
        if !playTarget.directors.isEmpty {
          Text("Directed by \(playTarget.directors.prefix(2).map(\.tag).joined(separator: ", "))")
            .astraFont(size: 14, weight: .semibold)
            .foregroundStyle(Astra.Color.muted)
            .lineLimit(1)
            .padding(.top, 8)
        }
        if let file = PhoneFileInfo(item: playTarget) {
          file.padding(.top, 22)
        }
        if notOnServer {
          Text("Not on your Plex server.").astraFont(size: 13).foregroundStyle(Astra.Color.muted).padding(.top, 10)
        }
        if let error {
          Text(error).astraFont(size: 13).foregroundStyle(Astra.Color.muted).padding(.top, 10)
        }
      }
      .padding(.leading, PhoneDetail.margin)
      .padding(.trailing, PhoneDetail.trailing)
      .padding(.top, logoTop)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(alignment: .top) {
        ZStack {
          // KP (2026-11-09): framed so the faces end above the logo, for any title.
          FramedArtwork(
            library: library, item: titleItem, kind: .keyArt, zoneHeight: logoTop + 90, limitY: logoTop - 4,
            imageURL: episodeStill, fadesTop: false)
          PhoneDetail.backdropShade
        }
        .frame(width: width, height: logoTop + 90)
        // Sharp at the card's top edge, melting into the colour below (Plex's card).
        .mask(PhoneDetail.cardArtMask)
        // KP (2026-11-26, "how everything acts", like the Apple TV app): pulling
        // the page down past the top stretches the art from its top edge, and
        // scrolling up carries it up with the page, a little slower (parallax),
        // instead of holding it still and fading it.
        .scaleEffect(1 + max(0, -scrolled) / (logoTop + 90), anchor: .bottom)
        .offset(y: max(0, scrolled) * PhoneDetail.artParallax)
      }
    }

    /// The full-width white Play, or "Resume · 20m left" with a ring showing
    /// how much is watched (Plex's card).
    private var phonePlayButton: some View {
      Button {
        playItem(playTarget)
      } label: {
        HStack(spacing: 10) {
          if let progress = resumeProgress {
            PhoneProgressRing(value: progress)
          } else {
            Image(systemName: "play.fill")
          }
          Text(timeLeft.map { "\(playLabel) · \($0)" } ?? playLabel)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .contentTransition(.opacity)
        }
        .frame(maxWidth: .infinity)
      }
      .buttonStyle(SolidCapsuleButtonStyle())
      .disabled(shown.isCatalogOnly || !app.canPlay(playTarget))
    }

    /// My List, Mark as Watched, Download and More: round glass with the name
    /// under each, spread across the card (Plex's card).
    private var phoneActions: some View {
      HStack(alignment: .top, spacing: 0) {
        if let target = watchlistTarget {
          PhoneWatchlistColumn(item: target).frame(maxWidth: .infinity)
        }
        if !shown.isCatalogOnly, shown.type == .movie || playTarget.type == .episode {
          PhoneWatchedColumn(library: library, item: playTarget).frame(maxWidth: .infinity)
        }
        if shown.type != .collection, !shown.isCatalogOnly {
          DownloadButton(item: shown, labeled: true).frame(maxWidth: .infinity)
        }
        if !shown.isCatalogOnly {
          Menu {
            ItemMenuItems(library: library, item: playTarget, onDetails: true)
          } label: {
            PhoneActionLabel(title: "More") { Image(systemName: "ellipsis") }
          }
          .menuIndicator(.hidden)
          .buttonStyle(PhoneActionButtonStyle())
          .frame(maxWidth: .infinity)
        }
      }
    }

    var phoneCastRow: some View {
      VStack(alignment: .leading, spacing: 12) {
        PhoneRowHeader(title: "Cast") { showAllCast = true }
        ScrollView(.horizontal) {
          LazyHStack(alignment: .top, spacing: PhoneDetail.rowSpacing) {
            ForEach(Array(titleItem.roles.prefix(20).enumerated()), id: \.offset) { _, role in
              PhoneCastCard(role: role)
            }
          }
          .padding(.horizontal, PhoneDetail.margin)
        }
        .scrollIndicators(.never)
      }
    }

    func phoneRelatedRow(_ hub: PlexHub) -> some View {
      VStack(alignment: .leading, spacing: 12) {
        PhoneRowHeader(title: hub.title) { allRelated = hub }
        ScrollView(.horizontal) {
          LazyHStack(alignment: .top, spacing: PhoneDetail.rowSpacing) {
            ForEach(hub.items) { PhoneRelatedTile(library: library, item: $0) }
          }
          .padding(.horizontal, PhoneDetail.margin)
        }
        .scrollIndicators(.never)
        .scrollClipDisabled()
      }
    }
  }

  extension PhoneDetail {
    /// Where the sharp artwork shows: soft at the top edge, fading out under the
    /// logo and buttons so the frosted blur takes over without a seam.
    static var backdropMask: some View {
      LinearGradient(
        stops: [
          .init(color: .black.opacity(0), location: 0),
          .init(color: .black, location: 0.14),
          .init(color: .black, location: 0.45),
          .init(color: .black.opacity(0.55), location: 0.7),
          .init(color: .black.opacity(0), location: 1),
        ], startPoint: .top, endPoint: .bottom)
    }

    /// The card's artwork: sharp at the top edge, fading out under the logo
    /// so the colour of the card takes over without a seam (Plex's card).
    static var cardArtMask: some View {
      LinearGradient(
        stops: [
          .init(color: .black, location: 0),
          .init(color: .black, location: 0.55),
          .init(color: .black.opacity(0.7), location: 0.72),
          .init(color: .black.opacity(0.25), location: 0.88),
          .init(color: .black.opacity(0), location: 1),
        ], startPoint: .top, endPoint: .bottom)
    }

    /// A light shade on the lower artwork so the logo and meta line stay readable.
    @MainActor static var backdropShade: some View {
      LinearGradient(
        stops: [
          .init(color: Astra.Color.bg.opacity(0), location: 0.35),
          .init(color: Astra.Color.bg.opacity(AstraAppearance.shared.palette.isLight ? 0.5 : 0.35), location: 1),
        ], startPoint: .top, endPoint: .bottom
      )
      .allowsHitTesting(false)
    }
  }

  /// iPhone Details as a card (KP, 2026-11-26, like Plex): the page is
  /// clipped to a card whose rounded top sits just under the status bar, with
  /// a round glass X at its top left. The whole card is what the zoom
  /// transition moves, so dragging it shrinks and follows the finger.
  struct PhoneDetailCard: ViewModifier {
    var enabled: Bool
    var close: () -> Void

    @State private var topInset: CGFloat = Self.windowTopInset

    /// The status bar's height before the first layout, so the card never jumps.
    private static var windowTopInset: CGFloat {
      UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.keyWindow?.safeAreaInsets.top
        ?? 59
    }

    func body(content: Content) -> some View {
      if enabled {
        let card = UnevenRoundedRectangle(
          topLeadingRadius: PhoneDetail.cardRadius, topTrailingRadius: PhoneDetail.cardRadius, style: .continuous)
        content
          .overlay(alignment: .topLeading) {
            Button(action: close) {
              Image(systemName: "xmark")
            }
            .astraIconButton(size: 40, variant: .clear)
            .accessibilityLabel("Close")
            .padding(PhoneDetail.closeInset)
          }
          .clipShape(card)
          .overlay(card.stroke(Astra.Color.hairline).allowsHitTesting(false))
          .padding(.top, topInset)
          .background(Astra.Color.bg)
          .ignoresSafeArea(edges: .top)
          .onGeometryChange(for: CGFloat.self, of: { $0.safeAreaInsets.top }) { inset in
            if inset > 0 { topInset = inset }
          }
      } else {
        content
      }
    }
  }

  /// The colour behind the iPhone Details card (KP, 2026-11-26, like Plex):
  /// no blur, one smooth colour taken from the card's own picture, rich just
  /// under the art and deepening to near black at the foot. It holds still
  /// while the page scrolls, and eases to the new colour when the episode changes.
  struct PhoneFrostedBackground: View {
    var library: LibraryStore
    var item: PlexMetadata
    var kind: LibraryStore.ArtKind = .heroBackdrop
    /// A picture to use instead of the title's artwork (a picked episode's still).
    var imageURL: URL? = nil

    @State private var colour: ArtColour?

    var body: some View {
      ZStack {
        Astra.Color.bg
        if let colour {
          LinearGradient(
            stops: [
              .init(color: colour.top, location: 0),
              .init(color: colour.top, location: 0.3),
              .init(color: colour.bottom, location: 1),
            ], startPoint: .top, endPoint: .bottom)
          .transition(.opacity)
        }
      }
      .astraAnimation(Astra.Motion.page, value: colour)
      .ignoresSafeArea()
      .allowsHitTesting(false)
      .accessibilityHidden(true)
      .task(id: "\(item.id)|\(imageURL?.absoluteString ?? "")") {
        let found: URL?
        if let imageURL { found = imageURL } else { found = await library.artworkURL(for: item, kind, width: 780, height: 1170) }
        guard let found, !Task.isCancelled else { return }
        if let hit = ArtColourStore.shared.cached(found) {
          colour = hit
          return
        }
        let measured = await ArtColourStore.shared.colour(for: found)
        guard !Task.isCancelled, let measured else { return }
        colour = measured
      }
    }
  }

  /// "Cast  >": a section title with a chevron that opens the full list.
  struct PhoneRowHeader: View {
    var title: String
    var action: () -> Void

    var body: some View {
      Button(action: action) {
        HStack {
          Text(title).astraFont(size: 21, weight: .bold).foregroundStyle(Astra.Color.ink).lineLimit(1)
          Spacer(minLength: 8)
          Image(systemName: "chevron.right")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Astra.Color.ink.opacity(0.85))
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .padding(.leading, PhoneDetail.margin)
      .padding(.trailing, PhoneDetail.trailing)
      .accessibilityLabel("\(title), see all")
    }
  }

  /// Resume / Play: a bright Liquid Glass capsule, the strongest control on the page.
  struct PhoneResumeButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.astraAccent) private var accent

    func makeBody(configuration: Configuration) -> some View {
      configuration.label
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(.white)
        .labelStyle(.titleAndIcon)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.horizontal, 18)
        .frame(height: PhoneDetail.resumeHeight)
        .contentShape(Capsule())
        .shadow(color: .black.opacity(0.35), radius: 3)
        // Light theme: dark glass, so the white label still reads on a pale page.
        .astraGlass(
          in: Capsule(), variant: .clear, interactive: true,
          tint: accent?.opacity(0.6)
            ?? (AstraAppearance.shared.palette.isLight ? Astra.Color.ink.opacity(0.82) : .white.opacity(0.32)))
        .astraGlassEdge(Capsule(), strength: 1.1)
        .scaleEffect(configuration.isPressed ? 0.97 : 1)
        .opacity(isEnabled ? 1 : 0.45)
        .astraAnimation(Astra.Motion.fast, value: configuration.isPressed)
    }
  }

  /// A round glass icon with its name under it (KP, 2026-11-26: like Plex's
  /// card; replaces the 2026-11-09 icon-only circles).
  struct PhoneActionLabel<Icon: View>: View {
    var title: String
    @ViewBuilder var icon: Icon

    var body: some View {
      VStack(spacing: 7) {
        icon
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(Astra.Color.ink)
          .frame(width: PhoneDetail.actionCircle, height: PhoneDetail.actionCircle)
          .astraGlass(in: Circle(), variant: .regular, interactive: true)
          .astraGlassEdge(Circle(), strength: 0.6)
        Text(title)
          .astraFont(size: 11.5, weight: .medium)
          .foregroundStyle(Astra.Color.muted)
          .multilineTextAlignment(.center)
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(width: PhoneDetail.actionColumn)
      .contentShape(Rectangle())
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(title)
    }
  }

  struct PhoneActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
      configuration.label
        .scaleEffect(configuration.isPressed ? 0.94 : 1)
        .astraAnimation(Astra.Motion.fast, value: configuration.isPressed)
    }
  }

  /// My List: the Plex Watchlist, a bookmark (filled once added).
  struct PhoneWatchlistColumn: View {
    var item: PlexMetadata
    @Environment(AppModel.self) private var app

    var body: some View {
      let on = app.isOnWatchlist(item)
      Button {
        Task { await app.toggleWatchlist(item) }
      } label: {
        PhoneActionLabel(title: on ? "On My List" : "My List") {
          Image(systemName: on ? "bookmark.fill" : "bookmark").contentTransition(.symbolEffect(.replace))
        }
      }
      .buttonStyle(PhoneActionButtonStyle())
      .sensoryFeedback(.success, trigger: on)
      .accessibilityLabel(on ? "Remove from My List" : "Add to My List")
      .task { await app.loadWatchlistIfNeeded() }
    }
  }

  /// The thin bar under Resume: white fill on a faint track.
  struct PhoneProgressLine: View {
    var value: Double

    var body: some View {
      Capsule()
        .fill(.white.opacity(0.2))
        .frame(height: 4)
        .overlay(alignment: .leading) {
          GeometryReader { geo in
            Capsule().fill(.white).frame(width: max(4, geo.size.width * value))
          }
        }
        .accessibilityElement()
        .accessibilityLabel("Watched \(Int(value * 100)) percent")
    }
  }

  /// Mark as Watched / Watched: a tick in a ring, filled once watched; flips at once.
  struct PhoneWatchedColumn: View {
    var library: LibraryStore
    var item: PlexMetadata

    var body: some View {
      let on = library.isWatched(item)
      Button {
        Task { await library.setWatched(item, watched: !on) }
      } label: {
        PhoneActionLabel(title: on ? "Watched" : "Mark as Watched") {
          Image(systemName: on ? "checkmark.circle.fill" : "checkmark.circle")
            .contentTransition(.symbolEffect(.replace))
        }
      }
      .buttonStyle(PhoneActionButtonStyle())
      .sensoryFeedback(.success, trigger: on)
      .accessibilityLabel(on ? "Mark as Unwatched" : "Mark as Watched")
    }
  }

  /// The small ring inside "Resume · 20m left": how much has been watched.
  struct PhoneProgressRing: View {
    var value: Double

    var body: some View {
      ZStack {
        Circle().stroke(.foreground.opacity(0.2), lineWidth: 2.5)
        Circle()
          .trim(from: 0, to: max(0.04, value))
          .stroke(.foreground, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
          .rotationEffect(.degrees(-90))
      }
      .frame(width: 17, height: 17)
      .accessibilityHidden(true)
    }
  }

  /// "Video 1080p (H.264) / Audio English (AC3 5.1) / Subtitles Off", the
  /// file that will play (Plex's card). Nil for shows and seasons.
  struct PhoneFileInfo: View {
    let rows: [(String, String)]

    init?(item: PlexMetadata) {
      guard item.type == .movie || item.type == .episode, let media = item.media.first else { return nil }
      let streams = media.parts.first?.streams ?? []
      func pick(_ type: Int) -> PlexStream? {
        streams.first { $0.streamType == type && $0.selected == true }
          ?? streams.first { $0.streamType == type && $0.default == true }
          ?? (type == 3 ? nil : streams.first { $0.streamType == type })
      }
      var rows: [(String, String)] = []
      let video = pick(1)?.displayTitle
        ?? [media.videoResolution.map { $0.allSatisfy(\.isNumber) ? "\($0)p" : $0.uppercased() },
            media.videoCodec.map { "(\($0.uppercased()))" }].compactMap { $0 }.joined(separator: " ").nilIfEmpty
      if let video { rows.append(("Video", video)) }
      let audio = pick(2)?.displayTitle
        ?? [media.audioCodec?.uppercased(), media.audioChannels.map { "\($0)ch" }].compactMap { $0 }
          .joined(separator: " ").nilIfEmpty
      if let audio { rows.append(("Audio", audio)) }
      rows.append(("Subtitles", pick(3)?.displayTitle ?? "Off"))
      guard rows.count > 1 else { return nil }
      self.rows = rows
    }

    var body: some View {
      Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
        ForEach(rows, id: \.0) { row in
          GridRow {
            Text(row.0).foregroundStyle(Astra.Color.muted)
            Text(row.1).foregroundStyle(Astra.Color.ink.opacity(0.9)).lineLimit(1)
          }
        }
      }
      .astraFont(size: 15)
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityElement(children: .combine)
    }
  }

  /// A rounded photo with the name on two lines and the character under it.
  struct PhoneCastCard: View {
    var role: PlexTag

    var body: some View {
      VStack(spacing: 6) {
        RemoteImage(url: role.thumb.flatMap { URL(string: $0) })
          .frame(width: PhoneDetail.castPhoto.width, height: PhoneDetail.castPhoto.height)
          .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
          .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Astra.Color.hairline))
          .overlay {
            if role.thumb == nil {
              Image(systemName: "person.fill").font(.system(size: 22)).foregroundStyle(Astra.Color.muted)
            }
          }
        Text(role.tag)
          .astraFont(size: 13, weight: .semibold)
          .foregroundStyle(Astra.Color.ink)
          .multilineTextAlignment(.center)
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
        if let character = role.role, !character.isEmpty {
          Text(character)
            .astraFont(size: 12)
            .foregroundStyle(Astra.Color.muted)
            .multilineTextAlignment(.center)
            .lineLimit(1)
        }
      }
      .frame(width: PhoneDetail.castPhoto.width + 8)
    }
  }

  /// More Like This: artwork with the title's logo on it, no caption (KP's mockup).
  struct PhoneRelatedTile: View {
    var library: LibraryStore
    var item: PlexMetadata
    var size: CGSize = PhoneDetail.relatedTile

    @Environment(\.openItem) private var openItem
    @State private var logo: URL?
    @State private var resolved = false

    var body: some View {
      Button {
        openItem(item)
      } label: {
        ZStack(alignment: .bottom) {
          ArtworkImage(library: library, item: item, kind: .poster, width: size.width * 3, height: size.height * 3)
            .frame(width: size.width, height: size.height)
          // Posters carry their own title; a name only when there's no artwork.
          Group {
            if logo == nil, resolved, item.thumb == nil {
              Text(item.displayTitle)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            }
          }
          .padding(.horizontal, 6)
          .padding(.bottom, 8)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .detailZoomSource(item)
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Astra.Color.hairline))
        .contentShape(Rectangle())
      }
      .buttonStyle(AstraCardButtonStyle())
      .itemMenu(library: library, item: item)
      .accessibilityLabel(item.displayTitle)
      .task(id: item.id) {
        logo = await library.artworkURL(for: item, .logo, width: size.width * 3, height: size.height)
        resolved = true
      }
    }
  }

  /// The full cast, from the Cast row's chevron.
  struct PhoneCastList: View {
    var roles: [PlexTag]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
      NavigationStack {
        List(Array(roles.enumerated()), id: \.offset) { _, role in
          HStack(spacing: 14) {
            RemoteImage(url: role.thumb.flatMap { URL(string: $0) })
              .frame(width: 52, height: 52)
              .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
              Text(role.tag).font(.system(size: 16, weight: .semibold)).foregroundStyle(Astra.Color.ink)
              if let character = role.role, !character.isEmpty {
                Text(character).font(.system(size: 14)).foregroundStyle(Astra.Color.muted)
              }
            }
          }
          .listRowBackground(Astra.Color.bg)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Astra.Color.bg)
        .navigationTitle("Cast")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .topBarTrailing) {
            Button("Done") { dismiss() }
          }
        }
      }
      .presentationDragIndicator(.visible)
      .preferredColorScheme(.dark)
    }
  }

  /// Everything in a related row, as a grid, from the row's chevron.
  struct PhoneRelatedGrid: View {
    var library: LibraryStore
    var hub: PlexHub
    var open: (PlexMetadata) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
      NavigationStack {
        ScrollView {
          LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 16) {
            ForEach(hub.items) { item in
              PosterCard(library: library, item: item, width: 104)
            }
          }
          .padding(16)
        }
        .background(Astra.Color.bg)
        .navigationTitle(hub.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .topBarTrailing) {
            Button("Done") { dismiss() }
          }
        }
      }
      .environment(\.openItem) { open($0) }
      .presentationDragIndicator(.visible)
      .preferredColorScheme(.dark)
    }
  }
#endif
