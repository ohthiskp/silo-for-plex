import AstraKit
import SwiftUI

struct HomeView: View {
  var library: LibraryStore
  @Environment(\.contentLeading) private var leading
  /// The visible height of the page, measured once per resize; the hero is a share of it.
  @State private var viewport: CGFloat = 800
  @State private var showSettings = false
  @State private var showWatchlist = false
  @AppStorage(Preferences.serviceAccentsKey) private var serviceAccents = true
  /// The switcher shows only near the top of the page, so the hero's title
  /// never slides under it. Changes only when crossing the line, not every frame.
  @State private var showsTopBar = true
  /// The hero title on screen; the frosted page background follows it.
  @State private var heroItem: PlexMetadata?
  #if os(iOS)
    /// Only moved by the CI demo (`-AstraDemoScroll`), to screenshot the rows below the hero.
    @State private var scrollPosition = ScrollPosition(edge: .top)
  #endif

  private var heroHeight: CGFloat {
    min(Astra.Layout.heroHeight, max(380, viewport * Astra.Layout.heroShare))
  }

  var body: some View {
    let _ = PerfProbe.count("HomeView.body")
    // The page runs under the title bar / status bar; the switcher above it stays inside the safe area.
    ZStack(alignment: .top) {
      page
      #if os(iOS)
        // KP (2026-11-09): the tabs vanished on bright artwork. A blur runs
        // down from the Dynamic Island, behind the bar while it shows and
        // under the status bar once the page scrolls, fading out softly.
        TopEdgeBlur()
          .frame(height: showsTopBar ? 112 : 34)
          .ignoresSafeArea(edges: .top)
          .allowsHitTesting(false)
          .astraAnimation(Astra.Motion.base, value: showsTopBar)
      #endif
      #if os(iOS)
        // KP (2026-11-09): rows soften under the tab bar instead of meeting it.
        BottomEdgeBlur()
          .frame(maxHeight: .infinity, alignment: .bottom)
      #endif
      topBar
        .opacity(showsTopBar ? 1 : 0)
        .offset(y: showsTopBar ? 0 : -12)
        .allowsHitTesting(showsTopBar)
        .astraAnimation(Astra.Motion.base, value: showsTopBar)
    }
    // KP (2026-11-09): frosted Liquid Glass over the hero's artwork, not flat black.
    .background(AmbientBackdrop(library: library, item: heroItem ?? library.homeHero.first))
    // Astra: the chosen service's brand colour accents the page (Apple TV+'s is white).
    // Settings → Appearance → Streaming Service Accents turns it off.
    .environment(
      \.astraAccent,
      serviceAccents ? library.selectedService.flatMap { $0.id == "appletv" ? nil : Color(hex: $0.accent) } : nil)
    .astraAnimation(Astra.Motion.base, value: library.selectedService)
    #if os(iOS)
      .navigationDestination(isPresented: $showWatchlist) { WatchlistView(library: library) }
      .sheet(isPresented: $showSettings) {
        NavigationStack {
          SettingsView()
            .navigationTitle("Settings")
            .toolbar {
              ToolbarItem(placement: .confirmationAction) { Button("Done") { showSettings = false } }
            }
        }
      }
    #endif
  }

