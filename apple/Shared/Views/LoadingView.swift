import SwiftUI

/// The launch screen: a drifting band of stars that gathers into one violet
/// star while Astra connects, then "Connected" at the bottom.
struct LoadingView: View {
  /// True once the server answered; shows "Connected".
  var connected: Bool

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var start = Date()

  var body: some View {
    ZStack {
      LinearGradient(
        stops: [
          .init(color: Color(hex: 0x05040E), location: 0),
          .init(color: Color(hex: 0x0D0B2A), location: 0.45),
          .init(color: Color(hex: 0x1A1450), location: 1),
        ], startPoint: .top, endPoint: .bottom)

      TimelineView(.animation(minimumInterval: 1 / 60, paused: reduceMotion)) { context in
        let t = reduceMotion ? 6 : context.date.timeIntervalSince(start)
        Canvas { canvas, size in
          Starfield.draw(in: &canvas, size: size, time: t)
        }
      }
      .accessibilityHidden(true)

      VStack {
        Spacer()
        Text("Connected")
          .font(.system(size: 15, weight: .medium))
          .tracking(1.5)
          .foregroundStyle(.white.opacity(0.85))
          .opacity(connected ? 1 : 0)
          .offset(y: connected || reduceMotion ? 0 : 6)
          .animation(.easeOut(duration: 0.5), value: connected)
          .padding(.bottom, 56)
      }
    }
    .ignoresSafeArea()
    .accessibilityElement(children: .combine)
    .accessibilityLabel(connected ? "Connected" : "Connecting")
  }
}

/// The particles and the star, drawn in one Canvas pass.
enum Starfield {
  struct Particle {
    var x: Double
    var y: Double
    var radius: Double
    var drift: Double
    var twinkle: Double
    var pull: Double
    var swirl: Double
    var tint: Int
  }

  /// A fixed field, seeded so it looks the same every launch.
  static let particles: [Particle] = {
    var rng = SeededRandom(seed: 0xA57A)
    return (0..<320).map { i in
      let inBand = i % 5 != 0  // most stars sit in the bright band
      let y = inBand ? 0.46 + rng.gaussian() * 0.025 : rng.next()
      return Particle(
        x: rng.next(), y: y,
        radius: inBand ? 0.5 + rng.next() * 1.4 : 0.4 + rng.next() * 1.1,
        drift: (0.004 + rng.next() * 0.012) * (rng.next() < 0.5 ? -1 : 1),
        twinkle: rng.next() * .pi * 2,
        pull: 0.35 + rng.next() * 0.6,
        swirl: (rng.next() - 0.5) * 1.6,
        tint: Int(rng.next() * 3))
    }
  }()

  static let center = CGPoint(x: 0.5, y: 0.44)

  static func draw(in canvas: inout GraphicsContext, size: CGSize, time t: Double) {
    // 0 → 1 between 1.2 s and 3.6 s: the band gathers towards the centre.
    let gather = smoothstep((t - 1.2) / 2.4)
    // The star blooms as the stars arrive, then breathes.
    let bloom = smoothstep((t - 2.2) / 1.4)
    let breathe = 1 + 0.07 * sin(t * 2.1)
    let cx = center.x * size.width
    let cy = center.y * size.height
    let span = max(size.width, size.height)

    // Soft glow behind everything.
    if bloom > 0 {
      let r = span * 0.42 * bloom * breathe
      canvas.fill(
        Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)),
        with: .radialGradient(
          Gradient(colors: [Color(hex: 0x6A4BFF, opacity: 0.45 * bloom), Color(hex: 0x2A1E8C, opacity: 0)]),
          center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: r))
    }

    for p in particles {
      var x = (p.x + p.drift * t).truncatingRemainder(dividingBy: 1)
      if x < 0 { x += 1 }
      var px = x * size.width
      var py = p.y * size.height
      // Gather: move towards the centre along a slight spiral.
      let k = gather * p.pull * 0.85
      if k > 0 {
        let dx = px - cx
        let dy = py - cy
        let angle = p.swirl * gather
        let rx = dx * cos(angle) - dy * sin(angle)
        let ry = dx * sin(angle) + dy * cos(angle)
        px = cx + rx * (1 - k)
        py = cy + ry * (1 - k)
      }
      let flicker = 0.55 + 0.45 * sin(t * 2.4 + p.twinkle)
      let colour: Color =
        switch p.tint {
        case 0: .white
        case 1: Color(hex: 0xB9C8FF)
        default: Color(hex: 0xD9B8FF)
        }
      let r = p.radius
      canvas.fill(
        Path(ellipseIn: CGRect(x: px - r, y: py - r, width: r * 2, height: r * 2)),
        with: .color(colour.opacity(0.35 + 0.6 * flicker)))
    }

    // The star: a hot pink-white core with a violet halo.
    if bloom > 0 {
      let halo = span * 0.09 * bloom * breathe
      canvas.fill(
        Path(ellipseIn: CGRect(x: cx - halo, y: cy - halo, width: halo * 2, height: halo * 2)),
        with: .radialGradient(
          Gradient(stops: [
            .init(color: .white.opacity(bloom), location: 0),
            .init(color: Color(hex: 0xFF5BD8, opacity: 0.9 * bloom), location: 0.12),
            .init(color: Color(hex: 0x8A5CFF, opacity: 0.5 * bloom), location: 0.4),
            .init(color: Color(hex: 0x7C4DFF, opacity: 0), location: 1),
          ]),
          center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: halo))
      // A thin horizontal flare.
      let flare = span * 0.12 * bloom * breathe
      canvas.fill(
        Path(ellipseIn: CGRect(x: cx - flare, y: cy - 1.2, width: flare * 2, height: 2.4)),
        with: .linearGradient(
          Gradient(colors: [.clear, Color(hex: 0xFFC2F2, opacity: 0.7 * bloom), .clear]),
          startPoint: CGPoint(x: cx - flare, y: cy), endPoint: CGPoint(x: cx + flare, y: cy)))
    }
  }

  static func smoothstep(_ x: Double) -> Double {
    let c = min(1, max(0, x))
    return c * c * (3 - 2 * c)
  }
}

/// SplitMix64, so the star field is the same on every launch.
struct SeededRandom {
  private var state: UInt64

  init(seed: UInt64) { state = seed }

  /// A value in 0..<1.
  mutating func next() -> Double {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    z ^= z >> 31
    return Double(z >> 11) / Double(1 << 53)
  }

  /// Roughly normal, mean 0 and deviation 1.
  mutating func gaussian() -> Double {
    let u = max(next(), 1e-9)
    let v = next()
    return sqrt(-2 * log(u)) * cos(2 * .pi * v)
  }
}
