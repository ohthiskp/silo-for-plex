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

/// The Apple TV tabs: the iPhone's three (KP, 2026-11-09: "go based off how
/// iOS is"). Settings is the gear on Library, as on the iPhone.
enum TVTab: String, CaseIterable, Identifiable {
  case home, search, library

  var id: String { rawValue }

  var title: String {
    switch self {
    case .home: "Home"
    case .search: "Search"
    case .library: "Library"
    }
  }

  var symbol: String {
    switch self {
    case .home: "house.fill"
    case .search: "magnifyingglass"
    case .library: "square.stack.fill"
    }
  }
}

/// Signed in on Apple TV: the system tab bar along the top (Liquid Glass on
/// tvOS 26) with Home, Search and Library, each its own navigation stack.
/// Opening a title pushes its Details; Menu goes back, then up to the tab
/// bar, then out of the app, all handled by tvOS itself.
struct MainView: View {
  @Environment(AppModel.self) private var app
  var library: LibraryStore

  @State private var tab: TVTab = Demo.tvTab
  @State private var paths: [TVTab: [Route]] = [
    Demo.tvTab: Demo.openKey.flatMap(Demo.item).map { [.details($0)] } ?? []
  ]

  private func path(_ tab: TVTab) -> Binding<[Route]> {
    Binding(get: { paths[tab] ?? [] }, set: { paths[tab] = $0 })
  }

  var body: some View {
    TabView(selection: $tab) {
      ForEach(TVTab.allCases) { item in
        Tab(item.title, systemImage: item.symbol, value: item) {
          stack(item)
        }
      }
    }
    // While the player is up, nothing under it can take focus, so the remote
    // (Menu above all) stays with the player.
    .disabled(app.player.isActive)
    .environment(\.playItem) { app.play($0) }
    .environment(\.ambient, AmbientSource(library: library, item: library.homeHero.first))
    .onAppear {
      app.player.openDetails = { item in paths[tab, default: []].append(.details(item)) }
    }
  }

  private func stack(_ item: TVTab) -> some View {
    NavigationStack(path: path(item)) {
      page(item)
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
        .astraPageBackground()
    case .library: TVLibraryPage(library: library)
    }
  }
}

extension Demo {
  /// `-AstraDemoTab home|search|libraries|settings` for the TV screenshots.
  static var tvTab: TVTab {
    switch tab {
    case "search": .search
    case "libraries", "library", "watchlist", "settings": .library
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
