import AstraKit
#if os(iOS) || os(tvOS)
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
  #if os(iOS) || os(tvOS)
    @ObservationIgnored private var pip: PipCoordinator?
  #endif

  @ObservationIgnored weak var window: PlatformWindow?
  #if os(macOS)
    /// Builds the player controls for the Mac player window.
    @ObservationIgnored var makeOverlay: (() -> AnyView)?
    @ObservationIgnored private var host: PlayerWindowHost?
  #endif
  @ObservationIgnored var server: PlexServerClient? {
    // Connected (at launch, or again after a server switch or reconnect):
    // progress watched while it couldn't be reached goes now (QA P2-6).
    didSet { if server != nil { flushPendingTimelines() } }
  }
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
  /// Lock screen, Control Center, headphones and media keys.
  @ObservationIgnored private let nowPlaying = NowPlaying()
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
    prepareStreams(for: item, source: source, local: local != nil, library: library)

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
    #if os(iOS) || os(tvOS)
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
    core.command(["loadfile", source.mpvURL ?? source.url.absoluteString, "replace"])
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
    nowPlaying.begin(
      title: source.title, subtitle: source.subtitle, duration: duration,
      artwork: server?.imageURL(item.grandparentThumb ?? item.thumb, width: 600, height: 900),
      handlers: .init(
        play: { [weak self] in self?.setPaused(false) },
        pause: { [weak self] in self?.setPaused(true) },
        toggle: { [weak self] in self?.togglePause() },
        skip: { [weak self] in self?.seek(by: $0) },
        seek: { [weak self] in self?.seek(to: $0) }
      ))
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

  @ObservationIgnored private var stallTask: Task<Void, Never>?
  /// The stalled file is being opened again; its first frame ends the watch.
  @ObservationIgnored private var reopening = false

  /// Waiting for data mid-film: after 20 s the file is opened again at the
  /// same place (a dropped connection usually comes back that way); if it is
  /// still waiting 30 s later, the player closes and says why, instead of
  /// spinning for ever.
  private func watchMidPlaybackStall() {
    stallTask?.cancel()
    guard let started = source else { return }
    stallTask = Task { [weak self] in
      try? await Task.pause(20)
      guard let self, !Task.isCancelled, self.isActive, self.buffering, self.source?.url == started.url,
        let core = self.core
      else { return }
      self.reopening = true
      // A reopened file lists its tracks again; external subtitles go back on.
      self.selectionApplied = false
      core.setProperty("start", value: String(format: "%.3f", self.position))
      core.command(["loadfile", started.mpvURL ?? started.url.absoluteString, "replace"])
      try? await Task.pause(30)
      guard !Task.isCancelled, self.isActive, self.reopening, self.source?.url == started.url else { return }
      self.close()
      self.lastError = "The server stopped sending this video. Check your connection to the Plex server, then play it again."
    }
  }

  func close() {
    guard isActive else { return }
    stallTask?.cancel()
    stallTask = nil
    reopening = false
    reporter?.cancel()
    reporter = nil
    report(.stopped)
    nowPlaying.end()
    #if os(iOS) || os(tvOS)
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
  ///
  /// Only values other than the one Astra set count as an echo, and only
  /// until mpv reports Astra's value (events arrive in order, so anything
  /// after that is real: PiP, an interruption, the end of the file), or 0.5 s.
  @ObservationIgnored private var localSets: [String: (value: Double, at: Date)] = [:]
  private func markLocalSet(_ name: String, _ value: Double) { localSets[name] = (value, Date()) }
  private func isEcho(_ name: String, _ value: Double) -> Bool {
    guard let set = localSets[name] else { return false }
    if abs(set.value - value) < 0.5 || Date().timeIntervalSince(set.at) >= 0.5 {
      localSets[name] = nil  // Confirmed (or too old): from here on mpv's values are real.
      return false
    }
    return true
  }

  func setPaused(_ value: Bool) {
    guard let core else { return }
    markLocalSet("pause", value ? 1 : 0)
    paused = value
    core.setProperty("pause", value: value ? "yes" : "no")
    #if os(macOS)
      core.setPaused(value)
    #endif
    report(value ? .paused : .playing)
    updateNowPlaying()
  }

  private func updateNowPlaying() {
    nowPlaying.update(position: position, duration: duration, playing: !paused && !buffering)
  }

  /// While a seek runs, mpv's older positions are not shown, so the bar
  /// stays where it was let go instead of jumping back and forth.
  @ObservationIgnored private var seekingSince: Date?

  func seek(by seconds: Double) {
    guard let core else { return }
    let target = max(0, duration > 0 ? min(duration, position + seconds) : position + seconds)
    position = target
    seekingSince = Date()
    core.command(["seek", String(seconds), "relative+exact"])
  }

  func seek(to seconds: Double) {
    guard let core else { return }
    position = seconds
    seekingSince = Date()
    // Exact, so playback continues where the bar was let go; keyframe seeks
    // landed up to a few seconds early and the bar jumped back.
    core.command(["seek", String(format: "%.3f", seconds), "absolute+exact"])
  }

  func selectAudio(_ id: Int) {
    audioId = id
    core?.setProperty("aid", value: String(id))
    saveStreamChoice(audio: plexAudioID(forTrack: id))
  }

  func selectSubtitle(_ id: Int?) {
    subtitleId = id
    core?.setProperty("sid", value: id.map(String.init) ?? "no")
    // 0 is Plex's "no subtitles".
    saveStreamChoice(subtitle: id.map { plexSubtitleID(forTrack: $0) } ?? 0)
  }

  // MARK: - Audio and subtitle tracks from Plex

  /// What mpv lists for one track (by "audio:<id>" / "sub:<id>").
  private struct TrackInfo {
    var ffIndex: Int?
    var externalFile: String?
  }

  @ObservationIgnored private var selection: StreamSelection?
  @ObservationIgnored private var selectionApplied = false
  @ObservationIgnored private var trackInfo: [String: TrackInfo] = [:]
  /// Sidecar subtitle URL (or saved file path) → its Plex stream id.
  @ObservationIgnored private var externalStreamIDs: [String: Int] = [:]
  /// A download's saved sidecar subtitles: path, language, Plex's choice.
  @ObservationIgnored private var localSidecars: [(path: String, language: String?, selected: Bool)] = []

  /// Reads Plex's track choice and sidecar subtitles for the file about to
  /// play. A Home or season listing often leaves the streams out, so they
  /// are read from the title's details then.
  private func prepareStreams(for item: PlexMetadata, source: PlaybackSource, local: Bool, library: LibraryStore) {
    selection = nil
    selectionApplied = false
    trackInfo = [:]
    externalStreamIDs = [:]
    localSidecars = []
    if local {
      let folder = source.url.deletingLastPathComponent()
      let name = source.url.lastPathComponent
      let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
      localSidecars = SidecarSubtitle.files(of: name, in: names).map { file in
        let described = SidecarSubtitle.describe(file, videoFileName: name)
        return (folder.appendingPathComponent(file).path, described.language, described.selected)
      }
      return
    }
    if !source.part.streams.isEmpty {
      selection = StreamSelection(part: source.part)
      return
    }
    let started = source.url
    Task { [weak self] in
      guard let full = try? await library.details(item.ratingKey) else { return }
      let part = full.media.flatMap(\.parts).first { $0.id == source.part.id && !$0.streams.isEmpty }
      guard let self, let part, self.source?.url == started else { return }
      self.selection = StreamSelection(part: part)
      self.applyStreamsIfReady()
    }
  }

  /// Once mpv has listed the file's tracks: adds the sidecar subtitles and
  /// switches to the tracks Plex has selected. Once per file.
  private func applyStreamsIfReady() {
    guard !selectionApplied, let core, !trackInfo.isEmpty else { return }
    if !localSidecars.isEmpty {
      selectionApplied = true
      for sidecar in localSidecars {
        let title = sidecar.language.map { Locale.current.localizedString(forLanguageCode: $0) ?? $0 } ?? "External"
        core.command(["sub-add", sidecar.path, sidecar.selected ? "select" : "auto", title, sidecar.language ?? ""])
      }
      return
    }
    guard let selection, let server = playbackServer else { return }
    selectionApplied = true
    for external in selection.externals {
      let url = server.url(forKey: external.key).absoluteString
      externalStreamIDs[url] = external.streamID
      // The token travels in mpv's http-header-fields, as for the video.
      core.command(["sub-add", url, external.selected ? "select" : "auto", external.title, external.language ?? ""])
    }
    if let index = selection.audioIndex, let id = trackID("audio", ffIndex: index) {
      audioId = id
      core.setProperty("aid", value: String(id))
    }
    if let index = selection.subtitleIndex, let id = trackID("sub", ffIndex: index) {
      subtitleId = id
      core.setProperty("sid", value: String(id))
    }
  }

  private func trackID(_ type: String, ffIndex: Int) -> Int? {
    trackInfo.first { $0.key.hasPrefix(type + ":") && $0.value.ffIndex == ffIndex }
      .flatMap { Int($0.key.dropFirst(type.count + 1)) }
  }

  private func plexAudioID(forTrack id: Int) -> Int? {
    guard let index = trackInfo["audio:\(id)"]?.ffIndex else { return nil }
    return selection?.audioIDs[index]
  }

  private func plexSubtitleID(forTrack id: Int) -> Int? {
    guard let info = trackInfo["sub:\(id)"] else { return nil }
    if let file = info.externalFile { return externalStreamIDs[file] }
    return info.ffIndex.flatMap { selection?.subtitleIDs[$0] }
  }

  /// A track picked in the player is saved on the server as the file's
  /// choice, like any Plex app does, so it is used next time. Streaming only.
  private func saveStreamChoice(audio: Int? = nil, subtitle: Int?? = .none) {
    guard currentMediaID != nil, let server = playbackServer, let part = source?.part, part.id > 0 else { return }
    let subtitleID: Int? = subtitle ?? nil
    guard audio != nil || subtitleID != nil else { return }
    Task { try? await server.setStreams(partID: part.id, audio: audio, subtitle: subtitleID) }
  }

  func setVolume(_ value: Double) {
    volume = min(100, max(0, value))
    markLocalSet("volume", volume)
    core?.setProperty("volume", value: String(format: "%.0f", volume))
    if muted, volume > 0 { setMuted(false) }
  }

  func setMuted(_ value: Bool) {
    muted = value
    markLocalSet("mute", value ? 1 : 0)
    core?.setProperty("mute", value: value ? "yes" : "no")
  }

  func setSpeed(_ value: Double) {
    speed = value
    core?.setProperty("speed", value: String(format: "%.2f", value))
  }

  static let speeds: [Double] = [0.5, 0.75, 1, 1.25, 1.5, 2]

  static var supportsPictureInPicture: Bool {
    #if os(iOS) || os(tvOS)
      PipCoordinator.isSupported
    #else
      true
    #endif
  }

  /// iPhone: system Picture in Picture. Mac: a small floating window in the
  /// corner of the screen, above other apps (mpv has no Mac PiP).
  func togglePictureInPicture() {
    #if os(iOS) || os(tvOS)
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
    #if os(iOS) || os(tvOS)
      core?.updateFrame()
    #endif
  }

  // MARK: - mpv events

  fileprivate func propertyChanged(_ name: String, _ value: Any?) {
    switch name {
    case "time-pos":
      if let v = value as? Double {
        // A seek in flight (up to 5 s): keep the target on the bar.
        if let since = seekingSince, Date().timeIntervalSince(since) < 5 { break }
        position = v
      }
    case "duration":
      if let v = value as? Double, v > 0 {
        duration = v
        updateNowPlaying()
      }
    case "pause":
      if let v = value as? Bool, !isEcho("pause", v ? 1 : 0) {
        paused = v
        updateNowPlaying()
      }
    case "volume": if let v = value as? Double, !isEcho("volume", v) { volume = v }
    case "mute": if let v = value as? Bool, !isEcho("mute", v ? 1 : 0) { muted = v }
    case "speed": if let v = value as? Double { speed = v }
    case "paused-for-cache":
      buffering = (value as? Bool) ?? false
      updateNowPlaying()
      if buffering, hasFirstFrame, !reopening {
        watchMidPlaybackStall()
      } else if !buffering, !reopening {
        stallTask?.cancel()
      }
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
      seekingSince = nil
      if reopening {
        reopening = false
        stallTask?.cancel()
      }
      let wasStarted = hasFirstFrame
      hasFirstFrame = true
      updateNowPlaying()
      // After a seek: Plex gets the new position now, not up to 10 s later.
      if wasStarted { reportSoon() }
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
    previews = SeekPreviewGenerator(url: source.url, mpvURL: source.mpvURL, headers: source.headers)
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
    trackInfo = [:]
    for case let entry as [String: Any] in list {
      guard let id = (entry["id"] as? Int) ?? (entry["id"] as? Int64).map(Int.init), let type = entry["type"] as? String
      else { continue }
      let ffIndex = (entry["ff-index"] as? Int) ?? (entry["ff-index"] as? Int64).map(Int.init)
      trackInfo["\(type):\(id)"] = TrackInfo(ffIndex: ffIndex, externalFile: entry["external-filename"] as? String)
      let lang = (entry["lang"] as? String).map { Locale.current.localizedString(forLanguageCode: $0) ?? $0 }
      let label = [entry["title"] as? String, lang].compactMap { $0 }.first ?? "Track \(id)"
      if type == "audio" { audio.append(Track(id: id, title: label)) }
      if type == "sub" { subs.append(Track(id: id, title: label)) }
    }
    audioTracks = audio
    subtitleTracks = subs
    applyStreamsIfReady()
  }

  // MARK: - Plex progress

  @ObservationIgnored private var lastReportAt = Date.distantPast

  /// A report now, at most one a second (a run of double taps seeks many times).
  private func reportSoon() {
    guard Date().timeIntervalSince(lastReportAt) >= 1 else { return }
    report(paused ? .paused : .playing)
  }

  @ObservationIgnored private var lifecycleObservers: [NSObjectProtocol] = []

  /// Background and quit: the position reaches Plex then too, not only on
  /// the 10 s timer. On quit it is also kept on disk first, so it is sent at
  /// the next launch if the request can't finish in time.
  private func observeLifecycle() {
    guard lifecycleObservers.isEmpty else { return }
    let center = NotificationCenter.default
    #if os(iOS) || os(tvOS)
      let background = UIApplication.didEnterBackgroundNotification
      let quit = UIApplication.willTerminateNotification
    #else
      let background = NSApplication.didResignActiveNotification
      let quit = NSApplication.willTerminateNotification
    #endif
    lifecycleObservers.append(
      center.addObserver(forName: background, object: nil, queue: .main) { [weak self] _ in
        MainActor.assumeIsolated { self?.reportInBackground() }
      })
    lifecycleObservers.append(
      center.addObserver(forName: quit, object: nil, queue: .main) { [weak self] _ in
        MainActor.assumeIsolated { self?.reportOnQuit() }
      })
  }

  private func reportInBackground() {
    guard isActive else { return }
    #if os(iOS) || os(tvOS)
      // A little time to finish the request if iOS suspends Astra (no PiP, paused).
      let task = UIApplication.shared.beginBackgroundTask(withName: "astra.timeline")
      report(paused ? .paused : .playing) {
        if task != .invalid { UIApplication.shared.endBackgroundTask(task) }
      }
    #else
      report(paused ? .paused : .playing)
    #endif
  }

  private func reportOnQuit() {
    guard isActive, let server = playbackServer, let source else { return }
    let report = TimelineReport(
      ratingKey: source.ratingKey, key: source.metadataKey, state: .stopped, timeMs: Int(position * 1000),
      durationMs: duration > 0 ? Int(duration * 1000) : source.durationMs)
    pendingTimelines.record(report, server: server.serverName)
    pendingTimelines.save()
    // Up to a second for the request; whatever doesn't make it goes next launch.
    let done = DispatchSemaphore(value: 0)
    Task.detached {
      try? await server.reportTimeline(report)
      done.signal()
    }
    if done.wait(timeout: .now() + 1) == .success {
      pendingTimelines.superseded(ratingKey: report.ratingKey, server: server.serverName)
      pendingTimelines.save()
    }
  }

  private func startReporting() {
    observeLifecycle()
    reporter?.cancel()
    reporter = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.pause(10)
        guard let self, !Task.isCancelled else { return }
        self.report(self.paused ? .paused : (self.buffering ? .buffering : .playing))
      }
    }
  }

  private func report(_ state: TimelineReport.State, completion: (@MainActor () -> Void)? = nil) {
    guard let server = playbackServer, let source else {
      completion?()
      return
    }
    lastReportAt = Date()
    let report = TimelineReport(
      ratingKey: source.ratingKey, key: source.metadataKey, state: state, timeMs: Int(position * 1000),
      durationMs: duration > 0 ? Int(duration * 1000) : source.durationMs)
    Task { [weak self] in
      do {
        try await server.reportTimeline(report)
        self?.timelineReached(report, server: server)
      } catch {
        // QA P2-6: the final position of a title watched while the server
        // couldn't be reached (offline, a download on a plane) is kept and
        // sent once it answers, instead of being lost.
        if state == .stopped { self?.keepForLater(report, server: server) }
      }
      completion?()
    }
  }

  // MARK: - Progress watched offline (QA P2-6)

  @ObservationIgnored private var pendingTimelines = PendingTimelines.load()
  @ObservationIgnored private var flushing = false
  @ObservationIgnored private var retryTask: Task<Void, Never>?

  private func keepForLater(_ report: TimelineReport, server: PlexServerClient) {
    pendingTimelines.record(report, server: server.serverName)
    pendingTimelines.save()
    scheduleRetry()
  }

  /// A report got through: an older kept one for that title is out of date,
  /// and the server is answering, so send what is still kept.
  private func timelineReached(_ report: TimelineReport, server: PlexServerClient) {
    if !pendingTimelines.reports(for: server.serverName).isEmpty {
      pendingTimelines.superseded(ratingKey: report.ratingKey, server: server.serverName)
      pendingTimelines.save()
      flushPendingTimelines()
    }
  }

  /// Sends the kept reports to the connected server, oldest first. The app
  /// may call it when the server is back online too; it is cheap when nothing is kept.
  func flushPendingTimelines() {
    guard !flushing, let server, !pendingTimelines.reports(for: server.serverName).isEmpty else { return }
    flushing = true
    Task { [weak self] in
      guard let self else { return }
      defer { self.flushing = false }
      var sent: [String] = []
      // Continue Watching and Details show the progress that just arrived.
      defer { for key in sent { self.library?.playbackEnded(ratingKey: key) } }
      for report in self.pendingTimelines.reports(for: server.serverName) {
        do {
          try await server.reportTimeline(report)
          sent.append(report.ratingKey)
        } catch {
          self.scheduleRetry()
          return
        }
        // Only if a newer one for the title wasn't kept meanwhile.
        if self.pendingTimelines.reports(for: server.serverName).contains(report) {
          self.pendingTimelines.superseded(ratingKey: report.ratingKey, server: server.serverName)
          self.pendingTimelines.save()
        }
      }
    }
  }

  /// Tries again later: 30 s, then 1, 2 and 5 minutes, then every 5 minutes.
  private func scheduleRetry() {
    guard retryTask == nil else { return }
    retryTask = Task { [weak self] in
      var wait: Double = 30
      while !Task.isCancelled {
        try? await Task.pause(wait)
        guard let self, !Task.isCancelled else { return }
        guard let server = self.server, !self.pendingTimelines.reports(for: server.serverName).isEmpty else {
          self.retryTask = nil
          return
        }
        self.flushPendingTimelines()
        wait = min(wait * 2, 300)
      }
    }
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
