import AstraKit
import SwiftUI
#if os(iOS)
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
  #if os(iOS)
    /// The swipe in progress: which side, and the level when it started.
    @State private var swipe: (brightness: Bool, start: Double)?
    /// Shown on the left while brightness is being changed.
    @State private var brightnessLevel: Double?
  #endif
  #if os(macOS)
    // Astra: the control panel can be dragged anywhere over the video (KP, 2026-11-07).
    @AppStorage("player.panelX") private var panelX = 0.0
    @AppStorage("player.panelY") private var panelY = 0.0
    @State private var panelDragStart: CGSize?
    /// The panel's offset while it is being dragged; saved when the drag ends.
    @State private var panelLive: CGSize?
    @State private var panelRest: CGRect = .zero
    @State private var playerBounds: CGRect = .zero
  #endif

  private var player: PlayerController { app.player }

  var body: some View {
    ZStack {
      // Clear, but hit-testable. Mac: click pauses, double-click goes full screen.
      // iPhone: tap shows or hides the controls.
      #if os(macOS)
        // Click pauses, double-click goes full screen; the title strip (and the mini window) drag the window.
        WindowDragArea(
          onClick: { player.togglePause() }, onDoubleClick: { player.toggleFullScreen() }
        )
        .ignoresSafeArea()
      #else
        // Astra: tap shows/hides the controls; swiping up or down on the left
        // half sets the screen brightness, on the right half the volume (KP).
        GeometryReader { geo in
          Color.black.opacity(0.001)
            .contentShape(Rectangle())
            .onTapGesture { visible ? hide() : poke() }
            .gesture(
              DragGesture(minimumDistance: 14)
                .onChanged { drag in swipeAdjust(drag, height: geo.size.height, width: geo.size.width) }
                .onEnded { _ in endSwipeAdjust() }
            )
        }
        .ignoresSafeArea()

        if let level = brightnessLevel {
          HStack {
            LevelPill(symbol: "sun.max.fill", level: level)
            Spacer()
          }
          .padding(.leading, 24)
          .allowsHitTesting(false)
          .transition(.opacity)
        }
      #endif

      chrome
        .opacity(visible ? 1 : 0)
        .allowsHitTesting(visible)

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
    .animation(Astra.Motion.base, value: visible)
    .animation(Astra.Motion.fast, value: player.buffering)
    .animation(Astra.Motion.base, value: player.hasFirstFrame)
    #if os(macOS)
      .onContinuousHover { phase in
        // Every mouse move reaches here; restart the hide timer at most a few times a second.
        if case .active = phase, !visible || Date().timeIntervalSince(lastPoke) > 0.25 { poke() }
      }
    #endif
    .coordinateSpace(.named(Self.space))
    .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .local) }) { bounds in
      #if os(macOS)
        playerBounds = bounds
      #endif
    }
    .onAppear { poke() }
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

  /// iPhone: while the controls show, loading is the ring around Play.
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

  #if os(macOS)
    private static let bottomScrim = 0.3
  #else
    private static let bottomScrim = 0.7
  #endif

  // MARK: Mac (docs/design/desktop-player.png)

  #if os(macOS)
    private var macChrome: some View {
      VStack(spacing: 0) {
        HStack(spacing: 16) {
          Button {
            player.close()
          } label: {
            Image(systemName: "chevron.left")
          }
          .astraIconButton(size: 32, variant: .clear)
          .keyboardShortcut(.cancelAction)
          .help("Back (Esc)")
          .accessibilityLabel("Close Player")
          VStack(alignment: .leading, spacing: 2) {
            Text(player.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
            if let subtitle = player.subtitle {
              Text(subtitle).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
            }
          }
          Spacer(minLength: 16)
          HStack(spacing: 12) {
            pipButton(size: 32)
            moreMenu
          }
          .astraGlassGroup(spacing: 12)
        }
        // Clear of the traffic lights.
        .padding(.top, 34)
        Spacer()
        macPanel
      }
      .padding(.horizontal, 24)
      .padding(.bottom, 20)
    }

    /// The glass control panel along the bottom.
    private var macPanel: some View {
      // Astra: one slim row, Infuse-style (KP, 2026-11-07: "wayyyy smaller").
      HStack(spacing: 10) {
        transport(small: 15, large: 18, gap: 4, framedPause: false)
        PlayerClock(player: player, scrubbing: scrubbing, remaining: false)
          .frame(minWidth: 44, alignment: .trailing)
        timeline
        PlayerClock(player: player, scrubbing: scrubbing, remaining: true)
          .frame(minWidth: 48, alignment: .leading)
        Button {
          player.setMuted(!player.muted)
        } label: {
          Image(systemName: volumeSymbol).font(.system(size: 13, weight: .semibold))
        }
        .buttonStyle(PlayerGlyphButtonStyle(size: 26))
        .accessibilityLabel(player.muted ? "Unmute" : "Mute")
        ScrubBar(
          fraction: player.muted ? 0 : player.volume / 100, knob: 10, height: 3,
          onChange: { player.setVolume($0 * 100) }, onCommit: { player.setVolume($0 * 100) }
        )
        .frame(width: 64)
        .accessibilityLabel("Volume")
        captionsChip
        versionChip
        Button {
          player.toggleFullScreen()
        } label: {
          Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 13, weight: .semibold))
        }
        .buttonStyle(PlayerGlyphButtonStyle(size: 26))
        .keyboardShortcut("f", modifiers: [])
        .help("Full Screen (F)")
        .accessibilityLabel("Full Screen")
      }
      .font(.system(size: 12, weight: .medium).monospacedDigit())
      .foregroundStyle(.white)
      .padding(.horizontal, 14)
      .frame(height: 46)
      .shadow(color: .black.opacity(0.45), radius: 4)  // keeps white glyphs crisp on clear glass
      .contentShape(Capsule())
      .astraGlass(in: Capsule(), variant: .clear)
      .astraGlassEdge(Capsule())
      .shadow(color: .black.opacity(0.2), radius: 16, y: 4)
      .frame(maxWidth: 820)
      .offset(panelOffset)
      .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named(Self.space)) }) { panelRest = $0 }
      .gesture(panelDrag)
      .onTapGesture(count: 2) { setPanelOffset(.zero) }
      .help("Drag to move the controls; double-click to put them back")
      .animation(panelDragStart == nil ? Astra.Motion.base : nil, value: panelOffset)
    }

    /// Where the panel is, kept inside the player even after the window shrinks.
    private var panelOffset: CGSize {
      PlayerGeometry.panelOffset(
        panelLive ?? CGSize(width: panelX, height: panelY), panel: panelRest, in: playerBounds)
    }

    private var panelDrag: some Gesture {
      DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.space))
        .onChanged { drag in
          let start = panelDragStart ?? panelOffset
          panelDragStart = start
          panelLive = CGSize(
            width: start.width + drag.translation.width, height: start.height + drag.translation.height)
          poke()
        }
        .onEnded { _ in
          if let panelLive { setPanelOffset(panelLive) }
          panelLive = nil
          panelDragStart = nil
        }
    }

    private func setPanelOffset(_ offset: CGSize) {
      let clamped = PlayerGeometry.panelOffset(offset, panel: panelRest, in: playerBounds)
      panelX = clamped.width
      panelY = clamped.height
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

    private var volumeSymbol: String {
      if player.muted || player.volume == 0 { return "speaker.slash" }
      return player.volume < 34 ? "speaker.wave.1" : player.volume < 67 ? "speaker.wave.2" : "speaker.wave.3"
    }

    /// Audio track and playback speed.
    private var moreMenu: some View {
      Menu {
        if player.audioTracks.count > 1 {
          Section("Audio") { audioButtons }
        }
        Section("Speed") {
          ForEach(PlayerController.speeds, id: \.self) { speed in
            Button {
              player.setSpeed(speed)
            } label: {
              checked(speed == 1 ? "Normal" : String(format: "%g×", speed), player.speed == speed)
            }
          }
        }
      } label: {
        Image(systemName: "ellipsis")
      }
      .menuStyle(.button)
      .buttonStyle(GlassIconButtonStyle(size: 32, variant: .clear))
      .menuIndicator(.hidden)
      .fixedSize()
      .help("More")
      .accessibilityLabel("More")
    }
  #endif

  // MARK: iPhone (docs/design/iphone-player.png)

  #if os(iOS)
    /// Astra: Infuse-style layout (KP's reference screenshot, 2026-11-07).
    /// Top left close + PiP, top right a volume capsule; a plain back / play /
    /// forward cluster in the middle; the episode line and the title bottom
    /// left, captions and quality in one glass capsule bottom right; the
    /// timeline with its times along the bottom. Always landscape.
    private var phoneChrome: some View {
      ZStack {
        VStack(spacing: 0) {
          HStack(alignment: .center, spacing: 12) {
            Button {
              player.close()
            } label: {
              Image(systemName: "xmark")
            }
            .astraIconButton(size: 40, variant: .clear)
            .accessibilityLabel("Close Player")
            if PlayerController.supportsPictureInPicture { pipButton(size: 40) }
            Spacer()
            phoneVolume
          }
          .astraGlassGroup(spacing: 12)
          Spacer()
          HStack(alignment: .bottom, spacing: 16) {
            Button {
              player.showDetails()
            } label: {
              VStack(alignment: .leading, spacing: 4) {
                if let subtitle = player.subtitle {
                  Text(subtitle).font(.system(size: 13, weight: .semibold)).opacity(0.9).lineLimit(1)
                }
                Text(player.title).font(.system(size: 22, weight: .bold)).lineLimit(1)
              }
              .foregroundStyle(.white)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(player.title), Details")
            Spacer(minLength: 16)
            HStack(spacing: 4) {
              captionsChip
              versionChip
            }
            .padding(.horizontal, 6)
            .frame(height: 44)
            .astraGlass(in: Capsule(), variant: .clear)
            .astraGlassEdge(Capsule(), strength: 0.6)
          }
          .padding(.bottom, 12)
          HStack(spacing: 12) {
            PlayerClock(player: player, scrubbing: scrubbing, remaining: false)
              .frame(minWidth: 44, alignment: .leading)
            timeline
            PlayerClock(player: player, scrubbing: scrubbing, remaining: true)
              .frame(minWidth: 48, alignment: .trailing)
          }
          .font(.system(size: 12, weight: .medium).monospacedDigit())
          .foregroundStyle(.white.opacity(0.8))
        }
        phoneTransport
      }
      // Inside the safe area: clear of the notch / Dynamic Island and the home indicator.
      .padding(.horizontal, 20)
      .padding(.top, 10)
      .padding(.bottom, 6)
    }

    /// Back 10 s, a round play/pause whose ring shows loading, forward 10 s.
    private var phoneTransport: some View {
      HStack(spacing: 64) {
        Button {
          player.seek(by: -10)
          poke()
        } label: {
          Image(systemName: "arrow.counterclockwise").font(.system(size: 26, weight: .medium))
        }
        .buttonStyle(PlayerGlyphButtonStyle(size: 52))
        .accessibilityLabel("Back 10 Seconds")

        Button {
          player.togglePause()
        } label: {
          ZStack {
            Circle().stroke(.white.opacity(0.35), lineWidth: 2)
            if player.buffering || !player.hasFirstFrame {
              PlayerRingSpinner()
            }
            Image(systemName: player.paused ? "play.fill" : "pause.fill")
              .font(.system(size: 34, weight: .bold))
              .offset(x: player.paused ? 3 : 0)
              .contentTransition(.symbolEffect(.replace))
          }
          .frame(width: 84, height: 84)
          .contentShape(Circle())
        }
        .buttonStyle(PlayerGlyphButtonStyle(size: 84))
        .accessibilityLabel(player.paused ? "Play" : "Pause")

        Button {
          player.seek(by: 10)
          poke()
        } label: {
          Image(systemName: "arrow.clockwise").font(.system(size: 26, weight: .medium))
        }
        .buttonStyle(PlayerGlyphButtonStyle(size: 52))
        .accessibilityLabel("Forward 10 Seconds")
      }
      .shadow(color: .black.opacity(0.35), radius: 8)
    }

    private var screen: UIScreen? {
      UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen }.first
    }

    /// A vertical swipe: a full screen height is the whole range.
    private func swipeAdjust(_ drag: DragGesture.Value, height: CGFloat, width: CGFloat) {
      // Only mostly-vertical swipes.
      guard abs(drag.translation.height) > abs(drag.translation.width) || swipe != nil, height > 0 else { return }
      if swipe == nil {
        let left = drag.startLocation.x < width / 2
        swipe = (left, left ? Double(screen?.brightness ?? 0.5) : (player.muted ? 0 : player.volume / 100))
      }
      guard let swipe else { return }
      let value = min(1, max(0, swipe.start - Double(drag.translation.height / (height * 0.8))))
      if swipe.brightness {
        screen?.brightness = CGFloat(value)
        withAnimation(Astra.Motion.fast) { brightnessLevel = value }
      } else {
        player.setVolume(value * 100)
        // The volume capsule at the top right shows the level.
        if !visible { poke() }
      }
    }

    private func endSwipeAdjust() {
      swipe = nil
      Task { @MainActor in
        try? await Task.pause(0.8)
        if swipe == nil { withAnimation(Astra.Motion.base) { brightnessLevel = nil } }
      }
    }

    /// "40%", a short slider and the speaker glyph (mpv's volume; tap the glyph to mute).
    private var phoneVolume: some View {
      HStack(spacing: 10) {
        Text("\(Int((player.muted ? 0 : player.volume).rounded()))%")
          .font(.system(size: 15, weight: .medium).monospacedDigit())
          .frame(minWidth: 42, alignment: .leading)
        ScrubBar(
          fraction: player.muted ? 0 : player.volume / 100, knob: 12, height: 3,
          onChange: { player.setVolume($0 * 100); poke() },
          onCommit: { player.setVolume($0 * 100) }
        )
        .frame(width: 110)
        Button {
          player.setMuted(!player.muted)
          poke()
        } label: {
          Image(systemName: phoneVolumeSymbol).font(.system(size: 15, weight: .semibold))
            .frame(width: 26, height: 26)
            .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(player.muted ? "Unmute" : "Mute")
      }
      .foregroundStyle(.white)
      .padding(.horizontal, 14)
      .frame(height: 40)
      .astraGlass(in: Capsule(), variant: .clear)
      .astraGlassEdge(Capsule(), strength: 0.6)
      .accessibilityElement(children: .contain)
      .accessibilityLabel("Volume")
    }

    private var phoneVolumeSymbol: String {
      if player.muted || player.volume == 0 { return "speaker.slash.fill" }
      return player.volume < 34 ? "speaker.wave.1.fill" : player.volume < 67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
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
        Image(systemName: player.paused ? "play.fill" : "pause.fill")
          .font(.system(size: large, weight: .bold))
          .contentTransition(.symbolEffect(.replace))
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
      #if os(iOS)
        if player.audioTracks.count > 1 {
          Section("Audio") { audioButtons }
        }
      #endif
    } label: {
      // Astra: a speech-bubble captions glyph (KP asked for a new icon); filled when subtitles are on.
      Image(systemName: player.subtitleId == nil ? "captions.bubble" : "captions.bubble.fill")
        .font(.system(size: 15, weight: .semibold))
        .contentTransition(.symbolEffect(.replace))
        .playerChip()
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
      ForEach(PlaybackQuality.allCases) { quality in
        Button {
          player.setQuality(quality)
        } label: {
          checked(quality.title, player.quality == quality)
        }
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

  var body: some View {
    let shown = scrubbing ?? player.position
    ScrubBar(
      fraction: player.duration > 0 ? shown / player.duration : 0, knob: 12, height: 3,
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
      ZStack(alignment: .leading) {
        Capsule().fill(.white.opacity(0.3)).frame(height: height)
        Capsule().fill(.white).frame(width: max(height, width * f), height: height)
        Circle().fill(.white)
          .frame(width: knob, height: knob)
          .shadow(color: .black.opacity(0.35), radius: 4)
          .scaleEffect(dragging ? 1.2 : 1)
          .offset(x: width * f - knob / 2)
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
    .animation(Astra.Motion.fast, value: dragging)
  }

  /// The preview card above the bar, centred on the pointer, kept inside the bar's width.
  @ViewBuilder
  private func previewView(_ content: (image: PlatformImage?, label: String), at: Double, width: CGFloat) -> some View {
    let size = Self.previewSize
    let hasImage = content.image != nil
    let cardWidth = hasImage ? size.width : 72
    let x = min(max(0, width * at - cardWidth / 2), max(0, width - cardWidth))
    VStack(spacing: 6) {
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
    .offset(x: x, y: -30)
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
      .animation(Astra.Motion.fast, value: configuration.isPressed)
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

/// A white arc turning around the play button while the video loads.
struct PlayerRingSpinner: View {
  @State private var turning = false

  var body: some View {
    Circle()
      .trim(from: 0, to: 0.22)
      .stroke(.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
      .rotationEffect(.degrees(turning ? 360 : 0))
      .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: turning)
      .onAppear { turning = true }
  }
}

#if os(iOS)
  /// The tall glass pill on the left that shows brightness while swiping.
  struct LevelPill: View {
    var symbol: String
    var level: Double

    var body: some View {
      VStack(spacing: 10) {
        Text("\(Int((level * 100).rounded()))%")
          .font(.system(size: 13, weight: .semibold).monospacedDigit())
        GeometryReader { geo in
          ZStack(alignment: .bottom) {
            Capsule().fill(.white.opacity(0.25))
            Capsule().fill(.white).frame(height: max(6, geo.size.height * level))
          }
        }
        .frame(width: 6)
        Image(systemName: symbol).font(.system(size: 14, weight: .semibold))
      }
      .foregroundStyle(.white)
      .padding(.vertical, 14)
      .frame(width: 52, height: 220)
      .astraGlass(in: Capsule(), variant: .clear)
      .astraGlassEdge(Capsule(), strength: 0.6)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Brightness \(Int((level * 100).rounded())) percent")
    }
  }
#endif
