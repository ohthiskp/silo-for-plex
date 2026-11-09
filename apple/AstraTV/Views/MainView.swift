import AstraKit
import CoreImage.CIFilterBuiltins
import SwiftUI

/// The Apple TV app uses the shared root: launch screen with the server name,
/// sign-in, server choice, then `MainView` below (KP, 2026-11-08).
struct TVRootView: View {
  @Environment(AppModel.self) private var app

  var body: some View {
    RootView()
      // The player draws under this window; play() needs it before the
      // player's own host is on screen.
      .background(WindowAccessor { app.player.window = $0 })
  }
}

/// The pages in the top bar (KP, 2026-11-09: laid out like Silo's Apple TV app).
enum TVTab: String, CaseIterable, Identifiable {
  case home, movies, shows, watchlist

  var id: String { rawValue }

  var title: String {
    switch self {
    case .home: "Home"
    case .movies: "Movies"
    case .shows: "Shows"
    case .watchlist: "Watchlist"
    }
  }
}

/// Where the bar can put focus: a tab, Search on its left, Settings on its right.
enum TVBarItem: Hashable {
  case tab(TVTab)
  case search
  case settings
}

/// What the page under the bar shows.
enum TVPage: Hashable {
  case tab(TVTab)
  case search
  case settings
}

/// Signed in on Apple TV: Silo's layout. A top bar (Search, Home, Movies,
/// Shows, Watchlist, Settings) over the page; opening a title pushes its
/// Details with the bar hidden, and Menu on the remote goes back.
///
/// Menu at the top level: from the page, focus goes up to the bar; from the
/// bar on any page but Home, back to Home; from Home's bar, out of the app.
struct MainView: View {
  @Environment(AppModel.self) private var app
  var library: LibraryStore

  @State private var page: TVPage = Demo.tvPage
  @State private var path: [Route] = Demo.openKey.flatMap(Demo.item).map { [.details($0)] } ?? []
  @FocusState private var barFocus: TVBarItem?
  /// The bar can't take focus until the page has had it: launch focus goes to
  /// the first card, not Search (Silo does the same).
  @State private var barLocked = true

  var body: some View {
    ZStack(alignment: .top) {
      NavigationStack(path: $path) {
        root
          .toolbar(.hidden, for: .navigationBar)
          .navigationDestination(for: Route.self) { route in
            switch route {
            case .details(let item):
              TVDetailPage(library: library, seed: item)
                .toolbar(.hidden, for: .navigationBar)
            }
          }
      }

      if path.isEmpty {
        TVTopBar(page: page, focus: $barFocus) { picked in
          if picked != page { page = picked }
        }
        .disabled(barLocked)
        .transition(.opacity)
      }
    }
    .background(TVColor.background.ignoresSafeArea())
    .environment(\.openItem) { item in path.append(.details(item)) }
    .environment(\.playItem) { app.play($0) }
    .environment(\.ambient, AmbientSource(library: library, item: library.homeHero.first))
    .onAppear {
      app.player.openDetails = { item in path.append(.details(item)) }
    }
    .task {
      try? await Task.pause(0.8)
      barLocked = false
    }
  }

  private var root: some View {
    pageView
      .id(page)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .onExitCommand(perform: exitAction)
  }

  @ViewBuilder private var pageView: some View {
    switch page {
    case .tab(.home): TVHomeFeed(library: library)
    case .tab(.movies): TVLibraryGrid(library: library, kind: "movie")
    case .tab(.shows): TVLibraryGrid(library: library, kind: "show")
    case .tab(.watchlist): TVWatchlistGrid(library: library)
    case .search:
      SearchView(library: library)
        .padding(.top, TVMetrics.pageTopInset)
        .background(Astra.Color.bg.ignoresSafeArea())
    case .settings:
      SettingsView(showsTitle: false)
        .padding(.top, TVMetrics.pageTopInset)
        .background(Astra.Color.bg.ignoresSafeArea())
    }
  }

