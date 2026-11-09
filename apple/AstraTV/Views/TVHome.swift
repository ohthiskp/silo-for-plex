import AstraKit
import SwiftUI

/// Home on Apple TV, the iPhone's Home made for the TV (KP, 2026-11-09: "go
/// based off how iOS is"): the streaming switcher, a full-width hero with the
/// title's logo, rating, Play and +, then Continue Watching, Top Trending,
/// Recently Released and All-Time Greats, each with its own Movies | Series
/// switch. All on the frosted artwork background.
struct TVHome: View {
  var library: LibraryStore

  @State private var index = 0
  /// Focus is in the hero's buttons: the hero stops turning by itself.
  @State private var heroFocused = false
  @AppStorage("astra.home.topTenSeries") private var topSeries = false

  private var heroItems: [PlexMetadata] { library.homeHero }
  private var current: PlexMetadata? {
    heroItems.isEmpty ? nil : heroItems[min(index, heroItems.count - 1)]
  }

  var body: some View {
    ZStack(alignment: .leading) {
      ScrollView(.vertical, showsIndicators: false) {
        VStack(alignment: .leading, spacing: TVLayout.sectionSpacing) {
          hero
          rows
        }
        .padding(.bottom, 80)
      }
      .scrollClipDisabled()
      .environment(\.tvLeading, TVLayout.homeLeading)
      .ignoresSafeArea(edges: .top)

      // KP (2026-11-09): the streaming services down the left, logos only
      // until focus moves onto them.
      TVServiceSidebar(library: library)
    }
    .background { AmbientBackdrop(library: library, item: current) }
    .onChange(of: heroItems.map(\.id)) { _, ids in if index >= ids.count { index = 0 } }
    // The hero turns every 9 s while focus is elsewhere.
    .task(id: "\(index)|\(heroFocused)|\(heroItems.count)") {
      guard !heroFocused, heroItems.count > 1 else { return }
      try? await Task.pause(9)
      guard !Task.isCancelled else { return }
      withAnimation(.easeInOut(duration: 0.6)) { index = (index + 1) % heroItems.count }
    }
    .task(id: heroItems.map(\.id).joined()) {
      await library.prewarmDetails(heroItems)
    }
  }

  // MARK: Hero

  @ViewBuilder private var hero: some View {
    ZStack(alignment: .bottomLeading) {
      if let current {
        ArtworkImage(
          library: library, item: current, kind: .heroBackdrop, width: 1920, height: 1080,
          placeholder: Color.clear
        )
        .frame(maxWidth: .infinity)
        .frame(height: TVLayout.heroHeight)
        .clipped()
        .overlay { HeroBlend() }
        .mask {
          LinearGradient(
            stops: [.init(color: .black, location: 0.7), .init(color: .clear, location: 1)],
            startPoint: .top, endPoint: .bottom)
        }
        // Edge to edge: out past the TV's 80 pt side safe area.
        .padding(.horizontal, -80)
        .id(current.id)
        .transition(.opacity)

        TVHeroInfo(
          library: library, item: current, count: heroItems.count, index: index,
          focused: $heroFocused, step: step
        )
        .id("info-\(current.id)")
        .transition(.opacity)
        .padding(.leading, TVLayout.homeLeading)
        .padding(.bottom, 40)
      } else {
        VStack(spacing: 20) {
          if library.isLoadingHome || library.isLoadingHero {
            ProgressView()
          } else if let error = library.homeError {
            Text(error).font(.system(size: 28, weight: .medium)).foregroundStyle(Astra.Color.muted)
            Button("Try Again") { Task { await library.loadHome() } }
          }
        }
        .frame(maxWidth: .infinity)
        .frame(height: TVLayout.heroHeight)
      }

    }
    .frame(height: TVLayout.heroHeight)
    .animation(.easeInOut(duration: 0.6), value: current?.id)
  }

  private func step(_ by: Int) {
    guard heroItems.count > 1 else { return }
    withAnimation(.easeInOut(duration: 0.45)) {
      index = (index + by + heroItems.count) % heroItems.count
    }
  }

  // MARK: Rows

