import AstraKit
import Foundation
import MediaPlayer

/// The system's Now Playing entry and remote commands for what the player is
/// playing: the lock screen and Control Center on iPhone, AirPods and other
/// headphones' play/pause, the Mac's media keys and menu-bar Now Playing.
/// System UI only; the player's own controls are untouched.
@MainActor
final class NowPlaying {
  struct Handlers {
    var play: () -> Void
    var pause: () -> Void
    var toggle: () -> Void
    var skip: (_ seconds: Double) -> Void
    var seek: (_ seconds: Double) -> Void
  }

  static let skipSeconds: Double = 10

  private var targets: [(MPRemoteCommand, Any)] = []
  private var info: [String: Any] = [:]
  private var artworkTask: Task<Void, Never>?

  /// Shows `title` and starts answering the remote commands.
  func begin(title: String, subtitle: String?, duration: Double, artwork: URL?, handlers: Handlers) {
    end()
    info = [
      MPMediaItemPropertyTitle: title,
      MPMediaItemPropertyPlaybackDuration: duration,
      MPNowPlayingInfoPropertyElapsedPlaybackTime: 0.0,
      MPNowPlayingInfoPropertyPlaybackRate: 0.0,
      MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
    ]
    if let subtitle, !subtitle.isEmpty { info[MPMediaItemPropertyArtist] = subtitle }
    publish(playing: false)

    let center = MPRemoteCommandCenter.shared()
    add(center.playCommand) { handlers.play() }
    add(center.pauseCommand) { handlers.pause() }
    add(center.togglePlayPauseCommand) { handlers.toggle() }
    center.skipForwardCommand.preferredIntervals = [NSNumber(value: Self.skipSeconds)]
    center.skipBackwardCommand.preferredIntervals = [NSNumber(value: Self.skipSeconds)]
    add(center.skipForwardCommand) { handlers.skip(Self.skipSeconds) }
    add(center.skipBackwardCommand) { handlers.skip(-Self.skipSeconds) }
    let seek = center.changePlaybackPositionCommand
    seek.isEnabled = true
    let target = seek.addTarget { event in
      guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
      let seconds = event.positionTime
      MainActor.assumeIsolated { handlers.seek(seconds) }
      return .success
    }
    targets.append((seek, target))
    // Episodes play one at a time (no autoplay): no next / previous track.
    center.nextTrackCommand.isEnabled = false
    center.previousTrackCommand.isEnabled = false

    if let artwork { loadArtwork(artwork) }
  }

  /// Position, length and whether it is playing; the system runs the clock
  /// between updates from the rate.
  func update(position: Double, duration: Double, playing: Bool) {
    guard !info.isEmpty else { return }
    info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = max(0, position)
    if duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
    publish(playing: playing)
  }

  /// Clears the entry and stops answering the commands.
  func end() {
    artworkTask?.cancel()
    artworkTask = nil
    for (command, target) in targets {
      command.removeTarget(target)
      command.isEnabled = false
    }
    targets = []
    guard !info.isEmpty else { return }
    info = [:]
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    #if os(macOS)
      MPNowPlayingInfoCenter.default().playbackState = .stopped
    #endif
  }

  private func add(_ command: MPRemoteCommand, _ action: @escaping @MainActor () -> Void) {
    command.isEnabled = true
    let target = command.addTarget { _ in
      MainActor.assumeIsolated { action() }
      return .success
    }
    targets.append((command, target))
  }

  private func publish(playing: Bool) {
    info[MPNowPlayingInfoPropertyPlaybackRate] = playing ? 1.0 : 0.0
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    #if os(macOS)
      MPNowPlayingInfoCenter.default().playbackState = playing ? .playing : .paused
    #endif
  }

  /// Built outside the main actor: the system calls the image handler on
  /// its own queue, and a main-actor closure there would trap.
  private nonisolated static func artwork(_ image: PlatformImage) -> MPMediaItemArtwork {
    nonisolated(unsafe) let image = image
    return MPMediaItemArtwork(boundsSize: image.size) { _ in image }
  }

  private func loadArtwork(_ url: URL) {
    artworkTask = Task { [weak self] in
      guard let (data, _) = try? await URLSession.shared.data(from: url), !Task.isCancelled,
        let image = PlatformImage(data: data)
      else { return }
      guard let self, !self.info.isEmpty else { return }
      self.info[MPMediaItemPropertyArtwork] = Self.artwork(image)
      MPNowPlayingInfoCenter.default().nowPlayingInfo = self.info
    }
  }
}
