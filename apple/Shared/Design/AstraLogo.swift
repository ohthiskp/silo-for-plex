import SwiftUI

/// Astra's mark in white: a play arrow whose back half is speed lines, the
/// shape of the app icon without its colour. `lit` 0…1 is how bright it is;
/// `streak` 0…1 how far the lines have drawn in.
struct AstraLogo: View {
  var lit: Double = 1
  var streak: Double = 1

  /// The lines' right ends (as a share of the width) and their heights, top to bottom,
  /// following the icon.
  private static let lines: [CGFloat] = [0.48, 0.58, 0.64, 0.6, 0.66, 0.54, 0.47, 0.42]

  var body: some View {
    Canvas { context, size in
      let w = size.width
      let h = size.height
      let top = h * 0.24
      let bottom = h * 0.76
      let step = (bottom - top) / CGFloat(Self.lines.count)
      let barHeight = step * 0.58
      let left = w * 0.12

      // The arrow head.
      var head = Path()
      head.move(to: CGPoint(x: w * 0.5, y: h * 0.3))
      head.addLine(to: CGPoint(x: w * 0.86, y: h * 0.5))
      head.addLine(to: CGPoint(x: w * 0.5, y: h * 0.7))
      head.closeSubpath()
      let headShading = GraphicsContext.Shading.linearGradient(
        Gradient(colors: [.white.opacity(0.15 * lit), .white.opacity(lit)]),
        startPoint: CGPoint(x: w * 0.45, y: 0), endPoint: CGPoint(x: w * 0.86, y: 0))
      context.fill(head, with: headShading)
      context.stroke(head, with: headShading, style: StrokeStyle(lineWidth: w * 0.06, lineJoin: .round))

      // The speed lines, fading in from the left.
      for (i, end) in Self.lines.enumerated() {
        let y = top + CGFloat(i) * step + (step - barHeight) / 2
        let length = (w * end - left) * streak
        guard length > 1 else { continue }
        let rect = CGRect(x: w * end - length, y: y, width: length, height: barHeight)
        context.fill(
          Path(roundedRect: rect, cornerRadius: barHeight / 2),
          with: .linearGradient(
            Gradient(colors: [.white.opacity(0), .white.opacity(0.9 * lit)]),
            startPoint: CGPoint(x: rect.minX, y: 0), endPoint: CGPoint(x: rect.maxX, y: 0)))
      }
    }
    .aspectRatio(1, contentMode: .fit)
    .accessibilityLabel("Astra")
  }
}
