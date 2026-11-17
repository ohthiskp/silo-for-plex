import AstraKit
import SwiftUI

/// Details on Apple TV: the iPhone's Details (KP's Avatar mockup) made wide
/// (KP, 2026-11-09: "go based off how iOS is"). The scenic backdrop fills the
/// top and fades into the frosted page; on the left the logo, rating box and
/// facts, the format badges, Resume with the round Watchlist bookmark and eye beside it,
/// the progress line, the synopsis and director. Below: the season's
/// episodes, Cast, More Like This.
struct TVDetailPage: View {
  var library: LibraryStore
  var seed: PlexMetadata

  @Environment(AppModel.self) private var app
  @Environment(\.playItem) private var playItem

  @State private var item: PlexMetadata?
  @State private var parentShow: PlexMetadata?
  @State private var seasons: [PlexMetadata] = []
  /// Settings → Library → Show Specials (off by default, KP 2026-11-16).
  @AppStorage(Preferences.showSpecialsKey) private var showSpecials = false
  @State private var selectedSeason: PlexMetadata?
  @State private var episodes: [PlexMetadata] = []
  /// A show's picked episode (KP, 2026-11-14): the header shows its details and
  /// Play / Resume plays it. Selecting an episode picks it and moves focus up
  /// to Play, so a second press plays it.
  @State private var focus: PlexMetadata?
  /// Once an episode is picked, the backdrop shows its still (KP, 2026-11-14).
  @State private var episodeArt = false
  @State private var related: [PlexHub] = []
  @State private var notOnServer = false
  @State private var error: String?
  @FocusState private var playFocused: Bool
  /// 0 at the top, 1 once the page has scrolled down to Cast and beyond: the
  /// backdrop blurs a little, then the page is all frosted glass (KP, 2026-11-16).
  @State private var frost: CGFloat = 0
  /// The season tab that has focus (KP, 2026-11-16: tabs, not a dropdown).
  @FocusState private var seasonFocus: String?
  @State private var seasonLoad: Task<Void, Never>?

  private var shown: PlexMetadata { item ?? seed }

  /// The show on an episode's or season's page: its logo, backdrop, facts and cast.
  private var titleItem: PlexMetadata {
    if shown.type == .episode || shown.type == .season, let parentShow { return parentShow }
    // Genres and length from TMDB for titles that aren't on Plex.
    return library.filled(shown)
  }

  private var playTarget: PlexMetadata { focus ?? shown }

  /// The picked episode's still, for the backdrop (nil until an episode is picked).
  private var episodeStill: URL? {
    guard episodeArt, let focus, focus.type == .episode, let thumb = focus.thumb else { return nil }
    return library.imageURL(thumb, width: 1920, height: 1080, scale: 1)
  }

  private var isSeries: Bool { shown.type == .show || shown.type == .season || shown.type == .episode }

  var body: some View {
    // KP (2026-11-14): Details stays Frosted Glass, even on the Light theme.
    page.astraDetailsTheme()
  }

