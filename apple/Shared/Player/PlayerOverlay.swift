import AstraKit
import SwiftUI

/// The minimal player chrome over the video: close and title at the top,
/// big 10 s / pause / 10 s transport in the middle, a violet timeline and
/// track chips at the bottom. Fades out after 3 s without the pointer moving.
struct PlayerOverlay: View {
  @Environment(AppModel.self) private var app
  @State private var visible = true
  @State private var hideTask: Task<Void, Never>?
  @State private var scrubbing: Double?

  private var player: PlayerController { app.player }

  var body: some View {
    ZStack {
      // Clear, but hit-testable. Mac: click pauses, double-click goes full screen.
      // iPhone: tap shows or hides the controls.
      #if os(macOS)
        Color.black.opacity(0.001)
          .onTapGesture(count: 2) { player.toggleFullScreen() }
          .onTapGesture { player.togglePause() }
      #else
        Color.black.opacity(0.001)
          .onTapGesture { visible ? hide() : poke() }
      #endif

      chrome
        .opacity(visible ? 1 : 0)
        .allowsHitTesting(visible)

      if player.buffering {
        ProgressView().controlSize(.large).tint(.white)
          .transition(.opacity)
      }
    }
    .animation(Astra.Motion.base, value: visible)
    .animation(Astra.Motion.fast, value: player.buffering)
    #if os(macOS)
      .onContinuousHover { phase in
        if case .active = phase { poke() }
      }
    #endif
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

  private var chrome: some View {
    ZStack {
      // Scrims so white text reads over any frame.
      VStack(spacing: 0) {
        LinearGradient(colors: [.black.opacity(0.65), .clear], startPoint: .top, endPoint: .bottom).frame(height: 170)
        Spacer()
        LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom).frame(height: 220)
      }
      .allowsHitTesting(false)

      VStack {
        topBar
        Spacer()
        transport
        Spacer()
        bottomBar
      }
      .padding(.horizontal, Self.inset)
      .padding(.vertical, 30)
    }
  }

  private var topBar: some View {
    HStack(alignment: .center, spacing: 16) {
      Button {
        player.close()
      } label: {
        Image(systemName: "xmark")
      }
      .astraIconButton(size: 42, variant: .clear)
      .help("Close (Esc)")

      VStack(alignment: .leading, spacing: 3) {
        Text(player.title).font(.system(size: 18, weight: .bold)).foregroundStyle(.white).lineLimit(1)
        if let subtitle = player.subtitle {
          Text(subtitle).font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
        }
      }
      Spacer()
      if let badge = player.resolutionBadge { Badge(text: badge) }
      #if os(macOS)
        Button {
          player.toggleFullScreen()
        } label: {
          Image(systemName: "arrow.up.left.and.arrow.down.right")
        }
        .astraIconButton(size: 42, variant: .clear)
        .help("Full Screen")
      #endif
    }
  }

  private var transport: some View {
    HStack(spacing: Self.transportSizes.gap) {
      Button {
        player.seek(by: -10)
        poke()
      } label: {
        Image(systemName: "gobackward.10")
      }
      .astraIconButton(size: Self.transportSizes.small, variant: .clear)

      Button {
        player.togglePause()
      } label: {
        Image(systemName: player.paused ? "play.fill" : "pause.fill")
          .contentTransition(.symbolEffect(.replace))
      }
      .astraIconButton(size: Self.transportSizes.large, variant: .clear)

      Button {
        player.seek(by: 10)
        poke()
      } label: {
        Image(systemName: "goforward.10")
      }
      .astraIconButton(size: Self.transportSizes.small, variant: .clear)
    }
    .astraGlassGroup(spacing: Self.transportSizes.gap)
  }

