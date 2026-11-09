import AstraKit
import SwiftUI

/// The Apple TV player chrome, laid out like Silo Apple's tvOS player (KP,
/// 2026-11-09; https://github.com/Silo-Server/silo-apple, AGPL-3.0-or-later,
/// Copyright (C) 2026 Silo Media L.L.C. and contributors). Playback itself is
/// still mpv with the original file; quality picks between the original files
/// on the server (Auto / HD / 4K), never a transcode.
///
/// The remote comes from `TVPlayerHost` (playback): click or Play/Pause plays
/// and pauses, left / right skip 10 s, a swipe scrubs, Menu hides the controls
/// and then closes the player. It is on while focus is on the timeline; on the
/// captions, quality or Next Episode button, clicks go to that button. Any
/// press shows the controls; they fade after a few seconds of playing.
struct PlayerOverlay: View {
  @Environment(AppModel.self) private var app
  @AppStorage(Preferences.nextEpisodeKey) private var showNextEpisode = true
  @State private var visible = true
  /// The time a swipe is scrubbing to, from the host; nil when not scrubbing.
  @State private var scrubbing: Double?
  /// Bumped on every press; the hide timer restarts from it.
  @State private var activity = 0
  @FocusState private var focus: Field?

  private enum Field: Hashable { case bar, back, playPause, forward, captions, quality, next, close }
  private var player: PlayerController { app.player }

  var body: some View {
    TVPlayerHost(
      player: player,
      controlsVisible: $visible,
      scrubbing: $scrubbing,
      remoteEnabled: focus == .bar || focus == nil,
      poke: poke
    ) {
      controls
    }
  }

  private var controls: some View {
    ZStack(alignment: .bottom) {
      Color.clear

      // Silo: a shallow gradient at the bottom only, so the picture stays clean.
      VStack(spacing: 0) {
        Spacer()
        LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
          .frame(height: 240)
      }
      .ignoresSafeArea()
      .opacity(visible ? 1 : 0)
      .allowsHitTesting(false)

      if !player.hasFirstFrame || player.buffering {
        ProgressView()
          .tint(.white)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .transition(.opacity)
      }

      scrubPreview

      chrome
        .opacity(visible ? 1 : 0)
    }
    .astraAnimation(Astra.Motion.base, value: visible)
    .astraAnimation(Astra.Motion.fast, value: player.buffering)
    // Menu (Back). While focus is in these controls SwiftUI gets the press
    // first and the host's Menu never runs, so the whole Back order is here:
    // cancel a scrub, else hide the controls, else close the player (KP,
    // 2026-11-09: "menu/back button doesn't work").
    .onExitCommand {
      if scrubbing != nil {
        scrubbing = nil
        poke()
      } else if visible {
        focus = .bar
        visible = false
      } else {
        player.close()
      }
    }
    .onAppear {
      focus = .bar
      poke()
    }
    .onChange(of: visible) {
      // Hidden controls keep focus on the timeline, so the remote stays live.
      if !visible { focus = .bar } else { activity &+= 1 }
    }
    .task(id: activity) {
      try? await Task.pause(5)
      guard !Task.isCancelled, !player.paused, scrubbing == nil, focus == .bar || focus == nil else { return }
      visible = false
    }
  }

