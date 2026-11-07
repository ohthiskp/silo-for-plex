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
    .safeAreaInset(edge: .bottom, spacing: 0) {
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

/// The bottom bar: a wide Liquid Glass capsule nearly the screen's width,
/// three equal buttons with large icons and labels, and a glass pill behind
/// the open tab that slides between them.
struct WideTabBar: View {
  var selection: MainView.TabID
  /// Running and waiting downloads, shown on Libraries (where Downloads lives).
  var downloads = 0
  var select: (MainView.TabID) -> Void

  @Namespace private var pill

  private let items: [(MainView.TabID, String, String)] = [
    (.home, "Home", "house.fill"),
    (.search, "Search", "magnifyingglass"),
    (.libraries, "Libraries", "square.stack.fill"),
  ]

  var body: some View {
    HStack(spacing: 4) {
      ForEach(items, id: \.0) { item in
        let (id, title, symbol) = item
        let selected = id == selection
        Button {
          select(id)
        } label: {
          VStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 22, weight: .semibold))
              .overlay(alignment: .topTrailing) {
                if id == .libraries, downloads > 0 {
                  CountBadge(count: downloads).offset(x: 12, y: -8)
                }
              }
            Text(title).font(.system(size: 12, weight: .semibold))
          }
          .foregroundStyle(selected ? Astra.Color.ink : Astra.Color.muted)
          .frame(maxWidth: .infinity, minHeight: 58)
          .background {
            if selected {
              Capsule().fill(.white.opacity(0.16))
                .matchedGeometryEffect(id: "tab", in: pill)
            }
          }
          .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
      }
    }
    .padding(6)
    .astraGlass(in: Capsule(), interactive: true)
    .animation(.snappy(duration: 0.25), value: selection)
    .padding(.horizontal, 16)
    .padding(.bottom, 2)
  }
}
