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
  var lastError: String?

  @ObservationIgnored weak var window: PlatformWindow?
  #if os(macOS)
    /// Builds the player controls for the Mac player window.
    @ObservationIgnored var makeOverlay: (() -> AnyView)?
    @ObservationIgnored private var host: PlayerWindowHost?
  #endif
  @ObservationIgnored var server: PlexServerClient?

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

  func play(_ item: PlexMetadata, library: LibraryStore) throws {
    guard let server else { throw PlexError.notSignedIn }
    guard let window else { throw PlexError.invalidResponse }
    // Always the original file; the preference only picks between versions.
    let source = try PlaybackResolver.directPlay(item, client: server, quality: .stored())
    if isActive { close() }

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
      ("eof-reached", "flag"), ("width", "double"), ("height", "double"), ("track-list", "node"), ("aid", "string"), ("sid", "string"),
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
    #endif

    isActive = true
    startReporting()
  }

  func close() {
    guard isActive else { return }
    reporter?.cancel()
    reporter = nil
    report(.stopped)
    core?.dispose()
    core = nil
    isActive = false
    if let key = source?.ratingKey { library?.playbackEnded(ratingKey: key) }
    source = nil
    #if os(macOS)
      host?.dismiss()
      host = nil
    #else
      try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    #endif
  }

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
    guard let server, let source else { return }
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