  @ViewBuilder private var rows: some View {
    if !library.homeContinueWatching.isEmpty {
      TVRow(title: "Continue Watching") {
        ForEach(library.homeContinueWatching) { item in
          TVContinueCard(library: library, item: item)
        }
      }
    }
    let split = library.homeTopTenSplit
    if !split.movies.isEmpty || !split.shows.isEmpty {
      let items = Array((topSeries ? split.shows : split.movies).prefix(10))
      TVRow(title: "Top Trending", series: $topSeries) {
        ForEach(Array(items.enumerated()), id: \.element.id) { rank, item in
          TVRankedCard(library: library, item: item, rank: rank + 1)
        }
      }
    }
    TVShelf(library: library, title: "Recently Released", shelf: library.homeRecent, key: "astra.home.recentSeries")
    TVShelf(library: library, title: "All-Time Greats", shelf: library.homeGreats, key: "astra.home.greatsSeries")
  }
}

// MARK: - Hero info

/// The hero's block, bottom left, after KP's hero mockup (2026-11-09) as on
/// the iPhone and Mac: the title's logo centred over the block, then
/// "2025 · 2h 8m · Sci-Fi [PG-13] [4K]" on one line, then a wide white Play
/// beside the round glass + (Watchlist). No Details button: hold Select on
/// Play for Details and the rest. Right on + turns the hero; the dots show
/// where you are.
private struct TVHeroInfo: View {
  var library: LibraryStore
  var item: PlexMetadata
  var count: Int
  var index: Int
  @Binding var focused: Bool
  var step: (Int) -> Void

  @Environment(\.playItem) private var playItem
  @Environment(AppModel.self) private var app
  @FocusState private var focus: Field?
  /// The server's full copy, for the 4K / Dolby badges and the runtime.
  @State private var full: PlexMetadata?

  private enum Field: Hashable { case play, plus }

  private static let blockWidth: CGFloat = 760

  private var playable: Bool { library.availability(of: item) != .notOnServer && app.canPlay(item) }
  private var firstFocus: Field { playable || item.tmdbKey == nil ? .play : .plus }
  private var shown: PlexMetadata { full ?? library.indexMatch(item) ?? item }

  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      VStack(spacing: 22) {
        TVLogoTitle(library: library, item: item, maxWidth: 700, maxHeight: 200, textSize: 90, centered: true)
          .frame(maxWidth: .infinity)
        HStack(spacing: 14) {
          DetailMetaLine(item: shown, library: library, fontSize: 26, genreLimit: 1, ratingAfter: true)
            .layoutPriority(1)
          TVFormatChips(item: shown, fontSize: 18, showsRating: false)
        }
        .frame(height: 40)
        .frame(maxWidth: .infinity)
      }

      HStack(spacing: 20) {
        Button {
          playItem(item)
        } label: {
          Label("Play", systemImage: "play.fill")
            .font(.system(size: 30, weight: .semibold))
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(TVGlassButtonStyle(prominent: true))
        .focused($focus, equals: .play)
        .disabled(!playable)
        // Hold Select for Details, Mark Watched and Go to (no downloads on TV).
        .itemMenu(library: library, item: item)

        if item.tmdbKey != nil {
          TVRoundWatchlist(item: item)
            .focused($focus, equals: .plus)
        }
      }
      .focusSection()
      .onMoveCommand { direction in
        // Only reached when focus can't move further that way.
        if direction == .right, focus == .plus || (focus == .play && item.tmdbKey == nil) { step(1) }
      }
      if count > 1 {
        TVDots(count: count, index: index)
          .frame(maxWidth: .infinity)
      }
    }
    .frame(width: Self.blockWidth)
    // Home opens on Play (or + when the title can't play here), not on the
    // sidebar or the tab bar.
    .defaultFocus($focus, firstFocus, priority: .userInitiated)
    .onChange(of: focus) { _, new in focused = new != nil }
    .task(id: item.id) {
      full = nil
      let key = item.isCatalogOnly ? library.indexMatch(item)?.ratingKey : item.ratingKey
      guard let key else { return }
      let found = try? await library.details(key)
      guard !Task.isCancelled else { return }
      full = found
    }
  }
}

/// The hero's page dots: the current one a wide white capsule.
private struct TVDots: View {
  var count: Int
  var index: Int

  var body: some View {
    HStack(spacing: 10) {
      ForEach(0..<min(count, 12), id: \.self) { dot in
        Capsule()
          .fill(.white.opacity(dot == index ? 1 : 0.4))
          .frame(width: dot == index ? 34 : 10, height: 10)
      }
    }
    .animation(.snappy(duration: 0.3), value: index)
    .accessibilityHidden(true)
  }
}

// MARK: - Streaming sidebar

