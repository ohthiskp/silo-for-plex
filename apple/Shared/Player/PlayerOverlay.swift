// Mac and iPhone player chrome. Apple TV has its own (AstraTV/Views/TVPlayerOverlay.swift),
// following docs/design/appletv-player.png.
#if !os(tvOS)

import AstraKit
import SwiftUI
import Observation
#if os(iOS)
  import AVFoundation
  import MediaPlayer
  import UIKit
#endif

/// The minimal player chrome over the video: close and title at the top,
/// big 10 s / pause / 10 s transport in the middle, a white timeline and
/// track chips at the bottom. Fades out after 3 s without the pointer moving.
struct PlayerOverlay: View {
  @Environment(AppModel.self) private var app
  @State private var visible = true
  @State private var hideTask: Task<Void, Never>?
  @State private var scrubbing: Double?
  @State private var lastPoke = Date.distantPast
  /// Settings → Playback → Next Episode button.
  @AppStorage(Preferences.nextEpisodeKey) private var showNextEpisode = true
  #if os(iOS)
    /// The double-tap skip being shown: which side and the seconds so far.
    @State private var skip: (forward: Bool, seconds: Int)?
    @State private var skipShownAt = Date.distantPast
    /// The brightness or volume being swiped, 0…1, while the HUD shows.
    /// The brightness or volume being swiped. Its own observable object, so a
    /// swipe redraws only the level pill, not the whole player.
    @State private var level = LevelState()
    /// Settings → Playback → Gestures (Astra 4.0).
    @AppStorage(Preferences.swipeGesturesKey) private var swipeGestures = true
    @AppStorage(Preferences.twoFingerPauseKey) private var twoFingerPause = true
    @AppStorage(Preferences.skipSecondsKey) private var skipSeconds = 10
    /// Where the visible controls are (window coordinates); taps there belong to them.
    @State private var controlFrames: [String: CGRect] = [:]
    /// The Next Episode button while it shows (it shows with the controls hidden
    /// too): a tap on it must not also show or hide the controls or double-tap skip.
    @State private var nextEpisodeFrame: CGRect?
    /// Whether the controls showed before the last single tap (a double tap restores it).
    @State private var visibleBeforeTap = false
    /// The system volume: what a swipe on the right and the slider set (instant, unlike mpv's).
    @State private var systemVolume = SystemVolume.shared
  #endif

  private var player: PlayerController { app.player }

  var body: some View {
    ZStack {
      // Clear, but hit-testable. Mac: click shows or hides the controls, double-click goes full screen.
      // iPhone: tap shows or hides the controls.
      #if os(macOS)
        // Astra (KP, 2026-11-07): a click on the picture never plays or pauses
        // (only the controls and Space do); it shows or hides the controls.
        // Double-click goes full screen; the title strip (and the mini window) drag the window.
        WindowDragArea(
          onClick: { visible ? hide() : poke() }, onDoubleClick: { player.toggleFullScreen() }
        )
        .ignoresSafeArea()
      #else
        // Astra: one tap shows or hides the controls; a double tap on the right
        // half skips forward 10 s, on the left half back 10 s (KP, 2026-11-07).
        // UIKit recognizers, so the single tap reliably waits for a double.
        PlayerTapSurface(
          blocked: (visible ? Array(controlFrames.values) : []) + [nextEpisodeFrame].compactMap { $0 },
          // KP (2026-11-10): "very very responsive": a tap shows or hides the
          // controls at once, without waiting to see whether a double tap follows.
          onTap: {
            visibleBeforeTap = visible
            visible ? hide() : poke()
          },
          onDoubleTap: { forward in
            // The double tap's first tap toggled the controls; put them back.
            if visible != visibleBeforeTap { visibleBeforeTap ? poke() : hide() }
            doubleTapSkip(forward: forward)
          },
          onSwipe: { right, delta in if swipeGestures { swipeLevel(right: right, delta: delta) } },
          // KP (2026-11-08): a two-finger tap plays or pauses.
          onTwoFingerTap: { if twoFingerPause { player.togglePause() } }
        )
        .ignoresSafeArea()

        // KP (2026-11-10): a swipe on the right moves the subtle volume slider
        // (top right); one on the left shows a brightness level top left, only
        // while the finger is down.
        BrightnessIndicator(level: level)
        if let skip {
          HStack {
            if skip.forward { Spacer() }
            SkipBadge(forward: skip.forward, seconds: skip.seconds)
            if !skip.forward { Spacer() }
          }
          .padding(.horizontal, 72)
          .allowsHitTesting(false)
          .astraTransition(.opacity.combined(with: .scale(scale: 0.9)))
          .id(skip.forward)
        }
      #endif

      chrome
        .opacity(visible ? 1 : 0)
        .allowsHitTesting(visible)

      // Astra 4.0: Next Episode in the last 15 s of an episode, tap only.
      // Only in the tree for an episode with a next one, so it never sits
      // over the swipe and tap areas otherwise.
      if showNextEpisode, player.upNext != nil {
        NextEpisodeButton(player: player, onFrame: onNextEpisodeFrame)
          #if os(macOS)
            .padding(.trailing, 28)
            .padding(.bottom, 150)
          #else
            // Clear of the captions/quality capsule and the timeline (KP: "spaced better").
            .padding(.trailing, 20)
            .padding(.bottom, 132)
          #endif
      }

      if loaderInRing {
        // iPhone with controls showing: the play button's ring shows loading.
      } else if !player.hasFirstFrame {
        // Until the first frame: the title and a spinner, never a blank black window.
        VStack(spacing: 14) {
          ProgressView().controlSize(.large).tint(.white)
          Text(player.title).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
            .lineLimit(1)
          Text("Starting…").font(.system(size: 13)).foregroundStyle(.white.opacity(0.6))
        }
        .padding(.horizontal, 24)
        .allowsHitTesting(false)
        .transition(.opacity)
      } else if player.buffering {
        ProgressView().controlSize(.large).tint(.white)
          .allowsHitTesting(false)
          .transition(.opacity)
      }
    }
    // iPhone: the controls come and go in 0.15 s (KP, 2026-11-10: "very very responsive").
    .astraAnimation(Self.showHide, value: visible)
    .astraAnimation(Astra.Motion.fast, value: player.buffering)
    .astraAnimation(Astra.Motion.base, value: player.hasFirstFrame)
    #if os(macOS)
      .onContinuousHover { phase in
        // Every mouse move reaches here; restart the hide timer at most a few times a second.
        if case .active = phase, !visible || Date().timeIntervalSince(lastPoke) > 0.25 { poke() }
      }
    #endif
    .coordinateSpace(.named(Self.space))
    .onAppear {
      poke()
      applyDemo()
    }
    .onChange(of: player.paused) { _, paused in
      if paused { visible = true } else { poke() }
    }
    .onDisappear { hideTask?.cancel() }
    .onGeometryChange(for: CGSize.self, of: { $0.size }) { _ in player.layoutChanged() }
    #if os(iOS)
      .statusBarHidden(!visible)
      .persistentSystemOverlays(.hidden)
    #endif
  }

