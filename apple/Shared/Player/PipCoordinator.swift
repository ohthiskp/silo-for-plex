#if os(iOS) || os(tvOS)
  import AVKit
  import UIKit

  /// iPhone Picture in Picture for the mpv player, using the Flutter app's
  /// `MpvPipController` unchanged. The same steps as its `MpvPlayerPlugin`:
  /// prepare the shared sample-buffer layer, start PiP, and restore the
  /// inline video when PiP ends.
  @MainActor
  final class PipCoordinator: NSObject, MpvPipDelegate {
    private weak var core: MpvPlayerCore?
    private var controller: MpvPipController?
    private var manualRequest = false
    /// Called with true when PiP starts and false when it ends.
    var onChange: ((Bool) -> Void)?

    static var isSupported: Bool { MpvPipController.isSupported }

    init(core: MpvPlayerCore) {
      self.core = core
      super.init()
    }

    var isActive: Bool { core?.isPipActive == true }

    /// Lets iOS start PiP by itself when the app goes to the background mid-playback.
    func enableAutoStart() {
      guard Self.isSupported, let pip = ensureController(), let core else { return }
      pip.setAutoStart(true)
      pip.warmLayer(currentTime: core.timePos, isPlaying: !core.isPaused)
    }

    func toggle() {
      if isActive { controller?.stopPip() } else { start() }
    }

    func start() {
      guard Self.isSupported, !manualRequest, let pip = prepare() else { return }
      manualRequest = true
      pip.startPip(waitForFrame: true) { [weak self] started in
        guard let self else { return }
        if !started, self.core?.isPipStarting == true { self.cleanup(notify: false) }
        if !started { self.manualRequest = false }
      }
    }

    func teardown() {
      let wasActive = isActive
      controller?.teardown()
      controller = nil
      core?.isPipActive = false
      if wasActive { onChange?(false) }
    }

    private func ensureController() -> MpvPipController? {
      if let controller { return controller }
      guard let layer = core?.sampleBufferDisplayLayer else { return nil }
      let pip = MpvPipController(sampleBufferDisplayLayer: layer)
      pip.delegate = self
      controller = pip
      return pip
    }

    @discardableResult
    private func prepare() -> MpvPipController? {
      guard let core, let pip = ensureController() else { return nil }
      core.setPipSubtitleCompositing(true)
      core.isPipStarting = true
      pip.invalidatePlaybackState()
      return pip
    }

    private func cleanup(notify: Bool, pause: Bool = false) {
      core?.setPipSubtitleCompositing(false)
      core?.isPipStarting = false
      core?.isPipActive = false
      manualRequest = false
      if pause {
        core?.setPropertyAsync("pause", value: "yes") { [weak self] result in
          guard case .success = result else { return }
          self?.controller?.invalidatePlaybackState()
        }
      }
      // Back inline: show the video in the app again.
      if let core {
        core.setVisible(true)
        core.updateFrame()
        if core.isPaused { core.forceDraw() }
      }
      if notify { onChange?(false) }
    }

    // MARK: MpvPipDelegate

    nonisolated func pipWillStart() {
      MainActor.assumeIsolated {
        guard let core, !core.isPipStarting else { return }
        // Started by iOS itself (app sent to the background).
        if prepare() == nil { controller?.stopPip() }
      }
    }

    nonisolated func pipDidStart() {
      MainActor.assumeIsolated {
        core?.isPipStarting = false
        core?.isPipActive = true
        onChange?(true)
        if manualRequest {
          manualRequest = false
          // Go to the Home Screen so the video floats, as the system player does.
          UIControl().sendAction(#selector(URLSessionTask.suspend), to: UIApplication.shared, for: nil)
        }
      }
    }

    nonisolated func pipDidStop(restored: Bool) {
      MainActor.assumeIsolated { cleanup(notify: true, pause: !restored) }
    }

    nonisolated func pipDidFailToStart(error: Error?) {
      MainActor.assumeIsolated { cleanup(notify: true) }
    }

    nonisolated func pipSetPlaying(_ playing: Bool) {
      MainActor.assumeIsolated {
        core?.setPropertyAsync("pause", value: playing ? "no" : "yes") { [weak self] result in
          guard case .success = result else { return }
          self?.controller?.invalidatePlaybackState()
        }
      }
    }

    nonisolated func pipSkip(byInterval seconds: Double, completion: @escaping () -> Void) {
      MainActor.assumeIsolated {
        guard let core else { return completion() }
        let target = max(0, core.timePos + seconds)
        core.commandAsync(["seek", String(target), "absolute"]) { [weak self] _ in
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self?.controller?.invalidatePlaybackState()
            completion()
          }
        }
      }
    }

    nonisolated var isPipPlaying: Bool { MainActor.assumeIsolated { !(core?.isPaused ?? true) } }
    nonisolated var pipDuration: Double { MainActor.assumeIsolated { core?.duration ?? 0 } }
    nonisolated var pipPosition: Double { MainActor.assumeIsolated { core?.timePos ?? 0 } }
  }
#endif