  private var page: some View {
    ScrollView(.vertical) {
      // A plain VStack: a lazy one guesses row heights and makes the page jump while scrolling.
      VStack(alignment: .leading, spacing: Astra.Spacing.xl) {
        if library.homeHero.isEmpty {
          // Holds the hero's space while trending titles load, so the rows don't jump down later.
          let heroComing = library.selectedService == nil ? library.isLoadingHero : library.isLoadingService
          Color.clear.frame(height: heroComing ? heroHeight : 120)
        } else {
          // Astra (KP, 2026-11-07): the hero follows the finger (or the
          // trackpad) and snaps to the next title; a stretching dot shows
          // where you are. No arrows, on iPhone and Mac.
          SwipeHero(library: library, items: library.homeHero, height: heroHeight) { heroItem = $0 }
          // A new set of titles (another service) starts a fresh carousel.
          .id(library.selectedService?.id ?? "for-you")
          .tvFullBleed()
        }

        if !library.homeContinueWatching.isEmpty {
          ContentRow(title: "Continue Watching") {
            ForEach(library.homeContinueWatching) { item in
              ContinueCard(library: library, item: item)
            }
          }
        }

        // Astra: one streaming-style Top 10 row on every tab (KP, 2026-11-07):
        // For You ranks trending titles on the server, a service tab what's
        // trending on that service.
        if !library.homeTopTen.isEmpty {
          TopTenRow(library: library)
            .id(library.selectedService?.id ?? "for-you")
        }

        // Astra 4.0 (KP, 2026-11-08): the same five sections on For You and
        // every service. Each Movies | Series switch keeps its own choice.
        ShelfRow(
          library: library, title: "Recently Released", shelf: library.homeRecent,
          storageKey: "astra.home.recentSeries")
        ShelfRow(
          library: library, title: "All-Time Greats", shelf: library.homeGreats,
          storageKey: "astra.home.greatsSeries")

        if let service = library.selectedService, let error = library.serviceError {
          // The rows already loaded stay above; this only says why new ones didn't come.
          EmptyState(
            symbol: "exclamationmark.triangle", title: "\(service.label) didn't load", message: error,
            action: ("Try Again", { library.retryService() }))
        } else if let service = library.selectedService, !library.isLoadingService, !library.homeHasSections {
          EmptyState(
            symbol: "tv", title: "Nothing from \(service.label)",
            message: "TMDB returned no titles for \(service.label). Try again in a moment.")
        }

        if library.selectedService == nil, let error = library.homeError {
          // Only a page with nothing at all gets the big message; otherwise a
          // quiet line (it retries by itself).
          if library.hubs.isEmpty && library.continueWatching.isEmpty && library.homeHero.isEmpty
            && library.homeTopTen.isEmpty
          {
            EmptyState(
              symbol: "exclamationmark.triangle", title: "Home didn't load", message: error,
              action: ("Try Again", { Task { await library.loadHome() } }))
          } else {
            // The technical reason is in Settings → About → Diagnostics.
            Text("Some rows didn't load yet. Astra is trying again.")
              .astraFont(.meta)
              .foregroundStyle(Astra.Color.muted)
              .padding(.leading, leading)
          }
        }
      }
      .padding(.bottom, 110)
      .onGeometryChange(for: Bool.self, of: { $0.frame(in: .scrollView).minY > -60 }) { showsTopBar = $0 }
    }
    .scrollIndicators(.never)
    #if os(iOS)
      .scrollPosition($scrollPosition)
      .task {
        guard let y = Demo.homeScroll, (try? await Task.pause(12)) != nil else { return }
        scrollPosition.scrollTo(y: y)
      }
    #endif
    .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { viewport = $0 }
    .overlay {
      if library.isLoadingHome || (library.isLoadingService && !library.homeHasSections) {
        ProgressView().astraControlSize(.large)
      }
    }
    .refreshable { await library.loadHome() }
    // Astra (KP, 2026-11-07): the hero and Top 10 Details are read ahead,
    // so tapping one opens it filled in. Restarts when the titles change.
    .task(id: prewarmKey) {
      let split = library.homeTopTenSplit
      await library.prewarmDetails(library.homeHero + split.movies + split.shows)
      // Then every other title on Home (KP, 2026-11-08: Details should be instant).
      let recent = library.homeRecent
      let greats = library.homeGreats
      await library.prewarmServerItems(
        library.homeContinueWatching + recent.movies + recent.shows + greats.movies + greats.shows)
    }
    .ignoresSafeArea(edges: .top)
  }

  private var prewarmKey: String {
    let split = library.homeTopTenSplit
    let recent = library.homeRecent
    let greats = library.homeGreats
    let all = library.homeHero + split.movies + split.shows + library.homeContinueWatching
      + recent.movies + recent.shows + greats.movies + greats.shows
    return all.map(\.id).joined(separator: ",")
  }

  private var topBar: some View {
    #if os(iOS)
      // KP's mockup (2026-11-09): only the streaming pills up top, right under
      // the Dynamic Island; the Watchlist lives in Library.
      VStack(alignment: .leading, spacing: 0) {
        if library.tmdb != nil {
          ServicePill(library: library)
        }
      }
      .padding(.top, Astra.Spacing.s)
      .padding(.leading, leading)
    #else
      HStack(spacing: Astra.Spacing.s) {
        if library.tmdb != nil {
          ServicePill(library: library)
        } else {
          Spacer()
        }
      }
      .padding(.top, Astra.Spacing.s)
      .padding(.leading, leading)
      .padding(.trailing, Astra.Spacing.pageTrailing)
    #endif
  }
}

#if os(iOS)
  /// A blur at the top of the screen that fades out downwards, with the
  /// page colour laid over it so white tabs and the clock always read.
  struct TopEdgeBlur: View {
    var body: some View {
      ZStack {
        Rectangle().fill(.regularMaterial)
        LinearGradient(
          colors: [Astra.Color.bg.opacity(0.7), Astra.Color.bg.opacity(0.35)],
          startPoint: .top, endPoint: .bottom)
      }
      .mask {
        LinearGradient(
          stops: [
            .init(color: .black, location: 0), .init(color: .black, location: 0.6),
            .init(color: .clear, location: 1),
          ],
          startPoint: .top, endPoint: .bottom)
      }
    }
  }
#endif

// MARK: - Streaming-service switcher

/// The floating glass switcher at the top of Home: For You and each service's logo.
/// Centred; scrolls sideways when the window is too narrow.
struct ServicePill: View {
  var library: LibraryStore
  @Namespace private var selection
  /// Settings → Appearance: brand-coloured logos, or plain white on glass.
  @AppStorage(Preferences.serviceLogoColorsKey) private var logoColors = true

