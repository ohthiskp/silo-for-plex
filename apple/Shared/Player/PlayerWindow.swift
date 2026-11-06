#if os(macOS)
  import AppKit
  import SwiftUI

  /// The Mac player's own window.
  ///
  /// The shared mpv core puts its video layer at the bottom of the window's
  /// content view layer. Under Flutter that view is a plain NSView. A SwiftUI
  /// window's content view is an NSHostingView, which owns its sublayers and
  /// drops a foreign layer when it redraws, so video never showed. This
  /// window's content view is a plain layer-backed NSView: the video layer
  /// sits at the bottom and the SwiftUI controls are a transparent hosting
  /// view on top of it, the same layering the Flutter app uses.
  @MainActor
  final class PlayerWindowHost: NSObject, NSWindowDelegate {
    let window: NSWindow
    private weak var mainWindow: NSWindow?
    private var closingFromCode = false
    /// Called when the person closes the window itself (red button, ⌘W).
    var onUserClose: (() -> Void)?

    init(over main: NSWindow, content: AnyView) {
      mainWindow = main
      let window = NSWindow(
        contentRect: main.frame,
        styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
        backing: .buffered, defer: false)
      window.setFrame(main.frame, display: false)
      window.title = "Astra"
      window.titleVisibility = .hidden
      window.titlebarAppearsTransparent = true
      window.backgroundColor = .black
      window.isReleasedWhenClosed = false
      window.collectionBehavior = [.fullScreenPrimary]
      window.minSize = main.minSize
      window.appearance = NSAppearance(named: .darkAqua)

      let root = NSView(frame: NSRect(origin: .zero, size: main.frame.size))
      root.wantsLayer = true
      root.layer?.backgroundColor = NSColor.black.cgColor
      let hosting = NSHostingView(rootView: content)
      hosting.frame = root.bounds
      hosting.autoresizingMask = [.width, .height]
      root.addSubview(hosting)
      window.contentView = root
      self.window = window
      super.init()
      window.delegate = self
    }

    func show() {
      window.makeKeyAndOrderFront(nil)
      // Follow the main window into full screen.
      if mainWindow?.styleMask.contains(.fullScreen) == true, !window.styleMask.contains(.fullScreen) {
        window.toggleFullScreen(nil)
      }
    }

    func dismiss() {
      let alreadyClosing = closingFromCode
      closingFromCode = true
      window.delegate = nil
      if !alreadyClosing {
        window.orderOut(nil)
        window.close()
      }
      mainWindow?.makeKeyAndOrderFront(nil)
    }

    func toggleFullScreen() {
      window.toggleFullScreen(nil)
    }

    func windowWillClose(_ notification: Notification) {
      guard !closingFromCode else { return }
      // The window is already closing; the controller's dismiss() must not close it again.
      closingFromCode = true
      onUserClose?()
    }
  }
#endif
