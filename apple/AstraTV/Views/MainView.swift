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

/// The Apple TV pages in the top bar (KP, 2026-11-09, with a reference
/// picture): the search icon, Home, Movies, Shows and Watchlist centred, and
/// Settings as a round button at the far right where a profile icon sits.
/// No logo at the top left.
enum TVTab: String, CaseIterable, Identifiable {
  case search, home, movies, shows, watchlist, settings

  var id: String { rawValue }

  var title: String {
    switch self {
    case .search: "Search"
    case .home: "Home"
    case .movies: "Movies"
    case .shows: "Shows"
    case .watchlist: "Watchlist"
    case .settings: "Settings"
    }
  }

  /// The centred text items; Search and Settings are icons.
  static let centre: [TVTab] = [.home, .movies, .shows, .watchlist]
}

/// Signed in on Apple TV: the top bar over the page, each page its own
/// navigation stack. Opening a title pushes its Details (the bar hides);
/// Menu goes back, then up to the bar, then out of the app.
struct MainView: View {
  @Environment(AppModel.self) private var app
  var library: LibraryStore

  @State private var tab: TVTab = Demo.tvTab
  @State private var paths: [TVTab: [Route]] = [
    Demo.tvTab: Demo.openKey.flatMap(Demo.item).map { [.details($0)] } ?? []
  ]
  /// The page has scrolled down: the bar fades out of the way.
  @State private var scrolledDown = false
  @FocusState private var barFocus: TVTab?

  private var atRoot: Bool { (paths[tab] ?? []).isEmpty }
  private var barShown: Bool { atRoot && (!scrolledDown || barFocus != nil) }

  private func path(_ tab: TVTab) -> Binding<[Route]> {
    Binding(get: { paths[tab] ?? [] }, set: { paths[tab] = $0 })
  }

  var body: some View {
    ZStack(alignment: .top) {
      // Every page stays alive (its scroll position and stack survive
      // switching pages); only the chosen one shows and takes focus.
      ForEach(TVTab.allCases) { item in
        stack(item)
          .opacity(item == tab ? 1 : 0)
          .disabled(item != tab)
          .accessibilityHidden(item != tab)
      }

      if atRoot {
        // A soft shade at the top so the bar reads over bright artwork.
        LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom)
          .frame(height: 220)
          .ignoresSafeArea()
          .allowsHitTesting(false)
          .opacity(barShown ? 1 : 0)
        TVTopBar(tab: $tab, focus: $barFocus)
          .opacity(barShown ? 1 : 0)
      }
    }
    .animation(.easeInOut(duration: 0.25), value: barShown)
    .onChange(of: tab) { scrolledDown = false }
    // While the player is up, nothing under it can take focus, so the remote
    // (Menu above all) stays with the player.
    .disabled(app.player.isActive)
    .environment(\.playItem) { app.play($0) }
    .environment(\.ambient, AmbientSource(library: library, item: library.homeHero.first))
    .environment(\.tvScrolledDown) { scrolledDown = $0 }
    .onAppear {
      app.player.openDetails = { item in paths[tab, default: []].append(.details(item)) }
    }
  }

  /// Brings the bar back (it fades out while a page is scrolled down, and
  /// a faded bar can't take focus), then moves focus onto the page's item.
  private func focusBar(_ item: TVTab) {
    scrolledDown = false
    Task { @MainActor in
      await Task.yield()
      try? await Task.pause(0.05)
      barFocus = item
    }
  }

  private func stack(_ item: TVTab) -> some View {
    NavigationStack(path: path(item)) {
      page(item)
        // Menu on a page goes up to the bar; on the bar it leaves the app
        // (nil hands the press on). It sits on the page itself, inside the
        // stack, so in Details the stack's own Back runs instead.
        .onExitCommand(perform: barFocus == nil ? { focusBar(item) } : nil)
        .navigationDestination(for: Route.self) { route in
          switch route {
          case .details(let title):
            TVDetailPage(library: library, seed: title)
          }
        }
    }
    .environment(\.openItem) { title in paths[item, default: []].append(.details(title)) }
  }

  @ViewBuilder private func page(_ item: TVTab) -> some View {
    switch item {
    case .home: TVHome(library: library)
    case .search:
      SearchView(library: library)
        .safeAreaPadding(.top, TVLayout.barSpace)
        .astraPageBackground()
    case .movies: TVLibraryGridPage(library: library, kind: "movie")
    case .shows: TVLibraryGridPage(library: library, kind: "show")
    case .watchlist: TVWatchlistPage(library: library)
    case .settings:
      SettingsView(showsTitle: true)
        .safeAreaPadding(.horizontal, TVLayout.leading)
        .safeAreaPadding(.top, TVLayout.barSpace - 40)
        .astraPageBackground()
    }
  }
}

