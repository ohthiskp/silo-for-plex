import AstraKit
import SwiftUI

/// Details on Apple TV: the iPhone's Details (KP's Avatar mockup) made wide
/// (KP, 2026-11-09: "go based off how iOS is"). The scenic backdrop fills the
/// top and fades into the frosted page; on the left the logo, rating box and
/// facts, the format badges, Resume with round My List and More beside it,
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
  @State private var selectedSeason: PlexMetadata?
  @State private var episodes: [PlexMetadata] = []
  /// A show's picked episode (KP, 2026-11-14): the header shows its details and
  /// Play / Resume plays it. Selecting an episode picks it and moves focus up
  /// to Play, so a second press plays it.
  @State private var focus: PlexMetadata?
  @State private var related: [PlexHub] = []
  @State private var notOnServer = false
  @State private var error: String?
  @State private var certification: String?
  @FocusState private var playFocused: Bool

  private var shown: PlexMetadata { item ?? seed }

  /// The show on an episode's or season's page: its logo, backdrop, facts and cast.
  private var titleItem: PlexMetadata {
    if shown.type == .episode || shown.type == .season, let parentShow { return parentShow }
    return shown
  }

  private var playTarget: PlexMetadata { focus ?? shown }

  private var isSeries: Bool { shown.type == .show || shown.type == .season || shown.type == .episode }

  var body: some View {
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
    .background {
      ZStack(alignment: .top) {
        AmbientBackdrop(library: library, item: titleItem)
        ArtworkImage(
          library: library, item: titleItem, kind: .scenery, width: 1920, height: 1080, placeholder: Color.clear
        )
        .frame(maxWidth: .infinity)
        .frame(height: 1080)
        .clipped()
        .overlay { HeroBlend() }
        .mask {
          LinearGradient(
            stops: [.init(color: .black, location: 0.55), .init(color: .clear, location: 1)],
            startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
      }
    }
    .ignoresSafeArea(edges: .top)
    .defaultFocus($playFocused, true, priority: .userInitiated)
    .task(id: seed.ratingKey) { await load() }
    .task(id: shown.ratingKey) {
      let key = shown.type == .episode ? shown.grandparentRatingKey : shown.type == .season ? shown.parentRatingKey : nil
      guard let key, parentShow?.ratingKey != key else { return }
      parentShow = try? await library.details(key)
    }
    .task(id: titleItem.id) {
      guard titleItem.officialRating == nil, titleItem.type == .movie || titleItem.type == .show else { return }
      certification = await library.tmdbArtwork(for: titleItem)?.certification
    }
  }

  // MARK: Header

  private var header: some View {
    VStack(alignment: .leading, spacing: 20) {
      TVLogoTitle(library: library, item: titleItem, maxWidth: 700, maxHeight: 200, textSize: 90)
        .padding(.bottom, 6)

      HStack(spacing: 16) {
        if let rating = titleItem.officialRating ?? certification {
          RatingBox(text: rating, fontSize: 20)
        }
        let facts = TVFacts.line(titleItem).replacingOccurrences(of: " · ", with: "  •  ")
        if !facts.isEmpty {
          Text(facts)
            .font(.system(size: 26, weight: .medium))
            .foregroundStyle(Astra.Color.ink.opacity(0.9))
            .lineLimit(1)
        }
      }
      TVFormatChips(item: playTarget, fontSize: 18, showsRating: false)

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

        if let target = watchlistTarget {
          TVLabeledRound(label: app.isOnWatchlist(target) ? "In My List" : "My List") {
            TVRoundWatchlist(item: target)
          }
        }
        if !shown.isCatalogOnly, !notOnServer {
          TVLabeledRound(label: "More") {
            Menu {
              ItemMenuItems(library: library, item: playTarget, onDetails: true)
            } label: {
              Image(systemName: "ellipsis")
                .font(.system(size: 30, weight: .semibold))
                .frame(width: TVLayout.roundButton, height: TVLayout.roundButton)
            }
            .buttonStyle(TVGlassButtonStyle(round: true))
            .accessibilityLabel("More")
          }
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

  /// KP (2026-11-14): a season dropdown, then the whole season.
  private var episodesSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 24) {
        if seasons.count > 1 {
          Menu {
            ForEach(seasons) { season in
              Button {
                Task { await selectSeason(season) }
              } label: {
                if season.id == selectedSeason?.id {
                  Label(season.title, systemImage: "checkmark")
                } else {
                  Text(season.title)
                }
              }
            }
          } label: {
            HStack(spacing: 12) {
              Text(selectedSeason?.title ?? "Season")
              Image(systemName: "chevron.down").font(.system(size: 18, weight: .bold))
            }
            .font(.system(size: 26, weight: .semibold))
            .padding(.horizontal, 28)
            .frame(height: 60)
          }
          .buttonStyle(TVGlassButtonStyle(chip: true))
          .accessibilityLabel("Season, \(selectedSeason?.title ?? "")")
        } else {
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
      .padding(.vertical, 12)
      .focusSection()
      ScrollView(.horizontal, showsIndicators: false) {
        LazyHStack(alignment: .top, spacing: 36) {
          ForEach(episodes) { episode in
            TVEpisodeCard(library: library, item: episode, selected: episode.ratingKey == focus?.ratingKey) {
              withAnimation(.easeInOut(duration: 0.25)) { focus = episode }
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
    seasons = try await library.children(of: show).filter { $0.type == .season }
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

/// A round button with its name under it (My List, More), as on the iPhone.
private struct TVLabeledRound<Content: View>: View {
  var label: String
  @ViewBuilder var content: Content

  var body: some View {
    VStack(spacing: 12) {
      content
      Text(label)
        .font(.system(size: 20, weight: .medium))
        .foregroundStyle(Astra.Color.ink.opacity(0.85))
        .lineLimit(1)
        .fixedSize()
    }
  }
}

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
        .overlay(alignment: .bottom) {
          if let progress = item.progress { TVProgressLine(value: progress).padding(14) }
        }
        .overlay(alignment: .topTrailing) {
          if library.isWatched(item) {
            Image(systemName: "checkmark.circle.fill")
              .symbolRenderingMode(.palette)
              .foregroundStyle(.black, .white)
              .font(.system(size: 30))
              .padding(12)
          }
        }
        .overlay(
          RoundedRectangle(cornerRadius: TVLayout.radius, style: .continuous)
            .strokeBorder(
              Astra.Color.ink.opacity(focused ? 0.8 : selected ? 0.55 : 0.08), lineWidth: focused || selected ? 4 : 1))
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
