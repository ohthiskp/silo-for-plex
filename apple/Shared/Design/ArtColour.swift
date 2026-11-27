import CoreGraphics
import ImageIO
import SwiftUI

/// One colour taken from a picture, for the wash behind the iPhone Details
/// card (KP, 2026-11-26, like Plex: the art fades into one smooth colour of its
/// own instead of a blur). Kept in memory only.
@MainActor final class ArtColourStore {
  static let shared = ArtColourStore()

  private var cache: [String: ArtColour] = [:]
  private var running: [String: Task<ArtColour?, Never>] = [:]

  func cached(_ url: URL) -> ArtColour? { cache[ArtFocusStore.key(url)] }

  func colour(for url: URL) async -> ArtColour? {
    let key = ArtFocusStore.key(url)
    if let hit = cache[key] { return hit }
    if let task = running[key] { return await task.value }
    let small = ArtFocusStore.analysisURL(url)
    let task = Task.detached(priority: .utility) { () -> ArtColour? in
      guard let loaded = try? await URLSession.shared.data(from: small) else { return nil }
      return ArtColour.measure(loaded.0)
    }
    running[key] = task
    let result = await task.value
    running[key] = nil
    if let result {
      if cache.count > 200 { cache.removeAll() }
      cache[key] = result
    }
    return result
  }
}

/// A picture's colour as hue, saturation and brightness (0…1).
struct ArtColour: Sendable, Hashable {
  var hue: Double
  var saturation: Double
  var brightness: Double

  /// The top of the wash, right under the art: the art's own hue, a little
  /// richer, kept dark enough for white text.
  var top: Color {
    Color(hue: hue, saturation: washSaturation, brightness: 0.3)
  }

  /// The foot of the page: the same hue, near black.
  var bottom: Color {
    Color(hue: hue, saturation: washSaturation, brightness: 0.1)
  }

  /// Grey art stays grey; coloured art gets a little richer (never neon).
  private var washSaturation: Double {
    saturation < 0.08 ? saturation : min(max(saturation * 1.5, 0.3), 0.7)
  }

  /// The average colour of the picture's lower half (where the wash meets it).
  nonisolated static func measure(_ data: Data) -> ArtColour? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil), image.width > 0, image.height > 0
    else { return nil }
    let lower = image.cropping(
      to: CGRect(x: 0, y: image.height / 2, width: image.width, height: image.height - image.height / 2)) ?? image
    var pixel = [UInt8](repeating: 0, count: 4)
    let drawn = pixel.withUnsafeMutableBytes { buffer -> Bool in
      guard
        let context = CGContext(
          data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
      else { return false }
      context.interpolationQuality = .medium
      context.draw(lower, in: CGRect(x: 0, y: 0, width: 1, height: 1))
      return true
    }
    guard drawn else { return nil }
    return hsb(r: Double(pixel[0]) / 255, g: Double(pixel[1]) / 255, b: Double(pixel[2]) / 255)
  }

  nonisolated static func hsb(r: Double, g: Double, b: Double) -> ArtColour {
    let high = max(r, g, b)
    let low = min(r, g, b)
    let delta = high - low
    var hue = 0.0
    if delta > 0 {
      if high == r {
        hue = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
      } else if high == g {
        hue = (b - r) / delta + 2
      } else {
        hue = (r - g) / delta + 4
      }
      hue /= 6
      if hue < 0 { hue += 1 }
    }
    return ArtColour(hue: hue, saturation: high > 0 ? delta / high : 0, brightness: high)
  }
}