  var body: some View {
    #if os(iOS)
      // KP's mockup (2026-11-09): each tab is its own glass pill, evenly
      // sized; logos are white, and the chosen service shows its real colour
      // on brighter glass. For You, when chosen, is a white pill.
      ScrollView(.horizontal) {
        HStack(spacing: 10) {
          railChip(nil, label: "For You") {
            Text("For You")
              .font(.system(size: 14.5, weight: .bold))
              .foregroundStyle(library.selectedService == nil ? Color.black : Color.white)
          }
          ForEach(StreamingService.all) { service in
            let selected = library.selectedService == service
            railChip(service, label: service.label) {
              Image(service.logo)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(height: service.logoHeight * 0.85)
                .foregroundStyle(selected && logoColors ? Color(hex: service.accent) : Color.white)
            }
          }
        }
        .padding(.vertical, 4)
        .padding(.trailing, 16)
      }
      .scrollIndicators(.never)
      .scrollClipDisabled()
      .astraAnimation(.snappy(duration: 0.22), value: library.selectedService)
    #else
      ViewThatFits(in: .horizontal) {
        chips
        ScrollView(.horizontal) { chips }
          .scrollIndicators(.never)
      }
      .astraGlass(in: Capsule())
      .frame(maxWidth: .infinity)
    #endif
  }

  #if os(iOS)
    private func railChip<Label: View>(
      _ service: StreamingService?, label: String, @ViewBuilder content: () -> Label
    ) -> some View {
      let selected = library.selectedService == service
      return Button {
        library.select(service)
      } label: {
        content()
          .padding(.horizontal, service == nil ? 18 : 14)
          .frame(minWidth: service == nil ? nil : 80)
          .frame(height: 38)
          .background {
            if selected && service == nil {
              Capsule().fill(.white)
            } else {
              // A dark tint under the glass keeps white logos readable on
              // bright artwork (KP, 2026-11-09).
              Capsule().fill(selected ? Color.white.opacity(0.22) : Color.black.opacity(0.28))
                .astraGlass(in: Capsule(), variant: .clear)
                .overlay {
                  if selected { Capsule().strokeBorder(.white.opacity(0.6), lineWidth: 1.5) }
                }
            }
          }
          .contentShape(Capsule())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(label)
      .accessibilityAddTraits(selected ? .isSelected : [])
    }
  #endif

  private var chips: some View {
    HStack(spacing: 2) {
      chip(nil, label: "For You") {
        Text("For You").font(.system(size: 14 * Astra.Layout.controlScale, weight: .bold))
      }
      ForEach(StreamingService.all) { service in
        chip(service, label: service.label) {
          Image(service.logo)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(height: service.logoHeight * 0.92 * Astra.Layout.controlScale)
        }
      }
    }
    .padding(5)
    .astraAnimation(.snappy(duration: 0.22), value: library.selectedService)
    // Apple TV: the switcher is its own block, reached by moving up from the hero.
    .tvFocusSection()
  }

  private func chip<Label: View>(_ service: StreamingService?, label: String, @ViewBuilder content: () -> Label)
    -> some View
  {
    let selected = library.selectedService == service
    return Button {
      library.select(service)
    } label: {
      content()
        .foregroundStyle(selected ? Color.black : Color.white.opacity(0.9))
        .padding(.horizontal, 14 * Astra.Layout.controlScale)
        .frame(height: 34 * Astra.Layout.controlScale)
        .background {
          if selected {
            Capsule().fill(.white).matchedGeometryEffect(id: "chip", in: selection)
          }
        }
        .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .help(label)
    .accessibilityLabel(label)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}

// MARK: - Top 10

/// "Top 10 This Week" (KP's mockup, 2026-11-07): one row of movies and series
/// in trending order, each poster with its big rank number laid over the
/// artwork's top-left corner, like the streaming apps. Titles not on the server open their details with Play greyed out.
struct TopTenRow: View {
  var library: LibraryStore
  @Environment(\.contentLeading) private var leading
  /// Astra (KP, 2026-11-07): Movies / Series, on For You and every service.
  @AppStorage("astra.home.topTenSeries") private var series = false

  private var items: [PlexMetadata] {
    let split = library.homeTopTenSplit
    return Array((series ? split.shows : split.movies).prefix(10))
  }
  private var title: String {
    // KP (2026-11-08): "Top Trending" on For You and every service.
    "Top Trending"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline, spacing: Astra.Spacing.s) {
        Text(title)
          .astraFont(.rowTitle)
          .foregroundStyle(Astra.Color.ink)
          .lineLimit(1)
        Spacer(minLength: 8)
        // KP (2026-11-08): no View All on the Top 10.
        KindSwitch(series: $series)
      }
      .padding(.leading, leading)
      .padding(.trailing, Astra.Spacing.pageTrailing)

      ScrollView(.horizontal) {
        LazyHStack(spacing: 6) {
          ForEach(Array(items.enumerated()), id: \.element.id) { rank, item in
            TopTenCard(library: library, item: item, rank: rank + 1)
          }
        }
        .padding(.horizontal, leading)
      }
      .scrollIndicators(.never)
      .scrollClipDisabled()
      .tvFocusSection()
    }
  }
}

/// A small glass capsule: Movies | Series, the chosen one white. Each Home
/// section owns its own (Astra 4.0: changing one never changes another).
struct KindSwitch: View {
  @Binding var series: Bool
  @Namespace private var kindPill

