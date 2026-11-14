import AstraKit
import SwiftUI

/// The Apple TV player chrome (KP's mockups 3–6, 2026-11-10). Playback is
/// mpv with the original file; quality picks between the original files on
/// the server (Auto / HD / 4K), never a transcode.
///
/// Controls, bottom only: the title with a small HD/4K badge and the
/// subtitle button on one row, the scrubber, the elapsed and remaining time
/// (a long press on the click pad toggles "Ends at"). No on-screen transport.
///
/// The remote (from `TVPlayerHost`): click = play/pause, click left / right
/// = back / forward 10 s with a "−10" / "+10" flash, swipe sideways = scrub
/// with a large preview (click jumps there), Back = exit the player.
///
/// Swipe down: a panel slides down from the top over the dimmed, still
/// playing video, with Info · Settings · Subtitles tabs. Left / right switch
/// tabs, down enters the list, Back or a swipe up from the tabs closes it.
struct PlayerOverlay: View {
  @Environment(AppModel.self) private var app
  @AppStorage(Preferences.nextEpisodeKey) private var showNextEpisode = true
  @AppStorage("astra.player.showEndsAt") private var showEndsAt = false
  @State private var visible = true
  /// The time a swipe is scrubbing to, from the host; nil when not scrubbing.
  @State private var scrubbing: Double?
  /// Bumped on every press; the hide timer restarts from it.
  @State private var activity = 0
  @State private var menuOpen = false
  @State private var tab: TVPlayerTab = .info
  /// The list of choices open in the top menu (Audio, Size…), if any.
  @State private var options: TVPlayerOptions?
  /// The "−10" / "+10" flash after a click left or right.
  @State private var flash: (forward: Bool, id: Int)?
  @State private var lastBack = Date.distantPast
  @FocusState private var focus: Field?

  enum Field: Hashable {
    case bar, captions, next
    case tab(TVPlayerTab)
    case row(String)
  }

  private var player: PlayerController { app.player }

  var body: some View {
    TVPlayerHost(
      player: player,
      controlsVisible: $visible,
      scrubbing: $scrubbing,
      remoteEnabled: !menuOpen && (focus == .bar || focus == nil),
      poke: poke,
      onBack: back,
      onSwipeDown: { openMenu(tab) },
      onLongSelect: {
        showEndsAt.toggle()
        poke()
      },
      onSkipped: showFlash
    ) {
      controls
    }
  }