  private var bottomBar: some View {
    VStack(spacing: 14) {
      Timeline(
        position: scrubbing ?? player.position,
        duration: player.duration,
        onScrub: { value in
          scrubbing = value
          poke()
        },
        onCommit: { value in
          player.seek(to: value)
          scrubbing = nil
        })
      HStack(spacing: 10) {
        Text(Self.clock(scrubbing ?? player.position))
        Spacer()
        trackMenu(
          title: "Audio", symbol: "speaker.wave.2.fill", tracks: player.audioTracks, selected: player.audioId,
          allowsOff: false
        ) { player.selectAudio($0 ?? 1) }
        trackMenu(
          title: "Subtitles", symbol: "captions.bubble.fill", tracks: player.subtitleTracks,
          selected: player.subtitleId, allowsOff: true
        ) { player.selectSubtitle($0) }
        Spacer()
        Text("-" + Self.clock(max(0, player.duration - (scrubbing ?? player.position))))
      }
      .font(.system(size: 13, weight: .semibold).monospacedDigit())
      .foregroundStyle(.white.opacity(0.9))
      .astraGlassGroup(spacing: 10)
    }
  }

  private func trackMenu(
    title: String, symbol: String, tracks: [PlayerController.Track], selected: Int?, allowsOff: Bool,
    choose: @escaping (Int?) -> Void
  ) -> some View {
    Menu {
      if allowsOff {
        Button {
          choose(nil)
        } label: {
          if selected == nil { Label("Off", systemImage: "checkmark") } else { Text("Off") }
        }
      }
      ForEach(tracks) { track in
        Button {
          choose(track.id)
        } label: {
          if selected == track.id { Label(track.title, systemImage: "checkmark") } else { Text(track.title) }
        }
      }
    } label: {
      Label(
        tracks.first { $0.id == selected }?.title ?? (allowsOff ? "Off" : title), systemImage: symbol
      )
      .font(.system(size: 12.5, weight: .semibold))
      .padding(.horizontal, 14)
      .frame(height: 32)
      .astraGlass(in: Capsule(), variant: .clear, interactive: true)
    }
    .menuStyle(.button)
    .buttonStyle(.plain)
    .menuIndicator(.hidden)
    .fixedSize()
    .disabled(tracks.isEmpty)
    .help(title)
  }

  /// Shows the chrome and schedules it to hide again.
  private func poke() {
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

  #if os(macOS)
    static let inset: CGFloat = 40
    static let transportSizes: (small: CGFloat, large: CGFloat, gap: CGFloat) = (64, 86, 44)
  #else
    static let inset: CGFloat = 20
    static let transportSizes: (small: CGFloat, large: CGFloat, gap: CGFloat) = (56, 76, 36)
  #endif

  static func clock(_ seconds: Double) -> String {
    let total = Int(seconds.rounded(.down))
    let h = total / 3600
    let m = (total % 3600) / 60
    let s = total % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
  }
}

/// A violet timeline that grows on hover. Dragging previews the time and seeks on release.
struct Timeline: View {
  var position: Double
  var duration: Double
  var onScrub: (Double) -> Void
  var onCommit: (Double) -> Void

  @State private var hovering = false

  var body: some View {
    GeometryReader { geo in
      let fraction = duration > 0 ? min(1, max(0, position / duration)) : 0
      ZStack(alignment: .leading) {
        Capsule().fill(.white.opacity(0.25))
        Capsule().fill(Astra.Color.purple)
          .frame(width: geo.size.width * fraction)
        Circle().fill(.white)
          .frame(width: 14, height: 14)
          .shadow(color: .black.opacity(0.4), radius: 4)
          .offset(x: geo.size.width * fraction - 7)
          .opacity(hovering ? 1 : 0)
      }
      .frame(height: 6)
      .scaleEffect(y: hovering ? 1.4 : 1)
      .frame(maxHeight: .infinity)
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { onScrub(value(at: $0.location.x, width: geo.size.width)) }
          .onEnded { onCommit(value(at: $0.location.x, width: geo.size.width)) }
      )
    }
    .frame(height: 22)
    .onHover { hovering = $0 }
    .animation(Astra.Motion.fast, value: hovering)
  }

  private func value(at x: CGFloat, width: CGFloat) -> Double {
    guard width > 0 else { return 0 }
    return Double(min(1, max(0, x / width))) * duration
  }
}
