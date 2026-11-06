import AstraKit
import SwiftUI

/// The sidebar destinations, in order.
enum SidebarItem: String, CaseIterable, Hashable, Identifiable {
  case home, movies, shows, downloads, search, settings

  var id: String { rawValue }

  var title: String {
    switch self {
    case .home: "Home"
    case .movies: "Movies"
    case .shows: "Shows"
    case .downloads: "Downloads"
    case .search: "Search"
    case .settings: "Settings"
    }
  }

  var symbol: String {
    switch self {
    case .home: "house.fill"
    case .movies: "film"
    case .shows: "tv"
    case .downloads: "arrow.down.circle"
    case .search: "magnifyingglass"
    case .settings: "gearshape.fill"
    }
  }

  /// ⌘1 to ⌘6.
  var shortcut: KeyEquivalent { KeyEquivalent(Character(String((Self.allCases.firstIndex(of: self) ?? 0) + 1))) }
}

/// The signed-in app: a docked glass sidebar and a navigation stack.
struct MainView: View {
  @Environment(AppModel.self) private var app
  var library: LibraryStore

  @State private var selection: SidebarItem = .home
  /// Pages stay alive once opened, so switching back is instant: no reload,
  /// no re-decoding artwork, scroll position kept.
  @State private var opened: [SidebarItem] = [.home]
  @State private var path: [Route] = []

  var body: some View {
    ZStack(alignment: .leading) {
      NavigationStack(path: $path) {
        ZStack {
          ForEach(opened) { item in
            let current = item == selection
            page(for: item)
              .opacity(current ? 1 : 0)
              .allowsHitTesting(current)
              .accessibilityHidden(!current)
          }
        }
        .navigationDestination(for: Route.self) { route in
          switch route {
          case .details(let item):
            DetailView(library: library, seed: item, path: $path)
          }
        }
      }
      .environment(\.contentLeading, Astra.Sidebar.contentInset)

      Sidebar(selection: $selection) { item in
        if !opened.contains(item) { opened.append(item) }
        // Instant: the page swaps without animation; only the sidebar's pill slides.
        selection = item
        path.removeAll()
      }
      .padding(.leading, Astra.Sidebar.margin)
    }
    .background(Astra.Color.bg.ignoresSafeArea())
    .environment(\.openItem) { item in
      app.resolve(item) { path.append(.details($0)) }
    }
    .environment(\.playItem) { app.play($0) }
  }

  @ViewBuilder private func page(for item: SidebarItem) -> some View {
    switch item {
    case .home:
      HomeView(library: library)
    case .movies:
      LibraryGridView(library: library, title: "Movies", sections: library.sections.filter { $0.type == "movie" })
    case .shows:
      LibraryGridView(library: library, title: "Shows", sections: library.sections.filter { $0.type == "show" })
    case .downloads:
      DownloadsView()
    case .search:
      SearchView(library: library)
    case .settings:
      SettingsPage()
    }
  }
}

// MARK: - Sidebar

/// Icon-only Liquid Glass sidebar.
struct Sidebar: View {
  @Binding var selection: SidebarItem
  var choose: (SidebarItem) -> Void
  @Namespace private var selectionSpace

  var body: some View {
    VStack(spacing: Astra.Spacing.xs) {
      ForEach(SidebarItem.allCases) { item in
        SidebarButton(symbol: item.symbol, title: item.title, selected: selection == item, namespace: selectionSpace) {
          choose(item)
        }
        .keyboardShortcut(item.shortcut, modifiers: .command)
      }
    }
    // Only the white selection pill moves, quickly.
    .animation(.snappy(duration: 0.22), value: selection)
    .padding(9)
    .frame(width: Astra.Sidebar.collapsedWidth)
    .astraGlass(in: Capsule())
    .frame(maxHeight: .infinity)
  }
}

/// One sidebar button: a 44 pt icon with a tooltip.
struct SidebarButton: View {
  var symbol: String
  var title: String
  var selected: Bool
  var namespace: Namespace.ID
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 17, weight: .semibold))
        .frame(width: 44, height: 44)
      .foregroundStyle(selected ? Color.black : Astra.Color.muted)
      .background {
        // A white fill, not glass: it sits on the sidebar's glass. It slides
        // from the old item to the new one instead of blinking.
        if selected {
          Capsule().fill(Astra.Color.accent)
            .matchedGeometryEffect(id: "selection", in: namespace)
        }
      }
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .help(title)
    .accessibilityLabel(title)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}
