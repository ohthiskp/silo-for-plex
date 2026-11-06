import AstraKit
import SwiftUI

/// The six sidebar destinations, in order.
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
  @State private var expanded = false
  @State private var path: [Route] = []
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    ZStack(alignment: .leading) {
      NavigationStack(path: $path) {
        page(for: selection)
          .id(selection)
          .transition(.opacity)
          .navigationDestination(for: Route.self) { route in
            switch route {
            case .details(let item):
              DetailView(library: library, seed: item, path: $path)
            }
          }
      }
      // Pages follow the sidebar's width, so an expanded sidebar never covers them.
      .environment(\.contentLeading, Astra.Sidebar.contentInset(expanded: expanded))

      Sidebar(selection: $selection, expanded: $expanded) {
        path.removeAll()
      }
      .padding(.leading, Astra.Sidebar.margin)
    }
    .background(Astra.Color.bg.ignoresSafeArea())
    .animation(Astra.Motion.resolved(Astra.Motion.page, reduceMotion: reduceMotion), value: expanded)
    .environment(\.openItem) { item in
      path.append(.details(item))
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

/// Icon-only Liquid Glass sidebar. Clicking the toggle shows the labels; it
/// never expands on hover.
struct Sidebar: View {
  @Binding var selection: SidebarItem
  @Binding var expanded: Bool
  var onReselect: () -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Namespace private var selectionSpace

  var body: some View {
    VStack(alignment: .leading, spacing: Astra.Spacing.xs) {
      SidebarButton(
        symbol: "sidebar.left", title: expanded ? "Hide Labels" : "Show Labels",
        expanded: expanded, selected: false, namespace: selectionSpace
      ) {
        expanded.toggle()
      }
      .keyboardShortcut("s", modifiers: [.command, .control])

      Divider().overlay(Astra.Color.hairline).padding(.horizontal, 12).padding(.vertical, 4)

      ForEach(SidebarItem.allCases) { item in
        SidebarButton(
          symbol: item.symbol, title: item.title, expanded: expanded, selected: selection == item,
          namespace: selectionSpace
        ) {
          withAnimation(reduceMotion ? Astra.Motion.fast : .spring(response: 0.38, dampingFraction: 0.82)) {
            selection = item
          }
          onReselect()
        }
        .keyboardShortcut(item.shortcut, modifiers: .command)
      }
    }
    .padding(.vertical, 9)
    .padding(.horizontal, 9)
    .frame(width: expanded ? Astra.Sidebar.expandedWidth : Astra.Sidebar.collapsedWidth, alignment: .leading)
    .astraGlass(in: RoundedRectangle(cornerRadius: Astra.Sidebar.collapsedWidth / 2, style: .continuous))
    .frame(maxHeight: .infinity)
  }
}

/// One sidebar row: a 44 pt icon, plus its label when the sidebar is expanded.
struct SidebarButton: View {
  var symbol: String
  var title: String
  var expanded: Bool
  var selected: Bool
  var namespace: Namespace.ID
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 10) {
        Image(systemName: symbol)
          .font(.system(size: 17, weight: .semibold))
          .frame(width: 44, height: 44)
        if expanded {
          Text(title)
            .font(.system(size: 14, weight: .semibold))
            .lineLimit(1)
            .fixedSize()
            .transition(.opacity)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .foregroundStyle(selected ? Color.white : Astra.Color.muted)
      .background {
        // A violet fill, not glass: it sits on the sidebar's glass. It slides
        // from the old item to the new one instead of blinking.
        if selected {
          Capsule().fill(Astra.Color.purple.opacity(0.9))
            .shadow(color: Astra.Color.purple.opacity(0.45), radius: 10, y: 3)
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