  static let space = "player"

  #if os(iOS)
    static let showHide = Astra.Motion.fast
  #else
    static let showHide = Astra.Motion.base
  #endif

  /// iPhone: while the controls show, the play button itself shows loading.
  private var loaderInRing: Bool {
    #if os(iOS)
      visible
    #else
      false
    #endif
  }

  private var chrome: some View {
    ZStack {
      // Scrims so white text reads over any frame.
      VStack(spacing: 0) {
        LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom).frame(height: 160)
        Spacer()
        // Light at the bottom: the Mac panel is clear glass and carries its own contrast.
        LinearGradient(colors: [.clear, .black.opacity(Self.bottomScrim)], startPoint: .top, endPoint: .bottom)
          .frame(height: 200)
      }
      .ignoresSafeArea()
      .allowsHitTesting(false)

      #if os(macOS)
        if player.isPictureInPicture { miniChrome } else { macChrome }
      #else
        phoneChrome
      #endif
    }
  }

  /// Both platforms: bare white controls over the picture need the same shade under them.
  private static let bottomScrim = 0.7

  // MARK: Mac (KP, 2026-11-10: the iPhone player's design on the Mac)

  #if os(macOS)
    /// The same layout as the iPhone player (KP's 2026-11-10 mockups): close
    /// top left, a subtle volume slider top right; back 10 / play / forward 10
    /// in the middle; the title with its HD/4K badge bottom left (and
    /// "S2 · E4 · Title" for an episode); bare subtitle, PiP and full-screen
    /// glyphs bottom right; the scrubber with its times along the bottom.
    /// While scrubbing only the scrubber shows.
    private var macChrome: some View {
      ZStack {
        VStack(spacing: 0) {
          HStack(alignment: .center, spacing: 12) {
            Button {
              player.close()
            } label: {
              Image(systemName: "xmark")
            }
            .astraIconButton(size: 36, variant: .clear)
            .keyboardShortcut(.cancelAction)
            .help("Close (Esc)")
            .accessibilityLabel("Close Player")
            Spacer()
            MacVolume(player: player, poke: poke)
          }
          // Below the traffic lights (the title-bar strip is ~28 pt).
          .padding(.top, 40)
          .opacity(scrubbing == nil ? 1 : 0)
          .allowsHitTesting(scrubbing == nil)
          Spacer()
          HStack(alignment: .bottom, spacing: 16) {
            Button {
              player.showDetails()
            } label: {
              VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                  Text(player.title).font(.system(size: 24, weight: .bold)).lineLimit(1)
                  // The real resolution of the frames playing; nothing until it is known.
                  if let badge = resolutionTag { ResolutionTag(text: badge, size: 10) }
                }
                if let subtitle = player.subtitle, !subtitle.isEmpty {
                  Text(subtitle).font(.system(size: 14, weight: .medium)).foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
                }
              }
              .foregroundStyle(.white)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Details")
            .accessibilityLabel("\(player.title), Details")
            Spacer(minLength: 16)
            HStack(spacing: 6) {
              captionsChip
              macGlyph(
                player.isPictureInPicture ? "pip.exit" : "pip.enter", label: "Picture in Picture",
                help: "Picture in Picture"
              ) { player.togglePictureInPicture() }
              macGlyph("arrow.up.left.and.arrow.down.right", label: "Full Screen", help: "Full Screen (F)") {
                player.toggleFullScreen()
              }
              .keyboardShortcut("f", modifiers: [])
            }
          }
          .padding(.bottom, 10)
          .opacity(scrubbing == nil ? 1 : 0)
          .allowsHitTesting(scrubbing == nil)
          PhoneScrubber(player: player, scrubbing: $scrubbing, poke: poke)
            .frame(maxWidth: 1400)
        }
        transport(small: 28, large: 42, gap: 64, framedPause: false)
          .opacity(scrubbing == nil ? 1 : 0)
          .allowsHitTesting(scrubbing == nil)
      }
      .padding(.horizontal, 28)
      .padding(.bottom, 18)
      // Laid out against the window's own edges, not its title-bar safe area,
      // so a short window (a wide film) keeps the X clear of the traffic lights
      // and the times under the scrubber on screen.
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .ignoresSafeArea()
      .astraAnimation(Astra.Motion.fast, value: scrubbing == nil)
    }

    /// A bare white glyph like the iPhone's subtitle button: no box or glass.
    private func macGlyph(_ symbol: String, label: String, help: String, action: @escaping () -> Void) -> some View {
      Button(action: action) {
        Image(systemName: symbol)
          .font(.system(size: 17, weight: .medium))
          .frame(width: 36, height: 36)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .foregroundStyle(.white)
      .shadow(color: .black.opacity(0.4), radius: 6)
      .help(help)
      .accessibilityLabel(label)
    }

    /// The small floating window: play/pause and a button back to full size.
    private var miniChrome: some View {
      ZStack {
        transport(small: 22, large: 28, gap: 26, framedPause: false)
        VStack {
          HStack {
            Spacer()
            pipButton(size: 32)
          }
          Spacer()
        }
        .padding(10)
      }
    }
  #endif

  // MARK: iPhone (docs/design/iphone-player.png)

  #if os(iOS)
    /// KP's player mockups (2026-11-10): close and PiP top left, a subtle
    /// volume slider top right; back 10 / play / forward 10 in the middle;
    /// the title with a small HD/4K badge bottom left (and "S2 · E4 · Title"
    /// for an episode), the subtitle button and ⋯ bottom right; the scrubber
    /// with its times along the bottom. While scrubbing only the scrubber shows.
    private var phoneChrome: some View {
      ZStack {
        VStack(spacing: 0) {
          HStack(alignment: .center, spacing: 12) {
            Button {
              player.close()
            } label: {
              Image(systemName: "xmark")
            }
            .astraIconButton(size: 44, variant: .clear)
            .accessibilityLabel("Close Player")
            .reportFrame("close", into: $controlFrames)
            Spacer()
            // KP (2026-11-10): no PiP and no ⋯ on iPhone; volume only, top right.
            SubtleVolume(player: player, volume: systemVolume, level: level, poke: poke)
              .reportFrame("volume", into: $controlFrames)
          }
          .opacity(scrubbing == nil ? 1 : 0)
          .allowsHitTesting(scrubbing == nil)
          Spacer()
          HStack(alignment: .bottom, spacing: 16) {
            Button {
              player.showDetails()
            } label: {
              VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                  Text(player.title).font(.system(size: 22, weight: .bold)).lineLimit(1)
                  // The real resolution of the frames playing; nothing until it is known.
                  if let badge = resolutionTag { ResolutionTag(text: badge, size: 9) }
                }
                // Episodes only: "S2 · E4 · Episode Title". Movies show nothing here.
                if let subtitle = player.subtitle, !subtitle.isEmpty {
                  Text(subtitle).font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
                }
              }
              .foregroundStyle(.white)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(player.title), Details")
            .reportFrame("titleButton", into: $controlFrames)
            Spacer(minLength: 16)
            // KP (2026-11-10): a bare subtitle glyph, no box or glass around it; alone bottom right.
            captionsChip
              .reportFrame("captions", into: $controlFrames)
          }
          .padding(.bottom, 10)
          .opacity(scrubbing == nil ? 1 : 0)
          .allowsHitTesting(scrubbing == nil)
          PhoneScrubber(player: player, scrubbing: $scrubbing, poke: poke)
            .reportFrame("timeline", into: $controlFrames)
        }
        phoneTransport
          .opacity(scrubbing == nil ? 1 : 0)
          .allowsHitTesting(scrubbing == nil)
      }
      // Inside the safe area: clear of the notch / Dynamic Island and the home indicator.
      .padding(.horizontal, 20)
      .padding(.top, 10)
      .padding(.bottom, 6)
      .astraAnimation(Astra.Motion.fast, value: scrubbing == nil)
    }

    /// Back 10 s, play/pause (a spinner in its place while loading), forward 10 s.
    /// No ring around Play (KP, 2026-11-07).
    private var phoneTransport: some View {
      HStack(spacing: 72) {
        Button {
          player.seek(by: -10)
          poke()
        } label: {
          Image(systemName: "gobackward.10").font(.system(size: 30, weight: .medium))
        }
        .buttonStyle(PlayerGlyphButtonStyle(size: 56))
        .accessibilityLabel("Back 10 Seconds")
        .reportFrame("back10", into: $controlFrames)

        Button {
          player.togglePause()
        } label: {
          ZStack {
            if player.buffering || !player.hasFirstFrame {
              ProgressView().controlSize(.large).tint(.white)
            } else {
              // Swapped at once (no symbol animation), so play/pause feels instant.
              Image(systemName: player.paused ? "play.fill" : "pause.fill")
                .font(.system(size: 44, weight: .bold))
            }
          }
          .frame(width: 76, height: 76)
          .contentShape(Circle())
        }
        .buttonStyle(PlayerGlyphButtonStyle(size: 76))
        .accessibilityLabel(player.paused ? "Play" : "Pause")
        .reportFrame("play", into: $controlFrames)

        Button {
          player.seek(by: 10)
          poke()
        } label: {
          Image(systemName: "goforward.10").font(.system(size: 30, weight: .medium))
        }
        .buttonStyle(PlayerGlyphButtonStyle(size: 56))
        .accessibilityLabel("Forward 10 Seconds")
        .reportFrame("forward10", into: $controlFrames)
      }
      .shadow(color: .black.opacity(0.35), radius: 8)
    }

    /// Swipe on the right: mpv's volume; on the left: the screen's brightness.
    private func swipeLevel(right: Bool, delta: Double?) {
      guard let delta else {
        let ended = level.generation
        Task { @MainActor in
          // The UI tests (demo mode) need longer to read it.
          try? await Task.pause(Demo.isOn ? 4 : 0.5)
          if level.generation == ended { level.shown = false }
        }
        return
      }
      if delta == 0 {
        level.generation += 1
        level.volume = right
        level.start = right ? (player.muted ? 0 : systemVolume.level) : Double(UIScreen.main.brightness)
        level.value = level.start
        if !right { level.brightness = level.start }
        level.shown = true
        // Volume shows on the slider among the controls; brightness has its own
        // indicator, so a swipe on the left leaves the controls as they are.
        if right || visible { poke() }
        return
      }
      let value = min(1, max(0, level.start + delta))
      level.value = value
      if right {
        if player.muted, value > 0 { player.setMuted(false) }
        // The system volume, like Infuse: it changes at once (mpv's own volume
        // only takes effect after its audio buffer, which felt like a delay).
        systemVolume.set(value)
      } else {
        level.brightness = value
        UIScreen.main.brightness = CGFloat(value)
      }
      if right || visible { poke() }
    }

    /// Skips 10 s; quick repeated double taps on the same side add up (10, 20, 30…).
    private func doubleTapSkip(forward: Bool) {
      let step = max(5, skipSeconds)
      player.seek(by: Double(forward ? step : -step))
      let now = Date()
      let adds = skip?.forward == forward && now.timeIntervalSince(skipShownAt) < 1
      astraWithAnimation(Astra.Motion.fast) { skip = (forward, adds ? (skip?.seconds ?? 0) + step : step) }
      skipShownAt = now
      Task { @MainActor in
        // The UI tests (demo mode) need longer to read the badge.
        let shown = Demo.isOn ? 8.0 : 0.9
        try? await Task.pause(shown)
        if Date().timeIntervalSince(skipShownAt) >= shown - 0.05 { astraWithAnimation(Astra.Motion.base) { skip = nil } }
      }
    }

  #endif

  // MARK: Shared pieces

  /// The timeline is its own view so the ~4 position updates a second
  /// redraw only the bar, not the whole player chrome.
  private var timeline: some View {
    PlayerTimeline(player: player, scrubbing: $scrubbing, poke: poke)
  }

  /// Back 10 s, play/pause, forward 10 s: bold white glyphs.
  private func transport(small: CGFloat, large: CGFloat, gap: CGFloat, framedPause: Bool) -> some View {
    HStack(spacing: gap) {
      Button {
        player.seek(by: -10)
        poke()
      } label: {
        Image(systemName: "gobackward.10").font(.system(size: small, weight: .regular))
      }
      .buttonStyle(PlayerGlyphButtonStyle(size: small * 1.6))
      .keyboardShortcut(.leftArrow, modifiers: [])
      .accessibilityLabel("Back 10 Seconds")

      Button {
        player.togglePause()
      } label: {
        // Swapped at once (no symbol animation), so play/pause feels instant.
        Image(systemName: player.paused ? "play.fill" : "pause.fill")
          .font(.system(size: large, weight: .bold))
      }
      .buttonStyle(PlayerGlyphButtonStyle(size: framedPause ? large * 2.3 : large * 1.6, filled: framedPause, square: true))
      .keyboardShortcut(.space, modifiers: [])
      .accessibilityLabel(player.paused ? "Play" : "Pause")

      Button {
        player.seek(by: 10)
        poke()
      } label: {
        Image(systemName: "goforward.10").font(.system(size: small, weight: .regular))
      }
      .buttonStyle(PlayerGlyphButtonStyle(size: small * 1.6))
      .keyboardShortcut(.rightArrow, modifiers: [])
      .accessibilityLabel("Forward 10 Seconds")
    }
    .shadow(color: .black.opacity(0.35), radius: 8)
  }

  private func pipButton(size: CGFloat) -> some View {
    Button {
      player.togglePictureInPicture()
    } label: {
      Image(systemName: player.isPictureInPicture ? "pip.exit" : "pip.enter")
    }
    .astraIconButton(size: size, variant: .clear)
    .help(player.isPictureInPicture ? "Exit Picture in Picture" : "Picture in Picture")
    .accessibilityLabel(player.isPictureInPicture ? "Exit Picture in Picture" : "Picture in Picture")
  }

  /// "CC": subtitles, and audio tracks on iPhone (the Mac has them under More).
  private var captionsChip: some View {
    Menu {
      Section("Subtitles") {
        Button {
          player.selectSubtitle(nil)
        } label: {
          checked("Off", player.subtitleId == nil)
        }
        ForEach(player.subtitleTracks) { track in
          Button {
            player.selectSubtitle(track.id)
          } label: {
            checked(track.title, player.subtitleId == track.id)
          }
        }
      }
    } label: {
      // Astra: a speech-bubble captions glyph (KP asked for a new icon); filled when subtitles are on.
      #if os(iOS)
        // iPhone: a bare glyph like the ⋯ and speaker, with a soft shadow for contrast.
        Image(systemName: player.subtitleId == nil ? "captions.bubble" : "captions.bubble.fill")
          .font(.system(size: 22, weight: .medium))
          .foregroundStyle(.white)
          .contentTransition(.symbolEffect(.replace))
          .frame(width: 44, height: 44)
          .contentShape(Rectangle())
          .shadow(color: .black.opacity(0.4), radius: 6)
      #else
        // Mac (KP, 2026-11-10): the same bare glyph, beside PiP and full screen.
        Image(systemName: player.subtitleId == nil ? "captions.bubble" : "captions.bubble.fill")
          .font(.system(size: 17, weight: .medium))
          .foregroundStyle(.white)
          .contentTransition(.symbolEffect(.replace))
          .frame(width: 36, height: 36)
          .contentShape(Rectangle())
          .shadow(color: .black.opacity(0.4), radius: 6)
      #endif
    }
    .menuStyle(.button)
    .buttonStyle(.plain)
    .menuIndicator(.hidden)
    .fixedSize()
    .help("Subtitles")
    .accessibilityLabel("Subtitles")
  }

  /// "4K ⌄": the resolution of the file playing. Its menu is Auto / HD / 4K,
  /// the same preference as Settings; it only picks between the title's
  /// original versions, nothing is ever transcoded.
  private var versionChip: some View {
    Menu {
      // Astra (KP, 2026-11-07): the real files of this title, HD and 4K
      // (including the copy in a 4K library); picking one switches to it.
      if player.versions.count > 1 {
        ForEach(player.versions) { version in
          Button {
            player.playVersion(version)
          } label: {
            if version.media.id == player.currentMediaID {
              Label("\(version.badge)  \(version.detail)", systemImage: "checkmark")
            } else {
              Text("\(version.badge)  \(version.detail)")
            }
          }
        }
      } else {
        Text(player.versions.isEmpty ? "Looking for other versions…" : "Only one version on your server")
      }
    } label: {
      HStack(spacing: 6) {
        Text(shortBadge).font(.system(size: 12, weight: .semibold))
        Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
      }
      .playerChip()
    }
    .menuStyle(.button)
    .buttonStyle(.plain)
    .menuIndicator(.hidden)
    .fixedSize()
    .help("Quality")
    .accessibilityLabel("Quality, \(shortBadge)")
  }

  /// iPhone: "4K" or "HD" from the frames mpv is decoding; nil (no badge) until known or below HD.
  private var resolutionTag: String? {
    guard let badge = player.resolutionBadge else { return nil }
    return badge == "4K UHD" ? "4K" : badge
  }

  /// "4K" or "HD" from what mpv is decoding; "SD" below 720.
  private var shortBadge: String {
    guard let badge = player.resolutionBadge else { return player.videoHeight > 0 ? "SD" : "—" }
    return badge == "4K UHD" ? "4K" : badge
  }

  @ViewBuilder private var audioButtons: some View {
    ForEach(player.audioTracks) { track in
      Button {
        player.selectAudio(track.id)
      } label: {
        checked(track.title, player.audioId == track.id)
      }
    }
  }

  @ViewBuilder private func checked(_ title: String, _ on: Bool) -> some View {
    if on { Label(title, systemImage: "checkmark") } else { Text(title) }
  }

  private var onNextEpisodeFrame: (CGRect?) -> Void {
    #if os(iOS)
      { nextEpisodeFrame = $0 }
    #else
      { _ in }
    #endif
  }

  /// Shows the chrome and schedules it to hide again.
  private func poke() {
    lastPoke = Date()
    visible = true
    hideTask?.cancel()
    hideTask = Task { @MainActor in
      try? await Task.pause(3)
      guard !Task.isCancelled, !player.paused, scrubbing == nil else { return }
      hide()
    }
  }

  /// CI screenshots: `-AstraDemoPlayer controls|scrub` (iPhone and Mac).
  private func applyDemo() {
    guard let shot = Demo.playerShot else { return }
    Task { @MainActor in
      for _ in 0..<60 where !player.hasFirstFrame { try? await Task.pause(0.25) }
      try? await Task.pause(1)
      player.setPaused(true)
      switch shot {
      case "scrub": scrubbing = player.duration * 0.35
      default: poke()
      }
    }
  }

  private func hide() {
    visible = false
    #if os(macOS)
      NSCursor.setHiddenUntilMouseMoves(true)
    #endif
  }

  static func clock(_ seconds: Double) -> String {
    let total = Int(seconds.rounded(.down))
    let h = total / 3600
    let m = (total % 3600) / 60
    let s = total % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
  }
}