  var body: some View {
    HStack(spacing: 0) {
      ForEach([false, true], id: \.self) { isSeries in
        Button {
          astraWithAnimation(Astra.Motion.fast) { series = isSeries }
        } label: {
          Text(isSeries ? "Series" : "Movies")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(series == isSeries ? Color.black : Astra.Color.ink)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background {
              if series == isSeries { Capsule().fill(.white).matchedGeometryEffect(id: "kind", in: kindPill) }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(series == isSeries ? .isSelected : [])
      }
    }
    .padding(3)
    .astraGlass(in: Capsule(), variant: .clear)
  }
}

/// Astra 4.0: Recently Released or All-Time Greats: a title, its own
/// Movies | Series switch, and a row of posters. Hidden when both are empty.
struct ShelfRow: View {
  var library: LibraryStore
  var title: String
  var shelf: HomeShelf
  @AppStorage private var series: Bool
  @Environment(\.contentLeading) private var leading

  init(library: LibraryStore, title: String, shelf: HomeShelf, storageKey: String) {
    self.library = library
    self.title = title
    self.shelf = shelf
    _series = AppStorage(wrappedValue: false, storageKey)
  }

  var body: some View {
    if !shelf.isEmpty {
      let items = shelf.items(series: series)
      VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .firstTextBaseline, spacing: Astra.Spacing.s) {
          Text(title)
            .astraFont(.rowTitle)
            .foregroundStyle(Astra.Color.ink)
            .lineLimit(1)
          Spacer(minLength: 8)
          KindSwitch(series: $series)
        }
        .padding(.leading, leading)
        .padding(.trailing, Astra.Spacing.pageTrailing)

        if items.isEmpty {
          Text(series ? "No series here yet." : "No movies here yet.")
            .font(Astra.Font.meta)
            .foregroundStyle(Astra.Color.muted)
            .padding(.leading, leading)
            .frame(height: 60, alignment: .leading)
        } else {
          ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 14) {
              ForEach(items) { PosterCard(library: library, item: $0) }
            }
            .padding(.horizontal, leading)
          }
          .scrollIndicators(.never)
          .scrollClipDisabled()
          .tvFocusSection()
          // Each kind keeps its own scroll position.
          .id(series)
        }
      }
    }
  }
}

/// One Top 10 entry, Netflix style (KP, 2026-11-07): a huge outlined rank
/// number standing beside the poster, the poster overlapping its right edge.
struct TopTenCard: View {
  var library: LibraryStore
  var item: PlexMetadata
  var rank: Int
  var width: CGFloat = 112 * Astra.Layout.controlScale

  @Environment(\.openItem) private var openItem

  var body: some View {
    let height = width * 1.5
    Button {
      openItem(item)
    } label: {
      HStack(alignment: .bottom, spacing: -width * 0.26) {
        RankNumber(rank: rank, size: height * 0.86)
        ArtworkImage(library: library, item: item, kind: .poster, width: width, height: height)
          .frame(width: width, height: height)
          .clipShape(RoundedRectangle(cornerRadius: Astra.Radius.card, style: .continuous))
          .overlay(
            RoundedRectangle(cornerRadius: Astra.Radius.card, style: .continuous).stroke(Astra.Color.hairline))
          .shadow(color: .black.opacity(0.45), radius: 6, x: -3, y: 0)
      }
      .pressable()
      .contentShape(Rectangle())
    }
    .buttonStyle(AstraCardButtonStyle())
    .itemMenu(library: library, item: item)
    .accessibilityLabel("Number \(rank), \(item.displayTitle)")
  }
}

/// The big Top 10 rank (KP, 2026-11-09: "a mix of white and frosted
/// glass"): the digits are cut from a frosted blur of whatever is behind
/// them, washed with white that is bright at the top and fades into the
/// glass towards the foot. Uses the page's ink, so Light keeps dark digits.
struct RankNumber: View {
  var rank: Int
  var size: CGFloat = 150

