import SwiftUI

/// The launch screen: the app icon's orange arrow by itself, animated (KP,
/// 2026-11-16: "just have the logo by itself"). The speed lines shoot in,
/// the arrow head follows, and light keeps running along the lines for as
/// long as Astra is loading. There is no text and no finished still frame:
/// the mark keeps moving while the screen fades into the app.
struct LoadingView: View {
  /// The server being connected to ("Omega"), read out by VoiceOver only.
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
      TimelineView(.animation(minimumInterval: 1 / 60, paused: reduceMotion)) { context in
        AstraLoadingMark(time: context.date.timeIntervalSince(start), settled: reduceMotion)
      }
      .frame(width: Self.markSize, height: Self.markSize)
      .opacity(appeared ? 1 : 0)
    }
    .ignoresSafeArea()
    .onAppear {
      withAnimation(.easeOut(duration: 0.3)) { appeared = true }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(serverName.map { "Connecting to \($0)" } ?? "Connecting")
  }
}