/// For You and the streaming services down the left of Home (KP,
/// 2026-11-09): only the logos while focus is elsewhere; move left onto them
/// and the sidebar opens on a glass panel with each service's name. The
/// chosen one is outlined in its brand colour.
private struct TVServiceSidebar: View {
  var library: LibraryStore
  @AppStorage(Preferences.serviceLogoColorsKey) private var logoColors = true
  /// The entry with focus, reported by each entry's button style.
  @State private var focused: String?
  @Namespace private var scope

  private static let forYou = "for-you"
  private var expanded: Bool { focused != nil }
  private var selectedKey: String { library.selectedService?.id ?? Self.forYou }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      row(nil)
      ForEach(StreamingService.all) { row($0) }
    }
    .padding(.vertical, 26)
    .padding(.horizontal, expanded ? 18 : 0)
    .background {
      if expanded {
        RoundedRectangle(cornerRadius: 40, style: .continuous)
          .fill(.black.opacity(0.35))
          .astraGlass(in: RoundedRectangle(cornerRadius: 40, style: .continuous))
          .transition(.opacity)
      }
    }
    .frame(maxHeight: .infinity, alignment: .center)
    .focusScope(scope)
    .focusSection()
    .animation(.snappy(duration: 0.25), value: expanded)
  }

  private func row(_ service: StreamingService?) -> some View {
    let key = service?.id ?? Self.forYou
    let selected = key == selectedKey
    let brand = logoColors ? (service.map { Color(hex: $0.accent) } ?? .white) : .white
    return Button {
      library.select(service)
    } label: {
      HStack(spacing: 18) {
        logo(service, brand: brand)
          .frame(width: TVLayout.sidebarCollapsed - 28, height: 44)
        if expanded {
          Text(service?.label ?? "For You")
            .font(.system(size: 26, weight: .semibold))
            .lineLimit(1)
            .fixedSize()
            .padding(.trailing, 10)
            .transition(.opacity.combined(with: .move(edge: .leading)))
        }
      }
      .padding(.horizontal, 14)
      .frame(height: 64)
    }
    .buttonStyle(
      TVSidebarButtonStyle(selected: selected, brand: brand) { has in
        if has { focused = key } else if focused == key { focused = nil }
      }
    )
    // Moving onto the sidebar lands on the chosen service.
    .prefersDefaultFocus(selected, in: scope)
    .accessibilityLabel(service?.label ?? "For You")
    .accessibilityAddTraits(selected ? .isSelected : [])
  }

  @ViewBuilder private func logo(_ service: StreamingService?, brand: Color) -> some View {
    if let service {
      Image(service.logo)
        .renderingMode(.template)
        .resizable()
        .scaledToFit()
        .frame(maxHeight: min(service.logoHeight * 1.1, 34))
        .foregroundStyle(brand)
    } else {
      Image(systemName: "sparkles")
        .font(.system(size: 28, weight: .semibold))
        .foregroundStyle(.white)
    }
  }
}

/// A sidebar entry: a glass capsule, lighter and larger when focused; the
/// chosen service is outlined in its brand colour.
private struct TVSidebarButtonStyle: ButtonStyle {
  var selected: Bool
  var brand: Color
  var onFocus: (Bool) -> Void

  func makeBody(configuration: Configuration) -> some View {
    TVSidebarButtonBody(configuration: configuration, selected: selected, brand: brand, onFocus: onFocus)
  }
}

private struct TVSidebarButtonBody: View {
  let configuration: ButtonStyleConfiguration
  var selected: Bool
  var brand: Color
  var onFocus: (Bool) -> Void
  @Environment(\.isFocused) private var focused

  var body: some View {
    configuration.label
      .foregroundStyle(.white)
      .background {
        Capsule().fill(.white.opacity(focused ? 0.28 : (selected ? 0.12 : 0)))
      }
      .astraGlass(in: Capsule(), variant: .clear, interactive: true)
      .overlay { if selected { Capsule().strokeBorder(brand, lineWidth: 2.5) } }
      .scaleEffect(configuration.isPressed ? 0.97 : (focused ? 1.06 : 1))
      .shadow(color: .black.opacity(focused ? 0.35 : 0), radius: 14, y: 6)
      .focusEffectDisabled()
      .animation(.easeOut(duration: 0.15), value: focused)
      .onChange(of: focused, initial: true) { _, new in onFocus(new) }
  }
}

// MARK: - Rows

