import Foundation

/// Where a backdrop goes so the people in it end above the title logo
/// (KP, 2026-11-09: "the logo goes over the faces"). Pure maths, so it is
/// the same on iPhone and Mac and covered by tests.
public enum ArtFraming {
  /// The rect to draw an image of `aspect` (width / height) in, inside a box
  /// `boxWidth` wide whose art area is `zoneHeight` tall.
  ///
  /// - Parameters:
  ///   - limitY: the faces must end above this line (the top of the logo slot).
  ///   - topOffset: where the image starts by default (room for the top blur).
  ///   - minTop: the faces may slide up, but never above this line.
  ///   - focus: the faces (or main subject), normalized 0…1 with a top-left
  ///     origin; nil draws a plain top-anchored cover crop.
  ///   - fallbackX: the horizontal centre to keep when there is no focus.
  public static func frame(
    boxWidth: Double, zoneHeight: Double, aspect: Double, limitY: Double,
    topOffset: Double = 0, minTop: Double = -.infinity, focus: CGRect? = nil, fallbackX: Double = 0.5
  ) -> CGRect {
    guard boxWidth > 0, zoneHeight > 0, aspect > 0 else { return .zero }
    // Cover the art area by default.
    let cover = max(zoneHeight - topOffset, boxWidth / aspect)
    var height = cover
    var top = topOffset
    if let focus, focus.maxY > 0 {
      // Shrink until the faces end above the logo, but never narrower than the
      // screen, and never below three quarters of the art area.
      let minHeight = min(cover, max(boxWidth / aspect, (zoneHeight - topOffset) * 0.75))
      let wanted = (limitY - top) / Double(focus.maxY)
      height = min(cover, max(minHeight, wanted))
      // Still too low: slide the image up, without pushing the faces under the top bar.
      let bottom = top + Double(focus.maxY) * height
      if bottom > limitY {
        let room = max(0, top + Double(focus.minY) * height - minTop)
        top -= min(bottom - limitY, room)
      }
    }
    let width = height * aspect
    let centre = focus.map { Double($0.midX) } ?? fallbackX
    let left = min(0, max(boxWidth - width, boxWidth / 2 - centre * width))
    return CGRect(x: left, y: top, width: width, height: height)
  }
}
