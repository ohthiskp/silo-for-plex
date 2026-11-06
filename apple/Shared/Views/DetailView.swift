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
  /// The visible height of the page; the header's backdrop is at least a share of it.
  @State private var viewport: CGFloat = 800

  @Environment(\.playItem) private var playItem
  @Environment(\.contentLeading) private var leading

  private var shown: PlexMetadata { item ?? seed }

  var body: some View {
    ScrollView(.vertical) {
      // A plain VStack: a lazy one guesses row heights and makes the page jump while scrolling.
      VStack(alignment: .leading, spacing: Astra.Spacing.xl - 4) {
        header
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
      .padding(.bottom, 80)
    }
    .scrollIndicators(.never)
    .astraScrollEdges()
    .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { viewport = $0 }
    // The backdrop runs under the title bar; the back button below stays inside the safe area.
    .ignoresSafeArea(edges: .top)
    .background(Astra.Color.bg.ignoresSafeArea())
    #if os(macOS)
      .overlay(alignment: .topLeading) {
        Button {
          if !path.isEmpty { path.removeLast() }
        } label: {
          Image(systemName: "chevron.left")
        }
        .astraIconButton(size: 40)
        .keyboardShortcut("[", modifiers: .command)
        .help("Back (⌘[)")
        .accessibilityLabel("Back")
        .padding(.leading, leading)
        .padding(.top, Astra.Spacing.s)
      }
      .navigationBarBackButtonHidden(true)
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
    VStack(alignment: .leading, spacing: 16) {
      HeroTitle(library: library, item: shown)
      MetaRow(item: shown)
      if let tagline = shown.tagline, !tagline.isEmpty {
        Text(tagline).font(.system(size: 15, weight: .medium)).italic().foregroundStyle(Astra.Color.muted)
          .lineLimit(1)
      }
      if let summary = shown.summary, !summary.isEmpty {
        Text(summary)
          .font(.system(size: 14.5))
          .lineSpacing(4)
          .foregroundStyle(Astra.Color.ink.opacity(0.85))
          .lineLimit(4)
          .frame(maxWidth: 620, alignment: .leading)
          .fixedSize(horizontal: false, vertical: true)
      }
      HStack(spacing: 14) {
        Button {
          playItem(shown)
        } label: {
          Label(playLabel, systemImage: "play.fill")
        }
        .astraPrimaryButton()
        .keyboardShortcut(.defaultAction)

        if shown.type != .collection {
          DownloadButton(item: shown)
        }

        Button {
          Task {
            await library.setWatched(shown, watched: !shown.isWatched)
            await load(refresh: true)
          }
        } label: {
          Label(shown.isWatched ? "Watched" : "Mark Watched", systemImage: shown.isWatched ? "checkmark" : "eye")
        }
        .astraSecondaryButton()
      }
      .astraGlassGroup(spacing: 14)
      .padding(.top, 4)
      if !shown.directors.isEmpty {
        Text("Directed by \(shown.directors.map(\.tag).joined(separator: ", "))")
          .font(.system(size: 13)).foregroundStyle(Astra.Color.muted).lineLimit(1)
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
        HeroScrim()
      }
    }
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
      let full = try await library.details(seed.ratingKey, refresh: refresh)
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
            if item.isWatched {
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
    // Outside the card's button, so it gets its own clicks.
    .overlay(alignment: .topTrailing) {
      DownloadButton(item: item, compact: true)
        .offset(x: 4, y: height + 1)
    }
  }
}