  private var controls: some View {
    ZStack(alignment: .bottom) {
      Color.clear

      // A shallow gradient at the bottom only, so the picture stays clean.
      VStack(spacing: 0) {
        Spacer()
        LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
          .frame(height: 300)
      }
      .ignoresSafeArea()
      .opacity(visible && !menuOpen ? 1 : 0)
      .allowsHitTesting(false)

      if !player.hasFirstFrame || player.buffering {
        ProgressView()
          .tint(.white)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .transition(.opacity)
      }

      scrubPreview

      if let flash {
        TVSkipFlash(forward: flash.forward)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: flash.forward ? .trailing : .leading)
          .padding(.horizontal, 260)
          .id(flash.id)
          .transition(.opacity.combined(with: .scale(scale: 0.9)))
          .allowsHitTesting(false)
      }

      chrome
        .opacity(visible && !menuOpen ? 1 : 0)

      if menuOpen {
        // The video keeps playing, dimmed, under the panel.
        Color.black.opacity(0.45)
          .ignoresSafeArea()
          .allowsHitTesting(false)
          .transition(.opacity)
        VStack(spacing: 0) {
          topMenu
          Spacer(minLength: 0)
        }
        // Edge to edge, like the mockup (not inset by the TV's safe area).
        .ignoresSafeArea(edges: [.top, .horizontal])
        .transition(.move(edge: .top).combined(with: .opacity))
      }
    }
    .astraAnimation(Astra.Motion.base, value: visible)
    .astraAnimation(Astra.Motion.base, value: menuOpen)
    .astraAnimation(Astra.Motion.fast, value: player.buffering)
    .astraAnimation(Astra.Motion.fast, value: flash?.id)
    // Back while focus is in these controls: SwiftUI gets the press first.
    .onExitCommand(perform: back)
    .onAppear {
      focus = .bar
      poke()
      applyDemo()
    }
    .onChange(of: visible) {
      // Hidden controls keep focus on the timeline, so the remote stays live.
      if !visible, !menuOpen { focus = .bar } else { activity &+= 1 }
    }
    .onChange(of: focus) { _, field in
      // Focusing a tab shows it (tvOS tab bars switch on focus).
      if case .tab(let next)? = field, next != tab {
        tab = next
        options = nil
      }
      if !menuOpen { poke() }
    }
    .task(id: activity) {
      try? await Task.pause(5)
      guard !Task.isCancelled, !player.paused, scrubbing == nil, !menuOpen, focus == .bar || focus == nil
      else { return }
      visible = false
    }
  }

  // MARK: Remote

  /// Back: closes a list of choices, then the top menu, then a scrub; else exits the player.
  /// The host and SwiftUI can both see one press, so a second call right after is ignored.
  private func back() {
    guard Date().timeIntervalSince(lastBack) > 0.35 else { return }
    lastBack = Date()
    if let open = options {
      options = nil
      focusSoon(.row(open.rowID))
    } else if menuOpen {
      closeMenu()
    } else if scrubbing != nil {
      scrubbing = nil
      poke()
    } else {
      player.close()
    }
  }

  private func openMenu(_ start: TVPlayerTab) {
    guard player.hasFirstFrame else { return }
    scrubbing = nil
    options = nil
    tab = start
    menuOpen = true
    focusSoon(.tab(start))
  }

  private func closeMenu() {
    menuOpen = false
    options = nil
    focus = .bar
    poke()
  }

  /// Focus a control that is only now appearing.
  private func focusSoon(_ field: Field) {
    Task { @MainActor in
      try? await Task.pause(0.05)
      focus = field
    }
  }

  private func showFlash(_ forward: Bool) {
    let id = (flash?.id ?? 0) &+ 1
    flash = (forward, id)
    Task { @MainActor in
      try? await Task.pause(0.7)
      if flash?.id == id { flash = nil }
    }
  }

  private func poke() {
    visible = true
    activity &+= 1
  }

  /// CI screenshots: `-AstraDemoPlayer controls|scrub|info|settings|subtitles`.
  private func applyDemo() {
    guard let shot = Demo.playerShot else { return }
    Task { @MainActor in
      for _ in 0..<60 where !player.hasFirstFrame { try? await Task.pause(0.25) }
      try? await Task.pause(1)
      player.setPaused(true)
      switch shot {
      case "scrub": scrubbing = player.duration * 0.35
      case "info": openMenu(.info)
      case "settings": openMenu(.settings)
      case "subtitles": openMenu(.subtitles)
      default: poke()
      }
    }
  }

  // MARK: Scrub preview

  /// A large still that follows the playhead while scrubbing.
  @ViewBuilder private var scrubPreview: some View {
    if let target = scrubbing, player.duration > 0, !menuOpen {
      GeometryReader { proxy in
        let inset = Self.inset
        let size = CGSize(width: 480, height: 270)
        let track = max(proxy.size.width - inset * 2, 0)
        let head = inset + track * CGFloat(min(1, max(0, target / player.duration)))
        let leading = min(max(head - size.width / 2, inset), proxy.size.width - inset - size.width)
        VStack(spacing: 10) {
          Group {
            if let image = player.thumbnail(at: target) {
              Image(platformImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
              Rectangle().fill(.black.opacity(0.5))
            }
          }
          .frame(width: size.width, height: size.height)
          .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
          .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.3), lineWidth: 1.5))
          Text(PlaybackClock.format(target))
            .font(.system(size: 30, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(.white)
        }
        .shadow(color: .black.opacity(0.5), radius: 18, y: 7)
        .frame(width: size.width)
        .padding(.leading, leading)
        .padding(.bottom, 230)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
      }
      .allowsHitTesting(false)
      .transition(.opacity)
    }
  }

  /// The side inset of the chrome.
  private static let inset: CGFloat = 90

  // MARK: Chrome

  private var resolutionTag: String? {
    guard let badge = player.resolutionBadge else { return nil }
    return badge == "4K UHD" ? "4K" : badge
  }

  /// The title with its badge and the subtitle button on one row, then the scrubber and times.
  private var chrome: some View {
    VStack(alignment: .leading, spacing: 22) {
      HStack(alignment: .center, spacing: 24) {
        VStack(alignment: .leading, spacing: 6) {
          HStack(alignment: .center, spacing: 16) {
            Text(player.title)
              .font(.system(size: 50, weight: .bold))
              .foregroundStyle(.white)
              .lineLimit(1)
            // About 40% of the title's height.
            if let tag = resolutionTag { ResolutionTag(text: tag, size: 19) }
          }
          if let subtitle = player.subtitle, !subtitle.isEmpty {
            Text(subtitle)
              .font(.system(size: 26, weight: .medium))
              .foregroundStyle(.white.opacity(0.65))
              .lineLimit(1)
          }
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
        // The subtitle button opens the top menu on Subtitles.
        Button {
          openMenu(.subtitles)
        } label: {
          TVCircleGlyph(
            symbol: player.subtitleId == nil ? "captions.bubble" : "captions.bubble.fill",
            focused: focus == .captions, size: 25)
        }
        .buttonStyle(TVBareButtonStyle())
        .focused($focus, equals: .captions)
        .accessibilityLabel("Subtitles")
        .accessibilityIdentifier("astra.player.subtitles")
      }
      // Hidden buttons can't take focus.
      .disabled(!visible || menuOpen)
      .focusSection()

      TVScrubBar(player: player, scrubbing: scrubbing, showEndsAt: showEndsAt)
        .focused($focus, equals: .bar)
    }
    .padding(.horizontal, Self.inset)
    .padding(.bottom, 56)
    .focusSection()
  }

  private var nextEpisodeShown: Bool {
    guard player.upNext != nil, player.duration > 0, player.hasFirstFrame else { return false }
    let left = player.duration - player.position
    return left > 0 && left <= PlayerController.nextEpisodeLead
  }

  // MARK: Top menu

  private var topMenu: some View {
    VStack(spacing: 34) {
      HStack(spacing: 18) {
        ForEach(TVPlayerTab.allCases) { item in
          Button {
            tab = item
          } label: {
            Text(item.title)
              .font(.system(size: 30, weight: .semibold))
              .foregroundStyle(tabFill(item) == .white ? Color.black : Color.white.opacity(tab == item ? 1 : 0.7))
              .padding(.horizontal, 30)
              .frame(height: 58)
              .background(Capsule().fill(tabFill(item)))
          }
          .buttonStyle(TVBareButtonStyle())
          .focused($focus, equals: .tab(item))
          .accessibilityAddTraits(tab == item ? .isSelected : [])
        }
      }
      .focusSection()
      // A swipe up from the tabs closes the menu.
      .onMoveCommand { direction in
        if direction == .up { closeMenu() }
      }

      Group {
        switch tab {
        case .info: info
        case .settings: rows(settingsRows)
        case .subtitles: rows(subtitleRows)
        }
      }
      .focusSection()
    }
    .padding(.top, 60)
    .padding(.bottom, 52)
    .padding(.horizontal, 120)
    .frame(maxWidth: .infinity)
    .background(
      UnevenRoundedRectangle(bottomLeadingRadius: 40, bottomTrailingRadius: 40, style: .continuous)
        .fill(Color(white: 0.09).opacity(0.94))
        .ignoresSafeArea(edges: [.top, .horizontal])
    )
    .shadow(color: .black.opacity(0.4), radius: 30, y: 10)
  }

  /// White when the tab has focus; a soft fill when it is the open tab and focus is in its list.
  private func tabFill(_ item: TVPlayerTab) -> Color {
    if focus == .tab(item) { return .white }
    if tab == item { return .white.opacity(0.2) }
    return .clear
  }

  /// Info (KP's mockup 4): poster, title + HD badge, "2025 [PG-13] 1h 56m · Genres", three lines of synopsis.
  @ViewBuilder private var info: some View {
    let item = player.nowPlayingItem
    HStack(alignment: .top, spacing: 40) {
      RemoteImage(url: player.posterURL, contentMode: .fill, placeholder: Color.white.opacity(0.08))
        .frame(width: 170, height: 255)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
      VStack(alignment: .leading, spacing: 14) {
        HStack(alignment: .center, spacing: 14) {
          Text(infoTitle(item))
            .font(.system(size: 46, weight: .bold))
            .foregroundStyle(.white)
            .lineLimit(1)
          if let tag = resolutionTag { ResolutionTag(text: tag, size: 18) }
        }
        HStack(spacing: 16) {
          if let year = item?.year { Text(String(year)) }
          if let rating = item?.contentRating, !rating.isEmpty {
            // A filled grey badge with no outline.
            RatingBox(text: rating, fontSize: 20, grey: true)
          }
          if let rest = durationAndGenres(item) { Text(rest) }
        }
        .font(.system(size: 26, weight: .medium))
        .foregroundStyle(.white.opacity(0.65))
        if let summary = item?.summary, !summary.isEmpty {
          Text(summary)
            .font(.system(size: 26))
            .foregroundStyle(.white.opacity(0.8))
            .lineLimit(3)
            .frame(maxWidth: 1240, alignment: .leading)
        }
      }
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// A movie's title; for an episode, the show's title (the episode is in the line under the controls).
  private func infoTitle(_ item: PlexMetadata?) -> String {
    guard let item else { return player.title }
    if item.type == .episode, let show = item.grandparentTitle { return show }
    return item.title
  }

  private func durationAndGenres(_ item: PlexMetadata?) -> String? {
    guard let item else { return nil }
    let genres = item.genres.prefix(2).map(\.tag).joined(separator: ", ")
    let parts = [item.durationLabel, genres.isEmpty ? nil : genres].compactMap { $0 }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
  }

  // MARK: Settings and Subtitles lists

  private struct Row: Identifiable {
    var id: String
    var title: String
    var value: String
    /// A list of choices opens on click; nil for Sync (left / right adjust it).
    var options: TVPlayerOptions?
  }

  private var settingsRows: [Row] {
    [
      Row(id: "audio", title: "Audio", value: currentAudio, options: .audio),
      Row(id: "quality", title: "Quality", value: player.quality.title, options: .quality),
      Row(id: "speed", title: "Speed", value: PlayerController.speedLabel(player.speed), options: .speed),
    ]
  }

  private var subtitleRows: [Row] {
    [
      Row(id: "track", title: "Track", value: currentSubtitle, options: .track),
      Row(id: "size", title: "Size", value: player.subtitleSize.title, options: .size),
      Row(id: "style", title: "Style", value: player.subtitleLook.title, options: .style),
      Row(id: "sync", title: "Sync", value: SubtitleSync.label(player.subtitleDelay), options: nil),
    ]
  }

  private var currentAudio: String {
    player.audioTracks.first { $0.id == player.audioId }?.title ?? player.audioTracks.first?.title ?? "—"
  }

  private var currentSubtitle: String {
    guard let id = player.subtitleId else { return "Off" }
    return player.subtitleTracks.first { $0.id == id }?.title ?? "On"
  }

  @ViewBuilder private func rows(_ rows: [Row]) -> some View {
    VStack(spacing: 6) {
      if let open = options {
        Text(open.title)
          .font(.system(size: 24, weight: .semibold))
          .foregroundStyle(.white.opacity(0.55))
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 30)
          .padding(.bottom, 4)
        ScrollView {
          VStack(spacing: 6) {
            ForEach(choices(open)) { choice in
              listRow(id: "opt-\(choice.id)", title: choice.title, value: choice.detail, checked: choice.selected) {
                choice.apply()
                options = nil
                focusSoon(.row(open.rowID))
              }
            }
          }
          .padding(.vertical, 8)
        }
        .frame(maxHeight: 420)
        .scrollClipDisabled()
      } else {
        ForEach(rows) { row in
          if row.options == nil {
            syncRow(row)
          } else {
            listRow(id: row.id, title: row.title, value: row.value) {
              options = row.options
              let selected = row.options.flatMap { choices($0).first(where: \.selected)?.id }
              focusSoon(.row("opt-\(selected ?? choices(row.options!).first?.id ?? "")"))
            }
          }
        }
      }
    }
    .frame(width: 1000)
  }

  /// One row: the name on the left, the value on the right; white when focused.
  private func listRow(
    id: String, title: String, value: String?, checked: Bool = false, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      TVMenuRow(title: title, value: value, checked: checked, focused: focus == .row(id))
    }
    .buttonStyle(TVBareButtonStyle())
    .focused($focus, equals: .row(id))
  }

  /// Sync: left / right move the subtitles 0.1 s earlier or later, live.
  private func syncRow(_ row: Row) -> some View {
    Button {} label: {
      TVMenuRow(
        title: row.title, value: focus == .row(row.id) ? "‹  \(row.value)  ›" : row.value, checked: false,
        focused: focus == .row(row.id))
    }
    .buttonStyle(TVBareButtonStyle())
    .focused($focus, equals: .row(row.id))
    .onMoveCommand { direction in
      switch direction {
      case .left: player.adjustSubtitleDelay(by: -1)
      case .right: player.adjustSubtitleDelay(by: 1)
      default: break
      }
    }
    .accessibilityLabel("Subtitle sync, \(row.value)")
  }

  private struct Choice: Identifiable {
    var id: String
    var title: String
    var detail: String? = nil
    var selected: Bool
    var apply: () -> Void
  }

  private func choices(_ list: TVPlayerOptions) -> [Choice] {
    switch list {
    case .audio:
      return player.audioTracks.map { track in
        Choice(id: "a\(track.id)", title: track.title, selected: player.audioId == track.id) {
          player.selectAudio(track.id)
        }
      }
    case .quality:
      var all: [Choice] = PlaybackQuality.allCases.map { quality in
        Choice(id: "q-\(quality.rawValue)", title: quality.title, selected: player.quality == quality) {
          player.setQuality(quality)
        }
      }
      // Other original files of this title (another library's 4K copy, say).
      if player.versions.count > 1 {
        all += player.versions.map { version in
          Choice(
            id: "v-\(version.id)", title: version.badge, detail: version.detail,
            selected: version.media.id == player.currentMediaID
          ) { player.playVersion(version) }
        }
      }
      return all
    case .speed:
      return PlayerController.speeds.map { speed in
        Choice(id: "s\(speed)", title: PlayerController.speedLabel(speed), selected: player.speed == speed) {
          player.setSpeed(speed)
        }
      }
    case .track:
      return [Choice(id: "off", title: "Off", selected: player.subtitleId == nil) { player.selectSubtitle(nil) }]
        + player.subtitleTracks.map { track in
          Choice(id: "t\(track.id)", title: track.title, selected: player.subtitleId == track.id) {
            player.selectSubtitle(track.id)
          }
        }
    case .size:
      return SubtitleSize.allCases.map { size in
        Choice(id: size.rawValue, title: size.title, selected: player.subtitleSize == size) {
          player.setSubtitleSize(size)
        }
      }
    case .style:
      return SubtitleLook.allCases.map { look in
        Choice(id: look.rawValue, title: look.title, selected: player.subtitleLook == look) {
          player.setSubtitleLook(look)
        }
      }
    }
  }
}

