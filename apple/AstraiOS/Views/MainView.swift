import AstraKit
import SwiftUI

/// The signed-in iPhone app: Home, Search and Library by default (KP's
/// mockups, 2026-11-07), reorderable and extendable to five tabs in
/// Settings → Navigation (KP, 2026-11-08), in Astra's own Liquid Glass bar,
/// one navigation stack per tab. Settings opens from Library's gear, or is a tab.
struct MainView: View {
  @Environment(AppModel.self) private var app
  var library: LibraryStore

  typealias TabID = PhoneTab

  /// Settings → Navigation (Astra 4.0): which tabs the bar shows.
  @AppStorage(TabLayout.storageKey) private var storedTabs = ""
  @State private var tab: TabID = Demo.tab.flatMap(PhoneTab.init(rawValue:)) ?? .home
  @State private var paths: [TabID: [Route]] = [
    .home: Demo.openKey.flatMap(Demo.item).map { [.details($0)] } ?? []
  ]

  private var tabs: [TabID] { TabLayout.tabs(from: storedTabs) }

  private func path(_ id: TabID) -> Binding<[Route]> {
    Binding(get: { paths[id] ?? [] }, set: { paths[id] = $0 })
  }

  var body: some View {
    // Astra (KP, 2026-11-07): Apple's floating tab bar was too narrow with
    // three tabs, so the system bar is hidden and a wide Liquid Glass bar
    // with large buttons (KP's mockup) sits at the bottom instead.
    TabView(selection: $tab) {
      ForEach(tabs) { id in
        Tab(id.title, systemImage: id.symbol, value: id) {
          stack(path(id)) { page(id) }
            .toolbar(.hidden, for: .tabBar)
        }
      }
    }
    // Astra: an overlay, not a safe-area inset, so pages scroll underneath
    // and the glass shows them through it (KP: "why isn't it Liquid Glass").
    // Pages leave room at their bottom for it.
    .overlay(alignment: .bottom) {
      WideTabBar(tabs: tabs, selection: tab, downloads: app.downloads.jobs.count) { picked in
        // Astra (KP, 2026-11-07): tapping Home always lands on For You.
        if picked == .home, library.selectedService != nil { library.select(nil) }
        if picked == tab {
          // Tapping the open tab again goes back to its first page.
          paths[picked] = []
        } else {
          tab = picked
        }
      }
    }
    // A tab turned off in Settings while open: back to Home.
    .onChange(of: storedTabs) { if !tabs.contains(tab) { tab = .home } }
    .environment(\.playItem) { app.play($0) }
    .environment(\.ambient, AmbientSource(library: library, item: library.homeHero.first))
    .onAppear {
      if !tabs.contains(tab) { tab = .home }
      // The title's chevron in the player opens its details in the current tab.
      app.player.openDetails = { item in
        paths[tab, default: []].append(.details(item))
      }
    }
  }

  @ViewBuilder private func page(_ id: TabID) -> some View {
    switch id {
    case .home: HomeView(library: library)
    case .search: PhoneSearchView(library: library)
    case .libraries: LibrariesView(library: library)
    case .downloads: DownloadsView()
    case .settings: SettingsView(showsTitle: true)
    case .watchlist:
      AstraPage {
        AstraSectionHeader(title: "Watchlist")
        WatchlistContent(library: library)
      }
      .refreshable { await app.refreshWatchlist(force: true) }
    }
  }

  /// A navigation stack whose rows open details by pushing onto `path`.
  private func stack<Content: View>(_ path: Binding<[Route]>, @ViewBuilder root: () -> Content) -> some View {
    NavigationStack(path: path) {
      root()
        // Top-level pages draw their own Didot titles; pushed details keep the system back button.
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: Route.self) { route in
          switch route {
          case .details(let item):
            DetailView(library: library, seed: item, path: path)
          }
        }
    }
    .environment(\.openItem) { item in path.wrappedValue.append(.details(item)) }
  }
}

/// The bottom bar: a wide Liquid Glass capsule nearly the screen's width with
/// equal tabs (three to five). The open tab sits under a Liquid Glass lens that slides
/// between tabs; press and drag along the bar and the lens lifts and follows
/// the finger, then settles on the tab it is let go over (like Apple's own
/// tab bar on iOS 26).
struct WideTabBar: View {
  var tabs: [MainView.TabID] = TabLayout.defaultTabs
  var selection: MainView.TabID
  /// Running and waiting downloads, shown on Libraries (where Downloads lives).
  var downloads = 0
  var select: (MainView.TabID) -> Void

