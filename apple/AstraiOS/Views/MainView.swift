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
    TabView(selection: $tab) {
      Tab("Home", systemImage: "house.fill", value: TabID.home) {
        stack($homePath) { HomeView(library: library) }
      }
      Tab("Search", systemImage: "magnifyingglass", value: TabID.search) {
        stack($searchPath) { PhoneSearchView(library: library) }
      }
      Tab("Libraries", systemImage: "square.stack.fill", value: TabID.libraries) {
        stack($librariesPath) { LibrariesView(library: library) }
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
