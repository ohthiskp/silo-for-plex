import AstraKit
import SwiftUI

/// The Mac's pages, in the top bar like Apple TV (KP, 2026-11-13): the search
/// icon, then Home, Movies, Shows and Watchlist centred; Downloads and
/// Settings as round buttons at the far right.
enum SidebarItem: String, CaseIterable, Hashable, Identifiable {
  case home, movies, shows, watchlist, search, downloads, settings

  var id: String { rawValue }

  var title: String {
    switch self {
    case .home: "Home"
    case .movies: "Movies"
    case .shows: "Shows"
    case .watchlist: "Watchlist"
    case .search: "Search"
    case .downloads: "Downloads"
    case .settings: "Settings"
    }
  }

  var symbol: String {
    switch self {
    case .home: "house.fill"
    case .movies: "film.fill"
    case .shows: "tv.fill"
    case .watchlist: "bookmark.fill"
    case .search: "magnifyingglass"
    case .downloads: "arrow.down.circle.fill"
    case .settings: "gearshape.fill"
    }
  }

  /// ⌘1 to ⌘7, in the order above.
  var shortcut: KeyEquivalent { KeyEquivalent(Character(String((Self.allCases.firstIndex(of: self) ?? 0) + 1))) }

  /// `-AstraDemoTab` for the CI screenshots.
  static var demo: SidebarItem {
    switch Demo.tab {
    case "libraries", "library", "movies": .movies
    case let tab?: SidebarItem(rawValue: tab) ?? .home
    case nil: .home
    }
  }
}

/// The signed-in app, laid out like Apple TV (KP, 2026-11-12): the main tabs
/// in a glass bar along the top, the streaming services as circles down the
/// left of Home, and details as stacked cards under the bar.
struct MainView: View {
  @Environment(AppModel.self) private var app
  var library: LibraryStore

  @State private var selection: SidebarItem = SidebarItem.demo
  /// Pages stay alive once opened, so switching back is instant: no reload,
  /// no re-decoding artwork, scroll position kept.
  /// Home is always laid out first: the window takes its size from Home, as at a normal launch.
  @State private var opened: [SidebarItem] = SidebarItem.demo == .home ? [.home] : [.home, SidebarItem.demo]
  @State private var path: [Route] = Demo.openKey.flatMap(Demo.item).map { [.details($0)] } ?? []
  /// The window's own top inset (the hidden title bar); pages leave room for the bar below it.
  @State private var safeTop: CGFloat = 28
  /// The window's size, and the size hidden pages keep: a page that isn't
  /// showing doesn't lay itself out again on every frame of a window resize
  /// (the main cause of the Mac's glitchy resizing, KP 2026-11-16). It takes
  /// the window's size again when it's opened.
  @State private var windowSize: CGSize = .zero
  @State private var hiddenSize: CGSize = .zero

  /// How far below the safe area pages and cards start, so they clear the bar.
  private var barClearance: CGFloat {
    max(0, Astra.Sidebar.barTop + Astra.Sidebar.barHeight + 14 - safeTop)
  }

  var body: some View {
    // The window sets the size; a page or card that asks for more width
    // can't grow the window or push the bar off screen (it runs off the right edge instead).
    GeometryReader { window in
      layers.frame(width: window.size.width, height: window.size.height)
    }
    .onGeometryChange(for: CGFloat.self, of: { $0.safeAreaInsets.top }) { safeTop = $0 }
    .onGeometryChange(for: CGSize.self, of: { $0.size }) { size in
      windowSize = size
      if hiddenSize == .zero { hiddenSize = size }
    }
    .onChange(of: selection) { hiddenSize = windowSize }
    .background(Astra.Color.bg.ignoresSafeArea())
    .environment(\.ambient, AmbientSource(library: library, item: library.homeHero.first))
    .environment(\.openItem) { item in
      // A TMDB-only title opens too; its page finds it on the server or greys out Play.
      astraWithAnimation(Self.cardMotion) { path.append(.details(item)) }
    }
    .environment(\.playItem) { app.play($0) }
  }

