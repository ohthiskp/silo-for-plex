import CoreGraphics
import Foundation

/// Where the Mac player window goes and how big it is. Pure maths, so it is tested.
public enum PlayerGeometry {
  /// A comfortable 16:9 window centred on the app's window, not covering all
  /// of it: 70% of its width, between 640 and 1280 pt, kept on screen.
  public static func initialFrame(over main: CGRect, visible: CGRect) -> CGRect {
    let width = min(1280, max(640, main.width * 0.7), visible.width - 40)
    let height = min(width * 9 / 16, visible.height - 40)
    let size = CGSize(width: height * 16 / 9, height: height)
    return clamp(
      CGRect(x: main.midX - size.width / 2, y: main.midY - size.height / 2, width: size.width, height: size.height),
      to: visible)
  }

  /// `frame` reshaped to the video's aspect ratio around its centre, keeping
  /// its width unless that would be taller than the screen.
  public static func fit(_ frame: CGRect, videoWidth: Double, videoHeight: Double, visible: CGRect) -> CGRect {
    guard videoWidth > 0, videoHeight > 0 else { return frame }
    var width = frame.width
    var height = width * videoHeight / videoWidth
    if height > visible.height - 40 {
      height = visible.height - 40
      width = height * videoWidth / videoHeight
    }
    return clamp(
      CGRect(x: frame.midX - width / 2, y: frame.midY - height / 2, width: width, height: height), to: visible)
  }

  /// The floating mini window: 400 pt wide, the video's shape, bottom-right corner.
  public static func miniFrame(aspect: Double, visible: CGRect) -> CGRect {
    let size = CGSize(width: 400, height: (400 / max(aspect, 0.1)).rounded())
    return CGRect(x: visible.maxX - size.width - 20, y: visible.minY + 20, width: size.width, height: size.height)
  }

  static func clamp(_ frame: CGRect, to visible: CGRect) -> CGRect {
    var f = frame
    f.origin.x = min(max(f.origin.x, visible.minX + 20), visible.maxX - f.width - 20)
    f.origin.y = min(max(f.origin.y, visible.minY + 20), visible.maxY - f.height - 20)
    return f
  }

  /// How far the player's control panel may be dragged from where it rests:
  /// `offset` limited so the panel (`panel`, its resting frame) stays inside
  /// `bounds` with `margin` to spare on every side.
  public static func panelOffset(_ offset: CGSize, panel: CGRect, in bounds: CGRect, margin: CGFloat = 12) -> CGSize {
    let area = bounds.insetBy(dx: margin, dy: margin)
    func limit(_ value: CGFloat, low: CGFloat, high: CGFloat) -> CGFloat {
      low > high ? (low + high) / 2 : min(high, max(low, value))
    }
    return CGSize(
      width: limit(offset.width, low: area.minX - panel.minX, high: area.maxX - panel.maxX),
      height: limit(offset.height, low: area.minY - panel.minY, high: area.maxY - panel.maxY))
  }
}
