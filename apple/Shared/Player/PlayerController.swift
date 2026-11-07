import AstraKit
#if os(iOS)
  import AVFoundation
#endif
import Foundation
import SwiftUI
import Observation

/// Drives the shared mpv core (`MpvPlayerCore`, unchanged from the Flutter app)
/// and reports progress to Plex.
///
/// The core draws video into a layer at the bottom of the window's content
/// view, under the SwiftUI layers, exactly as it does under Flutter; the
/// player overlay is ordinary SwiftUI on top with a clear background.
@MainActor
@Observable
final class PlayerController {
  struct Track: Identifiable, Hashable {
    var id: Int
    var title: String
  }

  // Playback state, fed by mpv property observers.
  private(set) var isActive = false
  private(set) var title = ""
  private(set) var subtitle: String?
  private(set) var position: Double = 0
  private(set) var duration: Double = 0
  private(set) var paused = false
  private(set) var buffering = true
  private(set) var videoWidth: Double = 0
  private(set) var videoHeight: Double = 0
  private(set) var audioTracks: [Track] = []
  private(set) var subtitleTracks: [Track] = []
  private(set) var audioId: Int?
  private(set) var subtitleId: Int?
  private(set) var volume: Double = 100
  private(set) var muted = false
  private(set) var speed: Double = 1
  /// iPhone Picture in Picture, or the Mac's small floating window.
  private(set) var isPictureInPicture = false
  var lastError: String?
  /// Opens the details page of what is playing (the title's chevron on iPhone).
  @ObservationIgnored var openDetails: ((PlexMetadata) -> Void)?
  #if os(iOS)
    @ObservationIgnored private var pip: PipCoordinator?
  #endif

  @ObservationIgnored weak var window: PlatformWindow?
  #if os(macOS)
    /// Builds the player controls for the Mac player window.
    @ObservationIgnored var makeOverlay: (() -> AnyView)?
    @ObservationIgnored private var host: PlayerWindowHost?
  #endif
  @ObservationIgnored var server: PlexServerClient?
  /// The server the current item came from. Progress goes there even if
  /// Settings switches to another server mid-playback.
  @ObservationIgnored private var playbackServer: PlexServerClient?

  @ObservationIgnored private var core: MpvPlayerCore?
  @ObservationIgnored private var source: PlaybackSource?
  @ObservationIgnored private weak var library: LibraryStore?
  @ObservationIgnored private var reporter: Task<Void, Never>?
  @ObservationIgnored private lazy var bridge = MpvDelegateBridge(owner: self)

  /// "4K UHD" or "HD" for the frames mpv is actually decoding, never the
  /// saved preference or the file's metadata. Nothing until the first frame.
  ///
  /// There is no Dolby Vision badge on Mac or iPhone: mpv shows Dolby Vision
  /// files there as HDR (or SDR), not through a Dolby Vision output path.
  var resolutionBadge: String? {
    guard videoWidth > 0 || videoHeight > 0 else { return nil }
    return VideoTier.badge(for: VideoTier.tier(width: Int(videoWidth), height: Int(videoHeight)))
  }

  // MARK: - Open and close

  /// The item playing, for switching between its versions.
  @ObservationIgnored private var item: PlexMetadata?
  private(set) var currentMediaID: Int?

