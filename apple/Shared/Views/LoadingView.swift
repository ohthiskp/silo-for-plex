import SwiftUI

/// The launch screen: Astra's mark in white and grey. While Astra connects
/// the speed lines draw in and the mark breathes; when the server answers it
/// lights up fully and settles. Below it, the server's name and
/// "Connecting…", then a checkmark and "Connected" (KP, 2026-11-08: so it
/// never looks like a blank wait).
struct LoadingView: View {
  /// True once the server answered.
  var connected: Bool
  /// The server being connected to ("Omega"); nil before one is chosen.
  var serverName: String? = nil

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var start = Date()
  @State private var appeared = false

  var body: some View {
    ZStack {
      Astra.Color.bg
      TimelineView(.animation(minimumInterval: 1 / 60, paused: reduceMotion || connected)) { context in
        let t = context.date.timeIntervalSince(start)
        // Lines draw in over the first 0.9 s, then the mark breathes between grey and white.
        let streak = reduceMotion ? 1 : min(1, t / 0.9)
        let breath = 0.5 + 0.5 * sin(t * 2.4)
        AstraLogo(lit: connected ? 1 : 0.45 + 0.3 * breath, streak: connected ? 1 : streak)
      }
      .frame(width: 120, height: 120)
      .scaleEffect(connected ? 1.06 : 1)
      .shadow(color: .white.opacity(connected ? 0.25 : 0), radius: 24)
      .animation(.easeOut(duration: 0.5), value: connected)
      .opacity(appeared ? 1 : 0)
      // Under the mark, so the mark stays exactly centred.
      .overlay(alignment: .bottom) { status.offset(y: 84) }
    }
    .ignoresSafeArea()
    .onAppear {
      withAnimation(.easeOut(duration: 0.5)) { appeared = true }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityText)
  }

  private var accessibilityText: String {
    let state = connected ? "Connected" : "Connecting"
    return serverName.map { "\(state) to \($0)" } ?? state
  }

  private var status: some View {
    VStack(spacing: 8) {
      if let serverName, !serverName.isEmpty {
        Text(serverName)
          .astraFont(size: 17, weight: .semibold)
          .foregroundStyle(Astra.Color.ink)
          .lineLimit(1)
      }
      HStack(spacing: 6) {
        if connected {
          Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 13, weight: .semibold))
            .transition(.opacity)
        } else {
          ProgressView().astraControlSize(.mini).tint(Astra.Color.muted)
        }
        Text(connected ? "Connected" : "Connecting…")
          .astraFont(.meta)
          .contentTransition(.opacity)
      }
      .foregroundStyle(connected ? Astra.Color.ink : Astra.Color.muted)
      .animation(.easeOut(duration: 0.3), value: connected)
    }
    .fixedSize()
    .opacity(appeared ? 1 : 0)
  }
}