/// Elapsed or remaining time. Reads the position itself, so only this text redraws as it ticks.
struct PlayerClock: View {
  let player: PlayerController
  var scrubbing: Double?
  var remaining: Bool

  var body: some View {
    let position = scrubbing ?? player.position
    Text(remaining ? "-" + PlayerOverlay.clock(max(0, player.duration - position)) : PlayerOverlay.clock(position))
  }
}

/// The playback timeline with seek previews.
struct PlayerTimeline: View {
  let player: PlayerController
  @Binding var scrubbing: Double?
  var poke: () -> Void
  /// 0 hides the knob (iPhone, Infuse-style).
  var knob: CGFloat = 12
  var height: CGFloat = 3

  var body: some View {
    let shown = scrubbing ?? player.position
    ScrubBar(
      fraction: player.duration > 0 ? shown / player.duration : 0, knob: knob, height: height,
      onChange: { fraction in
        scrubbing = fraction * player.duration
        poke()
      },
      onCommit: { fraction in
        player.seek(to: fraction * player.duration)
        scrubbing = nil
      },
      preview: { fraction in
        let seconds = fraction * player.duration
        return (image: player.thumbnail(at: seconds), label: PlayerOverlay.clock(seconds))
      }
    )
    .accessibilityLabel("Playback Position")
    .accessibilityValue(PlayerOverlay.clock(shown))
  }
}

