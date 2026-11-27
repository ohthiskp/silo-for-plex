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
      let headIn: Double = settled ? 1 : Self.easeOut((time - 0.35) / 0.7)
      if headIn > 0 {
        let dx: CGFloat = -s * 0.16 * CGFloat(1 - headIn)
        let angle: Double = (time - 1) / Self.shinePeriod * 2 * Double.pi - Double.pi / 2
        let beat: Double = time > 1 ? 0.5 + 0.5 * sin(angle) : 0
        let lit: Double = settled ? 1 : 0.62 + 0.38 * beat
        let midAlpha: Double = 0.6 * headIn * lit
        let tipAlpha: Double = 0.8 * headIn * lit
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
              .init(color: copper.opacity(midAlpha), location: 0.5),
              .init(color: amber.opacity(tipAlpha), location: 1),
            ]),
            startPoint: CGPoint(x: s * 0.43 + dx, y: 0), endPoint: CGPoint(x: s * 0.885 + dx, y: 0)))
      }

      // The speed lines.
      let count = Self.ends.count
      let top: CGFloat = s * 0.215
      let step: CGFloat = (s * 0.785 - top) / CGFloat(count)
      let bar: CGFloat = step * 0.5
      for (i, end) in Self.ends.enumerated() {
        let delay: Double = Self.stagger * Double(i)
        let k: Double = settled ? 1 : Self.easeOut((time - delay) / Self.lineSeconds)
        guard k > 0 else { continue }
        let right: CGFloat = s * end
        let full: CGFloat = right - s * Self.left
        let length: CGFloat = full * CGFloat(k)
        guard length > 1 else { continue }
        let slide: CGFloat = s * 0.25 * CGFloat(1 - k)
        let x: CGFloat = right - length - slide
        let y: CGFloat = top + CGFloat(i) * step + (step - bar) / 2
        let rect = CGRect(x: x, y: y, width: length, height: bar)
        let line = Path(roundedRect: rect, cornerRadius: bar / 2)
        let bodyAlpha: Double = 0.8 * k
        context.fill(
          line,
          with: .linearGradient(
            Gradient(stops: [
              .init(color: copper.opacity(0), location: 0),
              .init(color: copper.opacity(bodyAlpha), location: 0.55),
              .init(color: amber.opacity(k), location: 1),
            ]),
            startPoint: CGPoint(x: rect.minX, y: 0), endPoint: CGPoint(x: rect.maxX, y: 0)))

        // The light: a soft bright band running left to right, each line a little behind the one above.
        guard !settled, time > Self.shineStart else { continue }
        let turns: Double = (time - Self.shineStart) / Self.shinePeriod - Double(i) * 0.07
        let phase: Double = turns - turns.rounded(.down)
        let along: Double = phase * 1.5 - 0.25
        let strength: Double = 0.7 * min(1, max(0, along))
        guard strength > 0.01 else { continue }
        let centre: CGFloat = rect.minX + length * CGFloat(along)
        let half: CGFloat = length * 0.3
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
