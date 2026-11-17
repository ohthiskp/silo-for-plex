import Foundation

/// Where a backdrop goes so the people in it end above the title logo
/// (KP, 2026-11-09: "the logo goes over the faces"). Pure maths, so it is
/// the same on iPhone and Mac and covered by tests.
public enum ArtFraming {
  /// Faces spread wider than this share of the picture aren't one subject.
  public static let groupWidth: CGFloat = 0.3
  /// The smallest share of the art area the picture may shrink to.
  public static let minShare: Double = 0.55

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
      // screen, and never below `minShare` of the art area (a blurred copy
      // fills in below). KP (2026-11-14): with the bigger logo, faces must
      // still clear it, so the picture may shrink further than before.
      let minHeight = min(cover, max(boxWidth / aspect, (zoneHeight - topOffset) * Self.minShare))
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
    // One face or a tight group is centred across the screen. A wide spread
    // of faces (a crowded poster like Mario's) keeps the picture's own
    // centre, where the artist put the main subject (KP, 2026-11-09:
    // "Super Mario isn't even centered").
    let centre = focus.flatMap { $0.width <= Self.groupWidth ? Double($0.midX) : nil } ?? fallbackX
    let left = min(0, max(boxWidth - width, boxWidth / 2 - centre * width))
    return CGRect(x: left, y: top, width: width, height: height)
  }

  /// Apple TV's hero (KP, 2026-11-16): the title's logo and buttons sit on the
  /// left, the sharp art sits to the right and the rest is a soft blur. The
  /// art slides right only as far as it must for the faces (or main subject)
  /// to clear the logo block, between `minX` and `maxX`, so it is never pushed
  /// hard against the right edge.
  ///
  /// - Parameters:
  ///   - boxWidth, boxHeight: the hero; the art is drawn `boxHeight` tall.
  ///   - aspect: the picture's width / height.
  ///   - clearX: faces should start right of this line (the logo block's edge).
  ///   - rightMargin: faces should end this far from the right edge.
  ///   - minX, maxX: how far right the picture's left edge may sit.
  ///   - defaultX: where it sits when nothing was found in the picture.
  ///   - focus: the faces (or main subject), normalized, top-left origin.
  ///   - push: 0 moves the faces just past `clearX`; 1 moves them as far right
  ///     as they fit (KP, 2026-11-16, Avatar: "the faces are too close… it
  ///     should be on the right side").
  public static func side(
    boxWidth: Double, boxHeight: Double, aspect: Double, clearX: Double, rightMargin: Double = 40,
    minX: Double, maxX: Double, defaultX: Double, focus: CGRect? = nil, push: Double = 0
  ) -> CGRect {
    guard boxWidth > 0, boxHeight > 0, aspect > 0, maxX >= minX else { return .zero }
    let width = boxHeight * aspect
    var x = defaultX
    if let focus, focus.width > 0 {
      let region = boxWidth - rightMargin - clearX
      let faceWidth = Double(focus.width) * width
      if faceWidth <= region {
        // Just far enough right that the faces start past the logo block,
        // and never so far that they run off the right edge.
        let clear = clearX - Double(focus.minX) * width
        let onScreen = boxWidth - rightMargin - Double(focus.maxX) * width
        x = max(minX, min(clear, onScreen))
        x = max(x, min(defaultX, onScreen))
        if onScreen > x { x += (onScreen - x) * min(max(push, 0), 1) }
      } else {
        // Too many faces to clear the block: centre them in the space right
        // of it, or with `push`, move them toward the right edge.
        let centred = clearX + region / 2 - Double(focus.midX) * width
        let rightmost = boxWidth - rightMargin - Double(focus.maxX) * width
        x = centred + (rightmost - centred) * min(max(push, 0), 1)
      }
    }
    x = min(maxX, max(minX, x))
    return CGRect(x: x, y: 0, width: width, height: boxHeight)
  }
}
