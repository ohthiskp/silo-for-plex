import AstraKit
import SwiftUI

/// The signed-in iPhone app: Apple's tab bar (Liquid Glass on iOS 26), one
/// navigation stack per tab, and Search as the separated search tab.
struct MainView: View {
  @Environment(AppModel.self) private var app
  var library: LibraryStore

  // Same destinations as the Mac sidebar. Settings opens from Home's gear
  // button, which keeps the tab bar to its five-tab limit.
  enum TabID: Hashable { case home, movies, shows, downloads, search }

  @State private var tab: TabID = .home
  @State private var homePath: [Route] = []
  @State private var moviesPath: [Route] = []
  @State private var showsPath: [Route] = []
  @State private var searchPath: [Route] = []
  @State private var downloadsPath: [Route] = []

  var body: some View {
    TabView(selection: $tab) {
      Tab("Home", systemImage: "house.fill", value: TabID.home) {
        stack($homePath) { HomeView(library: library) }
      }
      Tab("Movies", systemImage: "film", value: TabID.movies) {
        stack($moviesPath) {
          LibraryGridView(library: library, title: "Movies", sections: library.sections.filter { $0.type == "movie" })
        }
      }
      Tab("Shows", systemImage: "tv", value: TabID.shows) {
        stack($showsPath) {
          LibraryGridView(library: library, title: "Shows", sections: library.sections.filter { $0.type == "show" })
        }
      }
      Tab("Downloads", systemImage: "arrow.down.circle", value: TabID.downloads) {
        stack($downloadsPath) { DownloadsView() }
      }
      Tab(value: TabID.search, role: .search) {
        stack($searchPath) { SearchView(library: library) }
      }
    }
    .environment(\.playItem) { app.play($0) }
    .onAppear {
      // The title's chevron in the player opens its details in the current tab.
      app.player.openDetails = { item in
        switch tab {
        case .home: homePath.append(.details(item))
        case .movies: moviesPath.append(.details(item))
        case .shows: showsPath.append(.details(item))
        case .downloads: downloadsPath.append(.details(item))
        case .search: searchPath.append(.details(item))
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
    .environment(\.openItem) { item in app.resolve(item) { path.wrappedValue.append(.details($0)) } }
  }
}
