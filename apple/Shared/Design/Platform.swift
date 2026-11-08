import SwiftUI

#if os(macOS)
  import AppKit
  typealias PlatformImage = NSImage
  typealias PlatformWindow = NSWindow
#else
  import UIKit
  typealias PlatformImage = UIImage
  typealias PlatformWindow = UIWindow
#endif

extension Image {
  init(platformImage: PlatformImage) {
    #if os(macOS)
      self.init(nsImage: platformImage)
    #else
      self.init(uiImage: platformImage)
    #endif
  }
}

extension PlatformImage {
  static func decoded(_ cgImage: CGImage) -> PlatformImage {
    #if os(macOS)
      NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    #else
      UIImage(cgImage: cgImage)
    #endif
  }

  /// Pixel area, for the cache's cost.
  var pixelArea: Int {
    #if os(macOS)
      Int(size.width * size.height)
    #else
      Int(size.width * scale * size.height * scale)
    #endif
  }
}

/// Reports the hosting window, which the player draws video beneath.
struct WindowAccessor: View {
  var onWindow: (PlatformWindow?) -> Void

  var body: some View {
    Representable(onWindow: onWindow).frame(width: 0, height: 0).allowsHitTesting(false)
  }

  #if os(macOS)
    struct Representable: NSViewRepresentable {
      var onWindow: (NSWindow?) -> Void
      func makeNSView(context: Context) -> ReportingView {
        let view = ReportingView()
        view.onWindow = onWindow
        return view
      }
      func updateNSView(_ nsView: ReportingView, context: Context) {}

      final class ReportingView: NSView {
        var onWindow: ((NSWindow?) -> Void)?
        override func viewDidMoveToWindow() {
          super.viewDidMoveToWindow()
          window?.backgroundColor = .black
          onWindow?(window)
        }
      }
    }
  #else
    struct Representable: UIViewRepresentable {
      var onWindow: (UIWindow?) -> Void
      func makeUIView(context: Context) -> ReportingView {
        let view = ReportingView()
        view.onWindow = onWindow
        return view
      }
      func updateUIView(_ uiView: ReportingView, context: Context) {}

      final class ReportingView: UIView {
        var onWindow: ((UIWindow?) -> Void)?
        override func didMoveToWindow() {
          super.didMoveToWindow()
          window?.backgroundColor = .black
          onWindow?(window)
        }
      }
    }
  #endif
}

extension PlatformImage {
  /// A UIImage / NSImage for a decoded frame.
  static func from(_ image: CGImage) -> PlatformImage {
    #if os(macOS)
      NSImage(cgImage: image, size: NSSize(width: image.width / 2, height: image.height / 2))
    #else
      UIImage(cgImage: image, scale: 2, orientation: .up)
    #endif
  }
}

// MARK: - tvOS

/// The size of a spinner or control. tvOS has no control sizes, so it keeps the system one there.
enum AstraControlSize {
  case mini, small, regular, large
}

extension View {
  @ViewBuilder func astraControlSize(_ size: AstraControlSize) -> some View {
    #if os(tvOS)
      self
    #else
      switch size {
      case .mini: controlSize(.mini)
      case .small: controlSize(.small)
      case .regular: controlSize(.regular)
      case .large: controlSize(.large)
      }
    #endif
  }
}

extension View {
  /// Apple TV: a row (or bar) the focus engine treats as one block, so up and
  /// down move between rows instead of jumping diagonally. Nothing elsewhere.
  @ViewBuilder func tvFocusSection() -> some View {
    #if os(tvOS)
      focusSection()
    #else
      self
    #endif
  }
}