/// A white scrub bar with a round white knob. Dragging previews and commits on release.
struct ScrubBar: View {
  var fraction: Double
  var knob: CGFloat
  var height: CGFloat
  var onChange: (Double) -> Void
  var onCommit: (Double) -> Void
  /// Seek preview: the image and time label for a point on the bar (the
  /// timeline only). Shown while dragging, and on Mac while hovering.
  var preview: ((Double) -> (image: PlatformImage?, label: String))? = nil

  @State private var dragging = false
  @State private var hover: Double?
  @State private var dragAt: Double?

  private static let previewSize = CGSize(width: 192, height: 108)

  var body: some View {
    GeometryReader { geo in
      let f = min(1, max(0, fraction.isFinite ? fraction : 0))
      let width = geo.size.width
      // Without a knob the bar itself thickens while dragging.
      let bar = knob == 0 && dragging ? height * 1.8 : height
      ZStack(alignment: .leading) {
        Capsule().fill(.white.opacity(0.3)).frame(height: bar)
        Capsule().fill(.white).frame(width: max(bar, width * f), height: bar)
        if knob > 0 {
          Circle().fill(.white)
            .frame(width: knob, height: knob)
            .shadow(color: .black.opacity(0.35), radius: 4)
            .scaleEffect(dragging ? 1.2 : 1)
            .offset(x: width * f - knob / 2)
        }
      }
      .frame(maxHeight: .infinity)
      .contentShape(Rectangle())
      .overlay(alignment: .bottomLeading) {
        if let preview, let at = dragAt ?? hover {
          previewView(preview(at), at: at, width: width)
        }
      }
      #if os(macOS)
        .onContinuousHover { phase in
          guard preview != nil else { return }
          switch phase {
          case .active(let point): hover = value(at: point.x, width: width)
          case .ended: hover = nil
          }
        }
      #endif
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged {
            dragging = true
            let v = value(at: $0.location.x, width: width)
            dragAt = v
            onChange(v)
          }
          .onEnded {
            dragging = false
            dragAt = nil
            onCommit(value(at: $0.location.x, width: width))
          }
      )
    }
    .frame(height: max(knob, 22) + 6)
    .astraAnimation(Astra.Motion.fast, value: dragging)
  }

  /// The preview card above the bar, centred on the pointer, kept inside the bar's width.
  @ViewBuilder
  private func previewView(_ content: (image: PlatformImage?, label: String), at: Double, width: CGFloat) -> some View {
    let size = Self.previewSize
    let hasImage = content.image != nil
    let cardWidth = hasImage ? size.width : 72
    let x = min(max(0, width * at - cardWidth / 2), max(0, width - cardWidth))
    VStack(spacing: 8) {
      if let image = content.image {
        Image(platformImage: image)
          .resizable()
          .aspectRatio(contentMode: .fill)
          .frame(width: size.width, height: size.height)
          .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
          .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(.white.opacity(0.35), lineWidth: 1))
          .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
      }
      Text(content.label)
        .font(.system(size: 13, weight: .semibold).monospacedDigit())
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.black.opacity(0.55), in: Capsule())
    }
    .frame(width: cardWidth)
    // Astra (KP, 2026-11-07): lifted clear of the bar and the controls'
    // glass panel above it, so the time never sits on the panel's edge.
    .offset(x: x, y: -(max(knob, 22) + 6) - 26)
    .allowsHitTesting(false)
    .transition(.opacity)
  }

  private func value(at x: CGFloat, width: CGFloat) -> Double {
    guard width > 0 else { return 0 }
    return Double(min(1, max(0, x / width)))
  }
}