  /// Plays `item`: from `local` (a downloaded file) when given, else the
  /// original file on the server.
  func play(_ item: PlexMetadata, library: LibraryStore, local: PlaybackSource? = nil) throws {
    guard let window else { throw PlexError.invalidResponse }
    // Always the original file; the preference only picks between versions.
    let source: PlaybackSource
    if let local {
      source = local
    } else {
      guard let server else { throw PlexError.notSignedIn }
      source = try PlaybackResolver.directPlay(item, client: server, quality: .stored())
    }
    if isActive { close() }
    self.item = item
    currentMediaID = local == nil ? source.media.id : nil
    quality = .stored()

    let core = MpvPlayerCore()
    core.delegate = bridge
    #if os(macOS)
      // Video plays in its own window whose content view is a plain NSView (see PlayerWindowHost).
      let host = PlayerWindowHost(over: window, content: makeOverlay?() ?? AnyView(EmptyView()))
      host.onUserClose = { [weak self] in self?.close() }
      guard core.initialize(in: host.window) else {
        host.dismiss()
        throw PlaybackFailure("mpv could not start.")
      }
      self.host = host
    #else
      guard core.initialize(in: window) else {
        throw PlaybackFailure("mpv could not start.")
      }
    #endif
    self.core = core
    self.source = source
    self.library = library
    playbackServer = server

    title = source.title
    subtitle = source.subtitle
    position = source.startSeconds
    duration = Double(source.durationMs) / 1000
    paused = false
    buffering = true
    videoWidth = 0
    videoHeight = 0
    audioTracks = []
    subtitleTracks = []
    lastError = nil

    for (name, format) in [
      ("time-pos", "double"), ("duration", "double"), ("pause", "flag"), ("paused-for-cache", "flag"),
      ("eof-reached", "flag"), ("volume", "double"), ("mute", "flag"), ("speed", "double"), ("width", "double"), ("height", "double"), ("track-list", "node"), ("aid", "string"), ("sid", "string"),
    ] {
      core.observeProperty(name, format: format)
    }
    core.setProperty("http-header-fields", value: PlaybackResolver.mpvHeaderFields(source.headers))
    core.setProperty("force-media-title", value: source.title)
    core.setProperty("start", value: source.startSeconds > 0 ? String(format: "%.3f", source.startSeconds) : "none")
    core.setProperty("pause", value: "no")
    core.command(["loadfile", source.url.absoluteString, "replace"])
    core.setVisible(true)
    #if os(macOS)
      core.setPaused(false)
      self.host?.show()
    #else
      try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
      try? AVAudioSession.sharedInstance().setActive(true)
      // The video sits under the hosting view, which must not paint over it.
      window.rootViewController?.view.backgroundColor = .clear
      core.updateFrame()
      let pip = PipCoordinator(core: core)
      pip.onChange = { [weak self] active in self?.isPictureInPicture = active }
      pip.enableAutoStart()
      self.pip = pip
    #endif

    isActive = true
    startReporting()
  }

  func close() {
    guard isActive else { return }
    reporter?.cancel()
    reporter = nil
    report(.stopped)
    #if os(iOS)
      pip?.teardown()
      pip = nil
    #endif
    core?.dispose()
    core = nil
    isActive = false
    isPictureInPicture = false
    if let key = source?.ratingKey { library?.playbackEnded(ratingKey: key) }
    source = nil
    #if os(macOS)
      host?.dismiss()
      host = nil
    #else
      try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    #endif
  }

  /// Auto / HD / 4K from the player's chip: saves the preference (the same
  /// one as Settings) and, if it picks a different original file, switches
  /// to it at the same position. Never transcodes.
  func setQuality(_ quality: PlaybackQuality) {
    quality.save()
    self.quality = quality
    guard var item, let library, currentMediaID != nil,
      let media = PlaybackResolver.preferredMedia(item.media, quality: quality), media.id != currentMediaID
    else { return }
    item.viewOffset = Int(position * 1000)
    try? play(item, library: library)
  }

  /// The quality the chip shows as chosen.
  private(set) var quality: PlaybackQuality = .stored()

  // MARK: - Transport

  func togglePause() { setPaused(!paused) }

  func setPaused(_ value: Bool) {
    guard let core else { return }
    paused = value
    core.setProperty("pause", value: value ? "yes" : "no")
    #if os(macOS)
      core.setPaused(value)
    #endif
    report(value ? .paused : .playing)
  }

  func seek(by seconds: Double) {
    core?.command(["seek", String(seconds), "relative+exact"])
  }

  func seek(to seconds: Double) {
    position = seconds
    core?.command(["seek", String(format: "%.3f", seconds), "absolute+keyframes"])
  }

  func selectAudio(_ id: Int) {
    audioId = id
    core?.setProperty("aid", value: String(id))
  }

  func selectSubtitle(_ id: Int?) {
    subtitleId = id
    core?.setProperty("sid", value: id.map(String.init) ?? "no")
  }

  func setVolume(_ value: Double) {
    volume = min(100, max(0, value))
    core?.setProperty("volume", value: String(format: "%.0f", volume))
    if muted, volume > 0 { setMuted(false) }
  }

  func setMuted(_ value: Bool) {
    muted = value
    core?.setProperty("mute", value: value ? "yes" : "no")
  }

  func setSpeed(_ value: Double) {
    speed = value
    core?.setProperty("speed", value: String(format: "%.2f", value))
  }

  static let speeds: [Double] = [0.5, 0.75, 1, 1.25, 1.5, 2]

