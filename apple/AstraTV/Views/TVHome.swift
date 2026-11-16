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
  @Environment(\.tvScrolledDown) private var scrolledDown
  /// Left reaches the streaming circles only from the first thing in a row
  /// or the first hero title (KP, 2026-11-16: "only go to the left if it's
  /// the first on the list"). Elsewhere Left walks back along the row or the hero.
  @State private var sidebarReachable = true
  /// Bumped to put focus on the hero's first button: Right from a circle,
  /// or Down from the top bar, when tvOS finds nothing that way by itself.
  @State private var heroFocusRequest = 0
  @Environment(\.tvFocusPage) private var pageFocus

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
      .onScrollGeometryChange(for: Bool.self, of: { $0.contentOffset.y + $0.contentInsets.top > 120 }) { _, down in
        scrolledDown(down)
      }
      .environment(\.tvLeading, TVLayout.homeLeading - TVLayout.sidebarColumn)
      .environment(\.tvLeftEdge) { sidebarReachable = $0 }
      .ignoresSafeArea(edges: .top)
      // The page starts right of the circles and is one focus section from
      // top to bottom, so Right from any circle lands on the page (KP,
      // 2026-11-16: only HBO Max, level with Play, could get back before).
      .padding(.leading, TVLayout.sidebarColumn)
      .focusSection()

      // KP (2026-11-09): the streaming services as circles down the left.
      TVServiceSidebar(library: library) { heroFocusRequest += 1 }
        .disabled(!sidebarReachable)
    }
    .onChange(of: pageFocus) { heroFocusRequest += 1 }
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
        // KP (2026-11-16): the logo on the left, the art on the right with
        // the faces clear of the logo, the rest of the picture softly blurred.
        TVHeroArt(library: library, item: current)
          .frame(width: 1920, height: TVLayout.heroHeight)
          .overlay { HeroBlend() }
          .mask {
            LinearGradient(
              stops: [.init(color: .black, location: 0.7), .init(color: .clear, location: 1)],
              startPoint: .top, endPoint: .bottom)
          }
          // Edge to edge: out past the circles and the TV's 80 pt side safe area.
          .padding(.leading, -(80 + TVLayout.sidebarColumn))
          .padding(.trailing, -80)
          .id(current.id)
          .transition(.opacity)

        // One block for every title, so focus stays on the button it's on
        // while Left and Right walk through the hero.
        TVHeroInfo(
          library: library, item: current, count: heroItems.count, index: index,
          focused: $heroFocused, focusRequest: heroFocusRequest, step: step
        )
        .padding(.leading, TVLayout.homeLeading - TVLayout.sidebarColumn)
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

/// The hero's block, bottom left (KP, 2026-11-16): the title's logo on the
/// left, then "2025 • 2h 8m [PG-13] [4K] [Atmos]" on one line as on the
/// iPhone and Mac, the genres under it, then just Play and Details ("keep it
/// simple"), each with room to grow when focused. Right on Details turns to
/// the next title; Left on Play goes back a title, and only from the first
/// title does Left reach the streaming circles.
private struct TVHeroInfo: View {
  var library: LibraryStore
  var item: PlexMetadata
  var count: Int
  var index: Int
  @Binding var focused: Bool
  var focusRequest: Int
  var step: (Int) -> Void

  @Environment(\.playItem) private var playItem
  @Environment(\.openItem) private var openItem
  @Environment(\.tvLeftEdge) private var leftEdge
  @Environment(AppModel.self) private var app
  @FocusState private var focus: Field?
  /// When focus last moved between the buttons: a Right that moved focus
  /// onto Details must not also turn the hero (KP: "it automatically moves to the right").
  @State private var movedAt = Date.distantPast
  /// The server's full copy, for the 4K / Dolby badges and the runtime.
  @State private var full: PlexMetadata?

  private enum Field: Hashable { case play, details }

  static let blockWidth: CGFloat = 820