/// A titled row, with a Movies | Series switch when `series` is given.
struct TVRow<Content: View>: View {
  var title: String
  var series: Binding<Bool>? = nil
  var spacing: CGFloat = 40
  @ViewBuilder var content: Content
  @Environment(\.tvLeading) private var leading

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(spacing: 24) {
        Text(title)
          .font(.system(size: 38, weight: .bold))
          .foregroundStyle(Astra.Color.ink)
          .lineLimit(1)
        if let series {
          TVKindSwitch(series: series)
        }
      }
      .padding(.leading, leading)
      .focusSection()
      ScrollView(.horizontal, showsIndicators: false) {
        LazyHStack(alignment: .top, spacing: spacing) {
          content
        }
        .padding(.horizontal, leading)
        .padding(.vertical, 20)
      }
      .scrollClipDisabled()
      .focusSection()
    }
  }
}

/// Movies | Series: two glass chips, the chosen one white.
struct TVKindSwitch: View {
  @Binding var series: Bool

  var body: some View {
    HStack(spacing: 10) {
      ForEach([false, true], id: \.self) { isSeries in
        Button {
          withAnimation(.snappy(duration: 0.2)) { series = isSeries }
        } label: {
          Text(isSeries ? "Series" : "Movies")
            .font(.system(size: 22, weight: .semibold))
            .padding(.horizontal, 22)
            .frame(height: 46)
        }
        .buttonStyle(TVGlassButtonStyle(chip: true, selected: series == isSeries))
        .accessibilityAddTraits(series == isSeries ? .isSelected : [])
      }
    }
  }
}

/// Recently Released or All-Time Greats: posters with their own switch.
private struct TVShelf: View {
  var library: LibraryStore
  var title: String
  var shelf: HomeShelf
  @AppStorage private var series: Bool

  init(library: LibraryStore, title: String, shelf: HomeShelf, key: String) {
    self.library = library
    self.title = title
    self.shelf = shelf
    _series = AppStorage(wrappedValue: false, key)
  }

  var body: some View {
    if !shelf.isEmpty {
      let items = shelf.items(series: series)
      TVRow(title: title, series: $series) {
        if items.isEmpty {
          Text(series ? "No series here yet." : "No movies here yet.")
            .font(.system(size: 24))
            .foregroundStyle(Astra.Color.muted)
            .frame(height: 120)
        } else {
          ForEach(items) { TVPosterCard(library: library, item: $0, width: TVLayout.poster) }
        }
      }
    }
  }
}

/// Continue Watching, as on the iPhone: the still with the title, episode
/// and progress inside it and a round play button. Opens Details (KP rule);
/// long-press plays or removes it.
struct TVContinueCard: View {
  var library: LibraryStore
  var item: PlexMetadata
  @Environment(\.openItem) private var openItem

  var body: some View {
    let size = TVLayout.continueCard
    Button {
      openItem(item)
    } label: {
      TVContinueLabel(library: library, item: item, size: size)
    }
    .buttonStyle(TVCardButtonStyle(scale: 1.06))
    .itemMenu(library: library, item: item, inContinueWatching: true)
  }
}

private struct TVContinueLabel: View {
  var library: LibraryStore
  var item: PlexMetadata
  var size: CGSize
  @Environment(\.isFocused) private var focused

  var body: some View {
    ZStack(alignment: .bottomLeading) {
      if item.type == .episode, item.thumb != nil {
        RemoteImage(url: library.imageURL(item.thumb, width: size.width, height: size.height), placeholder: Astra.Color.surface)
      } else {
        ArtworkImage(library: library, item: item, kind: .backdrop, width: size.width, height: size.height)
      }
      LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
      Image(systemName: "play.fill")
        .font(.system(size: 30, weight: .bold))
        .foregroundStyle(.white)
        .frame(width: 76, height: 76)
        .background(.black.opacity(0.35), in: Circle())
        .overlay(Circle().stroke(.white.opacity(0.3)))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      VStack(alignment: .leading, spacing: 6) {
        Text(item.displayTitle)
          .font(.system(size: 28, weight: .bold))
          .foregroundStyle(.white)
          .lineLimit(1)
        if let sub = [item.episodeLabel, item.type == .episode ? item.title : nil].compactMap({ $0 })
          .joined(separator: "  ·  ").nilIfEmpty
        {
          Text(sub).font(.system(size: 21, weight: .medium)).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
        }
        TVProgressLine(value: item.progress ?? 0)
          .padding(.top, 4)
      }
      .padding(22)
    }
    .frame(width: size.width, height: size.height)
    .clipShape(RoundedRectangle(cornerRadius: TVLayout.radius, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: TVLayout.radius, style: .continuous)
        .strokeBorder(.white.opacity(focused ? 0.8 : 0.08), lineWidth: focused ? 4 : 1))
  }
}

