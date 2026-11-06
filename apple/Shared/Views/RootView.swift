import AstraKit
import SwiftUI

/// Switches between sign-in, server choice and the app, and puts the player above everything.
struct RootView: View {
  @Environment(AppModel.self) private var app

  private enum Loader { case hidden, loading, connected }
  /// The launch screen stays up briefly after connecting to say "Connected".
  @State private var loader: Loader = .loading

  var body: some View {
    ZStack {
      // The browsing UI stays alive under the player so its scroll position and
      // navigation survive playback; it is hidden, not removed.
      #if os(macOS)
        // The Mac player has its own window (PlayerWindowHost); this one stays as it is.
        content
      #else
        content
          .opacity(app.player.isActive ? 0 : 1)
          .allowsHitTesting(!app.player.isActive)

        if app.player.isActive {
          PlayerOverlay()
            .transition(.opacity)
        }
      #endif

      if let error = app.player.lastError {
        VStack {
          Spacer()
          HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Astra.Color.ink)
            Text(error).font(.system(size: 13, weight: .medium)).foregroundStyle(Astra.Color.ink)
            Button {
              app.player.lastError = nil
            } label: {
              Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Astra.Color.muted)
          }
          .padding(.horizontal, 18)
          .frame(height: 44)
          .astraGlass(in: Capsule())
          .padding(.bottom, 30)
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
      }
    }
    .animation(Astra.Motion.page, value: app.player.lastError)
    .background { (app.player.isActive && !Self.playerHasOwnWindow ? Color.clear : Astra.Color.bg).ignoresSafeArea() }
    .background(WindowAccessor { app.player.window = $0 })
    #if os(macOS)
      .onAppear {
        app.player.makeOverlay = { [app] in
          AnyView(PlayerOverlay().environment(app).preferredColorScheme(.dark))
        }
      }
    #endif
    .animation(Astra.Motion.page, value: app.player.isActive)
    .onChange(of: app.phase, initial: true) { _, phase in updateLoader(for: phase) }
    // Controls stay inside the safe area (clear of the Mac title bar and the
    // iPhone status bar); only artwork and backgrounds extend under it.
  }

  #if os(macOS)
    static let playerHasOwnWindow = true
  #else
    static let playerHasOwnWindow = false
  #endif

  private func updateLoader(for phase: AppModel.Phase) {
    switch phase {
    case .launching, .connecting:
      loader = .loading
    case .ready where loader == .loading:
      loader = .connected
      Task {
        try? await Task.sleep(for: .seconds(1.1))
        withAnimation(Astra.Motion.hero) { loader = .hidden }
      }
    case .ready:
      break
    default:
      withAnimation(Astra.Motion.page) { loader = .hidden }
    }
  }

  @ViewBuilder private var content: some View {
    if loader != .hidden {
      LoadingView(connected: loader == .connected)
        .transition(.opacity)
    } else {
      phaseContent
    }
  }

  @ViewBuilder private var phaseContent: some View {
    switch app.phase {
    case .launching, .connecting:
      LoadingView(connected: false)
    case .signedOut, .waitingForApproval:
      SignInView()
    case .choosingServer(let servers):
      ServerPickerView(servers: servers)
    case .ready:
      if let library = app.library {
        MainView(library: library)
      }
    case .failed(let message):
      ErrorView(message: message)
    }
  }
}

struct ErrorView: View {
  @Environment(AppModel.self) private var app
  var message: String

  var body: some View {
    VStack(spacing: 20) {
      Text("ASTRA").astraDisplay(36, tracking: 16)
      Text(message)
        .font(.system(size: 15))
        .foregroundStyle(Astra.Color.ink)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 420)
      HStack(spacing: 12) {
        Button("Try Again") { Task { await app.retry() } }.astraPrimaryButton()
        Button("Sign Out") { app.signOut() }.astraSecondaryButton()
      }
      .astraGlassGroup(spacing: 12)
    }
    .padding(.horizontal, Astra.Spacing.l)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Astra.Color.bg.ignoresSafeArea())
  }
}
