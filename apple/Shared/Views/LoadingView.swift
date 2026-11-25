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

  /// How far right of its square's centre the arrow's visible shape sits, as a share of the square.
  static let opticalShift: CGFloat = 0.04

  var body: some View {
    ZStack {
      Astra.Color.bg
      TimelineView(.animation(minimumInterval: 1 / 60, paused: reduceMotion)) { context in
        AstraLoadingMark(time: context.date.timeIntervalSince(start), settled: reduceMotion)
      }
      .frame(width: Self.markSize, height: Self.markSize)
      // The arrow's visible shape sits right of its square (the speed lines
      // fade out to the left), so it read as off centre on the narrow iPhone
      // and Mac screens (KP, 2026-11-25). Moved left by that much.
      .offset(x: -Self.markSize * Self.opticalShift)
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