  private var layers: some View {
    ZStack(alignment: .top) {
      ZStack(alignment: .leading) {
        ForEach(opened) { item in
          let current = item == selection
          let frozen = current || hiddenSize == .zero ? nil : hiddenSize
          // The clear box takes the window's size; a hidden page inside it
          // keeps its own, without pushing anything else around.
          Color.clear.overlay(alignment: .topLeading) {
            page(for: item)
              .frame(width: frozen?.width, height: frozen?.height, alignment: .topLeading)
          }
            // Behind cards or another page: timers and the hero pause.
            .environment(\.isPageActive, current && path.isEmpty)
            .environment(\.contentLeading, item == .home ? Astra.Sidebar.contentInset : Astra.Sidebar.pageInset)
            .opacity(current ? 1 : 0)
            .allowsHitTesting(current && path.isEmpty)
            .accessibilityHidden(!current || !path.isEmpty)
        }

        if selection == .home, library.tmdb != nil {
          // As on Apple TV: For You and each service down the left of Home.
          MacServiceRail(library: library)
            .padding(.leading, Astra.Sidebar.margin)
            .allowsHitTesting(path.isEmpty)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

      // Apple TV's soft shade behind the bar, so the art never reads as part of it.
      MacTopShade()
        .frame(height: Astra.Sidebar.barTop + Astra.Sidebar.barHeight + 46)
        .ignoresSafeArea(edges: .top)

      cards
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

      MacTopBar(selection: selection) { item in
        if !opened.contains(item) { opened.append(item) }
        // Instant: the page and the bar both switch without animation.
        selection = item
        astraWithAnimation(Self.cardMotion) { path.removeAll() }
        // Astra (KP, 2026-11-07): clicking Home always goes back to For You.
        if item == .home, library.selectedService != nil { library.select(nil) }
      }
      .padding(.top, Astra.Sidebar.barTop)
      .ignoresSafeArea(edges: .top)
    }
  }

  static let cardMotion = Animation.spring(response: 0.42, dampingFraction: 0.9)
  /// Each card further up the stack starts this much further right, so the
  /// edges of the ones below show.
  private static let cardStep: CGFloat = 26

  /// Details open as cards sliding in from the right over the page, under
  /// the top bar. Opening another title from
  /// a card stacks a new card on top; X (or Esc, or a click on the dimmed
  /// page) closes the top one.
  private var cards: some View {
    ZStack(alignment: .leading) {
      if !path.isEmpty {
        Color.black.opacity(0.45)
          .ignoresSafeArea()
          .contentShape(Rectangle())
          .onTapGesture { closeTopCard() }
          .transition(.opacity)
      }
      // Keyed by position and title, so a new card never reuses a closing one's state.
      ForEach(Array(path.enumerated()), id: \.offset) { depth, route in
        let isTop = depth == path.count - 1
        card(for: route)
          .id("\(depth)|\(route.hashValue)")
          // Only the top card answers Return (Play) and Esc (Close).
          .environment(\.isPageActive, isTop)
          .padding(.leading, 14 + CGFloat(depth) * Self.cardStep)
          .padding(.trailing, 14)
          .padding(.top, barClearance)
          .padding(.bottom, 14)
          // Cards under the top one sink back a little.
          .scaleEffect(isTop ? 1 : 0.985, anchor: .leading)
          .brightness(isTop ? 0 : -0.12)
          .allowsHitTesting(isTop)
          .accessibilityHidden(!isTop)
          .astraTransition(.move(edge: .trailing))
          .zIndex(Double(depth))
      }
    }
  }

  private func card(for route: Route) -> some View {
    let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
    return Group {
      switch route {
      case .details(let item):
        DetailView(library: library, seed: item, path: $path)
      }
    }
    .environment(\.contentLeading, 40)
    .environment(\.closeCard) { closeTopCard() }
    .background(Astra.Color.bg)
    .clipShape(shape)
    .astraGlassEdge(shape, strength: 0.7)
    // The card's shadow is a plain gradient strip beside its left edge. A
    // .shadow on the whole card made the Mac blur a window-sized image on
    // every frame of the slide (KP 2026-11-17: "glitches every time i open
    // a new thing").
    .background(alignment: .leading) {
      LinearGradient(colors: [.clear, .black.opacity(0.5)], startPoint: .leading, endPoint: .trailing)
        .frame(width: 40)
        .offset(x: -40)
        .allowsHitTesting(false)
    }
  }

  private func closeTopCard() {
    guard !path.isEmpty else { return }
    astraWithAnimation(Self.cardMotion) { _ = path.removeLast() }
  }

  @ViewBuilder private func page(for item: SidebarItem) -> some View {
    switch item {
    case .home:
      HomeView(library: library)
    case .movies, .shows:
      AstraPage {
        LibraryGridContent(library: library, kind: item == .movies ? "movie" : "show", title: item.title)
      }
      .safeAreaPadding(.top, barClearance)
    case .watchlist:
      AstraPage {
        AstraSectionHeader(title: "Watchlist")
        WatchlistContent(library: library)
      }
      .safeAreaPadding(.top, barClearance)
    case .downloads:
      AstraPage {
        AstraSectionHeader(title: "Downloads")
        DownloadsContent()
      }
      .safeAreaPadding(.top, barClearance)
    case .search:
      SearchView(library: library).safeAreaPadding(.top, barClearance)
    case .settings:
      SettingsPage().safeAreaPadding(.top, barClearance)
    }
  }
}

// MARK: - Top bar

/// The top bar as on Apple TV (KP, 2026-11-16): no glass capsule around the
/// tabs, just the search icon, then Home, Movies, Shows and Watchlist as
/// plain items centred, the open one on a quiet glass pill. Downloads and
/// Settings stay round at the far right. No sliding pill: a click lights the
/// item at once.
struct MacTopBar: View {
  var selection: SidebarItem
  var choose: (SidebarItem) -> Void
  @Environment(AppModel.self) private var app

  var body: some View {
    ZStack {
      HStack(spacing: 4) {
        item(.search, iconOnly: true)
        item(.home)
        item(.movies)
        item(.shows)
        item(.watchlist)
      }

      HStack(spacing: 10) {
        Spacer()
        round(.downloads, count: app.downloads.jobs.count)
        round(.settings)
      }
      .padding(.trailing, Astra.Spacing.pageTrailing)
    }
    .frame(height: Astra.Sidebar.barHeight)
    // White type and dark glass over the artwork, on every theme.
    .astraOnArt()
    // Selection changes light at once.
    .transaction(value: selection) { $0.animation = nil }
  }

  /// Downloads and Settings: round glass, as the TV's Settings circle.
  private func round(_ page: SidebarItem, count: Int = 0) -> some View {
    item(page, iconOnly: true, count: count)
      .padding(3)
      .background { if selection != page { Circle().fill(.white.opacity(0.08)) } }
      .astraGlass(in: Circle(), variant: .clear)
  }

  private func item(_ page: SidebarItem, iconOnly: Bool = false, count: Int = 0) -> some View {
    MacBarButton(
      symbol: page.symbol, title: page.title, iconOnly: iconOnly, selected: selection == page, count: count
    ) { choose(page) }
    .keyboardShortcut(page.shortcut, modifiers: .command)
  }
}

/// One top-bar item: an icon and its name (or the icon alone for Search,
/// Downloads and Settings). The open page sits on a quiet glass pill, as on
/// Apple TV; the pointer brightens the others.
struct MacBarButton: View {
  var symbol: String
  var title: String
  var iconOnly = false
  var selected: Bool
  /// Astra (KP, 2026-11-07): Downloads shows how many are running.
  var count = 0
  var action: () -> Void
  @State private var hovering = false

  private var height: CGFloat { Astra.Sidebar.barHeight - 6 }

  private var badge: some View {
    Text("\(count)")
      .font(.system(size: 10, weight: .bold))
      .monospacedDigit()
      .foregroundStyle(Astra.Color.onAccent)
      .padding(.horizontal, 5)
      .frame(minWidth: 16, minHeight: 16)
      .background(Capsule().fill(Astra.Color.accent))
      .astraTransition(.scale.combined(with: .opacity))
  }

  var body: some View {
    Button(action: action) {
      HStack(spacing: 7) {
        Image(systemName: symbol)
          .font(.system(size: 14, weight: .semibold))
        if !iconOnly {
          Text(title)
            .font(.system(size: 15, weight: .semibold))
            .lineLimit(1)
            .fixedSize()
        }
        if count > 0, !iconOnly { badge }
      }
      .padding(.horizontal, iconOnly ? 0 : 16)
      .frame(width: iconOnly ? height : nil, height: height)
      // Downloads: how many are running, on the round button's corner.
      .overlay(alignment: .topTrailing) {
        if count > 0, iconOnly { badge.offset(x: 4, y: -4) }
      }
      // As on Apple TV (KP, 2026-11-16): the open page is a white pill with
      // black type; the others plain white text, a soft glass pill under the pointer.
      .foregroundStyle(selected ? Color.black : .white.opacity(hovering ? 1 : 0.75))
      .shadow(color: .black.opacity(selected ? 0 : 0.35), radius: 6, y: 1)
      .background {
        if selected {
          Capsule().fill(.white).shadow(color: .black.opacity(0.3), radius: 10, y: 4)
        } else if hovering {
          Capsule().fill(.white.opacity(0.1)).astraGlass(in: Capsule(), variant: .clear)
        }
      }
      .contentShape(Capsule())
    }
    .buttonStyle(MacBarButtonStyle())
    .onHover { hovering = $0 }
    .help(title)
    .accessibilityLabel(count > 0 ? "\(title), \(count)" : title)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}

/// The soft shade along the top of the window, under the bar, so its plain
/// items read over bright artwork (Apple TV's top shade), with a light blur
/// for rows that scroll under it. Fixed: it never redraws with the page.
struct MacTopShade: View {
  var body: some View {
    ZStack {
      Rectangle().fill(.ultraThinMaterial)
      LinearGradient(colors: [.black.opacity(0.5), .black.opacity(0)], startPoint: .top, endPoint: .bottom)
    }
    .mask {
      LinearGradient(
        stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.35), .init(color: .clear, location: 1)],
        startPoint: .top, endPoint: .bottom)
    }
    .environment(\.colorScheme, .dark)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}

/// No dimming on press (that read as a flicker); a slight scale instead.
private struct MacBarButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.94 : 1)
      .astraAnimation(.snappy(duration: 0.12), value: configuration.isPressed)
  }
}

