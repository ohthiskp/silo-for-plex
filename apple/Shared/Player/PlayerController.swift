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
  /// False from opening a file until mpv shows its first frame; the overlay
  /// shows a loading state instead of a black window meanwhile.
  private(set) var hasFirstFrame = false
  // Astra: seek previews are decoded by Astra from the file itself, like
  // Infuse (KP, 2026-11-07), not read from Plex. See SeekPreviewGenerator.
  @ObservationIgnored private var previews: SeekPreviewGenerator?
  /// Decoded previews by 2-second slot.
  @ObservationIgnored private var previewCache: [Int: PlatformImage] = [:]
  /// The newest preview, shown while the next one decodes.
  @ObservationIgnored private var lastPreview: PlatformImage?
  @ObservationIgnored private var requestedSlot: Int?
  /// Bumped when a preview arrives, so the timeline redraws.
  private(set) var previewVersion = 0
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
  /// Astra 4.0 (KP, 2026-11-08): plays the episode the Next Episode button
  /// offers. Only ever called from a tap; nothing plays on its own.
  @ObservationIgnored var playNext: ((PlexMetadata) -> Void)?
  /// The episode after the one playing, looked up when playback starts so
  /// the last seconds need no network. Nil for movies and the last episode.
  private(set) var upNext: PlexMetadata?
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

  /// Dolby Vision / HDR10 / HLG of the file playing (from Plex's metadata).
  /// On iPhone and Mac mpv shows Dolby Vision as HDR, so this names the file.
  var dynamicRange: DynamicRange? {
    guard let item else { return nil }
    if let currentMediaID, let media = item.media.first(where: { $0.id == currentMediaID }) {
      return media.dynamicRange
    }
    return item.dynamicRange()
  }

  /// Whether the file playing has a Dolby Atmos track (from Plex's metadata).
  var hasAtmos: Bool {
    guard let item else { return false }
    if let currentMediaID, let media = item.media.first(where: { $0.id == currentMediaID }) { return media.hasAtmos }
    return item.hasAtmos()
  }

  // MARK: - Open and close

  /// The item playing, for switching between its versions.
  @ObservationIgnored private var item: PlexMetadata?
  private(set) var currentMediaID: Int?

  /// One original file the player can switch to (another version of the same
  /// title, in this library or another one). Never a transcode.
  struct Version: Identifiable, Equatable {
    var item: PlexMetadata
    var media: PlexMedia
    var id: String { "\(item.ratingKey)-\(media.id)" }

    /// "4K", "HD" or "SD".
    var badge: String {
      let badge = VideoTier.badge(for: media.tier) ?? "SD"
      return badge == "4K UHD" ? "4K" : badge
    }

    /// "HEVC · 58.2 GB".
    var detail: String {
      [
        media.videoCodec?.uppercased(),
        media.parts.first?.size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) },
      ].compactMap { $0 }.joined(separator: " · ")
    }
  }

  /// Every version of what is playing, best first (loaded after playback starts).
  private(set) var versions: [Version] = []
  @ObservationIgnored private var versionsGUID: String?

  /// Switches to another original file, continuing from the same position.
  func playVersion(_ version: Version) {
    guard let library, version.media.id != currentMediaID else { return }
    var item = version.item
    item.media = [version.media]
    item.viewOffset = Int(position * 1000)
    do { try play(item, library: library) } catch { lastError = error.localizedDescription }
  }

  private func loadVersions(of item: PlexMetadata, library: LibraryStore) {
    guard item.guid != versionsGUID || versions.isEmpty else { return }
    versionsGUID = item.guid
    versions = []
    Task { [weak self] in
      let copies = await library.versions(of: item)
      let found = copies.flatMap { copy in
        copy.media.filter { $0.parts.first?.key != nil }.map { Version(item: copy, media: $0) }
      }
      .sorted { ($0.media.tier ?? 0, $0.media.bitrate ?? 0) > ($1.media.tier ?? 0, $1.media.bitrate ?? 0) }
      guard let self, self.versionsGUID == item.guid else { return }
      self.versions = found
    }
  }

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
      // Astra: Auto follows Library Quality (an HD device plays the HD version).
      source = try PlaybackResolver.directPlay(item, client: server, quality: .current())
    }
    if isActive { close() }
    self.item = item
    currentMediaID = local == nil ? source.media.id : nil
    if local == nil { loadVersions(of: item, library: library) } else { versions = []; versionsGUID = nil }
    quality = .stored()

    let core = MpvPlayerCore()
    core.delegate = bridge
    #if os(macOS)
      // Video plays in its own window whose content view is a plain NSView (see PlayerWindowHost).
      let host = PlayerWindowHost(over: window, content: makeOverlay?() ?? AnyView(EmptyView()))
      host.onUserClose = { [weak self] in self?.close() }
      host.onMiniChange = { [weak self] mini in self?.isPictureInPicture = mini }
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
    loadThumbnails(for: source, local: local != nil)

    title = source.title
    subtitle = source.subtitle
    position = source.startSeconds
    duration = Double(source.durationMs) / 1000
    paused = false
    buffering = true
    hasFirstFrame = false
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
    // A bigger read-ahead buffer, so a remote server's hiccups don't pause playback.
    #if os(iOS)
      core.setProperty("demuxer-max-bytes", value: "150MiB")
    #else
      core.setProperty("demuxer-max-bytes", value: "400MiB")
    #endif
    core.setProperty("demuxer-max-back-bytes", value: "50MiB")
    core.setProperty("demuxer-readahead-secs", value: "30")
    // Settings → Playback → Subtitles (Astra 4.0).
    for (name, value) in SubtitlePreference.current().mpvOptions(languages: Locale.preferredLanguages) {
      core.setProperty(name, value: value)
    }
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
    watchForStall(source)
    findUpNext(after: item, library: library, source: source)
  }

  /// Looks up the next episode once, at the start, for the Next Episode button.
  private func findUpNext(after item: PlexMetadata, library: LibraryStore, source started: PlaybackSource) {
    upNext = nil
    guard item.type == .episode else { return }
    Task { [weak self] in
      let next = await library.nextEpisode(after: item)
      guard let self, self.isActive, self.source?.url == started.url else { return }
      self.upNext = next
    }
  }

  /// Seconds left before the Next Episode button shows.
  static let nextEpisodeLead: Double = 15

  /// Next Episode tapped: plays the next episode now (progress of this one is reported on close).
  func playUpNext() {
    guard let next = upNext else { return }
    playNext?(next)
  }

  /// Astra (KP, 2026-11-07): when the server is down the player used to spin
  /// for ever. 30 s without a first frame closes it and says why.
  private func watchForStall(_ started: PlaybackSource) {
    Task { [weak self] in
      try? await Task.pause(30)
      guard let self, self.isActive, !self.hasFirstFrame, self.source?.url == started.url else { return }
      self.close()
      self.lastError = "The server isn't answering, so this can't play right now. Check that your Plex server is on."
    }
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
    previews?.close()
    previews = nil
    previewCache = [:]
    lastPreview = nil
    requestedSlot = nil
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
      let media = PlaybackResolver.preferredMedia(item.media, quality: .current()), media.id != currentMediaID
    else { return }
    item.viewOffset = Int(position * 1000)
    try? play(item, library: library)
  }

  /// The quality the chip shows as chosen.
  private(set) var quality: PlaybackQuality = .stored()

  // MARK: - Transport

  func togglePause() { setPaused(!paused) }

  /// When Astra last set a property itself: mpv's echo of an older value
  /// arriving just after is ignored, so the slider and Play/Pause never jump
  /// back (KP, 2026-11-08: "make playback snappier", "volume instant").
  @ObservationIgnored private var localSetAt: [String: Date] = [:]
  private func isEcho(_ name: String) -> Bool {
    localSetAt[name].map { Date().timeIntervalSince($0) < 0.5 } ?? false
  }

  func setPaused(_ value: Bool) {
    guard let core else { return }
    localSetAt["pause"] = Date()
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
    localSetAt["volume"] = Date()
    core?.setProperty("volume", value: String(format: "%.0f", volume))
    if muted, volume > 0 { setMuted(false) }
  }

  func setMuted(_ value: Bool) {
    muted = value
    localSetAt["mute"] = Date()
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
    case "pause": if let v = value as? Bool, !isEcho("pause") { paused = v }
    case "volume": if let v = value as? Double, !isEcho("volume") { volume = v }
    case "mute": if let v = value as? Bool, !isEcho("mute") { muted = v }
    case "speed": if let v = value as? Double { speed = v }
    case "paused-for-cache": buffering = (value as? Bool) ?? false
    case "width":
      videoWidth = (value as? Double) ?? 0
      fitWindowToVideo()
    case "height":
      videoHeight = (value as? Double) ?? 0
      fitWindowToVideo()
    case "eof-reached":
      // No autoplay (KP, Astra 4.0): the episode ends and the player closes.
      if (value as? Bool) == true { close() }
    case "aid": audioId = (value as? String).flatMap { Int($0) }
    case "sid": subtitleId = (value as? String).flatMap { Int($0) }
    case "track-list": updateTracks(value as? [Any] ?? [])
    default: break
    }
  }

  fileprivate func eventReceived(_ name: String, _ data: [String: Any]?) {
    switch name {
    case "playback-restart":
      // The first frame is decoded and on screen (also after every seek).
      buffering = false
      hasFirstFrame = true
    case "end-file":
      if let reason = data?["reason"] as? String, reason == "error" {
        lastError = (data?["message"] as? String) ?? "This file couldn't be played."
        close()
      }
    default:
      break
    }
  }

  /// A preview decoder on its own connection to the same file (nothing is
  /// opened until the first scrub).
  private func loadThumbnails(for source: PlaybackSource, local: Bool) {
    previews?.close()
    previewCache = [:]
    lastPreview = nil
    requestedSlot = nil
    previews = SeekPreviewGenerator(url: source.url, headers: source.headers)
  }

  /// The preview for a time on the timeline: the decoded frame for its
  /// 2-second slot, else the newest one while that slot decodes.
  func thumbnail(at seconds: Double) -> PlatformImage? {
    _ = previewVersion
    guard let previews, seconds.isFinite else { return nil }
    let slot = Int(max(0, seconds) / 2)
    if let hit = previewCache[slot] { return hit }
    if requestedSlot != slot {
      requestedSlot = slot
      let key = source?.ratingKey
      previews.request(at: Double(slot) * 2) { [weak self] image in
        MainActor.assumeIsolated {
          guard let self, self.source?.ratingKey == key, let image else { return }
          let preview = PlatformImage.from(image)
          if self.previewCache.count > 300 { self.previewCache.removeAll() }
          self.previewCache[slot] = preview
          self.lastPreview = preview
          self.previewVersion &+= 1
        }
      }
    }
    return lastPreview
  }

  private func fitWindowToVideo() {
    #if os(macOS)
      guard videoWidth > 0, videoHeight > 0 else { return }
      host?.fitVideo(width: videoWidth, height: videoHeight)
    #endif
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
        try? await Task.pause(10)
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