  /// The finger's x while pressing the bar; nil when not touching.
  @State private var dragX: CGFloat?
  @State private var dragged = false

  private var items: [(MainView.TabID, String, String)] { tabs.map { ($0, $0.title, $0.symbol) } }
  private static let inset: CGFloat = 5
  private static let height: CGFloat = 52

  var body: some View {
    GeometryReader { geo in
      let inner = geo.size.width - Self.inset * 2
      let tabWidth = inner / CGFloat(items.count)
      let selectedIndex = items.firstIndex { $0.0 == selection } ?? 0
      // Under the finger while dragging, else on the open tab.
      let lensX: CGFloat = {
        if let dragX, dragged { return min(max(dragX - Self.inset - tabWidth / 2, 0), inner - tabWidth) }
        return CGFloat(selectedIndex) * tabWidth
      }()
      let hovered = dragX.map { index(at: $0, tabWidth: tabWidth) }

      ZStack(alignment: .leading) {
        lens
          .frame(width: tabWidth, height: Self.height)
          .scaleEffect(dragX != nil ? 1.12 : 1)
          .offset(x: lensX)
          .astraAnimation(dragged ? .interactiveSpring(response: 0.25, dampingFraction: 0.8) : .snappy(duration: 0.32), value: lensX)
          .astraAnimation(.spring(response: 0.3, dampingFraction: 0.7), value: dragX != nil)

        HStack(spacing: 0) {
          ForEach(Array(items.enumerated()), id: \.offset) { i, item in
            let (id, title, symbol) = item
            let lit = dragged ? hovered == i : id == selection
            VStack(spacing: 4) {
              Image(systemName: symbol).font(.system(size: 20, weight: .semibold))
                .overlay(alignment: .topTrailing) {
                  // On Downloads when it is a tab, else on Library (where Downloads lives).
                  if downloads > 0, id == (tabs.contains(.downloads) ? .downloads : .libraries) {
                    CountBadge(count: downloads).offset(x: 12, y: -8)
                  }
                }
              Text(title).font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(lit ? Astra.Color.theme : Astra.Color.muted)
            .scaleEffect(lit && dragX != nil ? 1.08 : 1)
            .frame(width: tabWidth, height: Self.height)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityAddTraits(id == selection ? [.isSelected, .isButton] : .isButton)
            .accessibilityAction { select(id) }
          }
        }
        .astraAnimation(.snappy(duration: 0.2), value: hovered)
      }
      .padding(Self.inset)
      .frame(width: geo.size.width, height: Self.height + Self.inset * 2)
      .background { barGlass }
      .contentShape(Capsule())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { drag in
            if dragX == nil { dragged = false }
            dragX = drag.location.x
            if abs(drag.translation.width) > 8 { dragged = true }
          }
          .onEnded { drag in
            let i = index(at: drag.location.x, tabWidth: tabWidth)
            dragX = nil
            dragged = false
            select(items[i].0)
          })
    }
    .frame(height: Self.height + Self.inset * 2)
    .padding(.horizontal, 22)
    .padding(.bottom, 2)
    // Stays at the bottom when the keyboard opens (Search).
    .ignoresSafeArea(.keyboard)
    .sensoryFeedback(.selection, trigger: selection)
  }

  private func index(at x: CGFloat, tabWidth: CGFloat) -> Int {
    min(max(Int((x - Self.inset) / max(tabWidth, 1)), 0), items.count - 1)
  }

  /// The bar itself: regular Liquid Glass, tinted a little darker (KP, 2026-11-07).
  @ViewBuilder private var barGlass: some View {
    if #available(iOS 26.0, *) {
      Capsule().fill(.clear).glassEffect(.regular.tint(.black.opacity(0.35)), in: Capsule())
    } else {
      Capsule().fill(.regularMaterial).overlay(Capsule().fill(.black.opacity(0.3))).overlay(Capsule().stroke(Astra.Color.hairline))
    }
  }

  /// The selection lens: interactive clear glass that shimmers as it moves.
  @ViewBuilder private var lens: some View {
    if #available(iOS 26.0, *) {
      Capsule().fill(.white.opacity(0.08)).glassEffect(.clear.interactive(), in: Capsule())
    } else {
      Capsule().fill(.white.opacity(0.16))
    }
  }
}
