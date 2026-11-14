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
  @State private var selectedSeason: PlexMetadata?
  @State private var episodes: [PlexMetadata] = []
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

  var body: some View {
    ScrollView(.vertical) {
      // A plain VStack: a lazy one guesses row heights and makes the page jump while scrolling.
      VStack(alignment: .leading, spacing: sectionSpacing) {
        deviceHeader
        // Astra (KP, 2026-11-07): the backdrop stays still while the page
        // scrolls, so everything below the header covers it as it rises.
        VStack(alignment: .leading, spacing: sectionSpacing) {
          if shown.type == .show || shown.type == .season, !seasons.isEmpty || !episodes.isEmpty {
            episodesSection
          }
          if !shown.roles.isEmpty {
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
    .onGeometryChange(for: CGSize.self, of: { $0.size }) {
      viewport = $0.height
      pageWidth = $0.width
    }
    // The backdrop runs under the title bar; the back button below stays inside the safe area.
    .ignoresSafeArea(edges: .top)
    .background { pageBackground }
    #if os(macOS)
      .overlay(alignment: .topTrailing) {
        HStack(spacing: 10) {
          // KP (2026-11-08): ••• beside the X with the title's actions.
          if !shown.isCatalogOnly {
            moreMenu
              .menuStyle(.button)
              .astraIconButton(size: 36, variant: .clear)
          }
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
        }
        .padding(.trailing, 18)
        .padding(.top, 18)
      }
    #elseif os(iOS)
      // iPhone keeps the system back button (Liquid Glass on iOS 26) and swipe-back.
      .toolbarBackground(.hidden, for: .navigationBar)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        // KP (2026-11-08): ••• top right with the title's actions (the bar gives it its glass).
        if !shown.isCatalogOnly {
          ToolbarItem(placement: .topBarTrailing) { moreMenu }
        }
      }
      // The floating tab bar gets a dark floor, so it never sits on top of the
      // cast or posters (KP's mockup, 2026-11-08).
      .overlay(alignment: .bottom) {
        if narrow { BottomEdgeBlur() }
      }
      .sheet(isPresented: $showAllCast) { PhoneCastList(roles: shown.roles) }
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
      ItemMenuItems(library: library, item: shown, onDetails: true)
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
        PhoneFrostedBackground(library: library, item: shown)
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
      HeroTitle(library: library, item: shown, maxWidth: narrow ? 250 : 380, maxHeight: narrow ? 92 : 120)
        .padding(.bottom, 4)
      DetailMetaLine(item: shown, library: library)
      FormatBadges(item: shown)
      if let tagline = shown.tagline, !tagline.isEmpty {
        Text(tagline)
          .astraFont(size: 15, weight: .semibold)
          .italic()
          .foregroundStyle(Astra.Color.ink.opacity(0.9))
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.top, 4)
      }
      if let summary = shown.summary, !summary.isEmpty {
        ExpandableSummary(text: summary)
      }
      HStack(spacing: 12) {
        Button {
          playItem(shown)
        } label: {
          Label(playLabel, systemImage: "play.fill")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(SolidCapsuleButtonStyle())
        #if !os(tvOS)
          .keyboardShortcut(isActive ? .defaultAction : nil)
        #endif
        .disabled(shown.isCatalogOnly || !app.canPlay(shown))

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
      if !shown.directors.isEmpty {
        Text("Directed by \(shown.directors.map(\.tag).joined(separator: ", "))")
          .astraFont(size: 13).foregroundStyle(Astra.Color.muted).lineLimit(1)
      }
      if notOnServer {
        Text("Not on your Plex server.").astraFont(size: 13).foregroundStyle(Astra.Color.muted)
      }
      if let error {
        Text(error).astraFont(size: 13).foregroundStyle(Astra.Color.muted)
      }
    }
    .padding(.leading, leading)
    .padding(.trailing, Astra.Spacing.pageTrailing)
    // Room for the backdrop above the text, and for the back button.
    .padding(.top, max(140, viewport * 0.32))
    .padding(.bottom, 30)
    .frame(maxWidth: .infinity, minHeight: min(Astra.Layout.detailHeaderHeight, viewport * 0.72), alignment: .bottomLeading)
    .background {
      ZStack {
        ArtworkImage(library: library, item: shown, kind: .scenery, width: 1920, height: 1080, placeholder: Color.clear)
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
    if shown.type == .movie || shown.type == .episode { return shown.progress != nil ? "Resume" : "Play" }
    if let next = episodes.first(where: { ($0.viewOffset ?? 0) > 0 }) ?? episodes.first(where: { !$0.isWatched }),
      let label = next.episodeLabel
    {
      return "Play \(label.replacingOccurrences(of: " · ", with: " "))"
    }
    return "Play"
  }

  // MARK: Episodes

  private var episodesSection: some View {
    VStack(alignment: .leading, spacing: 14) {
      if seasons.count > 1 {
        ScrollView(.horizontal) {
          HStack(spacing: 8) {
            ForEach(seasons) { season in
              let selected = season.id == selectedSeason?.id
              Button(season.title) {
                Task { await selectSeason(season) }
              }
              .buttonStyle(.plain)
              .font(.system(size: 13, weight: .semibold))
              .foregroundStyle(selected ? Astra.Color.onAccent : Astra.Color.muted)
              .padding(.horizontal, 16)
              .frame(height: 34)
              .background {
                if selected { Capsule().fill(Astra.Color.accent) } else { Capsule().fill(Astra.Color.ink.opacity(0.08)) }
              }
              .astraAnimation(Astra.Motion.base, value: selected)
            }
          }
          .padding(.horizontal, leading)
        }
        .scrollIndicators(.never)
        .scrollClipDisabled()
      }
      HStack(spacing: Astra.Spacing.m) {
        Text(selectedSeason?.title ?? "Episodes")
          .astraFont(.rowTitle)
          .foregroundStyle(Astra.Color.ink)
          .lineLimit(1)
        if let selectedSeason, seasons.count > 1 {
          DownloadButton(item: selectedSeason, compact: true)
        }
      }
      .padding(.leading, leading)
      // The row stays in place when the season changes; only its cards are replaced.
      ScrollView(.horizontal) {
        LazyHStack(alignment: .top, spacing: 14) {
          ForEach(episodes) { episode in
            EpisodeCard(library: library, item: episode)
          }
        }
        .padding(.horizontal, leading)
      }
      .scrollIndicators(.never)
      .scrollClipDisabled()
    }
  }

  private var castRow: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Cast").astraFont(.rowTitle).foregroundStyle(Astra.Color.ink).padding(.leading, leading)
      ScrollView(.horizontal) {
        LazyHStack(alignment: .top, spacing: 16) {
          ForEach(Array(shown.roles.prefix(20).enumerated()), id: \.offset) { _, role in
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
      switch full.type {
      case .show:
        seasons = try await library.children(of: full.ratingKey).filter { $0.type == .season }
        let start = seasons.first { !$0.isWatched && ($0.index ?? 0) > 0 } ?? seasons.first
        if let start { await selectSeason(start) }
      case .season:
        episodes = try await library.children(of: full.ratingKey)
      default:
        break
      }
      related = await library.related(full.ratingKey)
      if !refresh { PerfProbe.value("details.complete.ms", Date().timeIntervalSince(opened) * 1000) }
    } catch {
      self.error = error.localizedDescription
    }
  }

  private func selectSeason(_ season: PlexMetadata) async {
    selectedSeason = season
    episodes = (try? await library.children(of: season.ratingKey)) ?? []
  }
}

struct EpisodeCard: View {
  var library: LibraryStore
  var item: PlexMetadata
  var width: CGFloat = Astra.Layout.episodeCard.width
  var height: CGFloat = Astra.Layout.episodeCard.height

  @Environment(\.playItem) private var playItem

  var body: some View {
    Button {
      playItem(item)
    } label: {
      VStack(alignment: .leading, spacing: 8) {
        RemoteImage(url: library.imageURL(item.thumb, width: width, height: height))
          .frame(width: width, height: height)
          .clipShape(RoundedRectangle(cornerRadius: Astra.Radius.card, style: .continuous))
          .overlay(alignment: .bottomLeading) {
            if let progress = item.progress { ProgressBar(value: progress).padding(10) }
          }
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
    }
    .buttonStyle(AstraCardButtonStyle())
    .itemMenu(library: library, item: item)
    // Outside the card's button, so it gets its own clicks.
    .overlay(alignment: .topTrailing) {
      DownloadButton(item: item, compact: true)
        .offset(x: 4, y: height + 1)
    }
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
      if showQuality, let badge = item.resolutionBadge(for: pick) {
        FormatPill { Text(badge == "4K UHD" ? "4K" : badge) }
      }
      if item.hasAtmos(for: pick) {
        FormatPill { logo("format-dolby-atmos", height: 11) }.accessibilityLabel("Dolby Atmos")
      }
      switch item.dynamicRange(for: pick) {
      case .dolbyVision?: FormatPill { logo("format-dolby-vision", height: 12) }.accessibilityLabel("Dolby Vision")
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
  @ViewBuilder var content: Content

  var body: some View {
    content
      .font(.system(size: 13 * formatBadgeScale, weight: .bold))
      .foregroundStyle(Astra.Color.ink)
      .padding(.horizontal, 10 * formatBadgeScale)
      .frame(height: 22 * formatBadgeScale)
      .overlay(
        RoundedRectangle(cornerRadius: 6 * formatBadgeScale, style: .continuous)
          .strokeBorder(Astra.Color.ink.opacity(0.5), lineWidth: 1)
      )
      .fixedSize()
  }
}

/// The official age rating (PG-13, R, TV-MA…) in a squared box with a solid
/// border and heavy condensed letters, like the rating box on a film's
/// poster or trailer (KP, 2026-11-09: "in a box… look very official"). The
/// same box on the hero, Details and Apple TV.
struct RatingBox: View {
  var text: String
  var fontSize: CGFloat = 12
  /// A soft grey filled box instead of the outlined one (KP's iPhone mockup, 2026-11-09).
  var grey = false

  var body: some View {
    Text(text.uppercased())
      .font(.system(size: fontSize, weight: .heavy).width(.condensed))
      .tracking(fontSize * 0.05)
      .monospacedDigit()
      .foregroundStyle(Astra.Color.ink.opacity(grey ? 0.9 : 1))
      .padding(.horizontal, fontSize * 0.5)
      .frame(height: fontSize * 1.75)
      .background {
        if grey { RoundedRectangle(cornerRadius: fontSize * 0.3, style: .continuous).fill(Astra.Color.ink.opacity(0.22)) }
      }
      .overlay(
        RoundedRectangle(cornerRadius: fontSize * 0.16, style: .continuous)
          .strokeBorder(Astra.Color.ink, lineWidth: grey ? 0 : max(1.25, fontSize * 0.12))
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

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 16 * Astra.Layout.controlScale, weight: .semibold))
      .foregroundStyle(Astra.Color.onSelection)
      .padding(.horizontal, 22 * Astra.Layout.controlScale)
      .frame(height: 50 * Astra.Layout.controlScale)
      .background(Capsule().fill(Astra.Color.ink.opacity(isEnabled ? 1 : 0.35)))
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
    /// The backdrop's height as a share of the width, fading into the page.
    /// Taller, and starting below the Dynamic Island so faces aren't cut
    /// off by it (KP, 2026-11-09: "the poster should be more down").
    static let backdropShare: CGFloat = 1.08
    static let backdropTop: CGFloat = 56
    static let logoWidth: CGFloat = 0.5
    static let logoHeight: CGFloat = 64
    /// The centred logo's box (KP's mockup, 2026-11-09).
    static let logoBox = CGSize(width: 210, height: 130)
    static let sectionGap: CGFloat = 26
    static let actionColumn: CGFloat = 50
    static let actionCircle: CGFloat = 50
    static let resumeHeight: CGFloat = 48
    static let castPhoto = CGSize(width: 78, height: 62)
    /// Related rows are 2:3 posters (KP, 2026-11-09: "the posters below are way too small").
    static let relatedTile = CGSize(width: 120, height: 180)
    static let rowSpacing: CGFloat = 14

    /// A dark floor behind the floating tab bar: content fades out above it.
    static var tabBarFloor: some View {
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
    /// Logo, meta line, badges, Resume with Download and My List beside it,
    /// the progress line, synopsis, director and More, in that order.
    var phoneHeader: some View {
      let width = max(pageWidth, 320)
      // KP's mockup (2026-11-09): the logo sits at about 38 % of the screen,
      // centred, with the faces framed above it.
      let logoTop = min(360, max(280, viewport * 0.377))
      return VStack(alignment: .leading, spacing: 0) {
        HeroTitle(
          library: library, item: shown, maxWidth: PhoneDetail.logoBox.width, maxHeight: PhoneDetail.logoBox.height,
          alignment: .bottom
        )
        .frame(maxWidth: .infinity)
        .frame(height: PhoneDetail.logoBox.height, alignment: .bottom)
        // "2024 • 2h 46m • [PG-13] [HD] [Dolby Atmos]", the genres under it.
        HStack(spacing: 8) {
          DetailMetaLine(
            item: shown, library: library, showsGenres: false, fontSize: 14, separator: "  •  ", ratingAfter: true,
            greyRating: true)
          FormatBadges(item: shown)
        }
        .minimumScaleFactor(0.85)
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
        if !shown.genres.isEmpty {
          Text(shown.genres.prefix(3).map(\.tag).joined(separator: " · "))
            .astraFont(size: 13.5)
            .foregroundStyle(Astra.Color.ink.opacity(0.62))
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .padding(.top, 6)
        }
        phoneActions
          .padding(.top, 16)
        if let left = timeLeft, let progress = resumeProgress {
          HStack(spacing: 14) {
            PhoneProgressLine(value: progress)
            Text(left)
              .astraFont(size: 13, weight: .medium)
              .monospacedDigit()
              .foregroundStyle(Astra.Color.muted)
              .fixedSize()
          }
          .padding(.top, 14)
        }
        if let summary = shown.summary, !summary.isEmpty {
          Text(summary)
            .astraFont(size: 15)
            .lineSpacing(3)
            .foregroundStyle(Astra.Color.ink.opacity(0.86))
            .lineLimit(summaryExpanded ? nil : 4)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 16)
        }
        if !shown.directors.isEmpty {
          HStack(spacing: 5) {
            Text("Directed by").foregroundStyle(Astra.Color.muted)
            Text(shown.directors.prefix(2).map(\.tag).joined(separator: ", "))
              .fontWeight(.semibold)
              .foregroundStyle(Astra.Color.ink)
          }
          .astraFont(size: 15)
          .lineLimit(1)
          .padding(.top, 10)
        }
        if (shown.summary?.count ?? 0) > 150 {
          Button {
            astraWithAnimation(Astra.Motion.base) { summaryExpanded.toggle() }
          } label: {
            HStack(spacing: 6) {
              Text(summaryExpanded ? "Less" : "More")
              Image(systemName: "chevron.down")
                .font(.system(size: 12, weight: .bold))
                .rotationEffect(.degrees(summaryExpanded ? 180 : 0))
            }
            .astraFont(size: 15, weight: .semibold)
            .foregroundStyle(Astra.Color.ink)
            .frame(minHeight: 32)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .padding(.top, 2)
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
            library: library, item: shown, kind: .scenery, zoneHeight: logoTop + 90, limitY: logoTop - 4,
            topOffset: PhoneDetail.backdropTop, minTop: PhoneDetail.backdropTop + 40)
          PhoneDetail.backdropShade
        }
        .frame(width: width, height: logoTop + 90)
        // Both edges melt into the frosted blur behind the page instead of into black,
        // and the sharp art dissolves into it as the page scrolls (KP, 2026-11-09).
        .mask(PhoneDetail.backdropMask)
        .opacity(max(0, 1 - max(0, scrolled) / 420))
        // Held in place while the page rises over it (KP, 2026-11-07).
        .offset(y: max(0, scrolled))
      }
    }

    /// Resume (the strongest thing on the page), then quieter round Download and My List.
    private var phoneActions: some View {
      HStack(alignment: .center, spacing: 14) {
        Button {
          playItem(shown)
        } label: {
          Label(playLabel, systemImage: "play.fill")
            .frame(maxWidth: .infinity)
        }
        // KP's mockup (2026-11-09): a white Play, like the hero's.
        .buttonStyle(SolidCapsuleButtonStyle())
        .disabled(shown.isCatalogOnly || !app.canPlay(shown))

        if shown.type != .collection, !shown.isCatalogOnly {
          DownloadButton(item: shown, labeled: true)
        }
        if let target = watchlistTarget {
          PhoneWatchlistColumn(item: target)
        }
      }
    }

    var phoneCastRow: some View {
      VStack(alignment: .leading, spacing: 12) {
        PhoneRowHeader(title: "Cast") { showAllCast = true }
        ScrollView(.horizontal) {
          LazyHStack(alignment: .top, spacing: PhoneDetail.rowSpacing) {
            ForEach(Array(shown.roles.prefix(20).enumerated()), id: \.offset) { _, role in
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

    /// A light shade on the lower artwork so the logo and meta line stay readable.
    static var backdropShade: some View {
      LinearGradient(
        stops: [
          .init(color: .black.opacity(0), location: 0.35),
          .init(color: .black.opacity(0.35), location: 1),
        ], startPoint: .top, endPoint: .bottom
      )
      .allowsHitTesting(false)
    }
  }

  /// The page behind iPhone Details: the title's artwork, heavily blurred and
  /// dimmed like frosted glass, held still while the page scrolls over it.
  struct PhoneFrostedBackground: View {
    var library: LibraryStore
    var item: PlexMetadata

    var body: some View {
      GeometryReader { geo in
        ZStack {
          Astra.Color.bg
          // A small image is enough under this much blur, and cheaper to draw.
          ArtworkImage(library: library, item: item, kind: .heroBackdrop, width: 480, height: 270, placeholder: Color.clear)
            .frame(width: geo.size.width * 1.4, height: geo.size.height * 1.1)
            .clipped()
            .blur(radius: 60, opaque: true)
            .saturation(1.25)
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
          // Darker toward the bottom so the synopsis and rows read easily
          // (lighter on the Light theme, where the text is dark).
          let light = AstraAppearance.shared.palette.isLight
          LinearGradient(
            stops: [
              .init(color: Astra.Color.bg.opacity(light ? 0.62 : 0.3), location: 0),
              .init(color: Astra.Color.bg.opacity(light ? 0.74 : 0.5), location: 0.45),
              .init(color: Astra.Color.bg.opacity(light ? 0.84 : 0.62), location: 1),
            ], startPoint: .top, endPoint: .bottom)
        }
      }
      .ignoresSafeArea()
      .allowsHitTesting(false)
      .accessibilityHidden(true)
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

  /// A round glass icon (Download, My List). KP (2026-11-09): no text under
  /// it; the title is read out to VoiceOver only.
  struct PhoneActionLabel<Icon: View>: View {
    var title: String
    @ViewBuilder var icon: Icon

    var body: some View {
      icon
        .font(.system(size: 19, weight: .semibold))
        .foregroundStyle(Astra.Color.ink)
        .frame(width: PhoneDetail.actionCircle, height: PhoneDetail.actionCircle)
        .astraGlass(in: Circle(), variant: .regular, interactive: true)
        .astraGlassEdge(Circle(), strength: 0.6)
        .frame(width: PhoneDetail.actionColumn)
        .contentShape(Circle())
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

  /// "+ My List": the Plex Watchlist.
  struct PhoneWatchlistColumn: View {
    var item: PlexMetadata
    @Environment(AppModel.self) private var app

    var body: some View {
      let on = app.isOnWatchlist(item)
      Button {
        Task { await app.toggleWatchlist(item) }
      } label: {
        PhoneActionLabel(title: "My List") {
          Image(systemName: on ? "checkmark" : "plus").contentTransition(.symbolEffect(.replace))
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