  var body: some View {
    let digits = Text("\(rank)")
      .font(.system(size: size, weight: .heavy))
      .fontWidth(.condensed)
      .monospacedDigit()
      .tracking(rank >= 10 ? -size * 0.08 : 0)
      .lineLimit(1)
      .fixedSize()
    ZStack {
      // Frosted glass in the shape of the digits.
      digits.hidden()
        .background(.ultraThinMaterial)
        .mask(digits)
      // The white wash over it.
      digits.foregroundStyle(
        LinearGradient(
          colors: [Astra.Color.ink.opacity(0.92), Astra.Color.ink.opacity(0.5), Astra.Color.ink.opacity(0.12)],
          startPoint: .top, endPoint: .bottom))
    }
    .fixedSize()
    .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
    // The glyphs carry space under the baseline; pull the number down so its
    // foot lines up with the poster's bottom edge.
    .padding(.bottom, -size * 0.14)
    .accessibilityHidden(true)
  }
}

// MARK: - Hero

/// The hero's text and buttons.
struct HeroInfo: View {
  var library: LibraryStore
  var item: PlexMetadata

  #if os(macOS)
    static let titleBox: CGFloat = 130
    static let logoWidth: CGFloat = 400
  #elseif os(tvOS)
    static let titleBox: CGFloat = 180
    static let logoWidth: CGFloat = 680
  #else
    static let titleBox: CGFloat = 104
    static let logoWidth: CGFloat = 300
  #endif
  @Environment(\.openItem) private var openItem
  @Environment(\.playItem) private var playItem
  @Environment(AppModel.self) private var app

  /// The server's full copy (read ahead for Home), for the 4K / Dolby /
  /// Atmos pills and the runtime: a streaming-list title has no media of
  /// its own, so without this the hero showed only "2026 · PG".
  @State private var full: PlexMetadata?

  private var playable: Bool {
    library.availability(of: item) != .notOnServer && app.canPlay(item)
  }

  /// Best copy known: the full one, else the index's match, else the title itself.
  private var shown: PlexMetadata { full ?? library.indexMatch(item) ?? item }

  /// KP's hero mockup (2026-11-09): one block at the left, its logo centred
  /// over the meta line and buttons; full width on iPhone.
  #if os(iOS)
    static let blockWidth: CGFloat = .infinity
  #elseif os(tvOS)
    static let blockWidth: CGFloat = 760
  #else
    static let blockWidth: CGFloat = 440
  #endif

  var body: some View {
    #if os(iOS)
      phoneBody
    #else
      wideBody
    #endif
  }

  #if os(iOS)
    /// KP's iPhone mockup (2026-11-09): logo centred right above the info,
    /// "2026 • 1h 41m • [PG] [HD]", the genres under it, then a white Play
    /// and the round + / ✓. Every box has a fixed height, so the hero's
    /// faces can be framed above the logo for any title.
    static let logoBox = CGSize(width: 240, height: 150)
    /// From the top of the logo box to the bottom of the buttons.
    static let blockHeight: CGFloat = 150 + 14 + 24 + 6 + 18 + 18 + 50

    private var phoneBody: some View {
      VStack(spacing: 0) {
        Button {
          openItem(item)
        } label: {
          HeroTitle(
            library: library, item: item, maxWidth: Self.logoBox.width, maxHeight: Self.logoBox.height,
            alignment: .bottom
          )
          .frame(maxWidth: .infinity)
          .frame(height: Self.logoBox.height, alignment: .bottom)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.displayTitle), Details")
        HStack(spacing: 8) {
          DetailMetaLine(
            item: shown, library: library, showsGenres: false, fontSize: 14, separator: "  •  ",
            ratingAfter: true, greyRating: true)
          FormatBadges(item: shown)
        }
        .frame(height: 24)
        .padding(.top, 14)
        .task(id: item.id) {
          full = nil
          let key = item.isCatalogOnly ? library.indexMatch(item)?.ratingKey : item.ratingKey
          guard let key else { return }
          let found = try? await library.details(key)
          guard !Task.isCancelled else { return }
          full = found
        }
        Text(shown.genres.prefix(3).map(\.tag).joined(separator: " · "))
          .astraFont(size: 13.5)
          .foregroundStyle(Astra.Color.ink.opacity(0.62))
          .lineLimit(1)
          .frame(height: 18)
          .padding(.top, 6)
        HStack(spacing: 20) {
          Button {
            playItem(item)
          } label: {
            Label(item.progress != nil ? "Resume" : "Play", systemImage: "play.fill")
              .frame(width: 156)
          }
          .buttonStyle(SolidCapsuleButtonStyle())
          .disabled(!playable)
          WatchlistButton(item: item, size: 48)
        }
        .frame(height: 50)
        .padding(.top, 18)
      }
      .frame(maxWidth: .infinity)
    }
  #endif