  /// Silo's still preview that follows the playhead while scrubbing.
  @ViewBuilder private var scrubPreview: some View {
    if let target = scrubbing, player.duration > 0, let image = player.thumbnail(at: target) {
      GeometryReader { proxy in
        let inset = Self.inset
        let cardWidth: CGFloat = 340
        let track = max(proxy.size.width - inset * 2, 0)
        let head = inset + track * CGFloat(min(1, max(0, target / player.duration)))
        let leading = min(max(head - cardWidth / 2, inset), proxy.size.width - inset - cardWidth)
        VStack(spacing: 8) {
          Image(platformImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: 320, height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
          Text(TVScrubBarLabel.clock(target))
            .font(.system(size: 24, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.ultraThinMaterial))
        .shadow(color: .black.opacity(0.5), radius: 18, y: 7)
        .frame(width: cardWidth)
        .padding(.leading, leading)
        .padding(.bottom, 300)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
      }
      .allowsHitTesting(false)
      .transition(.opacity)
    }
  }

  /// Silo's side inset for the transport.
  private static let inset: CGFloat = 80

  private func poke() {
    visible = true
    activity &+= 1
  }

  // MARK: Chrome

  /// Silo's transport: the title bottom left, the timeline with its puck,
  /// the times, then -10 / play / +10 on the left and Next Episode,
  /// subtitles, quality and close on the right.
  private var chrome: some View {
    VStack(alignment: .leading, spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        if let subtitle = player.subtitle, !subtitle.isEmpty {
          Text(subtitle)
            .font(.system(size: 22, weight: .medium))
            .foregroundStyle(.white.opacity(0.65))
            .lineLimit(1)
        }
        Text(player.title)
          .font(.system(size: 34, weight: .semibold))
          .foregroundStyle(.white)
          .lineLimit(1)
      }

      TVScrubBar(player: player, scrubbing: scrubbing)
        .focused($focus, equals: .bar)

      HStack(spacing: 10) {
        circle("gobackward.10", field: .back, label: "Back 10 seconds", primary: false) {
          player.seek(by: -NowPlaying.skipSeconds)
        }
        circle(player.paused ? "play.fill" : "pause.fill", field: .playPause, label: player.paused ? "Play" : "Pause", primary: true) {
          player.togglePause()
        }
        circle("goforward.10", field: .forward, label: "Forward 10 seconds", primary: false) {
          player.seek(by: NowPlaying.skipSeconds)
        }
        Spacer(minLength: 24)
        if showNextEpisode, nextEpisodeShown {
          Button {
            player.playUpNext()
          } label: {
            Label("Next Episode", systemImage: "forward.end.fill")
              .font(.system(size: 24, weight: .semibold))
              .foregroundStyle(focus == .next ? Color.black : Color.white)
              .padding(.horizontal, 26)
              .frame(height: 66)
              .background(Capsule().fill(focus == .next ? Color.white : Color.black.opacity(0.35)))
              .overlay(Capsule().stroke(Color.white.opacity(focus == .next ? 0 : 0.22), lineWidth: 1))
          }
          .buttonStyle(TVBareButtonStyle())
          .focused($focus, equals: .next)
        }
        captionsMenu
        qualityMenu
        circle("xmark", field: .close, label: "Close player", primary: false) {
          player.close()
        }
      }
      // Hidden buttons can't take focus.
      .disabled(!visible)
      .focusSection()
    }
    .padding(.horizontal, Self.inset)
    .padding(.bottom, 48)
    .focusSection()
    .onChange(of: focus) { poke() }
  }

  /// One of Silo's 66 pt round transport buttons: white when focused.
  private func circle(
    _ symbol: String, field: Field, label: String, primary: Bool, action: @escaping () -> Void
  ) -> some View {
    Button {
      action()
      poke()
    } label: {
      TVCircleGlyph(symbol: symbol, focused: focus == field, size: primary ? 30 : 25)
    }
    .buttonStyle(TVBareButtonStyle())
    .focused($focus, equals: field)
    .accessibilityLabel(label)
  }

  private var nextEpisodeShown: Bool {
    guard player.upNext != nil, player.duration > 0, player.hasFirstFrame else { return false }
    let left = player.duration - player.position
    return left > 0 && left <= PlayerController.nextEpisodeLead
  }

  private var captionsMenu: some View {
    Menu {
      Picker("Subtitles", selection: Binding(get: { player.subtitleId }, set: { player.selectSubtitle($0) })) {
        Text("Off").tag(Int?.none)
        ForEach(player.subtitleTracks) { track in
          Text(track.title).tag(Int?.some(track.id))
        }
      }
    } label: {
      TVCircleGlyph(
        symbol: player.subtitleId == nil ? "captions.bubble" : "captions.bubble.fill",
        focused: focus == .captions, size: 25)
    }
    .buttonStyle(TVBareButtonStyle())
    .focused($focus, equals: .captions)
    .accessibilityLabel("Subtitles")
  }

  private var qualityMenu: some View {
    Menu {
      ForEach(player.versions) { version in
        Button {
          player.playVersion(version)
        } label: {
          if version.media.id == player.currentMediaID {
            Label(version.badge, systemImage: "checkmark")
          } else {
            Text(version.badge)
          }
        }
      }
    } label: {
      HStack(spacing: 6) {
        Text(player.resolutionBadge ?? "Auto")
        Image(systemName: "chevron.down").font(.system(size: 16, weight: .bold))
      }
      .font(.system(size: 22, weight: .semibold))
      .foregroundStyle(focus == .quality ? Color.black : Color.white)
      .padding(.horizontal, 22)
      .frame(height: 66)
      .background(Capsule().fill(focus == .quality ? Color.white : Color.black.opacity(0.35)))
      .overlay(Capsule().stroke(Color.white.opacity(focus == .quality ? 0 : 0.22), lineWidth: 1))
    }
    .buttonStyle(TVBareButtonStyle())
    .disabled(player.versions.count < 2)
    .focused($focus, equals: .quality)
    .accessibilityLabel("Quality")
  }
}

/// The white timeline with the time played and the time left. It holds focus
/// while the remote drives playback; the host does the clicks and swipes.
private struct TVScrubBar: View {
  let player: PlayerController
  var scrubbing: Double?

