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
  @State private var related: [PlexHub] = []
  @State private var notOnServer = false
  @State private var error: String?
  @State private var certification: String?
  @FocusState private var playFocused: Bool

  private var shown: PlexMetadata { item ?? seed }

  var body: some View {
    ScrollView(.vertical, showsIndicators: false) {
      VStack(alignment: .leading, spacing: TVLayout.sectionSpacing) {
        header
        if (shown.type == .show || shown.type == .season), !episodes.isEmpty || !seasons.isEmpty {
          episodesSection
        }
        if !shown.roles.isEmpty {
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
        AmbientBackdrop(library: library, item: shown)
        ArtworkImage(
          library: library, item: shown, kind: .scenery, width: 1920, height: 1080, placeholder: Color.clear
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
    .task(id: shown.id) {
      guard shown.officialRating == nil, shown.type == .movie || shown.type == .show else { return }
      certification = await library.tmdbArtwork(for: shown)?.certification
    }
  }

  // MARK: Header

  private var header: some View {
    VStack(alignment: .leading, spacing: 20) {
      TVLogoTitle(library: library, item: shown, maxWidth: 700, maxHeight: 200, textSize: 90)
        .padding(.bottom, 6)

      HStack(spacing: 16) {
        if let rating = shown.officialRating ?? certification {
          RatingBox(text: rating, fontSize: 20)
        }
        let facts = TVFacts.line(shown).replacingOccurrences(of: " · ", with: "  •  ")
        if !facts.isEmpty {
          Text(facts)
            .font(.system(size: 26, weight: .medium))
            .foregroundStyle(Astra.Color.ink.opacity(0.9))
            .lineLimit(1)
        }
      }
      TVFormatChips(item: shown, fontSize: 18, showsRating: false)

      HStack(alignment: .top, spacing: 28) {
        Button {
          playItem(shown)
        } label: {
          Label(playLabel, systemImage: "play.fill")
            .font(.system(size: 30, weight: .semibold))
            .lineLimit(1)
            .frame(width: 400)
        }
        .buttonStyle(TVGlassButtonStyle(prominent: true))
        .focused($playFocused)
        .disabled(notOnServer || !app.canPlay(shown))

        if let target = watchlistTarget {
          TVLabeledRound(label: app.isOnWatchlist(target) ? "In My List" : "My List") {
            TVRoundWatchlist(item: target)
          }
        }
        if !shown.isCatalogOnly, !notOnServer {
          TVLabeledRound(label: "More") {
            Menu {
              ItemMenuItems(library: library, item: shown, onDetails: true)
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

      if let summary = shown.summary, !summary.isEmpty {
        Text(summary)
          .font(.system(size: 26))
          .foregroundStyle(Astra.Color.ink.opacity(0.88))
          .lineSpacing(4)
          .lineLimit(3)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: 1100, alignment: .leading)
      }
      if let director = shown.directors.first?.tag {
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

  /// How far into the movie or the next episode.
  private var resumeTarget: PlexMetadata? {
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
    VStack(alignment: .leading, spacing: 0) {
      if seasons.count > 1 {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 12) {
            ForEach(seasons) { season in
              Button {
                Task { await selectSeason(season) }
              } label: {
                Text(season.title)
                  .font(.system(size: 22, weight: .semibold))
                  .padding(.horizontal, 24)
                  .frame(height: 50)
              }
              .buttonStyle(TVGlassButtonStyle(chip: true, selected: season.id == selectedSeason?.id))
            }
          }
          .padding(.horizontal, TVLayout.leading)
          .padding(.vertical, 12)
        }
        .scrollClipDisabled()
        .focusSection()
      }
      TVRow(title: selectedSeason?.title ?? "Episodes", spacing: 36) {
        ForEach(episodes) { episode in
          TVEpisodeCard(library: library, item: episode)
        }
      }
    }
  }

  // MARK: Cast

  private var castSection: some View {
    TVRow(title: "Cast", spacing: 32) {
      ForEach(Array(shown.roles.prefix(24).enumerated()), id: \.offset) { _, role in
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
      switch full.type {
      case .show:
        seasons = try await library.children(of: full.ratingKey).filter { $0.type == .season }
        let start = seasons.first { !$0.isWatched && ($0.index ?? 0) > 0 } ?? seasons.first
        if let start { await selectSeason(start) }
      case .season:
        selectedSeason = full
        episodes = try await library.children(of: full.ratingKey)
      default:
        break
      }
      related = await library.related(full.ratingKey)
    } catch {
      self.error = error.localizedDescription
    }
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
/// and two lines of its summary. Selecting plays it.
private struct TVEpisodeCard: View {
  var library: LibraryStore
  var item: PlexMetadata
  @Environment(\.playItem) private var playItem

  var body: some View {
    Button {
      playItem(item)
    } label: {
      TVEpisodeLabel(library: library, item: item)
    }
    .buttonStyle(TVCardButtonStyle(scale: 1.05))
    .itemMenu(library: library, item: item)
  }
}

private struct TVEpisodeLabel: View {
  var library: LibraryStore
  var item: PlexMetadata
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
            .strokeBorder(.white.opacity(focused ? 0.8 : 0.08), lineWidth: focused ? 4 : 1))
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