enum TVPlayerTab: String, CaseIterable, Identifiable, Hashable {
  case info, settings, subtitles
  var id: String { rawValue }
  var title: String {
    switch self {
    case .info: "Info"
    case .settings: "Settings"
    case .subtitles: "Subtitles"
    }
  }
}

/// A list of choices in the top menu.
enum TVPlayerOptions: Hashable {
  case audio, quality, speed, track, size, style

  var title: String {
    switch self {
    case .audio: "Audio"
    case .quality: "Quality"
    case .speed: "Speed"
    case .track: "Subtitles"
    case .size: "Size"
    case .style: "Style"
    }
  }

  /// The row it opened from (focus goes back there).
  var rowID: String {
    switch self {
    case .audio: "audio"
    case .quality: "quality"
    case .speed: "speed"
    case .track: "track"
    case .size: "size"
    case .style: "style"
    }
  }
}

/// A row of the top menu: standard tvOS focus, a white fill with dark text.
private struct TVMenuRow: View {
  var title: String
  var value: String?
  var checked: Bool
  var focused: Bool

  var body: some View {
    HStack(spacing: 18) {
      if checked {
        Image(systemName: "checkmark").font(.system(size: 22, weight: .bold))
      }
      Text(title).font(.system(size: 28, weight: .medium)).lineLimit(1)
      Spacer(minLength: 24)
      if let value {
        Text(value)
          .font(.system(size: 26))
          .monospacedDigit()
          .lineLimit(1)
          .opacity(focused ? 0.7 : 0.6)
      }
    }
    .foregroundStyle(focused ? Color.black : Color.white)
    .padding(.horizontal, 30)
    .frame(height: 70)
    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(focused ? Color.white : Color.clear))
    .scaleEffect(focused ? 1.02 : 1)
    .contentShape(Rectangle())
    .animation(.snappy(duration: 0.22), value: focused)
  }
}