  /// Menu at the top level. Nil hands it to the system: out of the app.
  private var exitAction: (() -> Void)? {
    guard path.isEmpty else { return nil }
    if barFocus == nil {
      return { barFocus = barItem(for: page) }
    }
    if page != .tab(.home) {
      return {
        page = .tab(.home)
        barFocus = .tab(.home)
      }
    }
    return nil
  }

  private func barItem(for page: TVPage) -> TVBarItem {
    switch page {
    case .tab(let tab): .tab(tab)
    case .search: .search
    case .settings: .settings
    }
  }
}

extension Demo {
  /// `-AstraDemoTab home|search|libraries|shows|watchlist|settings` for the TV screenshots.
  static var tvPage: TVPage {
    switch tab {
    case "search": .search
    case "libraries", "library", "movies": .tab(.movies)
    case "shows": .tab(.shows)
    case "watchlist": .tab(.watchlist)
    case "settings": .settings
    default: .tab(.home)
    }
  }
}

// MARK: - Top bar

/// Silo's top menu bar: Search, the tabs centred on screen, Settings at the
/// right. Focused = white capsule with black text; the open page = a faint
/// grey capsule; the rest dimmed. The bar dims while focus is in the page.
struct TVTopBar: View {
  var page: TVPage
  var focus: FocusState<TVBarItem?>.Binding
  var choose: (TVPage) -> Void

  private var barFocused: Bool { focus.wrappedValue != nil }

  var body: some View {
    ZStack {
      HStack(spacing: TVMetrics.tabSpacing) {
        iconButton("magnifyingglass", item: .search, page: .search, label: "Search")
        ForEach(TVTab.allCases) { tab in
          tabButton(tab)
        }
        // Balances Search so the tabs stay centred on screen.
        Color.clear.frame(width: TVMetrics.barIconSize, height: TVMetrics.barIconSize)
      }
      .fixedSize()
      .frame(maxWidth: .infinity)

      HStack {
        Spacer()
        iconButton("gearshape.fill", item: .settings, page: .settings, label: "Settings")
      }
    }
    .frame(height: TVMetrics.barHeight)
    .padding(.horizontal, TVMetrics.safeAreaX)
    .padding(.top, TVMetrics.barTopInset)
    .frame(maxWidth: .infinity, alignment: .top)
    .ignoresSafeArea(edges: [.top, .horizontal])
    .opacity(barFocused ? 1 : TVMetrics.barDimmedOpacity)
    .animation(.easeInOut(duration: 0.2), value: barFocused)
    // Up from the page lands on the open page's tab, not whatever is above the card.
    .defaultFocus(focus, defaultItem, priority: .userInitiated)
    .focusSection()
  }

  private var defaultItem: TVBarItem {
    switch page {
    case .tab(let tab): .tab(tab)
    case .search: .search
    case .settings: .settings
    }
  }

  private func tabButton(_ tab: TVTab) -> some View {
    let focused = focus.wrappedValue == .tab(tab)
    let selected = page == .tab(tab)
    return Button {
      choose(.tab(tab))
    } label: {
      Text(tab.title)
        .font(.system(size: TVMetrics.tabLabelSize, weight: .semibold))
        .foregroundStyle(focused ? Color.black : (selected ? Color.white : Color.white.opacity(0.62)))
        .lineLimit(1)
        .padding(.horizontal, TVMetrics.tabPaddingHorizontal)
        .padding(.vertical, TVMetrics.tabPaddingVertical)
        .modifier(TVCapsuleChrome(selected: selected, focused: focused))
    }
    .buttonStyle(TVPlainButtonStyle())
    .focused(focus, equals: .tab(tab))
    // Moving across the bar opens each tab, as on the Apple TV app.
    .onChange(of: focused) { _, now in if now, !selected { choose(.tab(tab)) } }
    .accessibilityLabel(tab.title)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }

  private func iconButton(_ symbol: String, item: TVBarItem, page target: TVPage, label: String) -> some View {
    let focused = focus.wrappedValue == item
    let selected = page == target
    return Button {
      choose(target)
    } label: {
      Image(systemName: symbol)
        .font(.system(size: 26, weight: .semibold))
        .foregroundStyle(focused ? Color.black : (selected ? Color.white : Color.white.opacity(0.62)))
        .frame(width: TVMetrics.barIconSize, height: TVMetrics.barIconSize)
        .modifier(TVCapsuleChrome(selected: selected, focused: focused))
    }
    .buttonStyle(TVPlainButtonStyle())
    .focused(focus, equals: item)
    .accessibilityLabel(label)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}

private struct TVCapsuleChrome: ViewModifier {
  var selected: Bool
  var focused: Bool

  func body(content: Content) -> some View {
    content
      .background(Capsule().fill(focused ? Color.white : (selected ? TVColor.selectedFill : Color.clear)))
      .overlay(Capsule().strokeBorder(focused || !selected ? Color.clear : TVColor.selectedBorder, lineWidth: 1))
      .scaleEffect(focused ? 1.04 : 1)
      .animation(.spring(response: 0.3, dampingFraction: 0.8), value: focused)
      .animation(.easeInOut(duration: 0.18), value: selected)
  }
}

/// A button that draws only its label: no system focus glass.
struct TVPlainButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .contentShape(Capsule())
      .focusEffectDisabled()
      .scaleEffect(configuration.isPressed ? 0.96 : 1)
      .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
  }
}

// MARK: - Sign in

/// Sign in on Apple TV: "Go to plex.tv/link and enter" the short code, or scan
/// the QR code with a phone (KP, 2026-11-08).
struct TVSignInCode: View {
  @Environment(AppModel.self) private var app
  var code: String
  var url: URL

  var body: some View {
    HStack(alignment: .center, spacing: 90) {
      VStack(alignment: .leading, spacing: 22) {
        Text("Sign in with Plex")
          .astraFont(size: 34, weight: .bold)
          .foregroundStyle(Astra.Color.ink)
        Text("On your phone or computer, go to")
          .astraFont(.meta)
          .foregroundStyle(Astra.Color.muted)
        Text(PlexAccountClient.linkURL.host().map { "\($0)/link" } ?? "plex.tv/link")
          .astraFont(size: 30, weight: .semibold)
          .foregroundStyle(Astra.Color.ink)
        Text("and enter")
          .astraFont(.meta)
          .foregroundStyle(Astra.Color.muted)
        Text(code)
          .font(.system(size: 96, weight: .bold, design: .monospaced))
          .tracking(18)
          .foregroundStyle(Astra.Color.ink)
          .accessibilityLabel(code.map(String.init).joined(separator: " "))
        Button("Cancel") { app.cancelSignIn() }
          .astraSecondaryButton()
          .padding(.top, 12)
      }
      VStack(spacing: 18) {
        TVQRCode(text: url.absoluteString)
          .frame(width: 320, height: 320)
        Text("Or scan with your phone")
          .astraFont(.meta)
          .foregroundStyle(Astra.Color.muted)
      }
    }
    .astraTransition(.opacity)
  }
}

/// A crisp black-on-white QR code (CoreImage), drawn without smoothing.
struct TVQRCode: View {
  var text: String

  var body: some View {
    Group {
      if let image = Self.image(for: text) {
        Image(decorative: image, scale: 1)
          .interpolation(.none)
          .resizable()
          .scaledToFit()
          .padding(18)
          .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.white))
      } else {
        RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Astra.Color.surface)
      }
    }
    .accessibilityHidden(true)
  }

  static func image(for text: String) -> CGImage? {
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(text.utf8)
    filter.correctionLevel = "M"
    guard let output = filter.outputImage else { return nil }
    return CIContext().createCGImage(output, from: output.extent)
  }
}