  private var playable: Bool { library.availability(of: item) != .notOnServer && app.canPlay(item) }
  private var firstFocus: Field { playable ? .play : .details }
  /// TMDB fills what Plex doesn't give (genres, length) for titles not on Plex.
  private var shown: PlexMetadata { library.filled(full ?? library.indexMatch(item) ?? item) }
  private var settled: Bool { Date().timeIntervalSince(movedAt) > 0.3 }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 0) {
        TVLogoTitle(library: library, item: item, maxWidth: 760, maxHeight: 230, textSize: 90)
          .frame(height: 230, alignment: .bottomLeading)
        // KP's mockup (2026-11-16): "2024 [PG-13] 2h 46m 4K UHD Dolby Vision Dolby Atmos".
        MetaBadgeRow(item: shown, playTarget: shown, library: library, fontSize: TVLayout.metaSize)
        .frame(height: 42)
        .padding(.top, 26)
        Text(shown.genres.prefix(3).map(\.tag).joined(separator: " · "))
          .font(.system(size: 24, weight: .medium))
          .foregroundStyle(Astra.Color.ink.opacity(0.65))
          .lineLimit(1)
          .frame(height: 30)
          .padding(.top, 6)
      }
      .id(item.id)
      .transition(.opacity)

      HStack(spacing: 28) {
        Button {
          playItem(item)
        } label: {
          Label(item.progress != nil ? "Resume" : "Play", systemImage: "play.fill")
            .font(.system(size: 30, weight: .semibold))
            .lineLimit(1)
            .frame(width: 250)
        }
        .buttonStyle(TVGlassButtonStyle(prominent: true))
        .focused($focus, equals: .play)
        .disabled(!playable)
        // Hold Select for Mark Watched and Go to (no downloads on TV).
        .itemMenu(library: library, item: item)

        Button {
          openItem(item)
        } label: {
          Label("Details", systemImage: "info.circle")
            .font(.system(size: 30, weight: .semibold))
            .lineLimit(1)
            .frame(width: 200)
        }
        .buttonStyle(TVGlassButtonStyle())
        .focused($focus, equals: .details)
      }
      .padding(.top, 30)
      .focusSection()
      .onMoveCommand { direction in
        // Reached when focus has nowhere to go that way (the circles are off
        // while the hero isn't on its first title).
        guard settled else { return }
        if direction == .right, focus == .details { step(1) }
        if direction == .left, focus == firstFocus, index > 0 { step(-1) }
      }
      if count > 1 {
        TVDots(count: count, index: index)
          .padding(.top, 30)
          .padding(.leading, 6)
      }
    }
    .frame(width: Self.blockWidth, alignment: .leading)
    // Home opens on Play (or Details when the title can't play here), not on
    // the sidebar or the tab bar.
    .defaultFocus($focus, firstFocus, priority: .userInitiated)
    .onChange(of: focus) { _, new in
      focused = new != nil
      movedAt = Date()
      if new != nil { leftEdge(index == 0) }
    }
    .onChange(of: focusRequest) { if focus == nil { focus = firstFocus } }
    .onChange(of: index) { _, new in
      if focus != nil { leftEdge(new == 0) }
    }
    .onChange(of: item.id) {
      // The next title may have nothing to play: keep focus in the block.
      if focus == .play, !playable { focus = .details }
    }
    // Closing the player re-enables the page with nothing focused, and tvOS
    // would then pick the leftmost circle; land back on the hero instead.
    .onChange(of: app.player.isActive) { _, active in
      guard !active else { return }
      Task {
        try? await Task.pause(0.3)
        focus = firstFocus
      }
    }
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

/// The hero's picture (KP, 2026-11-16): the whole picture softly blurred
/// across the hero, and the sharp picture on the right, fading in from the
/// left behind the logo. Vision finds the faces once (ArtFocusStore) and the
/// sharp picture slides right just far enough for them to clear the logo
/// block, never hard against the right edge.
/// Face-aware art: the picture sharp on the right with its faces clear of the
/// text block on the left, the rest the same art softly blurred. The hero
/// and Details use it (KP, 2026-11-16: "his face should be more on right").
struct TVHeroArt: View {
  var library: LibraryStore
  var item: PlexMetadata
  var kind: LibraryStore.ArtKind = .heroBackdrop
  /// Where the text block ends on a 1920 pt screen; faces stay right of it.
  var clearX: CGFloat = TVHeroArt.heroClearX

