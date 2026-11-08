import AstraKit
import SwiftUI

/// Movie and TV details: backdrop header, actions, seasons and episodes, cast, related.
struct DetailView: View {
  var library: LibraryStore
  var seed: PlexMetadata
  @Binding var path: [Route]

  @State private var item: PlexMetadata?
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
      VStack(alignment: .leading, spacing: Astra.Spacing.xl - 4) {
        header
        // Astra (KP, 2026-11-07): the backdrop stays still while the page
        // scrolls, so everything below the header covers it as it rises.
        VStack(alignment: .leading, spacing: Astra.Spacing.xl - 4) {
          if shown.type == .show || shown.type == .season, !seasons.isEmpty || !episodes.isEmpty {
            episodesSection
          }
          if !shown.roles.isEmpty {
            castRow
          }
          ForEach(related) { hub in
            ContentRow(title: hub.title) {
              ForEach(hub.items) { ArtCard(library: library, item: $0) }
            }
          }
        }
        .padding(.bottom, 110)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Astra.Color.bg)
      }
    }
    .scrollIndicators(.never)
    .modifier(ScrollOffsetReader(offset: $scrolled))
    .astraScrollEdges()
    .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { viewport = $0 }
    // The backdrop runs under the title bar; the back button below stays inside the safe area.
    .ignoresSafeArea(edges: .top)
    .background(Astra.Color.bg.ignoresSafeArea())
    #if os(macOS)
      .overlay(alignment: .topTrailing) {
        // Astra: details are a card on the Mac; X closes it (Esc too).
        Button {
          if let closeCard { closeCard() } else if !path.isEmpty { path.removeLast() }
        } label: {
          Image(systemName: "xmark")
        }
        .astraIconButton(size: 36, variant: .clear)
        .keyboardShortcut(isActive ? .cancelAction : nil)
        .help("Close (Esc)")
        .accessibilityLabel("Close")
        .padding(.trailing, 18)
        .padding(.top, 18)
      }
    #else
      // iPhone keeps the system back button (Liquid Glass on iOS 26) and swipe-back.
      .toolbarBackground(.hidden, for: .navigationBar)
      .navigationBarTitleDisplayMode(.inline)
    #endif
    .task(id: seed.ratingKey) { await load() }
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
      DetailMetaLine(item: shown)
      FormatBadges(item: shown, library: library)
      if let tagline = shown.tagline, !tagline.isEmpty {
        Text(tagline)
          .font(.system(size: 15, weight: .semibold))
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
        .keyboardShortcut(isActive ? .defaultAction : nil)
        .disabled(shown.isCatalogOnly || !app.canPlay(shown))

        if shown.type != .collection, !shown.isCatalogOnly {
          DownloadButton(item: shown, wide: true)
        }

        if !shown.isCatalogOnly {
        Button {
          let watched = library.isWatched(shown)
          Task { @MainActor in
            await library.setWatched(shown, watched: !watched)
            await load(refresh: true)
          }
        } label: {
          let watched = library.isWatched(shown)
          Label(watched ? "Watched" : "Mark Watched", systemImage: watched ? "checkmark" : "eye")
            .labelStyle(WatchedLabelStyle(iconOnly: true))
            .contentTransition(.symbolEffect(.replace))
        }
        .accessibilityLabel(library.isWatched(shown) ? "Watched" : "Mark Watched")
        .help(library.isWatched(shown) ? "Watched" : "Mark Watched")
        .modifier(ActionButtonShape(round: true))
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
            .font(.system(size: 12, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(Astra.Color.muted)
        }
        .frame(maxWidth: narrow ? .infinity : 560)
      }
      if !shown.directors.isEmpty {
        Text("Directed by \(shown.directors.map(\.tag).joined(separator: ", "))")
          .font(.system(size: 13)).foregroundStyle(Astra.Color.muted).lineLimit(1)
      }
      if notOnServer {
        Text("Not on your Plex server.").font(.system(size: 13)).foregroundStyle(Astra.Color.muted)
      }
      if let error {
        Text(error).font(.system(size: 13)).foregroundStyle(Astra.Color.muted)
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
        ArtworkImage(library: library, item: shown, kind: .heroBackdrop, width: 1920, height: 1080, placeholder: Color.clear)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .clipped()
          // Darkens a little as the page rises over it.
          .overlay(Astra.Color.bg.opacity(min(0.55, max(0, scrolled) / 700)))
        HeroScrim()
      }
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
              .foregroundStyle(selected ? Color.black : Astra.Color.muted)
              .padding(.horizontal, 16)
              .frame(height: 34)
              .background {
                if selected { Capsule().fill(Astra.Color.accent) } else { Capsule().fill(.white.opacity(0.08)) }
              }
              .animation(Astra.Motion.base, value: selected)
            }
          }
          .padding(.horizontal, leading)
        }
        .scrollIndicators(.never)
        .scrollClipDisabled()
      }
      HStack(spacing: Astra.Spacing.m) {
        Text(selectedSeason?.title ?? "Episodes")
          .font(Astra.Font.rowTitle)
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
      Text("Cast").font(Astra.Font.rowTitle).foregroundStyle(Astra.Color.ink).padding(.leading, leading)
      ScrollView(.horizontal) {
        LazyHStack(alignment: .top, spacing: 16) {
          ForEach(Array(shown.roles.prefix(20).enumerated()), id: \.offset) { _, role in
            VStack(spacing: 6) {
              RemoteImage(url: role.thumb.flatMap { URL(string: $0) })
                .frame(width: 84, height: 84)
                .clipShape(Circle())
                .overlay(Circle().stroke(Astra.Color.hairline))
              Text(role.tag).font(.system(size: 12, weight: .semibold)).foregroundStyle(Astra.Color.ink)
                .lineLimit(1)
              if let character = role.role {
                Text(character).font(.system(size: 11)).foregroundStyle(Astra.Color.muted).lineLimit(1)
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
    do {
      // A refresh reloads the title already shown; otherwise start from the seed.
      var key = refresh ? (item?.ratingKey ?? seed.ratingKey) : seed.ratingKey
      if key.hasPrefix("tmdb:") {
        // A title from a streaming tab: find it on the server, else show TMDB's details.
        do {
          key = try await library.resolve(seed).ratingKey
        } catch LibraryStore.CatalogError.notOnServer {
          notOnServer = true
          return
        }
      }
      let full = try await library.details(key, refresh: refresh)
      withAnimation(Astra.Motion.base) { item = full }
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
            Text("\(index).").font(.system(size: 13, weight: .bold)).foregroundStyle(Astra.Color.muted)
          }
          Text(item.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Astra.Color.ink).lineLimit(1)
          Spacer(minLength: 0)
          if let duration = item.durationLabel {
            Text(duration).font(.system(size: 12)).foregroundStyle(Astra.Color.muted)
          }
          // Room for the download button drawn over this corner.
          Color.clear.frame(width: 30, height: 1)
        }
        if let summary = item.summary, !summary.isEmpty {
          Text(summary).font(.system(size: 12)).foregroundStyle(Astra.Color.muted).lineLimit(2)
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

private struct WatchedLabelStyle: LabelStyle {
  var iconOnly: Bool
  func makeBody(configuration: Configuration) -> some View {
    if iconOnly {
      configuration.icon
    } else {
      Label(configuration)
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

  var body: some View {
    let parts = [
      item.year.map(String.init),
      item.type == .show ? item.childCount.map { "\($0) Season\($0 == 1 ? "" : "s")" } : item.durationLabel,
      item.genres.prefix(2).map(\.tag).joined(separator: ", ").nilIfEmpty,
    ].compactMap { $0 }
    Text(parts.joined(separator: "  •  "))
      .font(.system(size: 15, weight: .medium))
      .foregroundStyle(Astra.Color.ink.opacity(0.9))
      .lineLimit(1)
  }
}

/// The format badges under the meta line: resolution, HDR format, Dolby
/// Atmos, then the official rating, each in a small grey pill. Dolby Vision
/// and Dolby Atmos use KP's official logos (Formats.xcassets); HDR10, HDR10+
/// and HLG share a plain "HDR".
struct FormatBadges: View {
  var item: PlexMetadata
  var library: LibraryStore

  @AppStorage(PlaybackQuality.storageKey) private var quality: PlaybackQuality = .auto
  @State private var fetchedRating: String?

  private var pick: PlaybackQuality { quality == .auto ? .current() : quality }
  private var rating: String? { item.officialRating ?? fetchedRating }

  var body: some View {
    HStack(spacing: 8) {
      if let badge = item.resolutionBadge(for: pick) {
        FormatPill { Text(badge == "4K UHD" ? "4K" : badge) }
      }
      switch item.dynamicRange(for: pick) {
      case .dolbyVision?: FormatPill { logo("format-dolby-vision", height: 15) }.accessibilityLabel("Dolby Vision")
      // KP: one general HDR badge for HDR10, HDR10+ and HLG.
      case .hdr10Plus?, .hdr10?, .hlg?: FormatPill { Text("HDR") }
      case nil: EmptyView()
      }
      if item.hasAtmos(for: pick) {
        FormatPill { logo("format-dolby-atmos", height: 12) }.accessibilityLabel("Dolby Atmos")
      }
      if let rating { FormatPill { Text(rating) }.accessibilityLabel("Rated \(rating)") }
    }
    .task(id: item.id) {
      fetchedRating = nil
      guard item.officialRating == nil, item.type == .movie || item.type == .show else { return }
      fetchedRating = await library.tmdbArtwork(for: item)?.certification
    }
  }

  private func logo(_ name: String, height: CGFloat) -> some View {
    Image(name)
      .renderingMode(.template)
      .resizable()
      .scaledToFit()
      .frame(height: height)
  }
}

/// One grey pill in the format row.
struct FormatPill<Content: View>: View {
  @ViewBuilder var content: Content

  var body: some View {
    content
      .font(.system(size: 12, weight: .bold))
      .foregroundStyle(Astra.Color.ink)
      .padding(.horizontal, 9)
      .frame(height: 26)
      .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Astra.Color.ink.opacity(0.14)))
      .fixedSize()
  }
}

/// The summary, four lines with "More ⌄" to open the rest.
struct ExpandableSummary: View {
  var text: String
  @State private var expanded = false

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(text)
        .font(.system(size: 14.5))
        .lineSpacing(4)
        .foregroundStyle(Astra.Color.ink.opacity(0.85))
        .lineLimit(expanded ? nil : 4)
        .frame(maxWidth: 620, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
      if text.count > 160 {
        Button {
          withAnimation(Astra.Motion.base) { expanded.toggle() }
        } label: {
          HStack(spacing: 4) {
            Text(expanded ? "Less" : "More")
            Image(systemName: "chevron.down")
              .font(.system(size: 10, weight: .bold))
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
      .font(.system(size: 16, weight: .semibold))
      .foregroundStyle(Color.black)
      .padding(.horizontal, 22)
      .frame(height: 50)
      .background(Capsule().fill(Astra.Color.ink.opacity(isEnabled ? 1 : 0.35)))
      .scaleEffect(configuration.isPressed ? 0.97 : 1)
      .animation(.snappy(duration: 0.15), value: configuration.isPressed)
      .contentShape(Capsule())
  }
}
