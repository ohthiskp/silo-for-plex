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

/// The signed-in app: a docked glass sidebar, the pages, and details as stacked cards.
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
      ZStack {
        ForEach(opened) { item in
          let current = item == selection
          page(for: item)
            // Behind cards or another page: timers and the hero pause.
            .environment(\.isPageActive, current && path.isEmpty)
            .opacity(current ? 1 : 0)
            .allowsHitTesting(current && path.isEmpty)
            .accessibilityHidden(!current || !path.isEmpty)
        }
      }
      .environment(\.contentLeading, Astra.Sidebar.contentInset)

      cards

      Sidebar(selection: $selection) { item in
        if !opened.contains(item) { opened.append(item) }
        // Instant: the page swaps without animation; only the sidebar's pill slides.
        selection = item
        withAnimation(Self.cardMotion) { path.removeAll() }
      }
      .padding(.leading, Astra.Sidebar.margin)
    }
    .background(Astra.Color.bg.ignoresSafeArea())
    .environment(\.openItem) { item in
      // A TMDB-only title opens too; its page finds it on the server or greys out Play.
      withAnimation(Self.cardMotion) { path.append(.details(item)) }
    }
    .environment(\.playItem) { app.play($0) }
  }

  static let cardMotion = Animation.spring(response: 0.42, dampingFraction: 0.9)
  /// Each card further up the stack starts this much further right, so the
  /// edges of the ones below show.
  private static let cardStep: CGFloat = 26

  /// Details open as cards sliding in from the right over the page, leaving
  /// the sidebar and a strip of the page visible. Opening another title from
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
      ForEach(Array(path.enumerated()), id: \.offset) { depth, route in
        let isTop = depth == path.count - 1
        card(for: route)
          .padding(.leading, Astra.Sidebar.contentInset + 24 + CGFloat(depth) * Self.cardStep)
          .padding(.trailing, 14)
          .padding(.vertical, 14)
          // Cards under the top one sink back a little.
          .scaleEffect(isTop ? 1 : 0.985, anchor: .leading)
          .brightness(isTop ? 0 : -0.12)
          .allowsHitTesting(isTop)
          .accessibilityHidden(!isTop)
          .transition(.move(edge: .trailing))
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
    withAnimation(Self.cardMotion) { _ = path.removeLast() }
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

/// Icon-only Liquid Glass sidebar with one white selection pill that slides
/// between items. The pill is a single view under all the icons, so there is
/// never more than one, and each icon's colour follows the same selection
/// with the same animation, so an icon is never black on the dark glass.
struct Sidebar: View {
  @Binding var selection: SidebarItem
  var choose: (SidebarItem) -> Void

  private static let itemSize: CGFloat = 44
  private static let spacing: CGFloat = Astra.Spacing.xs
  private static let motion = Animation.snappy(duration: 0.24)

  private var selectedIndex: Int { SidebarItem.allCases.firstIndex(of: selection) ?? 0 }

  var body: some View {
    VStack(spacing: Self.spacing) {
      ForEach(SidebarItem.allCases) { item in
        SidebarButton(symbol: item.symbol, title: item.title, selected: selection == item) {
          choose(item)
        }
        .keyboardShortcut(item.shortcut, modifiers: .command)
      }
    }
    .background(alignment: .top) {
      // A white fill, not glass: it sits on the sidebar's glass.
      Capsule()
        .fill(Astra.Color.accent)
        .frame(width: Self.itemSize, height: Self.itemSize)
        .offset(y: CGFloat(selectedIndex) * (Self.itemSize + Self.spacing))
        .allowsHitTesting(false)
    }
    .animation(Self.motion, value: selection)
    .padding(9)
    .frame(width: Astra.Sidebar.collapsedWidth)
    // Clear glass with a light edge, like the player's panel (KP's reference card).
    .astraGlass(in: Capsule(), variant: .clear)
    .astraGlassEdge(Capsule())
    .frame(maxHeight: .infinity)
  }
}

/// One sidebar button: a 44 pt icon. Its colour comes only from `selected`.
struct SidebarButton: View {
  var symbol: String
  var title: String
  var selected: Bool
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 17, weight: .semibold))
        .frame(width: 44, height: 44)
        .foregroundStyle(selected ? Color.black : Astra.Color.muted)
        .contentShape(Capsule())
    }
    .buttonStyle(SidebarButtonStyle())
    .accessibilityLabel(title)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}

/// No dimming on press (that read as a flicker); a slight scale instead.
private struct SidebarButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.92 : 1)
      .animation(.snappy(duration: 0.12), value: configuration.isPressed)
  }
}