/// A plain white glyph button for the player; `filled` adds a soft fill (it
/// sits on glass, so no glass on glass), `square` makes that fill a rounded square.
struct PlayerGlyphButtonStyle: ButtonStyle {
  var size: CGFloat
  var filled = false
  var square = false

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .foregroundStyle(.white)
      .frame(width: size, height: size)
      .background {
        if filled {
          if square {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).fill(.white.opacity(0.14))
          } else {
            Circle().fill(.white.opacity(0.12))
          }
        }
      }
      .contentShape(Rectangle())
      .scaleEffect(configuration.isPressed ? 0.9 : 1)
      .opacity(configuration.isPressed ? 0.8 : 1)
      .astraAnimation(Astra.Motion.fast, value: configuration.isPressed)
  }
}

extension View {
  /// The player's glass pill for CC and the version chip.
  func playerChip() -> some View {
    self
      .foregroundStyle(.white)
      .padding(.horizontal, 10)
      .frame(height: 28)
      .contentShape(Capsule())
      .astraGlass(in: Capsule(), variant: .clear, interactive: true)
  }
}

#if os(iOS)
  /// The round glass badge shown where a double tap skipped: "10" under the arrow.
  struct SkipBadge: View {
    var forward: Bool
    var seconds: Int

    var body: some View {
      VStack(spacing: 4) {
        Image(systemName: forward ? "goforward" : "gobackward").font(.system(size: 26, weight: .semibold))
        Text("\(seconds)s").font(.system(size: 13, weight: .semibold).monospacedDigit())
          .contentTransition(.numericText())
      }
      .foregroundStyle(.white)
      .frame(width: 88, height: 88)
      .astraGlass(in: Circle(), variant: .clear)
      .astraGlassEdge(Circle(), strength: 0.6)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(forward ? "Forward \(seconds) seconds" : "Back \(seconds) seconds")
      .accessibilityIdentifier(forward ? "astra.skip.forward" : "astra.skip.back")
    }
  }

  /// Top right (KP's mockup, 2026-11-10): a subtle volume slider, no pill and
  /// no percentage. A thin 3 pt track about 150 pt wide at 70% opacity; while
  /// dragging (or while a swipe on the right changes the volume) it thickens
  /// and goes fully opaque. The speaker glyph follows the level; tap it to mute.
  /// Its own view, so volume changes redraw only this slider.
  struct SubtleVolume: View {
    var player: PlayerController
    var volume: SystemVolume
    var level: LevelState
    var poke: () -> Void
    @State private var dragging = false

    private var value: Double { player.muted ? 0 : volume.level }
    /// Dragging here, or swiping on the right side of the picture.
    private var active: Bool { dragging || (level.shown && level.volume) }

    var body: some View {
      HStack(spacing: 10) {
        GeometryReader { geo in
          let width = geo.size.width
          let track: CGFloat = active ? 6 : 3
          ZStack(alignment: .leading) {
            Capsule().fill(.white.opacity(0.3)).frame(height: track)
            Capsule().fill(.white).frame(width: max(track, width * value), height: track)
          }
          .frame(maxHeight: .infinity)
          .contentShape(Rectangle())
          .gesture(
            DragGesture(minimumDistance: 0)
              .onChanged { drag in
                dragging = true
                if player.muted { player.setMuted(false) }
                volume.set(Double(drag.location.x / max(width, 1)))
                poke()
              }
              .onEnded { _ in dragging = false }
          )
        }
        .frame(width: 150, height: 44)
        Button {
          player.setMuted(!player.muted)
          poke()
        } label: {
          Image(systemName: symbol).font(.system(size: 15, weight: .semibold))
            .frame(width: 26, height: 44, alignment: .leading)
            .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(player.muted ? "Unmute" : "Mute")
      }
      .foregroundStyle(.white)
      .opacity(active ? 1 : 0.7)
      .shadow(color: .black.opacity(0.35), radius: 6)
      .astraAnimation(Astra.Motion.fast, value: active)
      .accessibilityElement(children: .contain)
      .accessibilityLabel("Volume")
      .accessibilityValue("\(Int((value * 100).rounded())) percent")
      .accessibilityIdentifier("astra.level.volume")
      .accessibilityAdjustableAction { direction in
        volume.set(value + (direction == .increment ? 0.1 : -0.1))
      }
    }

    private var symbol: String {
      if value == 0 { return "speaker.slash.fill" }
      return value < 0.34 ? "speaker.wave.1.fill" : value < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
    }
  }

  /// The phone's own volume (what the side buttons change), set through a
  /// hidden MPVolumeView so it changes instantly and the system's volume HUD
  /// stays away while the player shows. KP (2026-11-10): "immediate volume".
  @MainActor @Observable final class SystemVolume {
    static let shared = SystemVolume()

    /// 0…1, kept in step with the side buttons.
    private(set) var level = Double(AVAudioSession.sharedInstance().outputVolume)

    @ObservationIgnored private let view: MPVolumeView = {
      let view = MPVolumeView(frame: CGRect(x: -1000, y: -1000, width: 100, height: 40))
      view.alpha = 0.01
      view.isUserInteractionEnabled = false
      return view
    }()
    @ObservationIgnored private var observation: NSKeyValueObservation?

    /// The volume view must be in a window for its slider to work.
    func attach(to window: UIWindow) {
      if view.superview !== window { window.addSubview(view) }
      level = Double(AVAudioSession.sharedInstance().outputVolume)
      guard observation == nil else { return }
      observation = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.new]) { [weak self] _, change in
        guard let value = change.newValue, let self else { return }
        Task { @MainActor in self.level = Double(value) }
      }
    }

    func detach() {
      view.removeFromSuperview()
      observation?.invalidate()
      observation = nil
    }

    func set(_ value: Double) {
      let value = min(1, max(0, value))
      level = value
      guard let slider = view.subviews.lazy.compactMap({ $0 as? UISlider }).first else { return }
      slider.value = Float(value)
      slider.sendActions(for: .valueChanged)
    }
  }

  /// The brightness or volume being swiped. Its own observable object, so a
  /// swipe redraws only what shows it.
  @Observable final class LevelState {
    var shown = false
    var volume = false
    var value = 0.0
    var start = 0.0
    var generation = 0
    /// The screen's brightness while a swipe on the left changes it.
    var brightness = Double(UIScreen.main.brightness)
  }

  /// KP (2026-11-10): a brightness level top left, beside the close button,
  /// only while a swipe on the left changes it. It matches the volume slider:
  /// a sun that follows the level and a thin white track, no percentage.
  struct BrightnessIndicator: View {
    var level: LevelState

    private static let width: CGFloat = 150

    var body: some View {
      VStack {
        HStack {
          if level.shown && !level.volume {
            HStack(spacing: 10) {
              Image(systemName: level.brightness < 0.5 ? "sun.min.fill" : "sun.max.fill")
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 22)
              ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.3)).frame(width: Self.width, height: 6)
                Capsule().fill(.white).frame(width: max(6, Self.width * level.brightness), height: 6)
              }
            }
            .frame(height: 44)
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.35), radius: 6)
            .accessibilityElement()
            .accessibilityLabel("Brightness")
            .accessibilityValue("\(Int((level.brightness * 100).rounded())) percent")
            .accessibilityIdentifier("astra.level.brightness")
            .transition(.opacity)
          }
          Spacer(minLength: 0)
        }
        Spacer(minLength: 0)
      }
      // Beside the close button (20 pt edge + 44 pt button + 12 pt gap), on its row.
      .padding(.leading, 76)
      .padding(.top, 10)
      .allowsHitTesting(false)
      .astraAnimation(Astra.Motion.fast, value: level.shown && !level.volume)
    }
  }

  /// One tap / double tap anywhere on the player, read by UIKit recognizers on
  /// the window itself, so nothing SwiftUI draws can swallow them. Taps inside
  /// `blocked` (the visible controls) are left to the controls.
  struct PlayerTapSurface: UIViewRepresentable {
    var blocked: [CGRect]
    var onTap: () -> Void
    var onDoubleTap: (_ forward: Bool) -> Void
    /// A vertical swipe: which half it started on (right = true), and how far
    /// it has moved as a fraction of the screen's height (up is positive).
    /// `nil` when the swipe ends.
    var onSwipe: (_ right: Bool, _ delta: Double?) -> Void = { _, _ in }
    var onTwoFingerTap: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> Anchor {
      let view = Anchor()
      view.coordinator = context.coordinator
      view.isUserInteractionEnabled = false
      return view
    }

    func updateUIView(_ view: Anchor, context: Context) {
      context.coordinator.blocked = blocked
      context.coordinator.onTap = onTap
      context.coordinator.onDoubleTap = onDoubleTap
      context.coordinator.onSwipe = onSwipe
      context.coordinator.onTwoFingerTap = onTwoFingerTap
    }

    static func dismantleUIView(_ view: Anchor, coordinator: Coordinator) {
      coordinator.detach()
    }

    /// Installs the recognizers on whichever window it lands in.
    final class Anchor: UIView {
      weak var coordinator: Coordinator?
      override func didMoveToWindow() {
        super.didMoveToWindow()
        if let window { coordinator?.attach(to: window) } else { coordinator?.detach() }
      }
    }

    @MainActor final class Coordinator: NSObject, UIGestureRecognizerDelegate {
      var blocked: [CGRect] = []
      var onTap: () -> Void = {}
      var onDoubleTap: (Bool) -> Void = { _ in }
      var onSwipe: (Bool, Double?) -> Void = { _, _ in }
      var onTwoFingerTap: () -> Void = {}
      private var recognizers: [UIGestureRecognizer] = []
      private var swipeRight = false
      /// The last single tap: a tap soon after it, close by, is a double tap's second.
      private var lastTap: (at: Date, point: CGPoint) = (.distantPast, .zero)
      private weak var pan: UIPanGestureRecognizer?

      func attach(to window: UIWindow) {
        detach()
        let double = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        double.numberOfTapsRequired = 2
        // KP (2026-11-10): no waiting for a possible double tap; the single tap
        // fires at once (the double tap then puts the controls back).
        let single = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        // Astra (KP, 2026-11-07): swipe up/down on the left for brightness, on the right for volume.
        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        pan.maximumNumberOfTouches = 1
        let twoFinger = UITapGestureRecognizer(target: self, action: #selector(twoFingerTapped(_:)))
        twoFinger.numberOfTouchesRequired = 2
        for recognizer in [double, single, pan, twoFinger] {
          // Let SwiftUI see every touch too (buttons, the timeline).
          recognizer.cancelsTouchesInView = false
          recognizer.delaysTouchesEnded = false
          recognizer.delegate = self
          window.addGestureRecognizer(recognizer)
        }
        // A swipe that has begun owns its touches, so the button it started on doesn't fire.
        pan.cancelsTouchesInView = true
        self.pan = pan
        recognizers = [double, single, pan, twoFinger]
        SystemVolume.shared.attach(to: window)
        #if DEBUG
          NSLog("Astra gesture: recognizers attached to window %@", String(describing: window))
        #endif
      }

      func detach() {
        for recognizer in recognizers { recognizer.view?.removeGestureRecognizer(recognizer) }
        recognizers = []
        SystemVolume.shared.detach()
      }

      func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let window = recognizer.view else { return false }
        // KP (2026-11-10): the whole right side is volume and the whole left side
        // brightness, over the controls too (the swipe is vertical; the sliders are not).
        // KP (2026-11-10): with the subtitle menu open, a drag on it must not
        // change the volume (or a tap toggle the controls).
        if !isPlayerTouch(touch, in: window) { return false }
        if recognizer === pan { return true }
        let point = touch.location(in: window)
        let allowed = !blocked.contains { $0.insetBy(dx: -8, dy: -8).contains(point) }
        #if DEBUG
          NSLog("Astra gesture: touch at %@ allowed=%d blocked=%@", NSCoder.string(for: point), allowed ? 1 : 0, blocked.description)
        #endif
        return allowed
      }

      /// Whether a touch landed on the player itself, not on a menu UIKit put
      /// in the same window over it (the subtitle menu). The video sits under
      /// the SwiftUI views in the same window, so it is matched by what the
      /// menu is, not by where the player is.
      private func isPlayerTouch(_ touch: UITouch, in window: UIView) -> Bool {
        var view: UIView? = touch.view
        while let current = view, current !== window {
          let name = NSStringFromClass(type(of: current))
          if name.contains("Menu") || name.contains("Platter") { return false }
          view = current.superview
        }
        return true
      }

      func gestureRecognizer(
        _ recognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
      ) -> Bool { true }

      /// Only a mostly vertical drag adjusts brightness or volume.
      func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        guard let pan = recognizer as? UIPanGestureRecognizer, let view = pan.view else { return true }
        let v = pan.velocity(in: view)
        return abs(v.y) > abs(v.x) * 1.5
      }

      @objc func panned(_ pan: UIPanGestureRecognizer) {
        guard let view = pan.view else { return }
        switch pan.state {
        case .began:
          swipeRight = pan.location(in: view).x >= view.bounds.width / 2
          onSwipe(swipeRight, 0)
        case .changed:
          // A swipe of 60% of the screen's height covers the whole range.
          let delta = -pan.translation(in: view).y / max(view.bounds.height, 1) * 1.7
          onSwipe(swipeRight, delta)
        default:
          onSwipe(swipeRight, nil)
        }
      }

      @objc func twoFingerTapped(_ recognizer: UITapGestureRecognizer) {
        onTwoFingerTap()
      }

      @objc func tapped(_ recognizer: UITapGestureRecognizer) {
        let point = recognizer.location(in: recognizer.view)
        let now = Date()
        let follows = now.timeIntervalSince(lastTap.at) < 0.35 && hypot(point.x - lastTap.point.x, point.y - lastTap.point.y) < 80
        lastTap = (now, point)
        #if DEBUG
          NSLog("Astra gesture: single tap (second of a double: %d)", follows ? 1 : 0)
        #endif
        // The second tap of a double tap (or more, for 20 s, 30 s…) leaves the controls alone.
        if !follows { onTap() }
      }

      @objc func doubleTapped(_ recognizer: UITapGestureRecognizer) {
        guard let view = recognizer.view else { return }
        #if DEBUG
          NSLog("Astra gesture: double tap at x=%f of %f", recognizer.location(in: view).x, view.bounds.width)
        #endif
        onDoubleTap(recognizer.location(in: view).x >= view.bounds.width / 2)
      }
    }
  }

  extension View {
    /// Reports this view's frame in window coordinates under `key`.
    func reportFrame(_ key: String, into frames: Binding<[String: CGRect]>) -> some View {
      onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { frames.wrappedValue[key] = $0 }
    }
  }