  var body: some View {
    Button {} label: {
      TVScrubBarLabel(player: player, scrubbing: scrubbing)
    }
    .buttonStyle(TVBareButtonStyle())
    .accessibilityLabel(player.paused ? "Play" : "Pause")
    .accessibilityValue(TVScrubBarLabel.clock(scrubbing ?? player.position))
  }
}

struct TVScrubBarLabel: View {
  let player: PlayerController
  var scrubbing: Double?
  @Environment(\.isFocused) private var focused

  /// While scrubbing, the bar and clock show where a click will jump to.
  private var time: Double { scrubbing ?? player.position }

  private var fraction: Double {
    player.duration > 0 ? min(1, max(0, time / player.duration)) : 0
  }

  var body: some View {
    VStack(spacing: 10) {
      GeometryReader { geo in
        let width = geo.size.width
        ZStack(alignment: .leading) {
          Capsule().fill(.white.opacity(scrubbing != nil ? 0.48 : focused ? 0.35 : 0.24))
            .frame(height: barHeight)
          Capsule().fill(.white).frame(width: max(barHeight, width * fraction), height: barHeight)
          if focused {
            let puck: CGFloat = scrubbing != nil ? 36 : 30
            Circle()
              .fill(.white)
              .frame(width: puck, height: puck)
              .overlay(Circle().stroke(.white.opacity(scrubbing != nil ? 0.55 : 0), lineWidth: 8))
              .shadow(color: .black.opacity(0.48), radius: 8, y: 3)
              .offset(x: width * fraction - puck / 2)
          }
        }
        .frame(height: 56)
      }
      .frame(height: 56)
      HStack {
        HStack(spacing: 10) {
          if player.paused {
            Image(systemName: "pause.fill").font(.system(size: 22, weight: .bold))
          }
          Text(Self.clock(time))
        }
        Spacer()
        Text("\u{2212}" + Self.clock(max(0, player.duration - time)))
      }
      .font(.system(size: 28, weight: .semibold, design: .rounded))
      .monospacedDigit()
      .foregroundStyle(.white)
    }
    .contentShape(Rectangle())
    .astraAnimation(Astra.Motion.fast, value: focused)
  }

  private var barHeight: CGFloat { scrubbing != nil ? 12 : 7 }

  /// "1:02:05" or "12:05".
  static func clock(_ seconds: Double) -> String {
    let total = Int(seconds.rounded(.down))
    let h = total / 3600, m = (total % 3600) / 60, s = total % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
  }
}

/// No system focus platter: the bar shows focus itself (it thickens).
private struct TVBareButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .focusEffectDisabled()
      .scaleEffect(configuration.isPressed ? 0.96 : 1)
  }
}

/// Silo's round transport glyph: dark glass at rest, white with a black glyph when focused.
private struct TVCircleGlyph: View {
  var symbol: String
  var focused: Bool
  var size: CGFloat

  var body: some View {
    Image(systemName: symbol)
      .font(.system(size: size, weight: .semibold))
      .foregroundStyle(focused ? Color.black : Color.white)
      .frame(width: 66, height: 66)
      .background(Circle().fill(focused ? Color.white : Color.black.opacity(0.35)))
      .overlay(Circle().stroke(Color.white.opacity(focused ? 0 : 0.22), lineWidth: 1))
      .contentShape(Circle())
      .animation(.snappy(duration: 0.22), value: focused)
  }
}
