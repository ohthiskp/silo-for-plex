import AstraKit
import SwiftUI

struct HomeView: View {
  var library: LibraryStore
  @Environment(\.contentLeading) private var leading
  /// The visible height of the page, measured once per resize; the hero is a share of it.
  @State private var viewport: CGFloat = 800
  @State private var showSettings = false
  @State private var showWatchlist = false
  /// The switcher shows only near the top of the page, so the hero's title
  /// never slides under it. Changes only when crossing the line, not every frame.
  @State private var showsTopBar = true

  private var heroHeight: CGFloat {
    min(Astra.Layout.heroHeight, max(380, viewport * Astra.Layout.heroShare))
  }

  var body: some View {
    // The page runs under the title bar / status bar; the switcher above it stays inside the safe area.
    ZStack(alignment: .top) {
      page
      topBar
        .opacity(showsTopBar ? 1 : 0)
        .offset(y: showsTopBar ? 0 : -12)
        .allowsHitTesting(showsTopBar)
        .animation(Astra.Motion.base, value: showsTopBar)
    }
    .background(Astra.Color.bg.ignoresSafeArea())
    // Astra: the chosen service's brand colour accents the page (Apple TV+'s is white).
    .environment(\.astraAccent, library.selectedService.flatMap { $0.id == "appletv" ? nil : Color(hex: $0.accent) })
    .animation(Astra.Motion.base, value: library.selectedService)
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
          SwipeHero(library: library, items: library.homeHero, height: heroHeight)
          // A new set of titles (another service) starts a fresh carousel.
          .id(library.selectedService?.id ?? "for-you")
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

        ForEach(library.homeRows) { hub in
          ContentRow(title: hub.title) {
            // Movies and shows as posters; episodes keep landscape stills.
            if hub.items.contains(where: { $0.type == .episode || $0.type == .clip }) {
              ForEach(hub.items) { ArtCard(library: library, item: $0) }
            } else {
              ForEach(hub.items) { PosterCard(library: library, item: $0) }
            }
          }
        }

        if let service = library.selectedService, let error = library.serviceError {
          // The rows already loaded stay above; this only says why new ones didn't come.
          EmptyState(
            symbol: "exclamationmark.triangle", title: "\(service.label) didn't load", message: error,
            action: ("Try Again", { library.retryService() }))
        } else if let service = library.selectedService, !library.isLoadingService, library.homeRows.isEmpty {
          EmptyState(
            symbol: "tv", title: "Nothing from \(service.label)",
            message: "None of the popular titles on \(service.label) are on your Plex server.")
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
            Text("Some rows didn't load. Trying again shortly. (\(error))")
              .font(Astra.Font.meta)
              .foregroundStyle(Astra.Color.muted)
              .padding(.leading, leading)
          }
        }
      }
      .padding(.bottom, 110)
      .onGeometryChange(for: Bool.self, of: { $0.frame(in: .scrollView).minY > -60 }) { showsTopBar = $0 }
    }
    .scrollIndicators(.never)
    .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { viewport = $0 }
    .overlay {
      if library.isLoadingHome || (library.isLoadingService && library.homeRows.isEmpty) {
        ProgressView().controlSize(.large)
      }
    }
    .refreshable { await library.loadHome() }
    // Astra (KP, 2026-11-07): the hero and Top 10 Details are read ahead,
    // so tapping one opens it filled in. Restarts when the titles change.
    .task(id: prewarmKey) {
      let split = library.homeTopTenSplit
      await library.prewarmDetails(library.homeHero + split.movies + split.shows)
    }
    .ignoresSafeArea(edges: .top)
  }

  private var prewarmKey: String {
    let split = library.homeTopTenSplit
    return (library.homeHero + split.movies + split.shows).map(\.id).joined(separator: ",")
  }

  private var topBar: some View {
    HStack(spacing: Astra.Spacing.s) {
      if library.tmdb != nil {
        ServicePill(library: library)
      } else {
        Spacer()
      }
      // Astra: on iPhone Settings moved to the Libraries tab, and the top right
      // holds the Plex Watchlist (KP, 2026-11-07).
      #if os(iOS)
        Button {
          showWatchlist = true
        } label: {
          Image(systemName: "bookmark")
        }
        .astraIconButton(size: 40, variant: .clear)
        .accessibilityLabel("Watchlist")
      #endif
    }
    .padding(.top, Astra.Spacing.s)
    .padding(.leading, leading)
    .padding(.trailing, Astra.Spacing.pageTrailing)
  }
}

