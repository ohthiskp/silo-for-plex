import SwiftUI

/// The launch screen: only Astra's mark, in white and grey, no text. While
/// Astra connects the speed lines draw in and the mark breathes; when the
/// server answers it lights up fully and settles.
struct LoadingView: View {
  /// True once the server answered.
  var connected: Bool

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
    }
    .ignoresSafeArea()
    .onAppear {
      withAnimation(.easeOut(duration: 0.5)) { appeared = true }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(connected ? "Connected" : "Connecting")
  }
}
