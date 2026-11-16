import SwiftUI

/// The launch screen: the app icon's orange arrow, animated (KP,
/// 2026-11-16). While Astra connects the speed lines shoot in, the arrow
/// head follows and light runs along the lines; when the server answers the
/// mark settles, fully lit. Below it, the server's name and "Connecting…",
/// then a checkmark and "Connected" (KP, 2026-11-08: so it never looks like
/// a blank wait). It only shows while Astra is really loading.
struct LoadingView: View {
  /// True once the server answered.
  var connected: Bool
  /// The server being connected to ("Omega"); nil before one is chosen.
  var serverName: String? = nil

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var start = Date()
  @State private var appeared = false

  /// Bigger on Apple TV, where it is seen from across the room.
  #if os(tvOS)
    private static let markSize: CGFloat = 220
  #else
    private static let markSize: CGFloat = 132
  #endif

  var body: some View {
    ZStack {
      Astra.Color.bg
      TimelineView(.animation(minimumInterval: 1 / 60, paused: reduceMotion || connected)) { context in
        AstraLoadingMark(
          time: context.date.timeIntervalSince(start), settled: connected || reduceMotion)
      }
      .frame(width: Self.markSize, height: Self.markSize)
      .scaleEffect(connected ? 1.04 : 1)
      .animation(.easeOut(duration: 0.5), value: connected)
      .opacity(appeared ? 1 : 0)
      // Under the mark, so the mark stays exactly centred.
      .overlay(alignment: .bottom) { status.offset(y: Self.markSize * 0.2 + 60) }
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
