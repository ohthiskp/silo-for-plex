import AppKit
import AstraKit
import SwiftUI

struct SignInView: View {
  @Environment(AppModel.self) private var app

  var body: some View {
    VStack(spacing: 28) {
      Text("ASTRA").astraDisplay(56, tracking: 22)

      switch app.phase {
      case .waitingForApproval(let code, let url):
        VStack(spacing: 16) {
          Text("Finish signing in on the Plex page that just opened.")
            .font(.system(size: 15))
            .foregroundStyle(Astra.Color.ink)
          Text("Or go to plex.tv/link and enter")
            .font(Astra.Font.meta)
            .foregroundStyle(Astra.Color.muted)
          Text(code)
            .font(.system(size: 34, weight: .semibold, design: .monospaced))
            .tracking(8)
            .foregroundStyle(Astra.Color.ink)
            .textSelection(.enabled)
          HStack(spacing: 12) {
            Button("Open Plex Again") { NSWorkspace.shared.open(url) }
              .buttonStyle(GlassButtonStyle())
            Button("Cancel") { app.cancelSignIn() }
              .buttonStyle(GlassButtonStyle())
          }
          ProgressView().controlSize(.small).padding(.top, 6)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
      default:
        VStack(spacing: 14) {
          Text("Your Plex library, made cinematic.")
            .font(.system(size: 16))
            .foregroundStyle(Astra.Color.muted)
          Button("Sign in with Plex") { app.signIn() }
            .buttonStyle(PlayButtonStyle(violet: true))
            .keyboardShortcut(.defaultAction)
        }
        .transition(.opacity)
      }
    }
    .animation(Astra.Motion.page, value: app.phase)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(
      RadialGradient(
        colors: [Astra.Color.purple.opacity(0.22), Astra.Color.bg], center: .top, startRadius: 40, endRadius: 700)
    )
  }
}

struct ServerPickerView: View {
  @Environment(AppModel.self) private var app
  var servers: [PlexServerResource]

  var body: some View {
    VStack(spacing: 26) {
      Text("Choose a server").astraDisplay(34, tracking: 6)
      VStack(spacing: 10) {
        ForEach(servers) { server in
          Button {
            Task { await app.connect(to: server) }
          } label: {
            HStack(spacing: 14) {
              Image(systemName: "server.rack")
                .font(.system(size: 18))
                .foregroundStyle(Astra.Color.purpleLight)
              VStack(alignment: .leading, spacing: 2) {
                Text(server.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Astra.Color.ink)
                Text((server.owned ?? false) ? "Your server" : "Shared with you")
                  .font(.system(size: 12)).foregroundStyle(Astra.Color.muted)
              }
              Spacer()
              Image(systemName: "chevron.right").foregroundStyle(Astra.Color.muted)
            }
            .padding(.horizontal, 18)
            .frame(width: 420, height: 62)
            .astraGlass(in: RoundedRectangle(cornerRadius: 16), interactive: true)
            .contentShape(RoundedRectangle(cornerRadius: 16))
          }
          .buttonStyle(.plain)
          .pressable(hoverScale: 1.02)
        }
      }
      Button("Sign Out") { app.signOut() }
        .buttonStyle(.plain)
        .foregroundStyle(Astra.Color.muted)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Astra.Color.bg)
  }
}
