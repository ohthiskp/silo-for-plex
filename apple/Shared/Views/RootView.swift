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
          AnyView(PlayerOverlay().environment(app).preferredColorScheme(.dark).tint(.white))
        }
      }
    #endif
    .animation(Astra.Motion.page, value: app.player.isActive)
    .onChange(of: app.phase, initial: true) { _, phase in updateLoader(for: phase) }
    .task(id: loader) {
      // "Connected" stays up briefly, then the app fades in.
      guard loader == .connected else { return }
      try? await Task.pause(1.1)
      guard !Task.isCancelled, loader == .connected else { return }
      withAnimation(Astra.Motion.hero) { loader = .hidden }
    }
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
      // Astra: hidden by the `.task(id: loader)` below. An unstructured
      // Task here aborted the iPhone app in swift_task_dealloc (iOS 27).
      loader = .connected
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
        // A new server session starts with fresh pages: nothing from the
        // old server (its section keys, rows or scroll state) carries over.
        MainView(library: library)
          .id(library.generation)
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
        .font(.system(size: 15))
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
