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
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .tracking(8)
            .foregroundStyle(Astra.Color.ink)
            .textSelection(.enabled)
          HStack(spacing: 12) {
            Button("Open Plex Again") { AppModel.open(url) }
              .astraSecondaryButton()
            Button("Cancel") { app.cancelSignIn() }
              .astraSecondaryButton()
          }
          .astraGlassGroup(spacing: 12)
          ProgressView().controlSize(.small).padding(.top, 6)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
      default:
        VStack(spacing: 14) {
          Text("Your Plex library, made cinematic.")
            .font(.system(size: 16))
            .foregroundStyle(Astra.Color.muted)
          Button("Sign in with Plex") { app.signIn() }
            .astraPrimaryButton()
            .keyboardShortcut(.defaultAction)
        }
        .transition(.opacity)
      }
    }
    .animation(Astra.Motion.page, value: app.phase)
    .padding(.horizontal, Astra.Spacing.l)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(
      Astra.Color.bg.ignoresSafeArea()
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
                .foregroundStyle(Astra.Color.ink)
              VStack(alignment: .leading, spacing: 2) {
                Text(server.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Astra.Color.ink)
                Text((server.owned ?? false) ? "Your server" : "Shared with you")
                  .font(.system(size: 12)).foregroundStyle(Astra.Color.muted)
              }
              Spacer()
              Image(systemName: "chevron.right").foregroundStyle(Astra.Color.muted)
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: 420, minHeight: 62)
            .background(Astra.Color.surface2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Astra.Color.hairline))
            .contentShape(RoundedRectangle(cornerRadius: 16))
          }
          .buttonStyle(AstraCardButtonStyle())
          .pressable(hoverScale: 1.02)
        }
      }
      Button("Sign Out") { app.signOut() }
        .buttonStyle(.plain)
        .foregroundStyle(Astra.Color.muted)
    }
    // Rows shrink to fit an iPhone instead of running off both edges.
    .padding(.horizontal, Astra.Spacing.l)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Astra.Color.bg.ignoresSafeArea())
  }
}
