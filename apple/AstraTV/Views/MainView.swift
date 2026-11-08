import AstraKit
import CoreImage.CIFilterBuiltins
import SwiftUI

/// The Apple TV app uses the shared root: launch screen with the server name,
/// sign-in, server choice, then `MainView` below (KP, 2026-11-08).
struct TVRootView: View {
  var body: some View {
    RootView()
  }
}

/// The Apple TV sidebar's pages: the same four as the Mac and iPhone.
enum TVSection: String, CaseIterable, Identifiable {
  case home, library, search, settings

  var id: String { rawValue }

  var title: String {
    switch self {
    case .home: "Home"
    case .library: "Library"
    case .search: "Search"
    case .settings: "Settings"
    }
  }

  var symbol: String {
    switch self {
    case .home: "house.fill"
    case .library: "square.stack.fill"
    case .search: "magnifyingglass"
    case .settings: "gearshape.fill"
    }
  }
}

/// Signed in on Apple TV: the Mac's glass sidebar on the left, which expands
/// to icons and names while it has focus (KP, 2026-11-08), and the page to
/// its right. Details push onto the page's stack; Menu on the remote goes back.
struct MainView: View {
  @Environment(AppModel.self) private var app
  var library: LibraryStore

  @State private var section: TVSection = .home
  /// Pages stay alive once opened, so switching back keeps scroll and focus.
  @State private var opened: [TVSection] = [.home]
  @State private var paths: [TVSection: [Route]] = [:]
  @FocusState private var sidebarFocus: TVSection?

  private func path(_ id: TVSection) -> Binding<[Route]> {
    Binding(get: { paths[id] ?? [] }, set: { paths[id] = $0 })
  }

  var body: some View {
    ZStack(alignment: .leading) {
      ZStack {
        ForEach(opened) { id in
          let current = id == section
          stack(id)
            .environment(\.isPageActive, current)
            .opacity(current ? 1 : 0)
            .disabled(!current)
            .accessibilityHidden(!current)
        }
      }
      .environment(\.contentLeading, Astra.Sidebar.contentInset)
      .focusSection()

      TVSidebar(selection: section, focus: $sidebarFocus) { picked in
        if !opened.contains(picked) { opened.append(picked) }
        if picked == section {
          // Selecting the open page again goes back to its first screen.
          paths[picked] = []
          if picked == .home, library.selectedService != nil { library.select(nil) }
        } else {
          section = picked
        }
      }
      .padding(.leading, Astra.Sidebar.margin)
      .focusSection()
      // Moving left into the sidebar lands on the open page's icon.
      .defaultFocus($sidebarFocus, section)
    }
    .background(Astra.Color.bg.ignoresSafeArea())
    .environment(\.playItem) { app.play($0) }
    .onAppear {
      app.player.openDetails = { item in
        paths[section, default: []].append(.details(item))
      }
    }
  }

  private func stack(_ id: TVSection) -> some View {
    NavigationStack(path: path(id)) {
      page(id)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: Route.self) { route in
          switch route {
          case .details(let item):
            DetailView(library: library, seed: item, path: path(id))
          }
        }
    }
    .environment(\.openItem) { item in paths[id, default: []].append(.details(item)) }
  }

  @ViewBuilder private func page(_ id: TVSection) -> some View {
    switch id {
    case .home: HomeView(library: library)
    case .library: LibraryPage(library: library)
    case .search: SearchView(library: library)
    case .settings: SettingsView(showsTitle: true)
    }
  }
}

// MARK: - Sidebar

/// A column of glass: icons only, and icons with names while focus is in it.
/// Focus lands on the open page's icon when you move left into it, and the
/// column floats over the page, so expanding never moves the content.
struct TVSidebar: View {
  var selection: TVSection
  var focus: FocusState<TVSection?>.Binding
  var choose: (TVSection) -> Void

  private var expanded: Bool { focus.wrappedValue != nil }
  private static let shape = RoundedRectangle(cornerRadius: Astra.Sidebar.collapsedWidth / 2, style: .continuous)

  var body: some View {
    VStack(spacing: Astra.Spacing.s) {
      ForEach(TVSection.allCases) { item in
        Button { choose(item) } label: {
          TVSidebarLabel(item: item, selected: item == selection, expanded: expanded)
        }
        .buttonStyle(TVSidebarButtonStyle())
        .focused(focus, equals: item)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(item == selection ? .isSelected : [])
      }
    }
    .padding(14)
    .frame(width: expanded ? Astra.Sidebar.expandedWidth : Astra.Sidebar.collapsedWidth, alignment: .leading)
    .astraGlass(in: Self.shape, variant: .clear)
    .astraGlassEdge(Self.shape)
    .frame(maxHeight: .infinity)
    .astraAnimation(Astra.Motion.base, value: expanded)
  }
}

private struct TVSidebarLabel: View {
  var item: TVSection
  var selected: Bool
  var expanded: Bool
  @Environment(\.isFocused) private var focused

  var body: some View {
    HStack(spacing: 16) {
      Image(systemName: item.symbol)
        .font(.system(size: 28, weight: .semibold))
        .frame(width: 68, height: 68)
      if expanded {
        Text(item.title)
          .font(.system(size: 28, weight: .semibold))
          .lineLimit(1)
          .fixedSize()
          .transition(.opacity)
        Spacer(minLength: 0)
      }
    }
    .frame(width: expanded ? nil : 68, height: 68)
    .frame(maxWidth: expanded ? .infinity : nil, alignment: .leading)
    // Focus is a white fill with dark text (the remote's highlight); the open
    // page keeps a quieter grey fill so you always know where you are.
    .foregroundStyle(focused ? Color.black : (selected ? Astra.Color.ink : Astra.Color.muted))
    .background {
      if focused {
        Capsule().fill(Astra.Color.theme)
      } else if selected {
        Capsule().fill(Astra.Color.ink.opacity(0.16))
      }
    }
    .scaleEffect(focused ? 1.04 : 1)
    .astraAnimation(Astra.Motion.fast, value: focused)
  }
}

private struct TVSidebarButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .contentShape(Capsule())
      .scaleEffect(configuration.isPressed ? 0.96 : 1)
      .astraAnimation(Astra.Motion.fast, value: configuration.isPressed)
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
