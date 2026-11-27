#if os(macOS)
  import AppKit
  import AstraKit
  import SwiftUI

  /// The Mac player's window, laid exactly over the app's window so playback
  /// happens inside the app (KP, 2026-11-25: "dont make mac player another
  /// external box just leave it in the app if u exit it just goes back").
  ///
  /// The shared mpv core puts its video layer at the bottom of the window's
  /// content view layer. Under Flutter that view is a plain NSView. A SwiftUI
  /// window's content view is an NSHostingView, which owns its sublayers and
  /// drops a foreign layer when it redraws, so video never showed. This
  /// window's content view is a plain layer-backed NSView: the video layer
  /// sits at the bottom and the SwiftUI controls are a transparent hosting
  /// view on top of it, the same layering the Flutter app uses.
  ///
  /// It is a child of the app's window: it moves, resizes and goes full
  /// screen with it, has the same rounded corners, and closing the player
  /// leaves the app where it was. Only the small floating player (the Mac's
  /// picture in picture) leaves the app's window.
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
    /// The player put the app's window into full screen (F); it leaves full
    /// screen again when the player closes.
    private var enteredFullScreen = false
    private var observers: [NSObjectProtocol] = []
    /// While matching one window's frame to the other's.
    private var syncing = false

    init(over main: NSWindow, content: AnyView) {
      mainWindow = main
      let frame = main.frame
      let window = NSWindow(
        contentRect: frame,
        styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
        backing: .buffered, defer: false)
      window.setFrame(frame, display: false)
      window.isMovable = true
      window.title = "Astra"
      window.titleVisibility = .hidden
      window.titlebarAppearsTransparent = true
      window.backgroundColor = .black
      window.isReleasedWhenClosed = false
      // Full screen is the app window's (F and the green button go to it).
      window.collectionBehavior = [.fullScreenAuxiliary, .fullScreenNone]
      window.minSize = main.minSize
      window.appearance = NSAppearance(named: .darkAqua)
      window.standardWindowButton(.zoomButton)?.isEnabled = true

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
      // The green button fills the screen with the app (and the player in it).
      if let zoom = window.standardWindowButton(.zoomButton) {
        zoom.target = self
        zoom.action = #selector(zoomPressed)
      }
    }

    @objc private func zoomPressed() { toggleFullScreen() }

    func show() {
      guard let main = mainWindow else {
        window.makeKeyAndOrderFront(nil)
        return
      }
      window.setFrame(main.frame, display: false)
      main.addChildWindow(window, ordered: .above)
      window.makeKeyAndOrderFront(nil)
      // The app's window moving, resizing or changing full screen: the player follows.
      let center = NotificationCenter.default
      for name in [
        NSWindow.didResizeNotification, NSWindow.didMoveNotification,
        NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification,
      ] {
        observers.append(
          center.addObserver(forName: name, object: main, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.followMain() }
          })
      }
    }

    /// Lays the player over the app's window again.
    private func followMain() {
      guard !isMini, !syncing, let main = mainWindow, window.frame != main.frame else { return }
      syncing = true
      window.setFrame(main.frame, display: true)
      syncing = false
    }

    /// The person resized the player by its edge: the app's window takes the same size.
    func windowDidResize(_ notification: Notification) {
      guard !isMini, !syncing, let main = mainWindow, main.frame != window.frame,
        !main.styleMask.contains(.fullScreen)
      else { return }
      syncing = true
      main.setFrame(window.frame, display: true)
      syncing = false
    }

    func windowDidMove(_ notification: Notification) {
      guard !isMini, !syncing, let main = mainWindow, main.frame.origin != window.frame.origin,
        !main.styleMask.contains(.fullScreen)
      else { return }
      syncing = true
      main.setFrameOrigin(window.frame.origin)
      syncing = false
    }

    func dismiss() {
      let alreadyClosing = closingFromCode
      closingFromCode = true
      window.delegate = nil
      for observer in observers { NotificationCenter.default.removeObserver(observer) }
      observers = []
      mainWindow?.removeChildWindow(window)
      if !alreadyClosing {
        window.orderOut(nil)
        window.close()
      }
      if enteredFullScreen, let main = mainWindow, main.styleMask.contains(.fullScreen) {
        main.toggleFullScreen(nil)
      }
      mainWindow?.makeKeyAndOrderFront(nil)
    }

    func toggleFullScreen() {
      if isMini { _ = toggleMini() }
      guard let main = mainWindow else { return }
      enteredFullScreen = !main.styleMask.contains(.fullScreen)
      main.toggleFullScreen(nil)
      window.makeKeyAndOrderFront(nil)
    }

    private(set) var isMini = false
    private var videoAspect: Double?

    /// The video's shape, for the small floating window. The player in the
    /// app keeps the app window's size and letterboxes.
    func fitVideo(width: Double, height: Double) {
      guard width > 0, height > 0 else { return }
      videoAspect = width / height
      if isMini { window.contentAspectRatio = NSSize(width: width, height: height) }
    }

    /// The small window was dragged to a normal size: it goes back into the app.
    func windowDidEndLiveResize(_ notification: Notification) {
      guard isMini, window.frame.width > 720 else { return }
      leaveMini()
      onMiniChange?(false)
    }

    private func leaveMini() {
      isMini = false
      window.level = .normal
      window.collectionBehavior = [.fullScreenAuxiliary, .fullScreenNone]
      window.contentResizeIncrements = NSSize(width: 1, height: 1)
      if let main = mainWindow {
        syncing = true
        window.setFrame(main.frame, display: true, animate: true)
        syncing = false
        main.addChildWindow(window, ordered: .above)
      }
      window.makeKeyAndOrderFront(nil)
    }

    /// Shrinks the player into a small window floating in the screen's
    /// bottom-right corner, above other windows and on every Space, or
    /// puts it back into the app. Returns whether it is now small.
    func toggleMini() -> Bool {
      if isMini {
        leaveMini()
      } else {
        if let main = mainWindow, main.styleMask.contains(.fullScreen) {
          enteredFullScreen = false
          main.toggleFullScreen(nil)
        }
        mainWindow?.removeChildWindow(window)
        let visible = (window.screen ?? NSScreen.main)?.visibleFrame ?? window.frame
        let aspect = videoAspect ?? 16 / 9
        let frame = PlayerGeometry.miniFrame(aspect: aspect, visible: visible)
        isMini = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentAspectRatio = NSSize(width: aspect, height: 1)
        window.setFrame(frame, display: true, animate: true)
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

  /// The empty part of the player (under the controls): a click pauses, a
  /// double-click goes full screen. Dragging here does nothing; the window
  /// stays where it is.
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

      override var mouseDownCanMoveWindow: Bool { false }

      override func mouseDown(with event: NSEvent) {
        // The window still moves from its title strip, and the small floating
        // window moves from anywhere (it has nothing else to grab).
        if let window, !window.styleMask.contains(.fullScreen), event.clickCount == 1 {
          let point = convert(event.locationInWindow, from: nil)
          let fromTop = isFlipped ? point.y : bounds.height - point.y
          if fromTop < 32 || window.level != .normal {
            window.performDrag(with: event)
            return
          }
        }
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
        // A drag isn't a click, but it no longer moves the window.
        guard let dragStart else { return }
        let now = NSEvent.mouseLocation
        if abs(now.x - dragStart.mouse.x) + abs(now.y - dragStart.mouse.y) >= 3 { dragged = true }
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
