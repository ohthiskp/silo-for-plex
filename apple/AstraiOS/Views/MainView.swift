import AstraKit
import SwiftUI

/// The signed-in iPhone app: three tabs only, Home, Search and Libraries
/// (KP's mockups, 2026-11-07), in Apple's tab bar (Liquid Glass on iOS 26),
/// one navigation stack per tab. Settings opens from Libraries' gear.
struct MainView: View {
  @Environment(AppModel.self) private var app
  var library: LibraryStore

  enum TabID: Hashable { case home, search, libraries }

  @State private var tab: TabID = {
    switch Demo.tab {
    case "search": .search
    case "libraries": .libraries
    default: .home
    }
  }()
  @State private var homePath: [Route] = Demo.openKey.flatMap(Demo.item).map { [.details($0)] } ?? []
  @State private var searchPath: [Route] = []
  @State private var librariesPath: [Route] = []

  var body: some View {
    // Astra (KP, 2026-11-07): Apple's floating tab bar was too narrow with
    // three tabs, so the system bar is hidden and a wide Liquid Glass bar
    // with large buttons (KP's mockup) sits at the bottom instead.
    TabView(selection: $tab) {
      Tab("Home", systemImage: "house.fill", value: TabID.home) {
        stack($homePath) { HomeView(library: library) }
          .toolbar(.hidden, for: .tabBar)
      }
      Tab("Search", systemImage: "magnifyingglass", value: TabID.search) {
        stack($searchPath) { PhoneSearchView(library: library) }
          .toolbar(.hidden, for: .tabBar)
      }
      Tab("Libraries", systemImage: "square.stack.fill", value: TabID.libraries) {
        stack($librariesPath) { LibrariesView(library: library) }
          .toolbar(.hidden, for: .tabBar)
      }
    }
    // Astra: an overlay, not a safe-area inset, so pages scroll underneath
    // and the glass shows them through it (KP: "why isn't it Liquid Glass").
    // Pages leave room at their bottom for it.
    .overlay(alignment: .bottom) {
      WideTabBar(selection: tab, downloads: app.downloads.jobs.count) { picked in
        if picked == tab {
          // Tapping the open tab again goes back to its first page.
          switch picked {
          case .home: homePath.removeAll()
          case .search: searchPath.removeAll()
          case .libraries: librariesPath.removeAll()
          }
        } else {
          tab = picked
        }
      }
    }
    .environment(\.playItem) { app.play($0) }
    .onAppear {
      // The title's chevron in the player opens its details in the current tab.
      app.player.openDetails = { item in
        switch tab {
        case .home: homePath.append(.details(item))
        case .search: searchPath.append(.details(item))
        case .libraries: librariesPath.append(.details(item))
        }
      }
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
/// three equal tabs. The open tab sits under a Liquid Glass lens that slides
/// between tabs; press and drag along the bar and the lens lifts and follows
/// the finger, then settles on the tab it is let go over (like Apple's own
/// tab bar on iOS 26).
struct WideTabBar: View {
  var selection: MainView.TabID
  /// Running and waiting downloads, shown on Libraries (where Downloads lives).
  var downloads = 0
  var select: (MainView.TabID) -> Void

  /// The finger's x while pressing the bar; nil when not touching.
  @State private var dragX: CGFloat?
  @State private var dragged = false

  private let items: [(MainView.TabID, String, String)] = [
    (.home, "Home", "house.fill"),
    (.search, "Search", "magnifyingglass"),
    (.libraries, "Libraries", "square.stack.fill"),
  ]
  private static let inset: CGFloat = 6
  private static let height: CGFloat = 58

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
          .animation(dragged ? .interactiveSpring(response: 0.25, dampingFraction: 0.8) : .snappy(duration: 0.32), value: lensX)
          .animation(.spring(response: 0.3, dampingFraction: 0.7), value: dragX != nil)

        HStack(spacing: 0) {
          ForEach(Array(items.enumerated()), id: \.offset) { i, item in
            let (id, title, symbol) = item
            let lit = dragged ? hovered == i : id == selection
            VStack(spacing: 4) {
              Image(systemName: symbol).font(.system(size: 22, weight: .semibold))
                .overlay(alignment: .topTrailing) {
                  if id == .libraries, downloads > 0 {
                    CountBadge(count: downloads).offset(x: 12, y: -8)
                  }
                }
              Text(title).font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(lit ? Astra.Color.ink : Astra.Color.muted)
            .scaleEffect(lit && dragX != nil ? 1.08 : 1)
            .frame(width: tabWidth, height: Self.height)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityAddTraits(id == selection ? [.isSelected, .isButton] : .isButton)
            .accessibilityAction { select(id) }
          }
        }
        .animation(.snappy(duration: 0.2), value: hovered)
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
    .padding(.horizontal, 16)
    .padding(.bottom, 2)
    // Stays at the bottom when the keyboard opens (Search).
    .ignoresSafeArea(.keyboard)
    .sensoryFeedback(.selection, trigger: selection)
  }

  private func index(at x: CGFloat, tabWidth: CGFloat) -> Int {
    min(max(Int((x - Self.inset) / max(tabWidth, 1)), 0), items.count - 1)
  }

  /// The bar itself: regular Liquid Glass.
  @ViewBuilder private var barGlass: some View {
    if #available(iOS 26.0, *) {
      Capsule().fill(.clear).glassEffect(.regular, in: Capsule())
    } else {
      Capsule().fill(.regularMaterial).overlay(Capsule().stroke(Astra.Color.hairline))
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
