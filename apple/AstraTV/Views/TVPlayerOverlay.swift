import AstraKit
import SwiftUI

/// The Apple TV player chrome (docs/design/appletv-player.png, KP 2026-11-06):
/// the title bottom left with the white bar under it, and only two buttons at
/// the bottom right, captions and quality (Auto / HD / 4K between the original
/// files on the server, never a transcode).
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

  private enum Field: Hashable { case bar, captions, quality, next }
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

      // A dimming scrim under the controls only, so the picture stays clean.
      LinearGradient(
        stops: [.init(color: .clear, location: 0.45), .init(color: .black.opacity(0.8), location: 1)],
        startPoint: .top, endPoint: .bottom
      )
      .ignoresSafeArea()
      .opacity(visible ? 1 : 0)
      .allowsHitTesting(false)

      if !player.hasFirstFrame || player.buffering {
        ProgressView()
          .tint(.white)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .transition(.opacity)
      }

      chrome
        .opacity(visible ? 1 : 0)
    }
    .astraAnimation(Astra.Motion.base, value: visible)
    .astraAnimation(Astra.Motion.fast, value: player.buffering)
    // Menu on a button (where the host's remote is off) goes back to the timeline.
    .onExitCommand {
      if focus != .bar { focus = .bar }
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

  private func poke() {
    visible = true
    activity &+= 1
  }

  // MARK: Chrome

  private var chrome: some View {
    VStack(alignment: .leading, spacing: 26) {
      HStack(alignment: .bottom, spacing: 24) {
        VStack(alignment: .leading, spacing: 8) {
          if let subtitle = player.subtitle, !subtitle.isEmpty {
            Text(subtitle)
              .font(.system(size: 26, weight: .medium))
              .foregroundStyle(.white.opacity(0.75))
              .lineLimit(1)
          }
          Text(player.title)
            .font(.system(size: 44, weight: .bold))
            .foregroundStyle(.white)
            .lineLimit(2)
        }
        Spacer(minLength: 40)
        if showNextEpisode, nextEpisodeShown {
          Button {
            player.playUpNext()
          } label: {
            Label("Next Episode", systemImage: "forward.end.fill")
          }
          .astraSecondaryButton()
          .focused($focus, equals: .next)
        }
        captionsMenu
        qualityMenu
      }
      // Hidden buttons can't take focus.
      .disabled(!visible)

      TVScrubBar(player: player, scrubbing: scrubbing)
        .focused($focus, equals: .bar)
    }
    .padding(.horizontal, 90)
    .padding(.bottom, 60)
    .focusSection()
    .onChange(of: focus) { poke() }
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
      Image(systemName: player.subtitleId == nil ? "captions.bubble" : "captions.bubble.fill")
    }
    .astraIconButton(size: 50, variant: .clear)
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
      .foregroundStyle(.white)
      .padding(.horizontal, 22)
      .frame(height: 64)
      .astraGlass(in: Capsule(), variant: .clear, interactive: true)
      .tvFocusLift(1.08)
    }
    .buttonStyle(.plain)
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

private struct TVScrubBarLabel: View {
  let player: PlayerController
  var scrubbing: Double?
  @Environment(\.isFocused) private var focused

  /// While scrubbing, the bar and clock show where a click will jump to.
  private var time: Double { scrubbing ?? player.position }

  private var fraction: Double {
    player.duration > 0 ? min(1, max(0, time / player.duration)) : 0
  }

  var body: some View {
    VStack(spacing: 12) {
      GeometryReader { geo in
        ZStack(alignment: .leading) {
          Capsule().fill(.white.opacity(0.28))
          Capsule().fill(.white).frame(width: max(focused ? 10 : 6, geo.size.width * fraction))
        }
      }
      .frame(height: focused ? 10 : 6)
      HStack {
        HStack(spacing: 10) {
          if player.paused {
            Image(systemName: "pause.fill").font(.system(size: 20, weight: .bold))
          }
          Text(Self.clock(time))
        }
        Spacer()
        Text("-" + Self.clock(max(0, player.duration - time)))
      }
      .font(.system(size: 24, weight: .semibold))
      .monospacedDigit()
      .foregroundStyle(.white.opacity(focused ? 1 : 0.8))
    }
    .contentShape(Rectangle())
    .astraAnimation(Astra.Motion.fast, value: focused)
  }

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
  }
}