// MARK: - Streaming-service switcher

/// The floating glass switcher at the top of Home: For You and each service's logo.
/// Centred; scrolls sideways when the window is too narrow.
struct ServicePill: View {
  var library: LibraryStore
  @Namespace private var selection

  var body: some View {
    #if os(iOS)
      // Astra: iPhone shows a rail of separate glass chips that scrolls to the
      // right, each logo in its brand colour; the chosen one is outlined in it
      // (KP's mockup, 2026-11-07).
      ScrollView(.horizontal) {
        HStack(spacing: 8) {
          railChip(nil, label: "For You") {
            Text("For You").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
          }
          ForEach(StreamingService.all) { service in
            railChip(service, label: service.label) {
              Image(service.logo)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(height: service.logoHeight * 0.85)
                .foregroundStyle(Color(hex: service.accent))
            }
          }
        }
        .padding(.vertical, 2)
        .padding(.trailing, 16)
      }
      .scrollIndicators(.never)
      // Astra: the rail ends (fading out) before the Watchlist button instead
      // of sliding underneath it.
      .mask {
        LinearGradient(
          stops: [.init(color: .black, location: 0.9), .init(color: .clear, location: 1)],
          startPoint: .leading, endPoint: .trailing)
      }
      .animation(.snappy(duration: 0.22), value: library.selectedService)
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
      let brand = service.map { Color(hex: $0.accent) } ?? .white
      return Button {
        library.select(service)
      } label: {
        content()
          .padding(.horizontal, 16)
          .frame(height: 38)
          .background { if selected { Capsule().fill(brand.opacity(0.18)) } }
          .overlay { if selected { Capsule().strokeBorder(brand, lineWidth: 1.5) } }
          .astraGlass(in: Capsule(), variant: .clear, interactive: true)
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
        Text("For You").font(.system(size: 14, weight: .bold))
      }
      ForEach(StreamingService.all) { service in
        chip(service, label: service.label) {
          Image(service.logo)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(height: service.logoHeight * 0.92)
        }
      }
    }
    .padding(5)
    .animation(.snappy(duration: 0.22), value: library.selectedService)
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
        .padding(.horizontal, 14)
        .frame(height: 34)
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
/// artwork's top-left corner, and View All on the right, like the streaming
/// apps. Titles not on the server open their details with Play greyed out.
struct TopTenRow: View {
  var library: LibraryStore
  @Environment(\.contentLeading) private var leading
  @State private var showAll = false
  /// Astra (KP, 2026-11-07): Movies / Series, on For You and every service.
  @AppStorage("astra.home.topTenSeries") private var series = false
  @Namespace private var kindPill

  private var items: [PlexMetadata] {
    let split = library.homeTopTenSplit
    return Array((series ? split.shows : split.movies).prefix(10))
  }
  private var title: String {
    library.selectedService.map { "Top 10 on \($0.label)" } ?? "Top 10 This Week"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline, spacing: Astra.Spacing.s) {
        Text(title)
          .font(Astra.Font.rowTitle)
          .foregroundStyle(Astra.Color.ink)
          .lineLimit(1)
        Spacer(minLength: 8)
        kindSwitch
        Button {
          showAll = true
        } label: {
          HStack(spacing: 4) {
            Text("View All")
            Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
          }
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(Astra.Color.ink)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
    }
    .navigationDestination(isPresented: $showAll) {
      TopTenList(library: library, items: items, title: title)
    }
  }