#endif

/// The iPhone scrubber (KP's mockup 2, 2026-11-10): a 6 pt white track that
/// grows to 12 pt while dragging, a 160 pt 16:9 preview above the finger
/// (kept on screen) with its time under it, seeking on release. Elapsed time
/// on the left; remaining on the right, tap it for "Ends at 6:52 PM".
struct PhoneScrubber: View {
  let player: PlayerController
  @Binding var scrubbing: Double?
  var poke: () -> Void
  @AppStorage("astra.player.showEndsAt") private var showEndsAt = false

  /// 160 pt on iPhone (KP's mockup); larger on the Mac's bigger window.
  #if os(macOS)
    private static let previewWidth: CGFloat = 256
  #else
    private static let previewWidth: CGFloat = 160
  #endif

  var body: some View {
    let shown = scrubbing ?? player.position
    let fraction = player.duration > 0 ? min(1, max(0, shown / player.duration)) : 0
    VStack(spacing: 6) {
      GeometryReader { geo in
        let width = geo.size.width
        let track: CGFloat = scrubbing != nil ? 12 : 6
        ZStack(alignment: .leading) {
          Capsule().fill(.white.opacity(0.3)).frame(height: track)
          Capsule().fill(.white).frame(width: max(track, width * fraction), height: track)
        }
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .overlay(alignment: .bottomLeading) {
          if let target = scrubbing {
            preview(at: target, fraction: fraction, width: width)
          }
        }
        .gesture(
          DragGesture(minimumDistance: 0)
            .onChanged { drag in
              scrubbing = Double(min(1, max(0, drag.location.x / max(width, 1)))) * player.duration
              poke()
            }
            .onEnded { drag in
              let target = Double(min(1, max(0, drag.location.x / max(width, 1)))) * player.duration
              player.seek(to: target)
              scrubbing = nil
              poke()
            }
        )
      }
      .frame(height: 28)
      HStack {
        Text(PlaybackClock.format(shown))
        Spacer()
        Button {
          showEndsAt.toggle()
          poke()
        } label: {
          Group {
            if showEndsAt {
              Text(PlaybackClock.endsAt(remaining: player.duration - shown, speed: player.speed))
            } else {
              Text("-" + PlaybackClock.format(max(0, player.duration - shown)))
            }
          }
          .contentTransition(.numericText())
          .padding(.vertical, 4)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows when it ends")
      }
      .font(.system(size: 13, weight: .medium).monospacedDigit())
      .foregroundStyle(.white.opacity(0.7))
    }
    .astraAnimation(Astra.Motion.fast, value: scrubbing != nil)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Playback Position")
    .accessibilityValue(PlaybackClock.format(shown))
  }

  /// The preview and its time, centred on the finger and kept on screen.
  @ViewBuilder private func preview(at seconds: Double, fraction: Double, width: CGFloat) -> some View {
    let w = Self.previewWidth
    let x = min(max(0, width * fraction - w / 2), max(0, width - w))
    VStack(spacing: 6) {
      Group {
        if let image = player.thumbnail(at: seconds) {
          Image(platformImage: image).resizable().aspectRatio(contentMode: .fill)
        } else {
          Rectangle().fill(.ultraThinMaterial)
        }
      }
      .frame(width: w, height: w * 9 / 16)
      .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(.white.opacity(0.3), lineWidth: 1))
      Text(PlaybackClock.format(seconds))
        .font(.system(size: 13, weight: .semibold).monospacedDigit())
        .foregroundStyle(.white)
    }
    .shadow(color: .black.opacity(0.45), radius: 12)
    .frame(width: w)
    .offset(x: x, y: -26)
    .allowsHitTesting(false)
    .transition(.opacity)
  }
}

