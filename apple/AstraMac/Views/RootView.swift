import AppKit
import AstraKit
import SwiftUI

/// Switches between sign-in, server choice and the app, and puts the player above everything.
struct RootView: View {
  @Environment(AppModel.self) private var app

  var body: some View {
    ZStack {
      // The browsing UI stays alive under the player so its scroll position and
      // navigation survive playback; it is hidden, not removed.
      content
        .opacity(app.player.isActive ? 0 : 1)
        .allowsHitTesting(!app.player.isActive)

      if app.player.isActive {
        PlayerOverlay()
          .transition(.opacity)
      }

      if let error = app.player.lastError {
        VStack {
          Spacer()
          HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Astra.Color.purpleLight)
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
    .background(app.player.isActive ? Color.clear : Astra.Color.bg)
    .background(WindowAccessor { app.player.window = $0 })
    .animation(Astra.Motion.page, value: app.player.isActive)
    .ignoresSafeArea()
  }

  @ViewBuilder private var content: some View {
    switch app.phase {
    case .launching:
      SplashView(message: nil)
    case .connecting(let name):
      SplashView(message: "Connecting to \(name)…")
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

struct SplashView: View {
  var message: String?

  var body: some View {
    VStack(spacing: 18) {
      Text("ASTRA").astraDisplay(44, tracking: 18)
      if let message {
        Text(message).font(Astra.Font.meta).foregroundStyle(Astra.Color.muted)
          .transition(.opacity)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Astra.Color.bg)
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
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Astra.Color.bg)
  }
}

/// Hands the hosting NSWindow to the player, which draws video beneath the SwiftUI layers.
struct WindowAccessor: NSViewRepresentable {
  var onWindow: (NSWindow?) -> Void

  func makeNSView(context: Context) -> NSView {
    let view = WindowReportingView()
    view.onWindow = onWindow
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {}

  final class WindowReportingView: NSView {
    var onWindow: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      window?.backgroundColor = .black
      onWindow?(window)
    }
  }
}