/// Top Trending: the big outlined rank number beside the poster (Netflix style).
private struct TVRankedCard: View {
  var library: LibraryStore
  var item: PlexMetadata
  var rank: Int
  @Environment(\.openItem) private var openItem

  var body: some View {
    let width = TVLayout.poster
    Button {
      openItem(item)
    } label: {
      HStack(alignment: .bottom, spacing: -width * 0.2) {
        RankNumber(rank: rank, size: width * 1.5 * 0.86)
        TVRankPoster(library: library, item: item, width: width)
      }
    }
    .buttonStyle(TVCardButtonStyle(scale: 1.06))
    .itemMenu(library: library, item: item)
    .accessibilityLabel("Number \(rank), \(item.displayTitle)")
  }
}

private struct TVRankPoster: View {
  var library: LibraryStore
  var item: PlexMetadata
  var width: CGFloat
  @Environment(\.isFocused) private var focused

  var body: some View {
    ArtworkImage(library: library, item: item, kind: .poster, width: width, height: width * 1.5)
      .frame(width: width, height: width * 1.5)
      .clipShape(RoundedRectangle(cornerRadius: TVLayout.radius, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: TVLayout.radius, style: .continuous)
          .strokeBorder(.white.opacity(focused ? 0.8 : 0.08), lineWidth: focused ? 4 : 1))
      .shadow(color: .black.opacity(0.45), radius: 8, x: -4, y: 0)
  }
}

// MARK: - Buttons

/// Liquid Glass buttons for the TV, as on the iPhone: Play is a wide glass
/// capsule, + and ⓘ round glass, chips small capsules. Focused, each turns
/// white with dark text (the TV's focus) and lifts a little.
struct TVGlassButtonStyle: ButtonStyle {
  var prominent = false
  var round = false
  var chip = false
  var selected = false

  func makeBody(configuration: Configuration) -> some View {
    TVGlassButtonBody(configuration: configuration, style: self)
  }
}

private struct TVGlassButtonBody: View {
  let configuration: ButtonStyleConfiguration
  let style: TVGlassButtonStyle
  @Environment(\.isFocused) private var focused
  @Environment(\.isEnabled) private var enabled

  var body: some View {
    let label = configuration.label
      .foregroundStyle(focused ? Color.black : (style.selected ? Color.black : Color.white))
      .padding(.horizontal, style.round || style.chip ? 0 : 36)
      .frame(height: style.round ? TVLayout.roundButton : (style.chip ? nil : TVLayout.buttonHeight))
    Group {
      if style.round {
        label
          .background { if focused { Circle().fill(.white) } }
          .astraGlass(in: Circle(), interactive: true)
      } else {
        label
          .background {
            if focused || style.selected {
              Capsule().fill(.white.opacity(focused ? 1 : 0.92))
            } else if style.prominent {
              Capsule().fill(.white.opacity(0.14))
            }
          }
          .astraGlass(in: Capsule(), interactive: true)
      }
    }
    .opacity(enabled ? 1 : 0.4)
    .scaleEffect(configuration.isPressed ? 0.97 : (focused ? 1.06 : 1))
    .shadow(color: .black.opacity(focused ? 0.35 : 0), radius: 18, y: 8)
    .focusEffectDisabled()
    .animation(.easeOut(duration: 0.15), value: focused)
    .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
  }
}

/// The round + (Plex Watchlist), ✓ once added.
struct TVRoundWatchlist: View {
  var item: PlexMetadata
  @Environment(AppModel.self) private var app

  var body: some View {
    let on = app.isOnWatchlist(item)
    Button {
      Task { await app.toggleWatchlist(item) }
    } label: {
      Image(systemName: on ? "checkmark" : "plus")
        .font(.system(size: 30, weight: .semibold))
        .contentTransition(.symbolEffect(.replace))
        .frame(width: TVLayout.roundButton, height: TVLayout.roundButton)
    }
    .buttonStyle(TVGlassButtonStyle(round: true))
    .accessibilityLabel(on ? "Remove from Watchlist" : "Add to Watchlist")
    .task { await app.loadWatchlistIfNeeded() }
  }
}
