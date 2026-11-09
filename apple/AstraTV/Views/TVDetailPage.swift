// Details on Apple TV, adapted from Silo Apple's tvOS detail hero, action row
// and cast rail (https://github.com/Silo-Server/silo-apple, AGPL-3.0-or-later,
// Copyright (C) 2026 Silo Media L.L.C. and contributors).

import AstraKit
import SwiftUI

/// Silo's Details (KP, 2026-11-09): the artwork on the right, the logo at
/// the top left with the rating chip, facts and Astra's 4K / Dolby / HDR
/// badges, the synopsis and who's in it, then Play (or Resume) and a round +
/// for the Watchlist. Below: seasons and episodes, Cast & Crew, More Like This.
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
    ZStack(alignment: .top) {
      TVPageBackdrop(library: library, item: shown, showsTopScrim: false)
      ScrollView(.vertical, showsIndicators: false) {
        VStack(alignment: .leading, spacing: 0) {
          hero
          VStack(alignment: .leading, spacing: TVMetrics.bodySectionSpacing) {
            if (shown.type == .show || shown.type == .season), !episodes.isEmpty || !seasons.isEmpty {
              episodesSection
            }
            if !shown.roles.isEmpty || !shown.directors.isEmpty {
              castSection
            }
            ForEach(related) { hub in
              relatedSection(hub)
            }
          }
          .padding(.bottom, 140)
        }
      }
      .scrollClipDisabled()
    }
    .ignoresSafeArea()
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

  // MARK: Hero

  private var hero: some View {
    VStack(alignment: .leading, spacing: 18) {
      VStack(alignment: .leading, spacing: 14) {
        TVLogoTitle(library: library, item: shown, maxWidth: 650, maxHeight: 160, textSize: 72)

        // Rating chip, facts, then the format badges, on one line.
        HStack(spacing: 14) {
          if let rating = shown.officialRating ?? certification {
            TVChip { Text(rating) }
          }
          let facts = TVFacts.line(shown)
          if !facts.isEmpty {
            Text(facts)
              .font(.system(size: 24, weight: .medium))
              .foregroundStyle(.white.opacity(0.88))
              .lineLimit(1)
          }
          TVFormatChips(item: shown, showsRating: false)
        }

        if let summary = shown.summary, !summary.isEmpty {
          Text(summary)
            .font(.system(size: 26))
            .foregroundStyle(.white.opacity(0.92))
            .lineSpacing(4)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: TVMetrics.heroContentWidth, alignment: .leading)
        }

        if let credit {
          Text(credit)
            .font(.system(size: 23))
            .foregroundStyle(.white.opacity(0.7))
            .lineLimit(1)
        }

        if notOnServer {
          Text("Not on your Plex server.")
            .font(.system(size: 23))
            .foregroundStyle(.white.opacity(0.7))
        } else if let error {
          Text(error)
            .font(.system(size: 23))
            .foregroundStyle(.white.opacity(0.7))
            .lineLimit(2)
        }
      }
      .frame(maxWidth: TVMetrics.heroContentWidth, alignment: .leading)

      actionRow
        .padding(.top, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
    }
    .padding(.top, TVMetrics.heroTopInset)
    .padding(.horizontal, TVMetrics.detailInset)
    .frame(maxWidth: .infinity, minHeight: TVMetrics.heroHeight, alignment: .topLeading)
  }

  /// "Starring A, B, C", else "Directed by …".
  private var credit: String? {
    let cast = shown.roles.prefix(3).map(\.tag)
    if !cast.isEmpty { return "Starring \(cast.joined(separator: ", "))" }
    let directors = shown.directors.prefix(2).map(\.tag)
    if !directors.isEmpty { return "Directed by \(directors.joined(separator: ", "))" }
    return nil
  }

  /// Play (or Resume) and the round + only (KP, 2026-11-09).
  private var actionRow: some View {
    HStack(spacing: 24) {
      Button {
        playItem(shown)
      } label: {
        HStack(spacing: 16) {
          Image(systemName: "play.fill")
            .font(.system(size: 31, weight: .bold))
            .frame(width: 36, height: 36)
          Text(playLabel)
            .font(.system(size: 29, weight: .semibold))
            .lineLimit(1)
            .fixedSize()
        }
      }
      .buttonStyle(TVPillButtonStyle(width: 340))
      .focused($playFocused)
      .disabled(shown.isCatalogOnly || notOnServer || !app.canPlay(shown))

      if let target = watchlistTarget {
        TVWatchlistCircle(item: target)
      }
    }
  }

  /// What + adds: the title itself, or an episode's or season's show.
  private var watchlistTarget: PlexMetadata? {
    if shown.tmdbKey != nil, shown.type == .movie || shown.type == .show { return shown }
    if shown.type == .episode || shown.type == .season, let show = parentShow, show.tmdbKey != nil { return show }
    return nil
  }

  /// "Play", "Resume 1:02:13", or a show's next episode ("Play S1 E3").
  private var playLabel: String {
    if shown.type == .movie || shown.type == .episode {
      if let offset = shown.viewOffset, offset > 30_000, shown.progress != nil {
        return "Resume \(Self.clock(offset / 1000))"
      }
      return "Play"
    }
    if let next = episodes.first(where: { ($0.viewOffset ?? 0) > 0 }) ?? episodes.first(where: { !$0.isWatched }),
      let label = next.episodeLabel
    {
      let verb = (next.viewOffset ?? 0) > 0 ? "Resume" : "Play"
      return "\(verb) \(label.replacingOccurrences(of: " · ", with: " "))"
    }
    return "Play"
  }

  static func clock(_ seconds: Int) -> String {
    let h = seconds / 3600
    let m = (seconds % 3600) / 60
    let s = seconds % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
  }

  // MARK: Episodes

  private var episodesSection: some View {
    VStack(alignment: .leading, spacing: TVMetrics.sectionHeaderSpacing) {
      if seasons.count > 1 {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 12) {
            ForEach(seasons) { season in
              TVSeasonTab(title: season.title, selected: season.id == selectedSeason?.id) {
                Task { await selectSeason(season) }
              }
            }
          }
          .padding(.horizontal, TVMetrics.detailInset)
          .padding(.vertical, 10)
        }
        .scrollClipDisabled()
        .focusSection()
      } else {
        TVRowHeader(title: selectedSeason?.title ?? "Episodes", size: 36)
          .padding(.horizontal, TVMetrics.detailInset)
      }
      ScrollView(.horizontal, showsIndicators: false) {
        LazyHStack(alignment: .top, spacing: 48) {
          ForEach(episodes) { episode in
            TVLandscapeCard(
              library: library, item: episode,
              title: [episode.index.map { "E\($0)" }, episode.title].compactMap { $0 }.joined(separator: " · "),
              subtitle: episode.durationLabel ?? " ",
              action: { playItem(episode) })
          }
        }
        .padding(.horizontal, TVMetrics.detailInset)
        .padding(.vertical, 14)
      }
      .scrollClipDisabled()
      .focusSection()
    }
  }

  // MARK: Cast & Crew

  private var castSection: some View {
    VStack(alignment: .leading, spacing: TVMetrics.sectionHeaderSpacing) {
      TVRowHeader(title: "Cast & Crew", size: 36)
        .padding(.horizontal, TVMetrics.detailInset)
      ScrollView(.horizontal, showsIndicators: false) {
        LazyHStack(alignment: .top, spacing: 60) {
          ForEach(Array(people.enumerated()), id: \.offset) { _, person in
            TVCastCard(name: person.tag, role: person.role, photo: person.thumb)
          }
        }
        .padding(.horizontal, TVMetrics.detailInset)
        .padding(.vertical, 12)
      }
      .scrollClipDisabled()
      .focusSection()
    }
  }

  /// Directors first, then the cast.
  private var people: [PlexTag] {
    let directors = shown.directors.prefix(2).map { PlexTag(tag: $0.tag, role: "Director", thumb: $0.thumb) }
    return Array((directors + shown.roles).prefix(24))
  }

  // MARK: More Like This

  private func relatedSection(_ hub: PlexHub) -> some View {
    VStack(alignment: .leading, spacing: TVMetrics.sectionHeaderSpacing) {
      TVRowHeader(title: hub.title, size: 36)
        .padding(.horizontal, TVMetrics.detailInset)
      ScrollView(.horizontal, showsIndicators: false) {
        LazyHStack(alignment: .top, spacing: 40) {
          ForEach(hub.items) { TVPosterCard(library: library, item: $0, width: 200) }
        }
        .padding(.horizontal, TVMetrics.detailInset)
        .padding(.vertical, 14)
      }
      .scrollClipDisabled()
      .focusSection()
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

/// Silo's primary pill: white with black text when focused, a faint white
/// fill otherwise, 76 pt tall.
struct TVPillButtonStyle: ButtonStyle {
  var width: CGFloat? = nil

  func makeBody(configuration: Configuration) -> some View {
    TVPillBody(configuration: configuration, width: width)
  }
}

private struct TVPillBody: View {
  let configuration: ButtonStyleConfiguration
  let width: CGFloat?
  @Environment(\.isFocused) private var focused
  @Environment(\.isEnabled) private var enabled

  var body: some View {
    configuration.label
      .foregroundStyle(focused ? Color.black : Color.white)
      .padding(.horizontal, 22)
      .frame(width: width, height: 76)
      .background(Capsule().fill(focused ? Color.white : Color.white.opacity(0.10)))
      .opacity(enabled ? 1 : 0.4)
      .scaleEffect(configuration.isPressed ? 0.98 : 1)
      .shadow(color: .black.opacity(focused ? 0.24 : 0.14), radius: focused ? 10 : 4, y: focused ? 4 : 2)
      .focusEffectDisabled()
      .animation(.easeInOut(duration: 0.18), value: focused)
      .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
  }
}

/// The round + beside Play. A 76 pt circle that widens to show its name while
/// focused; ✓ once the title is on the Watchlist.
struct TVWatchlistCircle: View {
  var item: PlexMetadata
  @Environment(AppModel.self) private var app

  var body: some View {
    let on = app.isOnWatchlist(item)
    Button {
      Task { await app.toggleWatchlist(item) }
    } label: {
      TVCircleLabel(icon: on ? "checkmark" : "plus", title: on ? "In Watchlist" : "Watchlist")
    }
    .buttonStyle(TVPlainButtonStyle())
    .accessibilityLabel(on ? "Remove from Watchlist" : "Add to Watchlist")
    .task { await app.loadWatchlistIfNeeded() }
  }
}

private struct TVCircleLabel: View {
  var icon: String
  var title: String
  @Environment(\.isFocused) private var focused

  var body: some View {
    HStack(spacing: 14) {
      Image(systemName: icon)
        .font(.system(size: 31, weight: .semibold))
        .frame(width: 38, height: 38)
        .contentTransition(.symbolEffect(.replace))
      if focused {
        Text(title)
          .font(.system(size: 26, weight: .semibold))
          .lineLimit(1)
          .fixedSize()
          .transition(.opacity)
      }
    }
    .padding(.horizontal, focused ? 28 : 0)
    .foregroundStyle(focused ? Color.black : Color.white)
    .frame(minWidth: 76)
    .frame(height: 76)
    .background(Capsule().fill(focused ? Color.white : Color.white.opacity(0.10)))
    .clipShape(Capsule())
    .shadow(color: .black.opacity(focused ? 0.34 : 0), radius: focused ? 16 : 0, y: focused ? 6 : 0)
    .animation(.smooth(duration: 0.28), value: focused)
  }
}

/// A season in the season row: the open one filled grey, focused white.
private struct TVSeasonTab: View {
  var title: String
  var selected: Bool
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      TVSeasonLabel(title: title, selected: selected)
    }
    .buttonStyle(TVPlainButtonStyle())
  }
}

