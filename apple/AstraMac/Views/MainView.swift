import AstraKit
import SwiftUI

enum Route: Hashable {
  case details(PlexMetadata)
}

enum SidebarItem: Hashable {
  case home
  case search
  case section(PlexLibrarySection)
}

/// The signed-in app: a docked glass icon sidebar and a navigation stack.
struct MainView: View {
  @Environment(AppModel.self) private var app
  var library: LibraryStore

  @State private var selection: SidebarItem = .home
  @State private var path: [Route] = []

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
      .animation(Astra.Motion.page, value: selection)

      Sidebar(selection: $selection, sections: library.sections) {
        path.removeAll()
      }
      .padding(.leading, 14)
      .padding(.vertical, 60)
    }
    .background(Astra.Color.bg)
    .environment(\.openItem) { item in
      path.append(.details(item))
    }
    .environment(\.playItem) { item in
      Task {
        do {
          let playable = try await library.playable(for: item)
          try app.player.play(playable, library: library)
        } catch {
          app.player.lastError = error.localizedDescription
        }
      }
    }
  }

  @ViewBuilder private func page(for item: SidebarItem) -> some View {
    switch item {
    case .home:
      HomeView(library: library)
    case .search:
      SearchView(library: library)
    case .section(let section):
      LibraryGridView(library: library, section: section)
    }
  }
}

// MARK: - Actions passed down the tree

private struct OpenItemKey: EnvironmentKey {
  static let defaultValue: (PlexMetadata) -> Void = { _ in }
}

private struct PlayItemKey: EnvironmentKey {
  static let defaultValue: (PlexMetadata) -> Void = { _ in }
}

extension EnvironmentValues {
  /// Opens the details page for an item.
  var openItem: (PlexMetadata) -> Void {
    get { self[OpenItemKey.self] }
    set { self[OpenItemKey.self] = newValue }
  }

  /// Plays an item (a show or season plays its next episode).
  var playItem: (PlexMetadata) -> Void {
    get { self[PlayItemKey.self] }
    set { self[PlayItemKey.self] = newValue }
  }
}

// MARK: - Sidebar

struct Sidebar: View {
  @Binding var selection: SidebarItem
  var sections: [PlexLibrarySection]
  var onReselect: () -> Void
  @Environment(\.openSettings) private var openSettings
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Namespace private var selectionSpace

  var body: some View {
    VStack(spacing: 6) {
      icon("house.fill", "Home", .home)
      icon("magnifyingglass", "Search", .search)
      Divider().frame(width: 24).overlay(Astra.Color.hairline).padding(.vertical, 6)
      ForEach(sections) { section in
        icon(section.type == "show" ? "tv" : "film", section.title, .section(section))
      }
      Spacer(minLength: 12)
      Button {
        openSettings()
      } label: {
        Image(systemName: "gearshape.fill")
          .font(.system(size: 17, weight: .semibold))
          .frame(width: 44, height: 44)
          .foregroundStyle(Astra.Color.muted)
          .contentShape(Circle())
      }
      .buttonStyle(.plain)
      .help("Settings")
    }
    .padding(.vertical, 12)
    .frame(width: 62)
    .astraGlass(in: Capsule())
  }

  private func icon(_ symbol: String, _ title: String, _ item: SidebarItem) -> some View {
    let selected = selection == item
    return Button {
      withAnimation(reduceMotion ? Astra.Motion.fast : .spring(response: 0.38, dampingFraction: 0.82)) {
        selection = item
      }
      onReselect()
    } label: {
      Image(systemName: symbol)
        .font(.system(size: 17, weight: .semibold))
        .frame(width: 44, height: 44)
        .foregroundStyle(selected ? Color.white : Astra.Color.muted)
        .background {
          // A violet fill, not glass: it sits on the sidebar's glass. It slides
          // from the old icon to the new one instead of blinking.
          if selected {
            Circle().fill(Astra.Color.purple.opacity(0.9))
              .shadow(color: Astra.Color.purple.opacity(0.5), radius: 10)
              .matchedGeometryEffect(id: "selection", in: selectionSpace)
          }
        }
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .help(title)
  }
}