/// The top bar from KP's reference: search icon, then Home, Movies, Shows,
/// Watchlist as text, centred; the Settings circle at the far right.
/// Selecting an item opens its page; the chosen one sits on a glass pill.
private struct TVTopBar: View {
  @Binding var tab: TVTab
  var focus: FocusState<TVTab?>.Binding
  /// One white focus pill and one glass pill for the open page, each
  /// sliding from item to item (KP: "make the navigation from button to
  /// button seamless").
  @Namespace private var pills

  var body: some View {
    ZStack {
      HStack(spacing: 8) {
        item(.search) {
          Image(systemName: "magnifyingglass").font(.system(size: 28, weight: .semibold))
        }
        ForEach(TVTab.centre) { page in
          item(page) { Text(page.title).font(.system(size: 29, weight: .semibold)) }
        }
      }
      HStack {
        Spacer()
        item(.settings, round: true) {
          Image(systemName: "gearshape.fill").font(.system(size: 28, weight: .semibold))
        }
      }
    }
    .padding(.horizontal, TVLayout.leading)
    .padding(.top, 10)
    .frame(height: TVLayout.barHeight)
    .focusSection()
  }

  private func item<Label: View>(_ page: TVTab, round: Bool = false, @ViewBuilder label: () -> Label) -> some View {
    Button {
      tab = page
    } label: {
      label()
        .padding(.horizontal, round ? 0 : 26)
        .frame(width: round ? 66 : nil, height: 66)
    }
    .buttonStyle(TVBarButtonStyle(selected: tab == page, round: round, pills: pills))
    .focused(focus, equals: page)
    .accessibilityLabel(page.title)
    .accessibilityAddTraits(tab == page ? .isSelected : [])
  }
}

/// A top-bar item: plain text; the open page on a glass pill; focused white
/// with black text, a little larger.
private struct TVBarButtonStyle: ButtonStyle {
  var selected: Bool
  var round: Bool
  var pills: Namespace.ID

  func makeBody(configuration: Configuration) -> some View {
    TVBarButtonBody(configuration: configuration, selected: selected, round: round, pills: pills)
  }
}

private struct TVBarButtonBody: View {
  let configuration: ButtonStyleConfiguration
  var selected: Bool
  var round: Bool
  var pills: Namespace.ID
  @Environment(\.isFocused) private var focused

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: 33, style: .continuous)
    configuration.label
      .foregroundStyle(focused ? Color.black : (selected || round ? Color.white : Color.white.opacity(0.7)))
      .background {
        ZStack {
          if round, !focused {
            shape.fill(.white.opacity(0.08)).astraGlass(in: shape, variant: .clear)
          }
          if selected, !focused, !round {
            shape.fill(.white.opacity(0.08)).astraGlass(in: shape, variant: .clear)
              .matchedGeometryEffect(id: "page", in: pills)
          }
          if focused {
            shape.fill(.white)
              .shadow(color: .black.opacity(0.3), radius: 12, y: 5)
              .matchedGeometryEffect(id: "focus", in: pills)
          }
        }
      }
      .contentShape(shape)
      .scaleEffect(configuration.isPressed ? 0.96 : (focused ? 1.06 : 1))
      .focusEffectDisabled()
      .animation(.snappy(duration: 0.28), value: focused)
      .animation(.snappy(duration: 0.28), value: selected)
  }
}

extension Demo {
  /// `-AstraDemoTab home|search|libraries|movies|shows|watchlist|settings` for the TV screenshots.
  static var tvTab: TVTab {
    switch tab {
    case "search": .search
    case "libraries", "library", "movies": .movies
    case "shows": .shows
    case "watchlist": .watchlist
    case "settings": .settings
    default: .home
    }
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
