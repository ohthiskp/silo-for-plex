import AstraKit
import SwiftUI

/// Switches between sign-in, server choice and the app, and puts the player above everything.
struct RootView: View {
  @Environment(AppModel.self) private var app

  private enum Loader { case hidden, loading, connected }
  /// The launch screen stays up briefly after connecting to say "Connected".
  @State private var loader: Loader = .loading
  /// The last server's name ("Omega"), read once for the launch screen.
  @State private var savedServerName = SavedConnection.load()?.serverName

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

      // Astra: download failures show here too (they were silent before).
      if let error = app.player.lastError ?? app.downloads.lastError {
        VStack {
          Spacer()
          HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Astra.Color.ink)
            Text(error).astraFont(size: 13, weight: .medium).foregroundStyle(Astra.Color.ink)
            Button {
              app.player.lastError = nil
              app.downloads.lastError = nil
            } label: {
              Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Astra.Color.muted)
            .accessibilityLabel("Dismiss")
          }
          .padding(.horizontal, 18)
          .frame(height: 44)
          .astraGlass(in: Capsule())
          .padding(.bottom, 30)
        }
        .astraTransition(.opacity.combined(with: .move(edge: .bottom)))
      }
    }
    .astraAnimation(Astra.Motion.page, value: app.player.lastError ?? app.downloads.lastError)
    // QA P2-1: the message goes away by itself after a few seconds (on Apple
    // TV its X is hard to reach with the remote). A new message restarts the wait.
    .task(id: app.player.lastError ?? app.downloads.lastError) {
      let shown = app.player.lastError ?? app.downloads.lastError
      guard shown != nil, (try? await Task.pause(Self.messageSeconds)) != nil, !Task.isCancelled else { return }
      if app.player.lastError == shown { app.player.lastError = nil }
      if app.downloads.lastError == shown { app.downloads.lastError = nil }
    }
    .background { (app.player.isActive && !Self.playerHasOwnWindow ? Color.clear : Astra.Color.bg).ignoresSafeArea() }
    .background(WindowAccessor { app.player.window = $0 })
    #if os(macOS)
      .onAppear {
        app.player.makeOverlay = { [app] in
          AnyView(PlayerOverlay().environment(app).preferredColorScheme(.dark).tint(.white))
        }
      }
    #endif
    .astraAnimation(Astra.Motion.page, value: app.player.isActive)
    // Text grows with Text Size (KP, 2026-11-08) up to the largest standard
    // size; the accessibility sizes would break the fixed-height rows and bars.
    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    // Settings → Appearance → Theme (KP, 2026-11-09): light or dark system
    // glass and controls, and the theme's accent as the tint (never the
    // system accent, which can be purple).
    .preferredColorScheme(AstraAppearance.shared.colorScheme)
    .tint(AstraAppearance.shared.accent)
    .onChange(of: app.phase, initial: true) { _, phase in updateLoader(for: phase) }
    .task(id: loader) {
      // "Connected" shows for a moment, then the app fades in. It was 1.1 s,
      // added to every launch (KP, 2026-11-09: "a huge delay every time I open it").
      guard loader == .connected else { return }
      try? await Task.pause(0.35)
      guard !Task.isCancelled, loader == .connected else { return }
      astraWithAnimation(Astra.Motion.hero) { loader = .hidden }
    }
    // Controls stay inside the safe area (clear of the Mac title bar and the
    // iPhone status bar); only artwork and backgrounds extend under it.
  }

  /// How long an error message stays at the bottom of the screen.
  static let messageSeconds: Double = 6

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
      // Astra: hidden by the `.task(id: loader)` below. An unstructured
      // Task here aborted the iPhone app in swift_task_dealloc (iOS 27).
      loader = .connected
    case .ready:
      break
    default:
      astraWithAnimation(Astra.Motion.page) { loader = .hidden }
    }
  }

  @ViewBuilder private var content: some View {
    if loader != .hidden {
      // The saved server's name shows at once, before it answers.
      LoadingView(connected: loader == .connected, serverName: app.server?.serverName ?? savedServerName)
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
        // A new server session starts with fresh pages: nothing from the
        // old server (its section keys, rows or scroll state) carries over.
        MainView(library: library)
          .id(library.generation)
          // Astra 4.0: a small banner while the server can't stream.
          .overlay(alignment: .top) {
            if let health = app.health, !app.player.isActive {
              ServerHealthBanner(health: health)
            }
          }
          .sheet(
            isPresented: Binding(
              get: { app.serverSwitch != nil }, set: { if !$0 { app.cancelServerSwitch() } })
          ) {
            if let state = app.serverSwitch {
              ServerSwitchSheet(state: state).environment(app).preferredColorScheme(.dark).tint(.white)
            }
          }
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
      AstraLogo().frame(width: 72, height: 72)
      Text(message)
        .astraFont(size: 15)
        .foregroundStyle(Astra.Color.ink)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 420)
      HStack(spacing: 12) {
        Button("Try Again") { Task { await app.retry() } }.astraPrimaryButton()
        Button("Choose Server") { Task { await app.chooseServer() } }.astraSecondaryButton()
        Button("Sign Out") { app.signOut() }.astraSecondaryButton()
      }
      .astraGlassGroup(spacing: 12)
    }
    .padding(.horizontal, Astra.Spacing.l)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Astra.Color.bg.ignoresSafeArea())
  }
}

/// Astra 4.0 (KP, 2026-11-08): a small glass banner at the top while the
/// server is confirmed unavailable, the sign-in was rejected, or there's no
/// network. Cached rows and artwork stay; downloads still play.
struct ServerHealthBanner: View {
  let health: ServerHealthMonitor
  @Environment(AppModel.self) private var app

  private var message: String? {
    switch health.state {
    case .offline: AppModel.unavailableMessage
    case .authRequired: "Plex needs you to sign in again before anything can stream."
    case .networkUnavailable: "You're offline. Downloaded titles still play."
    case .connected, .checking, .degraded: nil
    }
  }

  var body: some View {
    ZStack {
      if let message {
        HStack(spacing: 10) {
          Image(systemName: health.state == .authRequired ? "person.crop.circle.badge.exclamationmark" : "wifi.exclamationmark")
            .font(.system(size: 13, weight: .semibold))
          Text(message)
            .astraFont(size: 12.5, weight: .medium)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
          if health.state == .authRequired {
            Button("Sign In") { app.signOut() }
              .font(.system(size: 12.5, weight: .semibold))
              .buttonStyle(.plain)
          } else if health.state == .offline {
            Button("Retry") { health.checkNow() }
              .font(.system(size: 12.5, weight: .semibold))
              .buttonStyle(.plain)
          }
        }
        .foregroundStyle(Astra.Color.ink)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: 560)
        .astraGlass(in: Capsule())
        .padding(.top, 8)
        .padding(.horizontal, 16)
        .astraTransition(.opacity.combined(with: .move(edge: .top)))
      }
    }
    .astraAnimation(Astra.Motion.page, value: health.state)
  }
}
