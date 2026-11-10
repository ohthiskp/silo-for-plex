#if os(tvOS)
  import AstraKit
  import SwiftUI
  import UIKit

  /// Apple TV: hosts the player on the TV (the window the video draws under,
  /// and the Siri Remote) with the player's controls as `content`. Design
  /// owns what `content` looks like; this only gives it the remote.
  ///
  /// The remote, as KP asked (2026-11-08):
  /// - click: play or pause (and show the controls); while scrubbing, jump there
  /// - Play/Pause button: play or pause
  /// - left / right on the click pad: back / forward 10 s
  /// - swipe on the touch surface: scrub, with seek previews; click to jump
  /// - Menu (Back): cancel a scrub, else hide the controls, else close the player
  ///
  /// While `remoteEnabled` is false (focus is on one of the controls, such as
  /// the captions or Next Episode button), clicks go to that control instead.
  struct TVPlayerHost<Content: View>: View {
    let player: PlayerController
    @Binding var controlsVisible: Bool
    /// The time being scrubbed to, shown on the timeline; nil when not scrubbing.
    @Binding var scrubbing: Double?
    var remoteEnabled: Bool = true
    /// Shows the controls and restarts their hide timer.
    var poke: () -> Void
    /// Back (Menu). When set it decides everything (KP, 2026-11-10: Back exits
    /// the player); otherwise: cancel a scrub, hide the controls, close.
    var onBack: (() -> Void)? = nil
    /// A swipe down on the touch surface (opens the player's top menu).
    var onSwipeDown: () -> Void = {}
    /// A long press on the click pad (the "Ends at" time toggle).
    var onLongSelect: () -> Void = {}
    /// After a click left or right skipped 10 s (forward = right), for the "+10" flash.
    var onSkipped: (_ forward: Bool) -> Void = { _ in }
    @ViewBuilder var content: () -> Content

    @State private var scrubStart: Double?

    var body: some View {
      ZStack {
        WindowAccessor { player.window = $0 }
        TVRemoteSurface(
          enabled: remoteEnabled,
          onSelect: select,
          onPlayPause: {
            player.togglePause()
            poke()
          },
          onSkip: { forward in
            cancelScrub()
            player.seek(by: forward ? NowPlaying.skipSeconds : -NowPlaying.skipSeconds)
            onSkipped(forward)
            poke()
          },
          onMenu: menu,
          onSwipe: swipe,
          onSwipeDown: onSwipeDown,
          onLongSelect: onLongSelect
        )
        .ignoresSafeArea()
        content()
      }
    }

    private func select() {
      if let target = scrubbing {
        player.seek(to: target)
        cancelScrub()
      } else {
        player.togglePause()
      }
      poke()
    }

    /// Menu: undoes the innermost thing first; with nothing open, closes the player.
    private func menu() {
      if let onBack {
        scrubStart = nil
        onBack()
        return
      }
      if scrubbing != nil {
        cancelScrub()
        poke()
      } else if controlsVisible {
        controlsVisible = false
      } else {
        player.close()
      }
    }

    private func swipe(_ fraction: Double?) {
      guard player.duration > 0 else { return }
      guard let fraction else {
        // The finger lifted: the scrub waits for a click (or Menu to cancel).
        scrubStart = nil
        return
      }
      let start = scrubStart ?? scrubbing ?? player.position
      if scrubStart == nil { scrubStart = start }
      scrubbing = RemoteScrub.target(start: start, fraction: fraction, duration: player.duration)
      poke()
    }

    private func cancelScrub() {
      scrubbing = nil
      scrubStart = nil
    }
  }

  /// The Siri Remote's presses and touch-surface swipes, read by UIKit
  /// recognizers on the window (the focused view gets presses first, so the
  /// recognizers turn off while a control has focus).
  struct TVRemoteSurface: UIViewRepresentable {
    var enabled: Bool
    var onSelect: () -> Void
    var onPlayPause: () -> Void
    var onSkip: (_ forward: Bool) -> Void
    var onMenu: () -> Void
    /// A horizontal swipe as a fraction of the surface's width (right is
    /// positive), from where it started; nil when the finger lifts.
    var onSwipe: (_ fraction: Double?) -> Void
    var onSwipeDown: () -> Void = {}
    var onLongSelect: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> Anchor {
      let view = Anchor()
      view.coordinator = context.coordinator
      view.isUserInteractionEnabled = false
      return view
    }

    func updateUIView(_ view: Anchor, context: Context) {
      let coordinator = context.coordinator
      coordinator.onSelect = onSelect
      coordinator.onPlayPause = onPlayPause
      coordinator.onSkip = onSkip
      coordinator.onMenu = onMenu
      coordinator.onSwipe = onSwipe
      coordinator.onSwipeDown = onSwipeDown
      coordinator.onLongSelect = onLongSelect
      coordinator.setEnabled(enabled)
    }

    static func dismantleUIView(_ view: Anchor, coordinator: Coordinator) {
      coordinator.detach()
    }

    final class Anchor: UIView {
      weak var coordinator: Coordinator?
      override func didMoveToWindow() {
        super.didMoveToWindow()
        if let window { coordinator?.attach(to: window) } else { coordinator?.detach() }
      }
    }

    @MainActor final class Coordinator: NSObject, UIGestureRecognizerDelegate {
      var onSelect: () -> Void = {}
      var onPlayPause: () -> Void = {}
      var onSkip: (Bool) -> Void = { _ in }
      var onMenu: () -> Void = {}
      var onSwipe: (Double?) -> Void = { _ in }
      var onSwipeDown: () -> Void = {}
      var onLongSelect: () -> Void = {}
      /// A long press just fired: the click that ends it doesn't also play or pause.
      private var longPressedAt = Date.distantPast
      private var recognizers: [UIGestureRecognizer] = []
      private var enabled = true

      func attach(to window: UIWindow) {
        detach()
        func press(_ type: UIPress.PressType, _ action: Selector) -> UITapGestureRecognizer {
          let tap = UITapGestureRecognizer(target: self, action: action)
          tap.allowedPressTypes = [NSNumber(value: type.rawValue)]
          tap.allowedTouchTypes = []
          return tap
        }
        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
        pan.delegate = self
        let down = UISwipeGestureRecognizer(target: self, action: #selector(swipedDown))
        down.direction = .down
        down.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
        let long = UILongPressGestureRecognizer(target: self, action: #selector(longPressed(_:)))
        long.allowedPressTypes = [NSNumber(value: UIPress.PressType.select.rawValue)]
        long.allowedTouchTypes = []
        long.minimumPressDuration = 0.6
        recognizers = [
          down,
          long,
          press(.select, #selector(selected)),
          press(.playPause, #selector(playPaused)),
          press(.leftArrow, #selector(left)),
          press(.rightArrow, #selector(right)),
          press(.menu, #selector(menu)),
          pan,
        ]
        for recognizer in recognizers {
          recognizer.isEnabled = enabled
          window.addGestureRecognizer(recognizer)
        }
      }

      func detach() {
        for recognizer in recognizers { recognizer.view?.removeGestureRecognizer(recognizer) }
        recognizers = []
      }

      func setEnabled(_ value: Bool) {
        enabled = value
        for recognizer in recognizers { recognizer.isEnabled = value }
      }

      /// Only a mostly sideways swipe scrubs (up and down move focus).
      func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        guard let pan = recognizer as? UIPanGestureRecognizer, let view = pan.view else { return true }
        let v = pan.velocity(in: view)
        return abs(v.x) > abs(v.y) * 1.5
      }

      @objc func selected() {
        if Date().timeIntervalSince(longPressedAt) < 1 { return }
        onSelect()
      }
      @objc func swipedDown() { onSwipeDown() }
      @objc func longPressed(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began else { return }
        longPressedAt = Date()
        onLongSelect()
      }
      @objc func playPaused() { onPlayPause() }
      @objc func left() { onSkip(false) }
      @objc func right() { onSkip(true) }
      @objc func menu() { onMenu() }

      @objc func panned(_ pan: UIPanGestureRecognizer) {
        guard let view = pan.view else { return }
        switch pan.state {
        case .began, .changed:
          onSwipe(Double(pan.translation(in: view).x / max(view.bounds.width, 1)))
        default:
          onSwipe(nil)
        }
      }
    }
  }
#endif
