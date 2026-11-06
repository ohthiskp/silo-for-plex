import AstraKit
import SwiftUI

/// The signed-in iPhone app: Apple's tab bar (Liquid Glass on iOS 26), one
/// navigation stack per tab, and Search as the separated search tab.
struct MainView: View {
  @Environment(AppModel.self) private var app
  var library: LibraryStore

  enum TabID: Hashable { case home, library, settings, search }

  @State private var tab: TabID = .home
  @State private var homePath: [Route] = []
  @State private var libraryPath: [Route] = []
  @State private var searchPath: [Route] = []

  var body: some View {
    TabView(selection: $tab) {
      Tab("Home", systemImage: "house.fill", value: TabID.home) {
        stack($homePath) { HomeView(library: library) }
      }
      Tab("Library", systemImage: "square.stack.fill", value: TabID.library) {
        stack($libraryPath) { LibrarySectionsView(library: library) }
      }
      Tab("Settings", systemImage: "gearshape.fill", value: TabID.settings) {
        NavigationStack { SettingsView().navigationTitle("Settings") }
      }
      Tab(value: TabID.search, role: .search) {
        stack($searchPath) { SearchView(library: library) }
      }
    }
    .modifier(MinimizingTabBar())
    .environment(\.playItem) { app.play($0) }
  }

  /// A navigation stack whose rows open details by pushing onto `path`.
  private func stack<Content: View>(_ path: Binding<[Route]>, @ViewBuilder root: () -> Content) -> some View {
    NavigationStack(path: path) {
      root()
        .toolbarBackground(.hidden, for: .navigationBar)
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

/// The tab bar tucks away while scrolling down on iOS 26.
private struct MinimizingTabBar: ViewModifier {
  func body(content: Content) -> some View {
    if #available(iOS 26.0, *) {
      content.tabBarMinimizationBehavior(.onScrollDown)
    } else {
      content
    }
  }
}

/// Movies, TV Shows… as glass-free rows; each opens its poster grid.
struct LibrarySectionsView: View {
  var library: LibraryStore

  var body: some View {
    List(library.sections) { section in
      NavigationLink {
        LibraryGridView(library: library, section: section)
      } label: {
        Label(section.title, systemImage: section.type == "show" ? "tv" : "film")
          .font(.system(size: 17, weight: .semibold))
      }
      .listRowBackground(Astra.Color.surface)
    }
    .scrollContentBackground(.hidden)
    .background(Astra.Color.bg)
    .navigationTitle("Library")
  }
}