/// "−10" / "+10" after a click left or right.
private struct TVSkipFlash: View {
  var forward: Bool

  var body: some View {
    VStack(spacing: 6) {
      Image(systemName: forward ? "goforward" : "gobackward").font(.system(size: 44, weight: .semibold))
      Text(forward ? "+10" : "\u{2212}10").font(.system(size: 30, weight: .bold)).monospacedDigit()
    }
    .foregroundStyle(.white)
    .frame(width: 170, height: 170)
    .background(Circle().fill(.black.opacity(0.45)))
    .accessibilityLabel(forward ? "Forward 10 seconds" : "Back 10 seconds")
  }
}

/// The white timeline with the time played and the time left. It holds focus
/// while the remote drives playback; the host does the clicks and swipes.
private struct TVScrubBar: View {
  let player: PlayerController
  var scrubbing: Double?
  var showEndsAt: Bool

  var body: some View {
    Button {} label: {
      TVScrubBarLabel(player: player, scrubbing: scrubbing, showEndsAt: showEndsAt)
    }
    .buttonStyle(TVBareButtonStyle())
    .accessibilityLabel(player.paused ? "Play" : "Pause")
    .accessibilityValue(PlaybackClock.format(scrubbing ?? player.position))
  }
}

struct TVScrubBarLabel: View {
  let player: PlayerController
  var scrubbing: Double?
  var showEndsAt = false