#if os(macOS)
  /// The Mac's volume, top right (KP, 2026-11-10: the iPhone's subtle slider):
  /// a thin 3 pt track about 150 pt wide at 70% opacity that thickens while
  /// dragged, and a speaker that follows the level (click it to mute). It sets
  /// mpv's volume; no percentage.
  struct MacVolume: View {
    let player: PlayerController
    var poke: () -> Void
    @State private var dragging = false
    @State private var hovering = false

    private var value: Double { player.muted ? 0 : player.volume / 100 }
    private var active: Bool { dragging || hovering }

    var body: some View {
      HStack(spacing: 10) {
        GeometryReader { geo in
          let width = geo.size.width
          let track: CGFloat = dragging ? 6 : 3
          ZStack(alignment: .leading) {
            Capsule().fill(.white.opacity(0.3)).frame(height: track)
            Capsule().fill(.white).frame(width: max(track, width * value), height: track)
          }
          .frame(maxHeight: .infinity)
          .contentShape(Rectangle())
          .gesture(
            DragGesture(minimumDistance: 0)
              .onChanged { drag in
                dragging = true
                player.setVolume(Double(min(1, max(0, drag.location.x / max(width, 1)))) * 100)
                poke()
              }
              .onEnded { _ in dragging = false }
          )
        }
        .frame(width: 150, height: 36)
        Button {
          player.setMuted(!player.muted)
          poke()
        } label: {
          Image(systemName: symbol).font(.system(size: 15, weight: .semibold))
            .frame(width: 26, height: 36, alignment: .leading)
            .contentTransition(.symbolEffect(.replace))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(player.muted ? "Unmute" : "Mute")
        .accessibilityLabel(player.muted ? "Unmute" : "Mute")
      }
      .foregroundStyle(.white)
      .opacity(active ? 1 : 0.7)
      .shadow(color: .black.opacity(0.35), radius: 6)
      .onHover { hovering = $0 }
      .astraAnimation(Astra.Motion.fast, value: active)
      .astraAnimation(Astra.Motion.fast, value: dragging)
      .accessibilityElement(children: .contain)
      .accessibilityLabel("Volume")
      .accessibilityValue("\(Int((value * 100).rounded())) percent")
      .accessibilityAdjustableAction { direction in
        player.setVolume((value + (direction == .increment ? 0.1 : -0.1)) * 100)
      }
    }

    private var symbol: String {
      if value == 0 { return "speaker.slash.fill" }
      return value < 0.34 ? "speaker.wave.1.fill" : value < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
    }
  }
#endif

/// An outlined tag beside the player title: "4K", "HD", "HDR", "DOLBY VISION".
private struct TitleTag: View {
  var text: String

  var body: some View {
    Text(text)
      .font(.system(size: 11, weight: .heavy))
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .overlay(RoundedRectangle(cornerRadius: 4).stroke(.white.opacity(0.8), lineWidth: 1.2))
      .fixedSize()
  }
}

/// Dolby Vision as KP's official logo; HDR10, HDR10+ and HLG as one "HDR" tag.
private struct PlayerFormatTag: View {
  var range: DynamicRange

  var body: some View {
    if range == .dolbyVision {
      Image("format-dolby-vision").renderingMode(.template).resizable().scaledToFit()
        .frame(height: 16).foregroundStyle(.white).accessibilityLabel("Dolby Vision")
    } else {
      TitleTag(text: "HDR")
    }
  }
}

/// The official Dolby Atmos logo beside the title.
private struct PlayerAtmosTag: View {
  var body: some View {
    Image("format-dolby-atmos").renderingMode(.template).resizable().scaledToFit()
      .frame(height: 13).foregroundStyle(.white).accessibilityLabel("Dolby Atmos")
  }
}

/// Astra 4.0 (KP, 2026-11-08): a small Liquid Glass "Next Episode" button in
/// the last 15 seconds of an episode that has a next one. Nothing plays
/// unless it is tapped. It reads the position itself, so only it redraws.
struct NextEpisodeButton: View {
  let player: PlayerController
  /// iPhone: where the button is while shown (nil once it goes), so the
  /// player's window-wide tap recognizers leave taps on it alone.
  var onFrame: (CGRect?) -> Void = { _ in }

  private var shown: Bool {
    guard player.upNext != nil, player.duration > 0, player.hasFirstFrame else { return false }
    let left = player.duration - player.position
    return left > 0 && left <= PlayerController.nextEpisodeLead
  }

  var body: some View {
    // Spacers place it bottom right without anything that catches touches
    // around it (the right-side swipe stays free).
    VStack(spacing: 0) {
      Spacer(minLength: 0)
      HStack(spacing: 0) {
        Spacer(minLength: 0)
        if shown {
          Button {
            player.playUpNext()
        } label: {
          HStack(spacing: 8) {
            Text("Next Episode")
            Image(systemName: "forward.end.fill")
          }
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(.white)
          .padding(.horizontal, 18)
          .frame(height: 44)
          .astraGlass(in: Capsule(), variant: .regular, interactive: true)
          .contentShape(Capsule())
        }
        .buttonStyle(.plain)
          .accessibilityIdentifier("next-episode")
          .accessibilityHint(player.upNext?.displayTitle ?? "")
          .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { onFrame($0) }
          .onDisappear { onFrame(nil) }
          .astraTransition(.opacity.combined(with: .scale(scale: 0.95)))
        }
      }
    }
    .astraAnimation(Astra.Motion.base, value: shown)
  }
}

#endif