private struct TVSeasonLabel: View {
  var title: String
  var selected: Bool
  @Environment(\.isFocused) private var focused

  var body: some View {
    Text(title)
      .font(.system(size: 26, weight: .semibold))
      .foregroundStyle(focused ? Color.black : (selected ? Color.white : Color.white.opacity(0.62)))
      .padding(.horizontal, 28)
      .padding(.vertical, 12)
      .background(Capsule().fill(focused ? Color.white : (selected ? TVColor.selectedFill : Color.clear)))
      .scaleEffect(focused ? 1.04 : 1)
      .animation(.easeOut(duration: 0.15), value: focused)
  }
}

/// A round portrait with the name and character under it.
private struct TVCastCard: View {
  var name: String
  var role: String?
  var photo: String?

  var body: some View {
    Button {} label: { TVCastLabel(name: name, role: role, photo: photo) }
      .buttonStyle(TVCardButtonStyle(scale: 1.05))
  }
}

private struct TVCastLabel: View {
  var name: String
  var role: String?
  var photo: String?
  @Environment(\.isFocused) private var focused

  private let size: CGFloat = 200

  var body: some View {
    VStack(spacing: 12) {
      ZStack {
        TVColor.surface
        if let photo, let url = URL(string: photo) {
          RemoteImage(url: url, placeholder: TVColor.surface)
        } else {
          Image(systemName: "person.fill")
            .font(.system(size: size * 0.4))
            .foregroundStyle(TVColor.secondaryText)
        }
      }
      .frame(width: size, height: size)
      .clipShape(Circle())
      .overlay(Circle().stroke(Color.white.opacity(focused ? 0.7 : 0.08), lineWidth: focused ? 4 : 1))
      VStack(spacing: 4) {
        Text(name)
          .font(.system(size: 20, weight: .semibold))
          .foregroundStyle(TVColor.onSurface.opacity(focused ? 1 : 0.88))
          .lineLimit(2, reservesSpace: true)
          .multilineTextAlignment(.center)
        if let role, !role.isEmpty {
          Text(role)
            .font(.system(size: 17))
            .foregroundStyle(TVColor.secondaryText)
            .lineLimit(1)
        }
      }
    }
    .frame(width: size)
  }
}