  /// While scrubbing, the bar and clock show where a click will jump to.
  private var time: Double { scrubbing ?? player.position }

  private var fraction: Double {
    player.duration > 0 ? min(1, max(0, time / player.duration)) : 0
  }

  var body: some View {
    VStack(spacing: 14) {
      GeometryReader { geo in
        let width = geo.size.width
        ZStack(alignment: .leading) {
          Capsule().fill(.white.opacity(scrubbing != nil ? 0.45 : 0.3)).frame(height: barHeight)
          Capsule().fill(.white).frame(width: max(barHeight, width * fraction), height: barHeight)
          if scrubbing != nil {
            Circle()
              .fill(.white)
              .frame(width: 30, height: 30)
              .shadow(color: .black.opacity(0.48), radius: 8, y: 3)
              .offset(x: width * fraction - 15)
          }
        }
        .frame(height: 36)
      }
      .frame(height: 36)
      HStack {
        Text(PlaybackClock.format(time))
        Spacer()
        if showEndsAt {
          Text(PlaybackClock.endsAt(remaining: player.duration - time, speed: player.speed))
        } else {
          Text("\u{2212}" + PlaybackClock.format(max(0, player.duration - time)))
        }
      }
      .font(.system(size: 28, weight: .medium))
      .monospacedDigit()
      .foregroundStyle(.white.opacity(0.75))
    }
    .contentShape(Rectangle())
    .astraAnimation(Astra.Motion.fast, value: scrubbing != nil)
  }

  private var barHeight: CGFloat { scrubbing != nil ? 14 : 8 }

  /// "1:02:05" or "12:05".
  static func clock(_ seconds: Double) -> String { PlaybackClock.format(seconds) }
}

/// No system focus platter: each control shows focus itself.
private struct TVBareButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .focusEffectDisabled()
      .scaleEffect(configuration.isPressed ? 0.96 : 1)
  }
}

/// A round glyph button: dark glass at rest, white with a black glyph when focused.
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
