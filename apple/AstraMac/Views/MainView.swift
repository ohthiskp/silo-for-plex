import AstraKit
import SwiftUI

/// The sidebar destinations, in order. Astra (KP, 2026-11-07): like the
/// iPhone tabs, Movies, Shows and Downloads live inside Library.
enum SidebarItem: String, CaseIterable, Hashable, Identifiable {
  case home, search, library, settings

  var id: String { rawValue }

  var title: String {
    switch self {
    case .home: "Home"
    case .search: "Search"
    case .library: "Library"
    case .settings: "Settings"
    }
  }

  var symbol: String {
    switch self {
    case .home: "house.fill"
    case .search: "magnifyingglass"
    case .library: "square.stack.fill"
    case .settings: "gearshape.fill"
    }
  }

  /// ⌘1 to ⌘4.
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
        // Instant: the page and the sidebar both switch without animation.
        selection = item
        astraWithAnimation(Self.cardMotion) { path.removeAll() }
        // Astra (KP, 2026-11-07): clicking Home always goes back to For You.
        if item == .home, library.selectedService != nil { library.select(nil) }
      }
      .padding(.leading, Astra.Sidebar.margin)
    }
    .background(Astra.Color.bg.ignoresSafeArea())
    .environment(\.ambient, AmbientSource(library: library, item: library.homeHero.first))
    .environment(\.openItem) { item in
      // A TMDB-only title opens too; its page finds it on the server or greys out Play.
      astraWithAnimation(Self.cardMotion) { path.append(.details(item)) }
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
      // Keyed by position and title, so a new card never reuses a closing one's state.
      ForEach(Array(path.enumerated()), id: \.offset) { depth, route in
        let isTop = depth == path.count - 1
        card(for: route)
          .id("\(depth)|\(route.hashValue)")
          // Only the top card answers Return (Play) and Esc (Close).
          .environment(\.isPageActive, isTop)
          .padding(.leading, Astra.Sidebar.contentInset + 24 + CGFloat(depth) * Self.cardStep)
          .padding(.trailing, 14)
          .padding(.vertical, 14)
          // Cards under the top one sink back a little.
          .scaleEffect(isTop ? 1 : 0.985, anchor: .leading)
          .brightness(isTop ? 0 : -0.12)
          .allowsHitTesting(isTop)
          .accessibilityHidden(!isTop)
          .astraTransition(.move(edge: .trailing))
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
    astraWithAnimation(Self.cardMotion) { _ = path.removeLast() }
  }

  @ViewBuilder private func page(for item: SidebarItem) -> some View {
    switch item {
    case .home:
      HomeView(library: library)
    case .library:
      LibraryPage(library: library)
    case .search:
      SearchView(library: library)
    case .settings:
      SettingsPage()
    }
  }
}

// MARK: - Sidebar

/// Liquid Glass sidebar: icons only, and icons plus names while the pointer
/// is over it (KP, 2026-11-08). It floats over the page, so expanding never
/// moves the content. Astra (KP, 2026-11-07): no sliding pill; a click lights
/// the chosen icon at once, with no animation.
struct Sidebar: View {
  @Binding var selection: SidebarItem
  var choose: (SidebarItem) -> Void
  @Environment(AppModel.self) private var app
  @State private var expanded = false

  private static let spacing: CGFloat = Astra.Spacing.xs
  /// The collapsed bar is a capsule; the same radius keeps its ends round when it widens.
  private static let shape = RoundedRectangle(cornerRadius: Astra.Sidebar.collapsedWidth / 2, style: .continuous)

  var body: some View {
    VStack(spacing: Self.spacing) {
      ForEach(SidebarItem.allCases) { item in
        SidebarButton(
          symbol: item.symbol, title: item.title, selected: selection == item, expanded: expanded,
          count: item == .library ? app.downloads.jobs.count : 0
        ) {
          choose(item)
        }
        .keyboardShortcut(item.shortcut, modifiers: .command)
      }
    }
    // Selection changes light at once; only the hover expand animates.
    .transaction(value: selection) { $0.animation = nil }
    .padding(9)
    .frame(width: expanded ? Astra.Sidebar.expandedWidth : Astra.Sidebar.collapsedWidth, alignment: .leading)
    // Clear glass with a light edge, like the player's panel (KP's reference card).
    .astraGlass(in: Self.shape, variant: .clear)
    .astraGlassEdge(Self.shape)
    .contentShape(Self.shape)
    .onHover { hovering in astraWithAnimation(Astra.Motion.base) { expanded = hovering } }
    .frame(maxHeight: .infinity)
  }
}

/// One sidebar button: a 44 pt icon, with its name beside it when the sidebar
/// is expanded. Its colour comes only from `selected`.
struct SidebarButton: View {
  var symbol: String
  var title: String
  var selected: Bool
  var expanded = false
  /// Astra (KP, 2026-11-07): Library shows how many downloads are running, like the iPhone tab.
  var count = 0
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 4) {
        Image(systemName: symbol)
          .font(.system(size: 17, weight: .semibold))
          .frame(width: 44, height: 44)
          .overlay(alignment: .topTrailing) {
            if count > 0 {
              Text("\(count)")
                .font(.system(size: 10, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Astra.Color.onAccent)
                .padding(.horizontal, 5)
                .frame(minWidth: 16, minHeight: 16)
                .background(Capsule().fill(Astra.Color.accent))
                .overlay(Capsule().stroke(Color.black.opacity(0.25)))
                .offset(x: 2, y: 2)
                .astraTransition(.scale.combined(with: .opacity))
            }
          }
          .astraAnimation(.snappy(duration: 0.2), value: count)
        if expanded {
          Text(title)
            .font(.system(size: 14, weight: .semibold))
            .lineLimit(1)
            .fixedSize()
            .transition(.opacity)
          Spacer(minLength: 0)
        }
      }
      .frame(width: expanded ? nil : 44, height: 44)
      .frame(maxWidth: expanded ? .infinity : nil, alignment: .leading)
      .foregroundStyle(selected ? Astra.Color.onTheme : Astra.Color.muted)
      // A white fill (Settings → Appearance → Theme), not glass: it sits on the sidebar's glass.
      .background { if selected { Capsule().fill(Astra.Color.theme) } }
      .contentShape(Capsule())
    }
    .buttonStyle(SidebarButtonStyle())
    .help(title)
    .accessibilityLabel(count > 0 ? "\(title), \(count)" : title)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}

/// No dimming on press (that read as a flicker); a slight scale instead.
private struct SidebarButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.92 : 1)
      .astraAnimation(.snappy(duration: 0.12), value: configuration.isPressed)
  }
}