// MARK: - Streaming services

/// Home and the streaming services down the left of Home, as on Apple TV
/// (KP, 2026-11-12). Since 2026-11-25 (KP's option E) they're bare logos,
/// white and dimmed. One white bar sits on the logo under the pointer (or the
/// chosen one when the pointer is away) and glides between them; only the
/// logo under the bar is lit and in its brand colour. Scrolls when the window
/// is too short for all of them.
struct MacServiceRail: View {
  var library: LibraryStore
  @AppStorage(Preferences.serviceLogoColorsKey) private var logoColors = true
  @Namespace private var barSpace
  /// The logo under the pointer. Cleared only when the pointer leaves the
  /// whole rail, so the bar doesn't snap back while crossing the gaps.
  @State private var hovered: String?

  private static let home = "home"
  private var barAt: String { hovered ?? library.selectedService?.id ?? Self.home }

  var body: some View {
    ViewThatFits(in: .vertical) {
      circles
      ScrollView(.vertical) { circles.padding(.vertical, 8) }
        .scrollIndicators(.never)
        .frame(width: Astra.Sidebar.collapsedWidth + 16)
    }
    .frame(maxHeight: .infinity, alignment: .center)
    .padding(.top, Astra.Sidebar.barTop + Astra.Sidebar.barHeight)
  }