  static var supportsPictureInPicture: Bool {
    #if os(iOS)
      PipCoordinator.isSupported
    #else
      true
    #endif
  }

  /// iPhone: system Picture in Picture. Mac: a small floating window in the
  /// corner of the screen, above other apps (mpv has no Mac PiP).
  func togglePictureInPicture() {
    #if os(iOS)
      pip?.toggle()
    #else
      guard let host else { return }
      isPictureInPicture = host.toggleMini()
    #endif
  }

  /// The title's details page, from the player.
  func showDetails() {
    guard let item, let openDetails else { return }
    close()
    openDetails(item)
  }

  func toggleFullScreen() {
    #if os(macOS)
      host?.toggleFullScreen()
    #endif
  }

  /// The window changed size (rotation, split view): resize the video layer.
  func layoutChanged() {
    #if os(iOS)
      core?.updateFrame()
    #endif
  }

  // MARK: - mpv events

  fileprivate func propertyChanged(_ name: String, _ value: Any?) {
    switch name {
    case "time-pos": if let v = value as? Double { position = v }
    case "duration": if let v = value as? Double, v > 0 { duration = v }
    case "pause": if let v = value as? Bool { paused = v }
    case "volume": if let v = value as? Double { volume = v }
    case "mute": if let v = value as? Bool { muted = v }
    case "speed": if let v = value as? Double { speed = v }
    case "paused-for-cache": buffering = (value as? Bool) ?? false
    case "width": videoWidth = (value as? Double) ?? 0
    case "height": videoHeight = (value as? Double) ?? 0
    case "eof-reached":
      if (value as? Bool) == true { close() }
    case "aid": audioId = (value as? String).flatMap { Int($0) }
    case "sid": subtitleId = (value as? String).flatMap { Int($0) }
    case "track-list": updateTracks(value as? [Any] ?? [])
    default: break
    }
  }

  fileprivate func eventReceived(_ name: String, _ data: [String: Any]?) {
    switch name {
    case "playback-restart", "file-loaded":
      buffering = false
    case "end-file":
      if let reason = data?["reason"] as? String, reason == "error" {
        lastError = (data?["message"] as? String) ?? "This file couldn't be played."
        close()
      }
    default:
      break
    }
  }

  private func updateTracks(_ list: [Any]) {
    var audio: [Track] = []
    var subs: [Track] = []
    for case let entry as [String: Any] in list {
      guard let id = (entry["id"] as? Int) ?? (entry["id"] as? Int64).map(Int.init), let type = entry["type"] as? String
      else { continue }
      let lang = (entry["lang"] as? String).map { Locale.current.localizedString(forLanguageCode: $0) ?? $0 }
      let label = [entry["title"] as? String, lang].compactMap { $0 }.first ?? "Track \(id)"
      if type == "audio" { audio.append(Track(id: id, title: label)) }
      if type == "sub" { subs.append(Track(id: id, title: label)) }
    }
    audioTracks = audio
    subtitleTracks = subs
  }

  // MARK: - Plex progress

  private func startReporting() {
    reporter?.cancel()
    reporter = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(10))
        guard let self, !Task.isCancelled else { return }
        self.report(self.paused ? .paused : (self.buffering ? .buffering : .playing))
      }
    }
  }

  private func report(_ state: TimelineReport.State) {
    guard let server = playbackServer, let source else { return }
    let report = TimelineReport(
      ratingKey: source.ratingKey, key: source.metadataKey, state: state, timeMs: Int(position * 1000),
      durationMs: duration > 0 ? Int(duration * 1000) : source.durationMs)
    Task.detached { try? await server.reportTimeline(report) }
  }
}

struct PlaybackFailure: LocalizedError {
  var errorDescription: String?
  init(_ message: String) { errorDescription = message }
}

/// The core calls its delegate on the main thread; this hops onto the main
/// actor so `PlayerController` can stay `@MainActor`.
final class MpvDelegateBridge: MpvPlayerDelegate {
  private weak var owner: PlayerController?

  init(owner: PlayerController) { self.owner = owner }

  func onPropertyChange(name: String, value: Any?, sourceId: Int64?) {
    MainActor.assumeIsolated { owner?.propertyChanged(name, value) }
  }

  func onEvent(name: String, data: [String: Any]?) {
    MainActor.assumeIsolated { owner?.eventReceived(name, data) }
  }
}