  @State private var url: URL?
  @State private var focus: ArtFocus?

  /// The logo block's right edge on a 1920 pt screen, plus clear air: KP
  /// (2026-11-16) wants faces well to the right, not crowding the logo.
  static let heroClearX: CGFloat = TVLayout.homeLeading + 80 + TVHeroInfo.blockWidth + 110

  var body: some View {
    GeometryReader { geo in
      let scale = geo.size.width / 1920
      let rect = ArtFraming.side(
        boxWidth: geo.size.width, boxHeight: geo.size.height, aspect: focus?.aspect ?? 16.0 / 9.0,
        clearX: clearX * scale, rightMargin: 60 * scale,
        minX: 240 * scale, maxX: 1040 * scale, defaultX: 420 * scale, focus: focus?.focus)
      ZStack(alignment: .topLeading) {
        // A colour wash only: blurred so far that no shape survives, so it
        // can't show a second, shifted copy of a face (KP, 2026-11-16: the
        // Breaking Bad art looked cut out with a ghost beside it).
        RemoteImage(url: url, contentMode: .fill, placeholder: Color.clear)
          .frame(width: geo.size.width, height: geo.size.height)
          .clipped()
          .blur(radius: 110, opaque: true)
          .opacity(0.55)
        // The blurred art sits exactly under the sharp art, so the fade
        // melts each thing into its own blur instead of into something else.
        RemoteImage(url: url, contentMode: .fill, placeholder: Color.clear)
          .frame(width: rect.width, height: rect.height)
          .clipped()
          .blur(radius: 34, opaque: true)
          .mask {
            LinearGradient(
              stops: [.init(color: .clear, location: 0), .init(color: .black.opacity(0.7), location: 0.3)],
              startPoint: .leading, endPoint: .trailing)
          }
          .offset(x: rect.minX)
        RemoteImage(url: url, contentMode: .fill, placeholder: Color.clear)
          .frame(width: rect.width, height: rect.height)
          .clipped()
          .mask {
            LinearGradient(
              stops: [
                // A long, soft fade so the sharp art's left edge melts into
                // the blur with no visible line (KP, 2026-11-16).
                .init(color: .clear, location: 0), .init(color: .black.opacity(0.3), location: 0.18),
                .init(color: .black.opacity(0.75), location: 0.35), .init(color: .black, location: 0.5),
              ],
              startPoint: .leading, endPoint: .trailing)
          }
          .offset(x: rect.minX)
      }
      .animation(.easeInOut(duration: 0.35), value: focus)
    }
    .clipped()
    .allowsHitTesting(false)
    .accessibilityHidden(true)
    .task(id: "\(item.id)|\(kind)") {
      focus = nil
      let found = await library.artworkURL(for: item, kind, width: 1920, height: 1080)
      guard !Task.isCancelled else { return }
      url = found
      guard let found else { return }
      if let hit = await ArtFocusStore.shared.cached(found) {
        focus = hit
        return
      }
      let result = await ArtFocusStore.shared.focus(for: found)
      guard !Task.isCancelled else { return }
      focus = result
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
    .accessibilityElement()
    .accessibilityLabel("Title \(index + 1) of \(count)")
    .accessibilityIdentifier("astra.hero.page")
  }
}

// MARK: - Streaming sidebar

/// For You and the streaming services as floating glass circles down the
/// left of Home (KP, 2026-11-09): a fixed list, the logo in each; it doesn't
/// open or grow. The chosen one is ringed in its brand colour.
private struct TVServiceSidebar: View {
  var library: LibraryStore
  /// Right from a circle, when tvOS finds nothing to its right by itself.
  var right: () -> Void = {}
  @AppStorage(Preferences.serviceLogoColorsKey) private var logoColors = true
  @FocusState private var focused: String?

  private static let forYou = "for-you"
  private var chosen: String { library.selectedService?.id ?? Self.forYou }