  private var wideBody: some View {
    VStack(alignment: .leading, spacing: 14) {
      // Fixed boxes for the title and the meta: every title takes the same
      // height, so the buttons and pager never move when the hero switches.
      // Tapping the logo opens Details.
      Button {
        openItem(item)
      } label: {
        // A wide logo across most of the block, centred over it (KP's mockup).
        HeroTitle(library: library, item: item, maxWidth: Self.logoWidth, maxHeight: Self.titleBox, alignment: .bottom)
          .frame(maxWidth: .infinity)
          .frame(height: Self.titleBox, alignment: .bottom)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("\(item.displayTitle), Details")
      // "2025 · 2h 8m · Sci-Fi [PG-13] [4K]" on one line, as in the mockup.
      HStack(spacing: 10) {
        DetailMetaLine(item: shown, library: library, fontSize: 14.5, genreLimit: 1, ratingAfter: true)
          .layoutPriority(1)
        FormatBadges(item: shown)
      }
      .task(id: item.id) {
        full = nil
        let key = item.isCatalogOnly ? library.indexMatch(item)?.ratingKey : item.ratingKey
        guard let key else { return }
        let found = try? await library.details(key)
        guard !Task.isCancelled else { return }
        full = found
      }
      // Same height for every title, so the buttons never move.
      .frame(height: 26 * Astra.Layout.textScale, alignment: .leading)
      HStack(spacing: 12) {
        Button {
          playItem(item)
        } label: {
          Label(item.progress != nil ? "Resume" : "Play", systemImage: "play.fill")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(SolidCapsuleButtonStyle())
        // On the service but not on the Plex server: nothing to play.
        // Greyed only once it's known the title isn't on the server, never
        // while the library is still loading.
        .disabled(!playable)
        // Apple TV: focus starts on Play, not on the sidebar.
        .tvLaunchFocus(item.id, when: playable)
        .help(library.availability(of: item) == .notOnServer ? "Not on your Plex server" : "")
        // KP (2026-11-09): the mockup's Details button is the round glass +
        // (Plex Watchlist). Tapping the logo opens Details.
        WatchlistButton(item: item)
          .tvLaunchFocus(item.id, when: !playable)
      }
      .astraGlassGroup(spacing: 12)
      .padding(.top, 4)
    }
    .frame(maxWidth: Self.blockWidth, alignment: .leading)
  }
}

struct HeroScrim: View {
  var body: some View {
    ZStack {
      LinearGradient(
        stops: [
          .init(color: Astra.Color.bg.opacity(0.0), location: 0.35),
          .init(color: Astra.Color.bg.opacity(0.75), location: 0.8),
          .init(color: Astra.Color.bg, location: 1),
        ], startPoint: .top, endPoint: .bottom)
      LinearGradient(
        colors: [Astra.Color.bg.opacity(0.85), Astra.Color.bg.opacity(0)], startPoint: .leading,
        endPoint: .init(x: 0.6, y: 0.5))
    }
    .allowsHitTesting(false)
  }
}

/// The Home hero's shade: dark behind the title at the left, a little at the
/// bottom; the bottom edge itself is a fade (mask), not a band of black.
struct HeroBlend: View {
  var body: some View {
    ZStack {
      LinearGradient(
        stops: [
          .init(color: Astra.Color.bg.opacity(0), location: 0.4),
          .init(color: Astra.Color.bg.opacity(0.5), location: 1),
        ], startPoint: .top, endPoint: .bottom)
      #if !os(iOS)
        LinearGradient(
          colors: [Astra.Color.bg.opacity(0.8), Astra.Color.bg.opacity(0)], startPoint: .leading,
          endPoint: .init(x: 0.6, y: 0.5))
      #endif
    }
    .allowsHitTesting(false)
  }
}

/// The title logo (TMDB's, else Plex's), else the title in Didot. Nothing is
/// drawn until the logo lookup finishes, so the text never flashes before the logo.
struct HeroTitle: View {
  var library: LibraryStore
  var item: PlexMetadata
  var maxWidth: CGFloat = 440
  var maxHeight: CGFloat = 140
  /// The hero centres its logo over the text (KP's mockup, 2026-11-09).
  var alignment: Alignment = .bottomLeading

  @State private var logo: URL?
  @State private var resolved = false

  var body: some View {
    ZStack(alignment: alignment) {
      if let logo {
        RemoteImage(url: logo, contentMode: .fit, placeholder: Color.clear)
          .frame(maxWidth: maxWidth, maxHeight: maxHeight, alignment: alignment)
          .shadow(color: .black.opacity(0.5), radius: 14, y: 4)
      } else if resolved {
        Text(item.displayTitle)
          .astraDisplay(Astra.Layout.titleSize, tracking: 10)
          .lineLimit(2)
          .minimumScaleFactor(0.5)
          .multilineTextAlignment(alignment == .bottom ? .center : .leading)
          .frame(maxWidth: 640, maxHeight: maxHeight, alignment: alignment)
      }
    }
    .frame(minHeight: 44, alignment: alignment)
    .task(id: item.id) {
      logo = await library.artworkURL(for: item, .logo, width: maxWidth, height: maxHeight)
      resolved = true
    }
  }
}

struct MetaRow: View {
  var item: PlexMetadata
  /// For the official rating of titles Plex has none for (TMDB-only ones).
  var library: LibraryStore? = nil
  var fontSize: CGFloat = 15
  @AppStorage(PlaybackQuality.storageKey) private var quality: PlaybackQuality = .auto
  @AppStorage(Preferences.qualityBadgesKey) private var showQuality = true

  var body: some View {
    HStack(spacing: 10) {
      let parts = [
        item.year.map(String.init),
        item.type == .show ? item.childCount.map { "\($0) Season\($0 == 1 ? "" : "s")" } : item.durationLabel,
        item.genres.prefix(2).map(\.tag).joined(separator: ", ").nilIfEmpty,
      ].compactMap { $0 }
      // The text truncates first; badges keep their size.
      Text(parts.joined(separator: "  •  "))
        .font(.system(size: fontSize, weight: .medium))
        .foregroundStyle(Astra.Color.ink.opacity(0.9))
        .lineLimit(1)
      // Astra (KP, 2026-11-07): the official rating first (PG-13, TV-MA…),
      // then the version this device would play. Still no star ratings.
      RatingBadge(item: item, library: library)
      let pick = quality == .auto ? PlaybackQuality.current() : quality
      if showQuality, let badge = item.resolutionBadge(for: pick) { Badge(text: badge).fixedSize() }
      // Astra (KP, 2026-11-07): Dolby Vision / HDR of that file, when Plex says.
      if let range = item.dynamicRange(for: pick) {
        Badge(text: range == .dolbyVision ? "Dolby Vision" : "HDR").fixedSize()
      }
    }
  }
}

extension String {
  var nilIfEmpty: String? { isEmpty ? nil : self }
}

/// The official age rating of a movie or show: Plex's when it has one, else
/// TMDB's US certification. Nothing when neither knows.
struct RatingBadge: View {
  var item: PlexMetadata
  var library: LibraryStore?

  @State private var fetched: String?
  @AppStorage(Preferences.ratingsKey) private var showRatings = true

  private var rating: String? { item.officialRating ?? fetched }

  var body: some View {
    Group {
      if showRatings, let rating { RatingBox(text: rating) }
    }
    .task(id: item.id) {
      fetched = nil
      guard item.officialRating == nil, item.type == .movie || item.type == .show, let library else { return }
      fetched = await library.tmdbArtwork(for: item)?.certification
    }
    .accessibilityLabel(rating.map { "Rated \($0)" } ?? "")
  }
}

/// A round grey Liquid Glass button: + adds the title to the Plex Watchlist,
/// ✓ (when it's already there) takes it off.
struct WatchlistButton: View {
  var item: PlexMetadata
  var size: CGFloat = 50
  /// Regular glass on the hero; clear on Details, like its Download and Watched buttons.
  var variant: AstraGlassVariant = .regular

  @Environment(AppModel.self) private var app

  var body: some View {
    let on = app.isOnWatchlist(item)
    Button {
      Task { await app.toggleWatchlist(item) }
    } label: {
      Image(systemName: on ? "checkmark" : "plus")
        .font(.system(size: 19, weight: .semibold))
        .contentTransition(.symbolEffect(.replace))
    }
    .astraIconButton(size: size, variant: variant)
    #if !os(tvOS)
      .sensoryFeedback(.success, trigger: on)
    #endif
    .help(on ? "Remove from Watchlist" : "Add to Watchlist")
    .accessibilityLabel(on ? "Remove from Watchlist" : "Add to Watchlist")
    .task { await app.loadWatchlistIfNeeded() }
  }
}

/// The hero: titles side by side in a paging scroll view, so a drag
  /// moves the artwork with the finger and lets go onto the next title. No
  /// arrows; the dots below stretch toward the title you're dragging to.
  struct SwipeHero: View {
    var library: LibraryStore
    var items: [PlexMetadata]
    var height: CGFloat
    /// The title now showing (for the page's frosted background).
    var onCurrent: (PlexMetadata) -> Void = { _ in }

    @State private var position: Int?
    /// How far the page has scrolled the hero up; it blurs and fades by it.
    @State private var scrolled: CGFloat = 0
    /// Pages scrolled, fractional while dragging (1.5 = halfway to the third).
    @State private var progress: CGFloat = 0
    @Environment(\.contentLeading) private var leading
    @Environment(\.openItem) private var openItem

    var body: some View {
      ScrollView(.horizontal) {
        LazyHStack(spacing: 0) {
          ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
            page(item)
              .containerRelativeFrame(.horizontal)
              .id(i)
          }
        }
        .scrollTargetLayout()
      }
      .scrollTargetBehavior(.paging)
      // The artwork sits behind the sliding pages as one layer, so a swipe
      // crossfades and blurs one title into the next with no seam between
      // two pictures (KP, 2026-11-09). Only the text slides.
      .background { artwork }
      .scrollPosition(id: $position)
      .scrollIndicators(.never)
      .modifier(PageProgressReader(progress: $progress, position: position))
      .modifier(ScrolledAway(offset: $scrolled))
      .onAppear { if let first = items.first { onCurrent(first) } }
      .onChange(of: position) { _, now in
        if let now, items.indices.contains(now) { onCurrent(items[now]) }
      }
      .overlay(alignment: .bottom) {
        if items.count > 1 {
          // On the Mac a click on a dot moves there too (a mouse can't swipe).
          StretchDots(count: items.count, progress: progress) { i in
            astraWithAnimation(.snappy(duration: 0.4)) { position = i }
          }
          .padding(.bottom, 6)
        }
      }
      #if !os(tvOS)
        .sensoryFeedback(.selection, trigger: position)
      #endif
    }

    /// The title being left and the one arriving, by how far the swipe is.
    private var artwork: some View {
      let count = items.count
      let base = min(max(0, Int(progress.rounded(.down))), max(0, count - 1))
      let mix = min(max(0, progress - CGFloat(base)), 1)
      let shown = items.isEmpty ? [] : [items[base]] + (base + 1 < count && mix > 0.001 ? [items[base + 1]] : [])
      return ZStack {
        ForEach(Array(shown.enumerated()), id: \.element.id) { i, item in
          #if os(iOS)
            // KP (2026-11-09): the faces always end above the logo, for any title.
            FramedArtwork(
              library: library, item: item, kind: .heroBackdrop, zoneHeight: height,
              limitY: height - 30 - HeroInfo.blockHeight - 6, topOffset: 24, minTop: 110
            )
            .opacity(i == 0 ? 1 : mix)
          #else
            ArtworkImage(
              library: library, item: item, kind: .heroBackdrop, width: 1920, height: 1080, placeholder: Color.clear
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .opacity(i == 0 ? 1 : mix)
          #endif
        }
        // Mid-swipe the two blur together; scrolling down blurs into the
        // frosted background below (KP, 2026-11-09).
        .blur(radius: sin(mix * .pi) * 22 + min(30, scrolled / 12))
        HeroBlend()
      }
      // The bottom dissolves into the frosted background (the same
      // artwork, blurred), so there is no edge between hero and rows.
      .mask {
        LinearGradient(
          // KP's mockup (2026-11-09): the artwork stays bright behind the
          // logo and buttons and only fades at the very bottom.
          stops: [.init(color: .black, location: 0.8), .init(color: .clear, location: 1)],
          startPoint: .top, endPoint: .bottom)
      }
      .clipped()
      .allowsHitTesting(false)
    }

    private func page(_ item: PlexMetadata) -> some View {
      VStack(alignment: .leading, spacing: 0) {
        HeroInfo(library: library, item: item)
      }
      .padding(.leading, leading)
      .padding(.trailing, Astra.Spacing.pageTrailing)
      // Room above the text for the artwork and the streaming switcher; below it for the dots.
      .padding(.top, 110)
      .padding(.bottom, 30)
      .frame(maxWidth: .infinity, minHeight: height, alignment: .bottomLeading)
      .clipped()
      // A tap anywhere opens Details; Play and + keep their own action.
      .contentShape(Rectangle())
      .onTapGesture { openItem(item) }
    }
  }

  /// Page dots where the current one is a long capsule; while dragging, it
  /// shrinks back to a dot as the next one grows into the capsule.
  struct StretchDots: View {
    var count: Int
    var progress: CGFloat
    var select: (Int) -> Void = { _ in }

    var body: some View {
      HStack(spacing: 6) {
        ForEach(0..<count, id: \.self) { i in
          let near = max(0, 1 - abs(progress - CGFloat(i)))
          Capsule()
            .fill(Astra.Color.ink.opacity(0.35 + 0.65 * near))
            .frame(width: 7 + 17 * near, height: 7)
            #if os(macOS)
              .padding(.vertical, 6)
              .contentShape(Rectangle())
              .onTapGesture { select(i) }
            #endif
        }
      }
      #if os(iOS)
        .allowsHitTesting(false)
      #endif
      .accessibilityElement()
      .accessibilityLabel("Title \(Int(progress.rounded()) + 1) of \(count)")
    }
  }

/// How far the hero has paged, fractional while dragging. macOS 14 has no
/// scroll geometry, so there it follows the page it settles on.
private struct PageProgressReader: ViewModifier {
  @Binding var progress: CGFloat
  var position: Int?

  func body(content: Content) -> some View {
    if #available(macOS 15.0, iOS 18.0, *) {
      content.onScrollGeometryChange(for: CGFloat.self, of: { geo in
        geo.containerSize.width > 0 ? geo.contentOffset.x / geo.containerSize.width : 0
      }) { _, value in
        progress = value
      }
    } else {
      content.onChange(of: position) { _, new in
        astraWithAnimation(.snappy(duration: 0.3)) { progress = CGFloat(new ?? 0) }
      }
    }
  }
}
