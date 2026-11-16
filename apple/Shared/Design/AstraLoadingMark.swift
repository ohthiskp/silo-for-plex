import SwiftUI

extension Astra.Color {
  /// The app icon's orange, dark end and bright end. Used only by the
  /// loading mark (KP, 2026-11-16); everything else in the app stays neutral.
  static let brandCopper = SwiftUI.Color(hex: 0xB04E24)
  static let brandAmber = SwiftUI.Color(hex: 0xF59E54)
  /// The light that runs along the speed lines while Astra loads.
  static let brandShine = SwiftUI.Color(hex: 0xFFD6AA)
}

/// The app icon's orange arrow, animated for the loading screen (KP,
/// 2026-11-16). `time` is seconds since the screen appeared: the speed lines
/// shoot in from the left one after another, the arrow head slides in behind
/// them, then light keeps running along the lines. `settled` draws the
/// finished mark, fully lit and still.
struct AstraLoadingMark: View {
  var time: Double
  var settled: Bool

  /// The lines' right ends as a share of the width, top to bottom, following the icon.
  private static let ends: [CGFloat] = [0.48, 0.60, 0.665, 0.60, 0.69, 0.545, 0.465, 0.41]
  private static let left: CGFloat = 0.17
  /// Seconds between one line starting and the next.
  private static let stagger = 0.06
  private static let lineSeconds = 0.6
  /// When the light starts running, and how long one pass takes.
  private static let shineStart = 0.9
  private static let shinePeriod = 1.8

  private static func easeOut(_ x: Double) -> Double {
    let c = min(1, max(0, x))
    return 1 - pow(1 - c, 3)
  }

  var body: some View {
    Canvas { context, size in
      let s = min(size.width, size.height)
      let copper = Astra.Color.brandCopper
      let amber = Astra.Color.brandAmber
      let shine = Astra.Color.brandShine

      // The arrow head, sliding in behind the lines.
      let headIn = settled ? 1 : Self.easeOut((time - 0.35) / 0.7)
      if headIn > 0 {
        let dx = CGFloat(1 - headIn) * -s * 0.16
        let beat = 0.5 + 0.5 * sin((time - 1) * 2 * .pi / Self.shinePeriod - .pi / 2)
        let lit = settled ? 1 : 0.62 + 0.38 * (time > 1 ? beat : 0)
        let a = CGPoint(x: s * 0.50 + dx, y: s * 0.275)
        let b = CGPoint(x: s * 0.885 + dx, y: s * 0.50)
        let c = CGPoint(x: s * 0.40 + dx, y: s * 0.79)
        let radius = s * 0.045
        var head = Path()
        head.move(to: CGPoint(x: (c.x + a.x) / 2, y: (c.y + a.y) / 2))
        head.addArc(tangent1End: a, tangent2End: b, radius: radius)
        head.addArc(tangent1End: b, tangent2End: c, radius: radius)
        head.addArc(tangent1End: c, tangent2End: a, radius: radius)
        head.closeSubpath()
        context.fill(
          head,
          with: .linearGradient(
            Gradient(stops: [
              .init(color: copper.opacity(0), location: 0),
              .init(color: copper.opacity(0.6 * headIn * lit), location: 0.5),
              .init(color: amber.opacity(0.8 * headIn * lit), location: 1),
            ]),
            startPoint: CGPoint(x: s * 0.43 + dx, y: 0), endPoint: CGPoint(x: s * 0.885 + dx, y: 0)))
      }

      // The speed lines.
      let count = Self.ends.count
      let top = s * 0.215
      let step = (s * 0.785 - top) / CGFloat(count)
      let bar = step * 0.5
      for (i, end) in Self.ends.enumerated() {
        let k = settled ? 1 : Self.easeOut((time - Self.stagger * Double(i)) / Self.lineSeconds)
        guard k > 0 else { continue }
        let right = s * end
        let length = (right - s * Self.left) * CGFloat(k)
        guard length > 1 else { continue }
        let x = right - length - CGFloat(1 - k) * s * 0.25
        let y = top + CGFloat(i) * step + (step - bar) / 2
        let rect = CGRect(x: x, y: y, width: length, height: bar)
        let line = Path(roundedRect: rect, cornerRadius: bar / 2)
        context.fill(
          line,
          with: .linearGradient(
            Gradient(stops: [
              .init(color: copper.opacity(0), location: 0),
              .init(color: copper.opacity(0.8 * k), location: 0.55),
              .init(color: amber.opacity(k), location: 1),
            ]),
            startPoint: CGPoint(x: rect.minX, y: 0), endPoint: CGPoint(x: rect.maxX, y: 0)))

        // The light: a soft bright band running left to right, each line a little behind the one above.
        guard !settled, time > Self.shineStart else { continue }
        let turns = (time - Self.shineStart) / Self.shinePeriod - Double(i) * 0.07
        let phase = turns - floor(turns)
        let along = phase * 1.5 - 0.25
        let strength = 0.7 * min(1, max(0, along))
        guard strength > 0.01 else { continue }
        let centre = rect.minX + length * CGFloat(along)
        let half = length * 0.3
        var clipped = context
        clipped.clip(to: line)
        clipped.fill(
          Path(rect),
          with: .linearGradient(
            Gradient(colors: [shine.opacity(0), shine.opacity(strength), shine.opacity(0)]),
            startPoint: CGPoint(x: centre - half, y: 0), endPoint: CGPoint(x: centre + half, y: 0)))
      }
    }
    .aspectRatio(1, contentMode: .fit)
    .accessibilityHidden(true)
  }
}