  private var circles: some View {
    VStack(spacing: 6) {
      circle(nil)
      ForEach(StreamingService.all) { circle($0) }
    }
    .onHover { inside in if !inside { hovered = nil } }
    // The white bar glides from logo to logo (KP, 2026-11-25).
    .astraAnimation(.smooth(duration: 0.32), value: barAt)
  }

  private func circle(_ service: StreamingService?) -> some View {
    let id = service?.id ?? Self.home
    let lit = barAt == id
    let brand = logoColors ? (service.map { Color(hex: $0.accent) } ?? .white) : .white
    return MacServiceCircle(
      selected: library.selectedService == service, lit: lit, barSpace: barSpace,
      label: service?.label ?? "Home, all services"
    ) {
      library.select(service)
    } hover: {
      hovered = id
    } content: {
      if let service {
        Image(service.logo)
          .renderingMode(.template)
          .resizable()
          .scaledToFit()
          .frame(width: Astra.Sidebar.collapsedWidth * 0.8, height: min(service.logoHeight * 0.8, 20))
          // White until the bar is on it; then its brand colour (KP).
          .foregroundStyle(lit ? brand : .white)
      } else {
        Image(systemName: "house.fill")
          .font(.system(size: 19, weight: .semibold))
          .foregroundStyle(.white)
      }
    }
  }
}

/// One streaming logo (KP's option E): no circle or glass. Dimmed unless the
/// rail's white bar is on it.
private struct MacServiceCircle<Content: View>: View {
  var selected: Bool
  var lit: Bool
  var barSpace: Namespace.ID
  var label: String
  var action: () -> Void
  var hover: () -> Void
  @ViewBuilder var content: Content

  var body: some View {
    let size = Astra.Sidebar.collapsedWidth
    Button(action: action) {
      content
        .frame(width: size, height: size * 0.86)
        .opacity(lit ? 1 : 0.5)
        .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
        .overlay(alignment: .leading) {
          if lit {
            Capsule().fill(.white)
              .frame(width: 4, height: size * 0.5)
              .shadow(color: .white.opacity(0.55), radius: 5)
              .matchedGeometryEffect(id: "rail-bar", in: barSpace)
              .offset(x: -12)
          }
        }
        .contentShape(Rectangle())
    }
    .buttonStyle(MacBarButtonStyle())
    .onHover { if $0 { hover() } }
    .help(label)
    .accessibilityLabel(label)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}
