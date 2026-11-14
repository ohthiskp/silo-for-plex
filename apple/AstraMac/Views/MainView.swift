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
          page(for: item)
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
    .shadow(color: .black.opacity(0.55), radius: 30, x: -8)
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

/// The top bar from Apple TV, made for the pointer: the search icon, Home,
/// Movies, Shows and Watchlist centred on one glass capsule; Downloads and
/// Settings as round glass buttons at the far right. The open page is a
/// white pill. Astra (KP, 2026-11-07): no sliding pill; a click lights the
/// item at once.
struct MacTopBar: View {
  var selection: SidebarItem
  var choose: (SidebarItem) -> Void
  @Environment(AppModel.self) private var app

  var body: some View {
    ZStack {
      HStack(spacing: 2) {
        item(.search, iconOnly: true)
        item(.home)
        item(.movies)
        item(.shows)
        item(.watchlist, iconOnly: true)
      }
      .padding(4)
      .astraGlass(in: Capsule(), variant: .clear)
      .astraGlassEdge(Capsule(), strength: 0.6)

      HStack(spacing: 10) {
        Spacer()
        round(.downloads, count: app.downloads.jobs.count)
        round(.settings)
      }
      .padding(.trailing, Astra.Spacing.pageTrailing)
    }
    .frame(height: Astra.Sidebar.barHeight)
    // Selection changes light at once.
    .transaction(value: selection) { $0.animation = nil }
  }

  private func round(_ page: SidebarItem, count: Int = 0) -> some View {
    item(page, iconOnly: true, count: count)
      .padding(4)
      .astraGlass(in: Circle(), variant: .clear)
      .astraGlassEdge(Circle(), strength: 0.6)
  }

  private func item(_ page: SidebarItem, iconOnly: Bool = false, count: Int = 0) -> some View {
    MacBarButton(
      symbol: page.symbol, title: page.title, iconOnly: iconOnly, selected: selection == page, count: count
    ) { choose(page) }
    .keyboardShortcut(page.shortcut, modifiers: .command)
  }
}

/// One top-bar item: an icon and its name (or the icon alone for Search and
/// Settings). Its colour comes only from `selected`.
struct MacBarButton: View {
  var symbol: String
  var title: String
  var iconOnly = false
  var selected: Bool
  /// Astra (KP, 2026-11-07): Library shows how many downloads are running.
  var count = 0
  var action: () -> Void
  @State private var hovering = false

  private var height: CGFloat { Astra.Sidebar.barHeight - 8 }

  private var badge: some View {
    Text("\(count)")
      .font(.system(size: 10, weight: .bold))
      .monospacedDigit()
      .foregroundStyle(selected && !iconOnly ? Astra.Color.theme : Astra.Color.onAccent)
      .padding(.horizontal, 5)
      .frame(minWidth: 16, minHeight: 16)
      .background(Capsule().fill(selected && !iconOnly ? Astra.Color.onTheme : Astra.Color.accent))
      .astraTransition(.scale.combined(with: .opacity))
  }

  var body: some View {
    Button(action: action) {
      HStack(spacing: 7) {
        Image(systemName: symbol)
          .font(.system(size: 14, weight: .semibold))
        if !iconOnly {
          Text(title)
            .font(.system(size: 14, weight: .semibold))
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
      .foregroundStyle(selected ? Astra.Color.onTheme : (hovering ? Astra.Color.ink : Astra.Color.muted))
      .background {
        if selected {
          Capsule().fill(Astra.Color.theme)
        } else if hovering {
          Capsule().fill(.white.opacity(0.1))
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

/// No dimming on press (that read as a flicker); a slight scale instead.
private struct MacBarButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.94 : 1)
      .astraAnimation(.snappy(duration: 0.12), value: configuration.isPressed)
  }
}

// MARK: - Streaming services

/// For You and the streaming services as floating glass circles down the
/// left of Home, as on Apple TV (KP, 2026-11-12). Logos are white until
/// chosen; the chosen one shows its brand colour with a ring. Scrolls when
/// the window is too short for all of them.
struct MacServiceRail: View {
  var library: LibraryStore
  @AppStorage(Preferences.serviceLogoColorsKey) private var logoColors = true

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
    VStack(spacing: 10) {
      circle(nil)
      ForEach(StreamingService.all) { circle($0) }
    }
  }

  private func circle(_ service: StreamingService?) -> some View {
    let selected = library.selectedService == service
    let brand = logoColors ? (service.map { Color(hex: $0.accent) } ?? .white) : .white
    return MacServiceCircle(selected: selected, brand: brand, label: service?.label ?? "For You") {
      library.select(service)
    } content: {
      if let service {
        Image(service.logo)
          .renderingMode(.template)
          .resizable()
          .scaledToFit()
          .frame(width: Astra.Sidebar.collapsedWidth * 0.66, height: min(service.logoHeight * 0.7, 18))
          .foregroundStyle(selected ? brand : .white)
      } else {
        Image(systemName: "sparkles")
          .font(.system(size: 17, weight: .semibold))
          .foregroundStyle(.white)
      }
    }
  }
}

/// One streaming circle: clear glass over a dark tint, lighter under the
/// pointer, the chosen one ringed in its brand colour.
private struct MacServiceCircle<Content: View>: View {
  var selected: Bool
  var brand: Color
  var label: String
  var action: () -> Void
  @ViewBuilder var content: Content
  @State private var hovering = false

  var body: some View {
    let size = Astra.Sidebar.collapsedWidth
    Button(action: action) {
      content
        .frame(width: size, height: size)
        .background { Circle().fill(.black.opacity(hovering ? 0.15 : 0.3)) }
        .background { if hovering { Circle().fill(.white.opacity(0.18)) } }
        .astraGlass(in: Circle(), variant: .clear)
        .overlay { if selected { Circle().strokeBorder(brand, lineWidth: 2.5) } }
        .overlay { if !selected { Circle().strokeBorder(.white.opacity(0.14), lineWidth: 1) } }
        .contentShape(Circle())
        .scaleEffect(hovering ? 1.06 : 1)
        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
    }
    .buttonStyle(MacBarButtonStyle())
    .onHover { h in astraWithAnimation(.snappy(duration: 0.18)) { hovering = h } }
    .help(label)
    .accessibilityLabel(label)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}