  @ViewBuilder private var page: some View {
    ScrollView(.vertical, showsIndicators: false) {
      VStack(alignment: .leading, spacing: TVLayout.sectionSpacing) {
        header
        if isSeries, !episodes.isEmpty || !seasons.isEmpty {
          episodesSection
        }
        if !titleItem.roles.isEmpty {
          castSection
        }
        ForEach(related) { hub in
          TVRow(title: hub.title == "Similar" || hub.title.isEmpty ? "More Like This" : hub.title) {
            ForEach(hub.items) { TVPosterCard(library: library, item: $0, width: TVLayout.poster) }
          }
        }
      }
      .padding(.bottom, 100)
    }
    .scrollClipDisabled()
    .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y + $0.contentInsets.top }) { _, y in
      let value = min(1, max(0, (y - 120) / 520))
      if abs(value - frost) > 0.02 || value == 0 || value == 1 { frost = value }
    }
    .background {
      ZStack(alignment: .top) {
        AmbientBackdrop(library: library, item: titleItem)
        Group {
          if let still = episodeStill {
            RemoteImage(url: still, placeholder: Color.clear)
          } else {
            // The art sits right with faces clear of the logo and buttons, the
            // rest softly blurred, like the hero (KP, 2026-11-16, Dune).
            TVHeroArt(library: library, item: titleItem, kind: .scenery, clearX: TVLayout.leading + 760 + 50, push: 0, maxX: 760)
          }
        }
        .id(episodeStill)
        .transition(.opacity)
        // Edge to edge: inside the safe area it left a dark strip down the left.
        .frame(width: 1920)
        .frame(height: 1080)
        .clipped()
        .blur(radius: frost * 28, opaque: true)
        .overlay { HeroBlend() }
        .mask {
          LinearGradient(
            stops: [.init(color: .black, location: 0.55), .init(color: .clear, location: 1)],
            startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
        // Frosted glass over everything once you're down in Cast, a touch lighter.
        Rectangle()
          .fill(.regularMaterial)
          .overlay(Color.white.opacity(0.04))
          .opacity(frost)
          .ignoresSafeArea()
      }
      .animation(.easeOut(duration: 0.25), value: frost)
    }
    .ignoresSafeArea(edges: .top)
    .defaultFocus($playFocused, true, priority: .userInitiated)
    .task(id: seed.ratingKey) { await load() }
    .task(id: shown.ratingKey) {
      let key = shown.type == .episode ? shown.grandparentRatingKey : shown.type == .season ? shown.parentRatingKey : nil
      guard let key, parentShow?.ratingKey != key else { return }
      parentShow = try? await library.details(key)
    }
  }

  // MARK: Header

  private var header: some View {
    VStack(alignment: .leading, spacing: 20) {
      TVLogoTitle(library: library, item: titleItem, maxWidth: 700, maxHeight: 200, textSize: 90)
        .padding(.bottom, 6)

      // KP (2026-11-16), the same as the hero, the iPhone and the Mac:
      // "2008 • 8 Seasons [TV-MA] [HD]" (a movie gives its length), the
      // genres on their own line under it.
      // KP's mockup (2026-11-16, Dune): "2024 [PG-13] 2h 46m 4K UHD Dolby Vision Dolby Atmos".
      MetaBadgeRow(item: titleItem, playTarget: playTarget, library: library, fontSize: TVLayout.metaSize)
      .frame(height: 42)
      if !titleItem.genres.isEmpty {
        Text(titleItem.genres.prefix(3).map(\.tag).joined(separator: " · "))
          .font(.system(size: 24, weight: .medium))
          .foregroundStyle(Astra.Color.ink.opacity(0.65))
          .lineLimit(1)
          .padding(.top, -8)
      }

      if let focus, focus.type == .episode {
        VStack(alignment: .leading, spacing: 6) {
          Text([focus.episodeLabel, focus.durationLabel].compactMap { $0 }.joined(separator: "  ·  "))
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(Astra.Color.muted)
          Text(focus.title)
            .font(.system(size: 36, weight: .bold))
            .foregroundStyle(Astra.Color.ink)
            .lineLimit(1)
        }
        .id(focus.ratingKey)
        .transition(.opacity)
      }

      HStack(alignment: .top, spacing: 28) {
        Button {
          playItem(playTarget)
        } label: {
          Label(playLabel, systemImage: "play.fill")
            .font(.system(size: 30, weight: .semibold))
            .lineLimit(1)
            .frame(width: 400)
        }
        .buttonStyle(TVGlassButtonStyle(prominent: true))
        .focused($playFocused)
        .disabled(notOnServer || !app.canPlay(playTarget))

        // KP (2026-11-16): the Watchlist bookmark and the eye stand alone,
        // with no names under them (as on the iPhone).
        if let target = watchlistTarget {
          TVRoundWatchlist(item: target)
        }
        // KP (2026-11-16, Apple TV): an eye that marks the movie or the
        // picked episode watched or unwatched, instead of More.
        // On a show with no episode picked it marks the whole show.
        if !shown.isCatalogOnly, !notOnServer, let markTarget = watchedTarget {
          let watched = library.isWatched(markTarget)
          Button {
            Task { await library.setWatched(markTarget, watched: !watched) }
          } label: {
            Image(systemName: watched ? "eye.fill" : "eye")
              .font(.system(size: 30, weight: .semibold))
              .contentTransition(.symbolEffect(.replace))
              .frame(width: TVLayout.roundButton, height: TVLayout.roundButton)
          }
          .buttonStyle(TVGlassButtonStyle(round: true))
          .accessibilityLabel(watched ? "Mark Unwatched" : "Mark Watched")
        }
      }
      .focusSection()
      .padding(.top, 6)

      if let progress = resumeProgress, let left = timeLeft {
        HStack(spacing: 20) {
          TVProgressLine(value: progress)
            .frame(width: 400)
          Text(left)
            .font(.system(size: 22, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(Astra.Color.muted)
        }
      }

      if let summary = headerSummary {
        Text(summary)
          .font(.system(size: 26))
          .foregroundStyle(Astra.Color.ink.opacity(0.88))
          .lineSpacing(4)
          .lineLimit(3)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: 1100, alignment: .leading)
      }
      if let director = playTarget.directors.first?.tag {
        (Text("Directed by ").foregroundStyle(Astra.Color.muted)
          + Text(director).foregroundStyle(Astra.Color.ink).bold())
          .font(.system(size: 24))
      }
      if notOnServer {
        Text("Not on your Plex server.").font(.system(size: 24)).foregroundStyle(Astra.Color.muted)
      } else if let error {
        Text(error).font(.system(size: 24)).foregroundStyle(Astra.Color.muted).lineLimit(2)
      }
    }
    .padding(.leading, TVLayout.leading)
    .padding(.trailing, 600)
    .padding(.top, 330)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// What the eye marks: the picked episode or the movie, else the show.
  private var watchedTarget: PlexMetadata? {
    switch playTarget.type {
    case .movie, .episode, .show, .season: return playTarget
    default: return titleItem.type == .show ? titleItem : nil
    }
  }

  /// What My List adds: the title itself, or an episode's or season's show.
  private var watchlistTarget: PlexMetadata? {
    if shown.tmdbKey != nil, shown.type == .movie || shown.type == .show { return shown }
    if shown.type == .episode || shown.type == .season, let show = parentShow, show.tmdbKey != nil { return show }
    return nil
  }

  /// The picked episode's synopsis on a show, else the title's own.
  private var headerSummary: String? {
    if let text = focus?.summary, !text.isEmpty { return text }
    if let text = shown.summary, !text.isEmpty { return text }
    return titleItem.summary?.isEmpty == false ? titleItem.summary : nil
  }

  /// How far into the movie or the next episode.
  private var resumeTarget: PlexMetadata? {
    if let focus { return focus }
    if shown.type == .movie || shown.type == .episode { return shown }
    return episodes.first { ($0.viewOffset ?? 0) > 0 }
  }

  private var resumeProgress: Double? { resumeTarget?.progress }

  /// "2h 21m left".
  private var timeLeft: String? {
    guard let target = resumeTarget, let offset = target.viewOffset, offset > 0, let duration = target.duration,
      duration > offset
    else { return nil }
    let minutes = max(1, (duration - offset) / 60_000)
    return (minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m") + " left"
  }

  /// "Play", "Resume", or a show's next episode ("Play S1 E3").
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

  /// KP (2026-11-16, Apple TV): the seasons as a row of tabs at the top,
  /// starting on the season being watched (Entourage opens on Season 3).
  /// Moving onto a tab shows that season; the whole season is listed below.
  private var episodesSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      if seasons.count > 1 {
        seasonTabs
      }
      HStack(spacing: 18) {
        if seasons.count <= 1 {
          Text(selectedSeason?.title ?? "Episodes")
            .font(.system(size: 30, weight: .bold))
            .foregroundStyle(Astra.Color.ink)
        }
        if !episodes.isEmpty {
          Text("\(episodes.count) Episode\(episodes.count == 1 ? "" : "s")")
            .font(.system(size: 22, weight: .medium))
            .foregroundStyle(Astra.Color.muted)
        }
      }
      .padding(.horizontal, TVLayout.leading)
      .padding(.top, 4)
      ScrollView(.horizontal, showsIndicators: false) {
        LazyHStack(alignment: .top, spacing: 36) {
          ForEach(episodes) { episode in
            TVEpisodeCard(library: library, item: episode, selected: episode.ratingKey == focus?.ratingKey) {
              withAnimation(.easeInOut(duration: 0.25)) {
              focus = episode
              episodeArt = true
            }
              playFocused = true
            }
          }
        }
        .padding(.horizontal, TVLayout.leading)
        .padding(.vertical, 20)
      }
      .scrollClipDisabled()
      .focusSection()
    }
  }

  private var seasonTabs: some View {
    ScrollViewReader { proxy in
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 16) {
          ForEach(seasons) { season in
            Button {
              chooseSeason(season)
            } label: {
              Text(season.title)
                .font(.system(size: 26, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, 30)
                .frame(height: 62)
            }
            .buttonStyle(TVGlassButtonStyle(chip: true, selected: season.id == selectedSeason?.id))
            .focused($seasonFocus, equals: season.ratingKey)
            .accessibilityAddTraits(season.id == selectedSeason?.id ? .isSelected : [])
            .id(season.ratingKey)
          }
        }
        .padding(.horizontal, TVLayout.leading)
        .padding(.vertical, 18)
      }
      .scrollClipDisabled()
      .focusSection()
      .onAppear { if let key = selectedSeason?.ratingKey { proxy.scrollTo(key, anchor: .center) } }
      .onChange(of: selectedSeason?.ratingKey) { _, key in
        if let key { withAnimation(.snappy(duration: 0.25)) { proxy.scrollTo(key, anchor: .center) } }
      }
    }
    .onChange(of: seasonFocus) { old, new in
      guard let new else { return }
      // Coming into the row lands on the season that's showing.
      if old == nil, let current = selectedSeason?.ratingKey, new != current {
        seasonFocus = current
        return
      }
      if let season = seasons.first(where: { $0.ratingKey == new }), season.id != selectedSeason?.id {
        chooseSeason(season)
      }
    }
  }

  /// Shows a season's episodes. The tab lights up straight away; the list
  /// follows a moment later, so sweeping across the tabs doesn't load each one.
  private func chooseSeason(_ season: PlexMetadata) {
    selectedSeason = season
    seasonLoad?.cancel()
    seasonLoad = Task {
      try? await Task.pause(0.2)
      guard !Task.isCancelled else { return }
      let list = (try? await library.children(of: season.ratingKey)) ?? []
      guard !Task.isCancelled, selectedSeason?.id == season.id else { return }
      withAnimation(.easeInOut(duration: 0.2)) { episodes = list }
    }
  }

  // MARK: Cast

  private var castSection: some View {
    TVRow(title: "Cast", spacing: 32) {
      ForEach(Array(titleItem.roles.prefix(24).enumerated()), id: \.offset) { _, role in
        TVCastTile(name: role.tag, role: role.role, photo: role.thumb)
      }
    }
  }

  // MARK: Loading

  private func load() async {
    let opened = Date()
    do {
      var key = seed.ratingKey
      if key.hasPrefix("tmdb:") {
        // A title from a streaming row: find it on the server, else show TMDB's details.
        if let quick = library.indexMatch(seed) { item = quick }
        do {
          key = try await library.resolve(seed).ratingKey
        } catch LibraryStore.CatalogError.notOnServer {
          notOnServer = true
          return
        }
      }
      let full = try await library.details(key)
      withAnimation(.easeInOut(duration: 0.2)) { item = full }
      library.recordOpen(seconds: Date().timeIntervalSince(opened))
      // KP (2026-11-14): a show, season or episode (Continue Watching) opens on
      // that episode's season with the episode picked.
      switch full.type {
      case .show:
        try await loadSeasons(show: full.ratingKey, season: nil, episode: nil)
      case .season:
        if let show = full.parentRatingKey {
          try await loadSeasons(show: show, season: full.ratingKey, episode: nil)
        } else {
          selectedSeason = full
          episodes = try await library.children(of: full.ratingKey)
          pickDefaultEpisode(nil)
        }
      case .episode:
        if let show = full.grandparentRatingKey {
          try await loadSeasons(show: show, season: full.parentRatingKey, episode: full.ratingKey)
        }
        if focus == nil { focus = full }
      default:
        break
      }
      let relatedKey =
        (full.type == .episode ? full.grandparentRatingKey : full.type == .season ? full.parentRatingKey : nil)
        ?? full.ratingKey
      related = await library.related(relatedKey)
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

  private func pickDefaultEpisode(_ key: String?) {
    let found =
      key.flatMap { key in episodes.first { $0.ratingKey == key } }
      ?? episodes.first { ($0.viewOffset ?? 0) > 0 } ?? episodes.first { !library.isWatched($0) } ?? episodes.first
    if let found { focus = found }
  }

  private func selectSeason(_ season: PlexMetadata) async {
    selectedSeason = season
    episodes = (try? await library.children(of: season.ratingKey)) ?? []
  }
}

// MARK: - Pieces

/// An episode: its still with the progress line, "1. Title" and the length,
/// and two lines of its summary. Selecting picks it (KP, 2026-11-14:
/// don't play on a click); pressing the picked one again plays it.
private struct TVEpisodeCard: View {
  var library: LibraryStore
  var item: PlexMetadata
  var selected: Bool
  var onSelect: () -> Void
  @Environment(\.playItem) private var playItem

  var body: some View {
    Button {
      if selected { playItem(item) } else { onSelect() }
    } label: {
      TVEpisodeLabel(library: library, item: item, selected: selected)
    }
    .buttonStyle(TVCardButtonStyle(scale: 1.05))
    .itemMenu(library: library, item: item)
  }
}

private struct TVEpisodeLabel: View {
  var library: LibraryStore
  var item: PlexMetadata
  var selected = false
  @Environment(\.isFocused) private var focused

  var body: some View {
    let size = TVLayout.episodeCard
    VStack(alignment: .leading, spacing: 12) {
      RemoteImage(url: library.imageURL(item.thumb, width: size.width, height: size.height), placeholder: Astra.Color.surface)
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: TVLayout.radius, style: .continuous))
        .watchedLook(library.isWatched(item), corner: TVLayout.radius, mark: 42, inset: 14)
        .overlay(alignment: .bottom) {
          if let progress = item.progress { TVProgressLine(value: progress).padding(14) }
        }
        .overlay(
          RoundedRectangle(cornerRadius: TVLayout.radius, style: .continuous)
            .strokeBorder(
              Astra.Color.ink.opacity(focused ? 0.8 : selected ? 0.55 : 0.08), lineWidth: focused || selected ? 4 : 1))
        .tvShine()
      HStack(spacing: 10) {
        Text([item.index.map { "\($0)." }, item.title].compactMap { $0 }.joined(separator: " "))
          .font(.system(size: 24, weight: .semibold))
          .foregroundStyle(Astra.Color.ink)
          .lineLimit(1)
        Spacer(minLength: 0)
        if let length = item.durationLabel {
          Text(length).font(.system(size: 20)).foregroundStyle(Astra.Color.muted)
        }
      }
      Text(item.summary ?? " ")
        .font(.system(size: 20))
        .foregroundStyle(Astra.Color.muted)
        .lineLimit(2, reservesSpace: true)
    }
    .frame(width: size.width, alignment: .leading)
  }
}