  var body: some View {
    VStack(spacing: 16) {
      circle(nil)
      ForEach(StreamingService.all) { circle($0) }
    }
    .frame(maxHeight: .infinity, alignment: .center)
    .focusSection()
    .onMoveCommand { if $0 == .right { right() } }
    .onChange(of: focused) { old, new in
      // Coming in from the page lands on the service that's showing, not
      // on whichever circle happens to sit level with the button.
      if old == nil, let new, new != chosen { focused = chosen }
    }
  }

  private func circle(_ service: StreamingService?) -> some View {
    let selected = library.selectedService == service
    let brand = logoColors ? (service.map { Color(hex: $0.accent) } ?? .white) : .white
    return Button {
      library.select(service)
    } label: {
      Group {
        if let service {
          Image(service.logo)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: TVLayout.sidebarCircle * 0.62, height: min(service.logoHeight * 0.9, 26))
            // White until chosen; the chosen one in its brand colour (KP).
            .foregroundStyle(selected ? brand : .white)
        } else {
          Image(systemName: "sparkles")
            .font(.system(size: 28, weight: .semibold))
            .foregroundStyle(.white)
        }
      }
      .frame(width: TVLayout.sidebarCircle, height: TVLayout.sidebarCircle)
    }
    .buttonStyle(TVSidebarButtonStyle(selected: selected, brand: brand))
    .focused($focused, equals: service?.id ?? Self.forYou)
    .accessibilityLabel(service?.label ?? "For You")
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}

/// A sidebar circle: clear glass, lighter and larger when focused; the
/// chosen service ringed in its brand colour.
private struct TVSidebarButtonStyle: ButtonStyle {
  var selected: Bool
  var brand: Color

  func makeBody(configuration: Configuration) -> some View {
    TVSidebarButtonBody(configuration: configuration, selected: selected, brand: brand)
  }
}

private struct TVSidebarButtonBody: View {
  let configuration: ButtonStyleConfiguration
  var selected: Bool
  var brand: Color
  @Environment(\.isFocused) private var focused

  var body: some View {
    configuration.label
      .background { Circle().fill(.black.opacity(focused ? 0.15 : 0.3)) }
      .background { if focused { Circle().fill(.white.opacity(0.35)) } }
      .astraGlass(in: Circle(), variant: .clear, interactive: true)
      .overlay { if selected { Circle().strokeBorder(brand, lineWidth: 3) } }
      .overlay { if focused { Circle().strokeBorder(.white, lineWidth: 3) } }
      .contentShape(Circle())
      .scaleEffect(configuration.isPressed ? 0.95 : (focused ? 1.12 : 1))
      .shadow(color: .black.opacity(focused ? 0.4 : 0.2), radius: focused ? 16 : 8, y: 6)
      .focusEffectDisabled()
      .animation(.snappy(duration: 0.22), value: focused)
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
  @Environment(\.tvLeftEdge) private var leftEdge

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
      .onTVFocus { if $0 { leftEdge(true) } }
      ScrollView(.horizontal, showsIndicators: false) {
        LazyHStack(alignment: .top, spacing: spacing) {
          // Each card says whether it's the row's first, so Left only
          // leaves the row for the streaming circles from there.
          Group(subviews: content) { cards in
            ForEach(Array(cards.enumerated()), id: \.element.id) { position, card in
              card.onTVFocus { if $0 { leftEdge(position == 0) } }
            }
          }
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
    .tvShine()
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
      .tvShine()
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
    .animation(.snappy(duration: 0.22), value: focused)
    .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
  }
}

/// The round Watchlist bookmark, filled once added (KP, 2026-11-16).
struct TVRoundWatchlist: View {
  var item: PlexMetadata
  @Environment(AppModel.self) private var app

  var body: some View {
    let on = app.isOnWatchlist(item)
    Button {
      Task { await app.toggleWatchlist(item) }
    } label: {
      Image(systemName: on ? "bookmark.fill" : "bookmark")
        .font(.system(size: 30, weight: .semibold))
        .contentTransition(.symbolEffect(.replace))
        .frame(width: TVLayout.roundButton, height: TVLayout.roundButton)
    }
    .buttonStyle(TVGlassButtonStyle(round: true))
    .accessibilityLabel(on ? "Remove from Watchlist" : "Add to Watchlist")
    .task { await app.loadWatchlistIfNeeded() }
  }
}