  /// A small glass capsule: Movies | Series, the chosen one white.
  private var kindSwitch: some View {
    HStack(spacing: 0) {
      ForEach([false, true], id: \.self) { isSeries in
        Button {
          withAnimation(Astra.Motion.fast) { series = isSeries }
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

/// One Top 10 entry, Netflix style (KP, 2026-11-07): a huge outlined rank
/// number standing beside the poster, the poster overlapping its right edge.
struct TopTenCard: View {
  var library: LibraryStore
  var item: PlexMetadata
  var rank: Int
  var width: CGFloat = 112

  @Environment(\.openItem) private var openItem

  var body: some View {
    let height = width * 1.5
    Button {
      openItem(item)
    } label: {
      HStack(alignment: .bottom, spacing: -width * 0.22) {
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

/// The big Top 10 rank: the page colour inside a light outline, like the
/// streaming apps (white and grey only), sitting on the poster's baseline.
struct RankNumber: View {
  var rank: Int
  var size: CGFloat = 150

  var body: some View {
    let digits = Text("\(rank)")
      .font(.system(size: size, weight: .black, design: .rounded))
      .monospacedDigit()
      .tracking(rank >= 10 ? -size * 0.12 : 0)
    let line = max(1.5, size / 70)
    ZStack {
      // An outline from eight offset copies (SwiftUI has no text stroke).
      ForEach(0..<8, id: \.self) { step in
        let angle = Double(step) * .pi / 4
        digits
          .foregroundStyle(Astra.Color.ink.opacity(0.85))
          .offset(x: cos(angle) * line, y: sin(angle) * line)
      }
      digits.foregroundStyle(Astra.Color.bg)
    }
    .lineLimit(1)
    .fixedSize()
    // The glyphs carry space under the baseline; pull the number down so its
    // foot lines up with the poster's bottom edge.
    .padding(.bottom, -size * 0.14)
    .accessibilityHidden(true)
  }
}

/// View All: the whole Top 10 as a ranked list.
struct TopTenList: View {
  var library: LibraryStore
  var items: [PlexMetadata]
  var title = "Top 10 This Week"

  @Environment(\.openItem) private var openItem

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 14) {
        ForEach(Array(items.enumerated()), id: \.element.id) { rank, item in
          Button {
            openItem(item)
          } label: {
            HStack(spacing: 14) {
              Text("\(rank + 1)")
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .italic()
                .monospacedDigit()
                .foregroundStyle(Astra.Color.ink)
                .frame(width: 44)
              ArtworkImage(library: library, item: item, kind: .poster, width: 70, height: 105)
                .frame(width: 70, height: 105)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
              VStack(alignment: .leading, spacing: 4) {
                Text(item.displayTitle)
                  .font(.system(size: 16, weight: .semibold))
                  .foregroundStyle(Astra.Color.ink)
                  .lineLimit(2)
                Text([item.type == .show ? "Series" : "Movie", item.year.map(String.init)].compactMap { $0 }
                  .joined(separator: " · "))
                  .font(Astra.Font.meta)
                  .foregroundStyle(Astra.Color.muted)
              }
              Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .itemMenu(library: library, item: item)
        }
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 12)
    }
    .scrollIndicators(.never)
    .background(Astra.Color.bg.ignoresSafeArea())
    .navigationTitle(title)
    #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar(.visible, for: .navigationBar)
    #endif
  }
}

// MARK: - Hero

/// The hero's text and buttons.
struct HeroInfo: View {
  var library: LibraryStore
  var item: PlexMetadata

  #if os(macOS)
    static let titleBox: CGFloat = 130
  #else
    static let titleBox: CGFloat = 96
  #endif
  @Environment(\.openItem) private var openItem
  @Environment(\.playItem) private var playItem
  @Environment(AppModel.self) private var app

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      // Fixed boxes for the title and summary: every title takes the same
      // height, so the buttons and pager never move when the hero switches.
      // Tapping the logo opens Details (the Details button became +, KP 2026-11-07).
      Button {
        openItem(item)
      } label: {
        HeroTitle(library: library, item: item, maxHeight: Self.titleBox)
          .frame(height: Self.titleBox, alignment: .bottomLeading)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("\(item.displayTitle), Details")
      MetaRow(item: item, library: library)
      Text(item.summary ?? "")
        .font(.system(size: 14.5))
        .lineSpacing(4)
        .foregroundStyle(Astra.Color.ink.opacity(0.82))
        .lineLimit(3)
        .frame(maxWidth: 560, alignment: .leading)
        .frame(height: 66, alignment: .topLeading)
      // Astra (KP, 2026-11-07): a white Play like the Apple TV app, and a
      // round grey Liquid Glass + that adds the title to the Plex Watchlist.
      HStack(spacing: 12) {
        Button {
          playItem(item)
        } label: {
          Label(item.progress != nil ? "Resume" : "Play", systemImage: "play.fill")
            .padding(.horizontal, 14)
        }
        .buttonStyle(SolidCapsuleButtonStyle())
        // On the service but not on the Plex server: nothing to play.
        // Greyed only once it's known the title isn't on the server, never
        // while the library is still loading.
        .disabled(library.availability(of: item) == .notOnServer)
        .help(library.availability(of: item) == .notOnServer ? "Not on your Plex server" : "")
        WatchlistButton(item: item)
      }
      .astraGlassGroup(spacing: 12)
      .padding(.top, 6)
    }
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

/// The title logo (TMDB's, else Plex's), else the title in Didot. Nothing is
/// drawn until the logo lookup finishes, so the text never flashes before the logo.
struct HeroTitle: View {
  var library: LibraryStore
  var item: PlexMetadata
  var maxWidth: CGFloat = 440
  var maxHeight: CGFloat = 140

  @State private var logo: URL?
  @State private var resolved = false

  var body: some View {
    ZStack(alignment: .bottomLeading) {
      if let logo {
        RemoteImage(url: logo, contentMode: .fit, placeholder: Color.clear)
          .frame(maxWidth: maxWidth, maxHeight: maxHeight, alignment: .bottomLeading)
          .shadow(color: .black.opacity(0.5), radius: 14, y: 4)
      } else if resolved {
        Text(item.displayTitle)
          .astraDisplay(Astra.Layout.titleSize, tracking: 10)
          .lineLimit(2)
          .minimumScaleFactor(0.5)
          .frame(maxWidth: 640, maxHeight: maxHeight, alignment: .bottomLeading)
      }
    }
    .frame(minHeight: 44, alignment: .bottomLeading)
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
      if let badge = item.resolutionBadge(for: pick) { Badge(text: badge).fixedSize() }
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

  private var rating: String? { item.officialRating ?? fetched }

  var body: some View {
    Group {
      if let rating { Badge(text: rating).fixedSize() }
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
    .astraIconButton(size: size, variant: .regular)
    .sensoryFeedback(.success, trigger: on)
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

    @State private var position: Int?
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
      .scrollPosition(id: $position)
      .scrollIndicators(.never)
      .modifier(PageProgressReader(progress: $progress, position: position))
      .overlay(alignment: .bottom) {
        if items.count > 1 {
          // On the Mac a click on a dot moves there too (a mouse can't swipe).
          StretchDots(count: items.count, progress: progress) { i in
            withAnimation(.snappy(duration: 0.4)) { position = i }
          }
          .padding(.bottom, 6)
        }
      }
      .sensoryFeedback(.selection, trigger: position)
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
      .background {
        ZStack {
          ArtworkImage(
            library: library, item: item, kind: .heroBackdrop, width: 1920, height: 1080, placeholder: Color.clear
          )
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .clipped()
          HeroScrim()
        }
      }
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
        withAnimation(.snappy(duration: 0.3)) { progress = CGFloat(new ?? 0) }
      }
    }
  }
}
