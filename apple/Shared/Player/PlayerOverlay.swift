import AstraKit
import SwiftUI

/// The minimal player chrome over the video: close and title at the top,
/// big 10 s / pause / 10 s transport in the middle, a white timeline and
/// track chips at the bottom. Fades out after 3 s without the pointer moving.
struct PlayerOverlay: View {
  @Environment(AppModel.self) private var app
  @State private var visible = true
  @State private var hideTask: Task<Void, Never>?
  @State private var scrubbing: Double?
  @State private var lastPoke = Date.distantPast
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
        Color.black.opacity(0.001)
          .ignoresSafeArea()
          .onTapGesture { visible ? hide() : poke() }
      #endif

      chrome
        .opacity(visible ? 1 : 0)
        .allowsHitTesting(visible)

      if !player.hasFirstFrame {
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
          .astraIconButton(size: 44, variant: .clear)
          .keyboardShortcut(.cancelAction)
          .help("Back (Esc)")
          .accessibilityLabel("Close Player")
          VStack(alignment: .leading, spacing: 2) {
            Text(player.title).font(.system(size: 22, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
            if let subtitle = player.subtitle {
              Text(subtitle).font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
            }
          }
          Spacer(minLength: 16)
          HStack(spacing: 12) {
            pipButton(size: 44)
            moreMenu
          }
          .astraGlassGroup(spacing: 12)
        }
        // Clear of the traffic lights.
        .padding(.top, 34)
        Spacer()
        macPanel
      }
      .padding(.horizontal, 40)
      .padding(.bottom, 28)
    }

    /// The glass control panel along the bottom.
    private var macPanel: some View {
      VStack(spacing: 14) {
        HStack(spacing: 18) {
          PlayerClock(player: player, scrubbing: scrubbing, remaining: false).frame(minWidth: 64, alignment: .leading)
          timeline
          PlayerClock(player: player, scrubbing: scrubbing, remaining: true).frame(minWidth: 64, alignment: .trailing)
        }
        .font(.system(size: 15, weight: .semibold).monospacedDigit())
        .foregroundStyle(.white)

        ZStack {
          HStack(spacing: 12) {
            Button {
              player.setMuted(!player.muted)
            } label: {
              Image(systemName: volumeSymbol)
            }
            .buttonStyle(PlayerGlyphButtonStyle(size: 44, filled: true))
            .accessibilityLabel(player.muted ? "Unmute" : "Mute")
            ScrubBar(
              fraction: player.muted ? 0 : player.volume / 100, knob: 16, height: 4,
              onChange: { player.setVolume($0 * 100) }, onCommit: { player.setVolume($0 * 100) }
            )
            .frame(width: 150)
            .accessibilityLabel("Volume")
            Spacer()
            captionsChip
            versionChip
            Button {
              player.toggleFullScreen()
            } label: {
              Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .buttonStyle(PlayerGlyphButtonStyle(size: 44))
            .keyboardShortcut("f", modifiers: [])
            .help("Full Screen (F)")
            .accessibilityLabel("Full Screen")
          }
          transport(small: 34, large: 34, gap: 40, framedPause: true)
        }
      }
      .padding(.horizontal, 30)
      .padding(.top, 24)
      .padding(.bottom, 20)
      .shadow(color: .black.opacity(0.45), radius: 6)  // keeps white glyphs crisp on clear glass
      .overlay(alignment: .top) {
        // The grip: drag here, or anywhere on the panel that isn't a control.
        Capsule().fill(.white.opacity(0.55)).frame(width: 40, height: 4).padding(.top, 9)
          .allowsHitTesting(false)
      }
      .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
      .astraGlass(in: RoundedRectangle(cornerRadius: 28, style: .continuous), variant: .clear)
      .astraGlassEdge(RoundedRectangle(cornerRadius: 28, style: .continuous))
      .shadow(color: .black.opacity(0.2), radius: 24, y: 6)
      .frame(maxWidth: 1500)
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
      .buttonStyle(GlassIconButtonStyle(size: 44, variant: .clear))
      .menuIndicator(.hidden)
      .fixedSize()
      .help("More")
      .accessibilityLabel("More")
    }
  #endif

  // MARK: iPhone (docs/design/iphone-player.png)

  #if os(iOS)
    private var phoneChrome: some View {
      ZStack {
        VStack(spacing: 0) {
          HStack(spacing: 14) {
            Button {
              player.close()
            } label: {
              Image(systemName: "xmark")
            }
            .astraIconButton(size: 44, variant: .clear)
            .accessibilityLabel("Close Player")
            if PlayerController.supportsPictureInPicture { pipButton(size: 44) }
            Spacer()
          }
          .astraGlassGroup(spacing: 14)
          Spacer()
          VStack(spacing: 10) {
            HStack(spacing: 10) {
              Button {
                player.showDetails()
              } label: {
                HStack(spacing: 8) {
                  VStack(alignment: .leading, spacing: 2) {
                    Text(player.title).font(.system(size: 20, weight: .semibold)).lineLimit(1)
                    if let subtitle = player.subtitle {
                      Text(subtitle).font(.system(size: 13, weight: .medium)).opacity(0.75).lineLimit(1)
                    }
                  }
                  Image(systemName: "chevron.right").font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.white)
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
              .accessibilityLabel("\(player.title), Details")
              Spacer(minLength: 12)
              captionsChip
              versionChip
            }
            timeline
            HStack {
              PlayerClock(player: player, scrubbing: scrubbing, remaining: false)
              Spacer()
              PlayerClock(player: player, scrubbing: scrubbing, remaining: true)
            }
            .font(.system(size: 13, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.7))
          }
        }
        transport(small: 30, large: 46, gap: 64, framedPause: false)
      }
      // Inside the safe area: clear of the notch and the home indicator.
      .padding(.horizontal, 24)
      .padding(.vertical, 14)
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
      Text("CC")
        .font(.system(size: 12, weight: .heavy))
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(lineWidth: 1.6))
        .opacity(player.subtitleId == nil ? 0.85 : 1)
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
        Text(shortBadge).font(.system(size: 15, weight: .semibold))
        Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold))
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
    hideTask = Task {
      try? await Task.sleep(for: .seconds(3))
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
      fraction: player.duration > 0 ? shown / player.duration : 0, knob: 18, height: 5,
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
      .padding(.horizontal, 16)
      .frame(height: 40)
      .contentShape(Capsule())
      .astraGlass(in: Capsule(), variant: .clear, interactive: true)
  }
}
