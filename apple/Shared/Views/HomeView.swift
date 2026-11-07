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
          HeroCarousel(library: library, items: library.homeHero, height: heroHeight)
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
          if library.hubs.isEmpty && library.continueWatching.isEmpty {
            EmptyState(
              symbol: "exclamationmark.triangle", title: "Home didn't load", message: error,
              action: ("Try Again", { Task { await library.loadHome() } }))
          } else {
            Text(error)
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
    .ignoresSafeArea(edges: .top)
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

  private var items: [PlexMetadata] { Array(library.homeTopTen.prefix(10)) }
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

/// One featured title at a time. The backdrop crossfades; the old title
/// fades out before the new one fades in, so two titles never overlap. The
/// next title's artwork is downloaded before the switch, so nothing blinks.
struct HeroCarousel: View {
  var library: LibraryStore
  var items: [PlexMetadata]
  var height: CGFloat

  @State private var index = 0
  /// Bumped by manual navigation so the next title is prefetched.
  @State private var interaction = 0
  @State private var switching = false

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.contentLeading) private var leading
  @Environment(\.isPageActive) private var isPageActive

  private static let titleTransition = AnyTransition.asymmetric(
    insertion: .opacity.animation(.easeOut(duration: 0.35).delay(0.3)),
    removal: .opacity.animation(.easeIn(duration: 0.2)))

  var body: some View {
    let item = items[min(index, items.count - 1)]
    // The text and pager are laid out in flow below the backdrop's top space,
    // so they can never spill onto the rows below. HeroInfo has a fixed
    // height for every title, so switching titles never resizes the hero.
    VStack(alignment: .leading, spacing: 22) {
      ZStack(alignment: .bottomLeading) {
        HeroInfo(library: library, item: item)
          .id(item.id)
          .transition(Self.titleTransition)
      }
      if items.count > 1 {
        HeroPager(count: items.count, index: index, previous: { step(-1) }, next: { step(1) })
      }
    }
    .padding(.leading, leading)
    .padding(.trailing, Astra.Spacing.pageTrailing)
    // Room above the text for the artwork and the streaming switcher.
    .padding(.top, 110)
    .padding(.bottom, 8)
    .frame(maxWidth: .infinity, minHeight: height, alignment: .bottomLeading)
    .background {
      ZStack {
        ZStack {
          ArtworkImage(
            library: library, item: item, kind: .heroBackdrop, width: 1920, height: 1080, placeholder: Color.clear
          )
          .id(item.id)
          .transition(.opacity.animation(.easeInOut(duration: reduceMotion ? 0.2 : 0.6)))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        HeroScrim()
      }
    }
    #if os(iOS)
      // Swipe the hero sideways to move between its titles.
      .simultaneousGesture(
        DragGesture(minimumDistance: 30).onEnded { drag in
          let dx = drag.translation.width
          guard abs(dx) > 50, abs(dx) > abs(drag.translation.height) * 1.5 else { return }
          step(dx < 0 ? 1 : -1)
        })
    #endif
    .task(id: "\(interaction)|\(isPageActive)") {
      // Behind another page (Movies, Shows…): no downloads, no switching.
      guard isPageActive else { return }
      // Astra (KP, 2026-11-07): a manual carousel; the hero only changes when
      // the user moves it. The next title's artwork is ready before then.
      await prefetch((index + 1) % max(items.count, 1))
    }
  }

  private func step(_ delta: Int) {
    guard items.count > 1, !switching else { return }
    let next = (index + delta + items.count) % items.count
    Task { @MainActor in
      await show(next)
      interaction += 1
    }
  }

  private func show(_ next: Int) async {
    guard next != index, !switching else { return }
    switching = true
    await prefetch(next)
    index = next
    switching = false
    await prefetch((next + 1) % items.count)
  }

  /// Downloads and decodes a title's backdrop and logo, so its switch-in is instant.
  private func prefetch(_ i: Int) async {
    guard items.indices.contains(i) else { return }
    let item = items[i]
    for kind in [LibraryStore.ArtKind.heroBackdrop, .logo] {
      if let url = await library.artworkURL(for: item, kind, width: 1920, height: 1080) {
        _ = await ImagePipeline.shared.image(for: url)
      }
    }
  }
}

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

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      // Fixed boxes for the title and summary: every title takes the same
      // height, so the buttons and pager never move when the hero switches.
      HeroTitle(library: library, item: item, maxHeight: Self.titleBox)
        .frame(height: Self.titleBox, alignment: .bottomLeading)
      MetaRow(item: item)
      Text(item.summary ?? "")
        .font(.system(size: 14.5))
        .lineSpacing(4)
        .foregroundStyle(Astra.Color.ink.opacity(0.82))
        .lineLimit(3)
        .frame(maxWidth: 560, alignment: .leading)
        .frame(height: 66, alignment: .topLeading)
      HStack(spacing: 14) {
        Button {
          playItem(item)
        } label: {
          Label(item.progress != nil ? "Resume" : "Play", systemImage: "play.fill")
        }
        .astraPrimaryButton()
        // On the service but not on the Plex server: nothing to play.
        .disabled(item.isCatalogOnly)
        .help(item.isCatalogOnly ? "Not on your Plex server" : "")
        Button {
          openItem(item)
        } label: {
          Label("Details", systemImage: "info.circle")
        }
        .astraSecondaryButton()
      }
      .astraGlassGroup(spacing: 14)
      .padding(.top, 6)
    }
  }
}

/// Previous and next buttons around the page dots.
struct HeroPager: View {
  var count: Int
  var index: Int
  var previous: () -> Void
  var next: () -> Void

  var body: some View {
    HStack(spacing: Astra.Spacing.m) {
      Button(action: previous) { Image(systemName: "chevron.left") }
        .astraIconButton(size: 32)
        .accessibilityLabel("Previous Title")
      PageDots(count: count, index: index)
      Button(action: next) { Image(systemName: "chevron.right") }
        .astraIconButton(size: 32)
        .accessibilityLabel("Next Title")
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
      // No age or star ratings for now (KP, 2026-11-06); only the version this
      // device would play, never a claim about HDR.
      if let badge = item.resolutionBadge(for: quality == .auto ? .current() : quality) { Badge(text: badge).fixedSize() }
    }
  }
}

struct PageDots: View {
  var count: Int
  var index: Int

  var body: some View {
    HStack(spacing: 7) {
      ForEach(0..<count, id: \.self) { i in
        Circle()
          .fill(Color.white.opacity(i == index ? 1 : 0.35))
          .frame(width: 6, height: 6)
      }
    }
    .animation(Astra.Motion.base, value: index)
  }
}

extension String {
  var nilIfEmpty: String? { isEmpty ? nil : self }
}