/// A cast member: a rounded-square photo with the name and character under it.
private struct TVCastTile: View {
  var name: String
  var role: String?
  var photo: String?

  var body: some View {
    Button {} label: { TVCastTileLabel(name: name, role: role, photo: photo) }
      .buttonStyle(TVCardButtonStyle(scale: 1.06))
  }
}

private struct TVCastTileLabel: View {
  var name: String
  var role: String?
  var photo: String?
  @Environment(\.isFocused) private var focused

  private let size: CGFloat = 180

  var body: some View {
    VStack(spacing: 10) {
      ZStack {
        Astra.Color.surface
        if let photo, let url = URL(string: photo) {
          RemoteImage(url: url, placeholder: Astra.Color.surface)
        } else {
          Image(systemName: "person.fill")
            .font(.system(size: size * 0.32))
            .foregroundStyle(Astra.Color.muted)
        }
      }
      .frame(width: size, height: size)
      .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 26, style: .continuous)
          .strokeBorder(.white.opacity(focused ? 0.8 : 0.08), lineWidth: focused ? 4 : 1))
      Text(name)
        .font(.system(size: 21, weight: .semibold))
        .foregroundStyle(Astra.Color.ink)
        .lineLimit(1)
      Text(role ?? " ")
        .font(.system(size: 18))
        .foregroundStyle(Astra.Color.muted)
        .lineLimit(1)
    }
    .frame(width: size)
  }
}
