#if os(macOS)
  import AppKit
  import AstraKit
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
    /// Called when the window leaves the small floating size on its own
    /// (the person dragged it bigger), so the controls switch back.
    var onMiniChange: ((Bool) -> Void)?
    private var fittedToVideo = false

    init(over main: NSWindow, content: AnyView) {
      mainWindow = main
      let visible = (main.screen ?? NSScreen.main)?.visibleFrame ?? main.frame
      // A comfortable size centred on the app's window, not over all of it.
      let frame = PlayerGeometry.initialFrame(over: main.frame, visible: visible)
      let window = NSWindow(
        contentRect: frame,
        styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
        backing: .buffered, defer: false)
      window.setFrame(frame, display: false)
      // Drag it by the title-bar strip as well as by the video (WindowDragArea).
      window.isMovable = true
      window.title = "Astra"
      window.titleVisibility = .hidden
      window.titlebarAppearsTransparent = true
      window.backgroundColor = .black
      window.isReleasedWhenClosed = false
      window.collectionBehavior = [.fullScreenPrimary]
      // Small enough for the floating mini player.
      window.minSize = NSSize(width: 320, height: 180)
      window.appearance = NSAppearance(named: .darkAqua)

      let root = NSView(frame: NSRect(origin: .zero, size: frame.size))
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
      if isMini { _ = toggleMini() }
      window.toggleFullScreen(nil)
    }

    private(set) var isMini = false
    private var fullFrame: NSRect?

    /// Matches the window to the video's shape once its size is known, keeping
    /// the width (and the window on screen). Later resizes keep that shape.
    func fitVideo(width: Double, height: Double) {
      guard width > 0, height > 0 else { return }
      window.contentAspectRatio = NSSize(width: width, height: height)
      guard !fittedToVideo, !window.styleMask.contains(.fullScreen) else { return }
      fittedToVideo = true
      let visible = (window.screen ?? NSScreen.main)?.visibleFrame ?? window.frame
      let frame = PlayerGeometry.fit(window.frame, videoWidth: width, videoHeight: height, visible: visible)
      window.setFrame(frame, display: true, animate: false)
    }

    /// The small window was dragged to a normal size: it is a normal window again.
    func windowDidEndLiveResize(_ notification: Notification) {
      guard isMini, window.frame.width > 720 else { return }
      leaveMini(restoreFrame: false)
      onMiniChange?(false)
    }

    func windowWillEnterFullScreen(_ notification: Notification) {
      if isMini {
        leaveMini(restoreFrame: false)
        onMiniChange?(false)
      }
    }

    private func leaveMini(restoreFrame: Bool) {
      window.level = .normal
      window.collectionBehavior = [.fullScreenPrimary]
      if restoreFrame, let fullFrame { window.setFrame(fullFrame, display: true, animate: true) }
      fullFrame = nil
      isMini = false
    }

    /// Shrinks the player into a small window floating in the screen's
    /// bottom-right corner, above other windows and on every Space, or
    /// puts it back. Returns whether it is now small.
    func toggleMini() -> Bool {
      if window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
      if isMini {
        leaveMini(restoreFrame: true)
      } else {
        fullFrame = window.frame
        let visible = (window.screen ?? NSScreen.main)?.visibleFrame ?? window.frame
        let aspect = window.frame.height > 0 ? window.frame.width / window.frame.height : 16 / 9
        let frame = PlayerGeometry.miniFrame(aspect: aspect, visible: visible)
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.setFrame(frame, display: true, animate: true)
        isMini = true
      }
      return isMini
    }

    func windowWillClose(_ notification: Notification) {
      guard !closingFromCode else { return }
      // The window is already closing; the controller's dismiss() must not close it again.
      closingFromCode = true
      onUserClose?()
    }
  }

  /// The empty part of the player (under the controls): drag moves the
  /// window, a click pauses, a double-click goes full screen.
  struct WindowDragArea: NSViewRepresentable {
    var onClick: () -> Void
    var onDoubleClick: () -> Void

    func makeNSView(context: Context) -> DragView {
      let view = DragView()
      view.onClick = onClick
      view.onDoubleClick = onDoubleClick
      return view
    }

    func updateNSView(_ view: DragView, context: Context) {
      view.onClick = onClick
      view.onDoubleClick = onDoubleClick
    }

    final class DragView: NSView {
      var onClick: (() -> Void)?
      var onDoubleClick: (() -> Void)?
      private var pendingClick: DispatchWorkItem?

      override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

      private var dragStart: (mouse: NSPoint, origin: NSPoint)?
      private var dragged = false

      override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 {
          pendingClick?.cancel()
          pendingClick = nil
          dragStart = nil
          onDoubleClick?()
          return
        }
        dragged = false
        dragStart = window.map { (NSEvent.mouseLocation, $0.frame.origin) }
      }

      override func mouseDragged(with event: NSEvent) {
        guard let window, let dragStart, !window.styleMask.contains(.fullScreen) else { return }
        let now = NSEvent.mouseLocation
        let dx = now.x - dragStart.mouse.x
        let dy = now.y - dragStart.mouse.y
        if !dragged, abs(dx) + abs(dy) < 3 { return }
        dragged = true
        window.setFrameOrigin(NSPoint(x: dragStart.origin.x + dx, y: dragStart.origin.y + dy))
      }

      override func mouseUp(with event: NSEvent) {
        defer { dragStart = nil }
        guard dragStart != nil, !dragged, event.clickCount == 1 else { return }
        // A click, unless a second one makes it a double-click.
        let click = DispatchWorkItem { [weak self] in self?.onClick?() }
        pendingClick = click
        DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval, execute: click)
      }
    }
  }
#endif
