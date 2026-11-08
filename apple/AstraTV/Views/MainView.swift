import AstraKit
import SwiftUI

/// The Apple TV shell's placeholder screens, so the target builds and runs end
/// to end (sign in, pick a server, connected). Design replaces these with the
/// shared views and the focus-expanding sidebar.
struct TVRootView: View {
  @Environment(AppModel.self) private var app

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()
      switch app.phase {
      case .launching:
        ProgressView()
      case .signedOut:
        VStack(spacing: 40) {
          Text("Astra").font(.system(size: 76, weight: .bold))
          Button("Sign In with Plex") { app.signIn() }
        }
      case .waitingForApproval(let code, let url):
        VStack(spacing: 28) {
          Text("Sign in on another device").font(.title2)
          Text(url.host() ?? "plex.tv").foregroundStyle(.secondary)
          Text(code).font(.system(size: 64, weight: .semibold, design: .monospaced))
          Button("Cancel") { app.cancelSignIn() }
        }
      case .choosingServer(let servers):
        VStack(spacing: 24) {
          Text("Choose a Server").font(.title2)
          ForEach(servers, id: \.clientIdentifier) { server in
            Button(server.name) { Task { await app.connect(to: server) } }
          }
        }
      case .connecting(let name):
        VStack(spacing: 24) {
          ProgressView()
          Text("Connecting to \(name)…").foregroundStyle(.secondary)
        }
      case .ready:
        TVMainView()
      case .failed(let message):
        VStack(spacing: 28) {
          Text(message).multilineTextAlignment(.center).frame(maxWidth: 1100)
          Button("Try Again") { app.signIn() }
          Button("Sign Out") { app.signOut() }
        }
      }
    }
  }
}

/// Connected. Placeholder for the sidebar (Home, Library, Search, Settings) and Home.
struct TVMainView: View {
  @Environment(AppModel.self) private var app

  var body: some View {
    VStack(spacing: 24) {
      Text("Connected to \(app.server?.serverName ?? "Plex")").font(.title2)
      Text("The Apple TV interface is being built.").foregroundStyle(.secondary)
      Button("Sign Out") { app.signOut() }
    }
  }
}
