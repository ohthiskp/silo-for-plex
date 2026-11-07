import SwiftUI

/// The launch screen, in white and grey only. The ASTRA wordmark sits in the
/// middle with a soft band of light sweeping across it while Astra connects;
/// under it a hairline that breathes. When the server answers, the line draws
/// out to full width and "Connected" fades in.
struct LoadingView: View {
  /// True once the server answered; shows "Connected".
  var connected: Bool

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var start = Date()
  @State private var appeared = false

  var body: some View {
    ZStack {
      Astra.Color.bg

      VStack(spacing: 22) {
        wordmark
        line
        Text("Connected")
          .font(.system(size: 13, weight: .medium))
          .tracking(2)
          .foregroundStyle(Astra.Color.muted)
          .opacity(connected ? 1 : 0)
          .offset(y: connected || reduceMotion ? 0 : 4)
          .animation(.easeOut(duration: 0.45), value: connected)
      }
      .opacity(appeared ? 1 : 0)
      .scaleEffect(appeared || reduceMotion ? 1 : 0.98)
    }
    .ignoresSafeArea()
    .onAppear {
      withAnimation(.easeOut(duration: 0.6)) { appeared = true }
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(connected ? "Connected" : "Connecting")
  }

  /// ASTRA in grey, with a band of white light passing over it every 2.4 s.
  private var wordmark: some View {
    let text = Text("ASTRA").font(Astra.Font.display(44)).tracking(18)
    return text
      .foregroundStyle(.white.opacity(0.28))
      .overlay {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: reduceMotion || connected)) { context in
          let t = context.date.timeIntervalSince(start)
          // 0 → 1 across the word, then a short rest.
          let phase = connected ? 1.2 : (t.truncatingRemainder(dividingBy: 2.4)) / 2.0
          GeometryReader { geo in
            LinearGradient(
              colors: [.clear, .white, .clear], startPoint: .leading, endPoint: .trailing
            )
            .frame(width: geo.size.width * 0.45)
            .offset(x: (phase * 1.6 - 0.45) * geo.size.width)
          }
          .mask(text)
        }
        .opacity(connected ? 0 : 1)
      }
      .overlay {
        // Fully lit once connected.
        text.foregroundStyle(.white).opacity(connected ? 1 : 0)
      }
      .animation(.easeOut(duration: 0.5), value: connected)
  }

  /// A hairline under the word: a short segment breathing while connecting,
  /// drawn out to the word's width when connected.
  private var line: some View {
    TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || connected)) { context in
      let t = context.date.timeIntervalSince(start)
      let breath = 0.5 + 0.5 * sin(t * 2.2)
      Capsule()
        .fill(.white.opacity(connected ? 0.9 : 0.25 + 0.35 * breath))
        .frame(width: connected ? 180 : 28 + 24 * breath, height: 1.5)
        .frame(width: 180)
        .animation(.easeInOut(duration: 0.6), value: connected)
    }
  }
}
