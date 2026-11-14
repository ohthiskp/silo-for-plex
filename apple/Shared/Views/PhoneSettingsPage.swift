import AstraKit
import SwiftUI

#if os(iOS)

  /// iPhone Settings, Direction C (KP picked it 2026-11-14 from design-audit/05):
  /// a root that fits on one screen, the server and library index first, then
  /// each category as a row showing its current value. Each category opens its
  /// own page; the live Home preview and the subtitle sample live on those
  /// pages. Quiet glass cards, no icon tiles, footers only where a choice has a
  /// consequence.
  struct PhoneSettingsPage: View {
    /// The Settings tab draws its own large title; the sheet from Library
    /// has a navigation bar that already says "Settings".
    var showsTitle: Bool
    @Environment(AppModel.self) private var app
    @AppStorage(PlaybackQuality.storageKey) private var quality: PlaybackQuality = .auto
    @AppStorage(Preferences.nextEpisodeKey) private var nextEpisode = true
    @AppStorage(SubtitlePreference.storageKey) private var subtitles: SubtitlePreference = .automatic
    @AppStorage(LibraryQuality.storageKey) private var libraryQuality: LibraryQuality = .deviceDefault
    @AppStorage(Preferences.qualityBadgesKey) private var qualityBadges = true
    @AppStorage(TabLayout.storageKey) private var storedTabs = ""
    @AppStorage(SubtitleSize.storageKey) private var subtitleSize: SubtitleSize = .medium
    /// CI screenshots (`-AstraDemoSettings appearance|playback|…`): open that page.
    @State private var demoPage: PhoneSettingsDestination?

    var body: some View {
      ScrollView {
        VStack(alignment: .leading, spacing: 22) {
          if showsTitle {
            Text("Settings")
              .astraFont(.display(Astra.Layout.pageTitleSize))
              .foregroundStyle(Astra.Color.ink)
          }
          PhoneServerCard()
          PhoneCard {
            PhoneLinkRow(title: "Appearance", value: AstraAppearance.shared.appTheme.title) { PhoneAppearancePage() }
            PhoneLinkRow(title: "Playback", value: "\(quality.title) · Next Episode \(nextEpisode ? "on" : "off")") {
              PhonePlaybackPage()
            }
            PhoneLinkRow(title: "Subtitles", value: "\(subtitles.title) · \(subtitleSize.shortTitle)") {
              PhoneSubtitlesPage()
            }
            PhoneLinkRow(title: "Library", value: "\(libraryQuality.title) · badges \(qualityBadges ? "on" : "off")") {
              PhoneLibraryPage()
            }
            PhoneLinkRow(title: "Downloads", value: downloadsValue) { PhoneDownloadsPage() }
          }
          PhoneCard {
            PhoneLinkRow(title: "Tab Bar", value: "\(TabLayout.tabs(from: storedTabs).count) tabs") {
              SettingsPaneView(pane: .tabs)
            }
            PhoneLinkRow(title: "About") { SettingsPaneView(pane: .about) }
          }
          Text("Astra \(SettingsView.versionText)")
            .astraFont(size: 13.5)
            .foregroundStyle(Astra.Color.ink.opacity(0.42))
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 16)
        .padding(.top, showsTitle ? Astra.Spacing.pageTop : 12)
        .padding(.bottom, PhoneSettingsMetrics.bottomRoom)
      }
      .scrollIndicators(.never)
      .contentMargins(.bottom, Astra.Layout.tabBarRoom, for: .scrollContent)
      .astraPageBackground()
      .navigationDestination(item: $demoPage) { $0.page }
      .task {
        guard Demo.isOn, let name = UserDefaults.standard.string(forKey: "AstraDemoSettings"),
          let page = PhoneSettingsDestination(rawValue: name), (try? await Task.pause(2)) != nil
        else { return }
        demoPage = page
      }
    }

    private var downloadsValue: String {
      let count = app.downloads.index.records.count
      guard count > 0 else { return "None" }
      return "\(count) · " + ByteCountFormatter.string(fromByteCount: app.downloads.storageUsed, countStyle: .file)
    }
  }

  /// The pages Settings opens; also the CI screenshot names.
  enum PhoneSettingsDestination: String, Identifiable, Hashable {
    case appearance, playback, subtitles, library, downloads, server

    var id: String { rawValue }

    @MainActor @ViewBuilder var page: some View {
      switch self {
      case .appearance: PhoneAppearancePage()
      case .playback: PhonePlaybackPage()
      case .subtitles: PhoneSubtitlesPage()
      case .library: PhoneLibraryPage()
      case .downloads: PhoneDownloadsPage()
      case .server: PhoneServerPage()
      }
    }
  }

  private enum PhoneSettingsMetrics {
    /// Past the floating tab bar, so the last row and the version line are never under it.
    static let bottomRoom: CGFloat = 56
  }

  // MARK: - Building blocks

  /// A titled group of rows on a quiet glass card, hairlines between rows,
  /// and an optional footer that explains a consequence.
  private struct PhoneCard<Content: View>: View {
    var title: String?
    var footer: String?
    @ViewBuilder var content: Content

    static var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 18, style: .continuous) }

    var body: some View {
      VStack(alignment: .leading, spacing: 8) {
        if let title {
          Text(title)
            .astraFont(size: 15, weight: .semibold)
            .foregroundStyle(Astra.Color.muted)
            .padding(.leading, 6)
            .accessibilityAddTraits(.isHeader)
        }
        // Each row draws a hairline along its top; the first sits under the card's edge.
        VStack(spacing: 0) { content }
          .background(Self.shape.fill(Astra.Color.ink.opacity(0.06)))
          .overlay(Self.shape.strokeBorder(Astra.Color.hairline, lineWidth: 1))
          .clipShape(Self.shape)
        if let footer {
          Text(footer)
            .astraFont(size: 13)
            .foregroundStyle(Astra.Color.muted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 6)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private struct PhoneRow<Control: View>: View {
    var title: String
    @ViewBuilder var control: Control

    var body: some View {
      HStack(spacing: 12) {
        // Labels wrap at large text sizes instead of shrinking (design-audit B-20).
        Text(title)
          .astraFont(size: 17, weight: .medium)
          .foregroundStyle(Astra.Color.ink)
          .fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 8)
        control
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 8)
      .frame(minHeight: 52)
      .phoneHairline()
    }
  }

  private struct PhoneSwitch: View {
    var title: String
    @Binding var isOn: Bool

    var body: some View {
      PhoneRow(title: title) {
        Toggle(title, isOn: $isOn).labelsHidden().tint(Astra.Color.switchOn)
      }
    }
  }

  /// A row that pushes a page, with its current value and a chevron.
  private struct PhoneLinkRow<Destination: View>: View {
    var title: String
    var value: String = ""
    @ViewBuilder var destination: () -> Destination

    var body: some View {
      NavigationLink {
        destination()
      } label: {
        PhoneRow(title: title) {
          HStack(spacing: 6) {
            if !value.isEmpty {
              Text(value)
                .astraFont(size: 15)
                .foregroundStyle(Astra.Color.muted)
                .lineLimit(1)
                .truncationMode(.middle)
            }
            Image(systemName: "chevron.right")
              .astraFont(size: 14, weight: .semibold)
              .foregroundStyle(Astra.Color.muted)
              .accessibilityHidden(true)
          }
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityValue(value)
    }
  }

  /// A whole row that runs an action (Index Now, Change Server…).
  private struct PhoneActionRow: View {
    var title: String
    var action: () -> Void

    var body: some View {
      Button(action: action) {
        PhoneRow(title: title) { EmptyView() }
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
    }
  }

  /// A plain read-only value on the right of a row.
  private struct PhoneValue: View {
    var text: String

    var body: some View {
      Text(text)
        .astraFont(size: 15)
        .monospacedDigit()
        .foregroundStyle(Astra.Color.muted)
        .multilineTextAlignment(.trailing)
    }
  }

  extension View {
    fileprivate func phoneHairline() -> some View {
      overlay(alignment: .top) { Rectangle().fill(Astra.Color.hairline).frame(height: 1) }
    }
  }

  /// A pushed Settings page: large title, the same background, room for the tab bar.
  private struct PhoneSettingsSubpage<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) { content }
          .padding(.horizontal, 16)
          .padding(.top, 8)
          .padding(.bottom, PhoneSettingsMetrics.bottomRoom)
      }
      .scrollIndicators(.never)
      .contentMargins(.bottom, Astra.Layout.tabBarRoom, for: .scrollContent)
      .astraPageBackground()
      .navigationTitle(title)
      .navigationBarTitleDisplayMode(.large)
      .toolbar(.visible, for: .navigationBar)
    }
  }

  // MARK: - Server card (root)

  /// The server at a glance: its name and connection, the library index bar
  /// with Index Now, and a tap opens the Server page.
  private struct PhoneServerCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
      VStack(spacing: 0) {
        NavigationLink {
          PhoneServerPage()
        } label: {
          HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
              Text(app.server?.serverName ?? "Not connected")
                .astraFont(size: 21, weight: .bold)
                .foregroundStyle(Astra.Color.ink)
              PhoneConnectionLine()
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
              .astraFont(size: 15, weight: .semibold)
              .foregroundStyle(Astra.Color.muted)
              .accessibilityHidden(true)
          }
          .padding(16)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Server, library index, Change Server and Sign Out")
        if let library = app.library {
          IndexProgress(library: library, scale: 1.2) {
            Button("Index Now") { library.reindexNow() }
              .astraFont(size: 16, weight: .semibold)
              .foregroundStyle(Astra.Color.ink)
              .buttonStyle(.plain)
              .disabled(library.indexStatus.phase == .indexing)
              .opacity(library.indexStatus.phase == .indexing ? 0.45 : 1)
          }
          .padding(16)
          .phoneHairline()
        }
      }
      .background(PhoneCard<EmptyView>.shape.fill(Astra.Color.ink.opacity(0.08)))
      .overlay(PhoneCard<EmptyView>.shape.strokeBorder(Astra.Color.hairline, lineWidth: 1))
      .clipShape(PhoneCard<EmptyView>.shape)
    }
  }

  /// "● Connected · Local network".
  private struct PhoneConnectionLine: View {
    @Environment(AppModel.self) private var app

    var body: some View {
      HStack(spacing: 7) {
        Circle()
          .fill(app.health?.state == .connected ? Astra.Color.ink : Astra.Color.muted)
          .frame(width: 7, height: 7)
          .accessibilityHidden(true)
        Text(text)
          .astraFont(size: 15)
          .foregroundStyle(Astra.Color.muted)
          .lineLimit(2)
      }
    }

    private var text: String {
      guard let url = app.server?.baseURL else { return "Plex Media Server" }
      let state = app.health?.state.title ?? "Connected"
      return "\(state) · \(ConnectionKind.classify(url).title)"
    }
  }

  // MARK: - Server page

  private struct PhoneServerPage: View {
    @Environment(AppModel.self) private var app

    var body: some View {
      PhoneSettingsSubpage(title: "Server") {
        PhoneCard {
          PhoneRow(title: "Name") { PhoneValue(text: app.server?.serverName ?? "Not connected") }
          PhoneRow(title: "Status") { PhoneValue(text: app.health?.state.title ?? "—") }
          if let url = app.server?.baseURL {
            PhoneRow(title: "Connection") { PhoneValue(text: ConnectionKind.classify(url).title) }
            PhoneRow(title: "Address") { PhoneValue(text: url.host() ?? "—") }
          }
        }
        if let library = app.library {
          PhoneIndexCard(library: library)
        }
        PhoneCard(
          footer: "Streams and downloads are fastest on your local network. Remote speed depends on the server's upload; Plex Relay is capped by Plex."
        ) {
          PhoneActionRow(title: "Change Server…") { Task { await app.chooseServer() } }
          SignOutButton(role: .destructive)
            .astraFont(size: 17, weight: .medium)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .padding(.horizontal, 16)
            .phoneHairline()
        }
      }
    }
  }

  /// Library index details (KP, 2026-11-09): per library, last full read,
  /// how long it took, retries and errors, how fast titles open, Index Now.
  private struct PhoneIndexCard: View {
    var library: LibraryStore

    var body: some View {
      let status = library.indexStatus
      PhoneCard(
        title: "Library index",
        footer: "Astra reads your library in the background and saves as it goes, so titles it has read open at once and an interrupted read carries on where it stopped."
      ) {
        PhoneRow(title: "Status") { PhoneValue(text: phaseText(status)) }
        ForEach(status.libraries) { section in
          PhoneRow(title: section.title) { PhoneValue(text: progressText(section)) }
        }
        PhoneRow(title: "Last full read") {
          PhoneValue(text: status.lastSuccess.map { $0.formatted(.relative(presentation: .named)) } ?? "Never")
        }
        if let duration = status.lastDuration {
          PhoneRow(title: "Took") { PhoneValue(text: LibraryIndexSection.seconds(duration)) }
        }
        if status.retries > 0 {
          PhoneRow(title: "Retries") { PhoneValue(text: "\(status.retries)") }
        }
        if let error = status.lastError {
          PhoneRow(title: "Last error") { PhoneValue(text: error) }
        }
        PhoneRow(title: "Opening a title") { PhoneValue(text: openText(library.openTimings)) }
        PhoneActionRow(title: "Index Now") { library.reindexNow() }
          .disabled(status.phase == .indexing)
          .opacity(status.phase == .indexing ? 0.45 : 1)
      }
    }

    private func phaseText(_ status: LibraryIndexStatus) -> String {
      switch status.phase {
      case .idle: "Not started"
      case .indexing: status.complete ? "Up to date, checking" : "Indexing"
      case .complete: "Up to date"
      case .failed: status.complete ? "Up to date, last check failed" : "Paused, will retry"
      }
    }

    private func progressText(_ section: LibraryIndexStatus.Library) -> String {
      if section.complete { return "\(section.fetched.formatted()) titles" }
      if let total = section.total { return "\(section.fetched.formatted()) of \(total.formatted())" }
      return "\(section.fetched.formatted()) so far"
    }

    private func openText(_ timings: OpenTimings) -> String {
      guard let last = timings.last, let median = timings.median else { return "Not measured yet" }
      return "last \(LibraryIndexSection.seconds(last)), typical \(LibraryIndexSection.seconds(median))"
    }
  }

  // MARK: - Appearance

  private struct PhoneAppearancePage: View {
    @Environment(AppModel.self) private var app
    @AppStorage(Preferences.serviceAccentsKey) private var serviceAccents = true
    @AppStorage(Preferences.serviceLogoColorsKey) private var logoColors = true
    private var appearance: AstraAppearance { .shared }

    var body: some View {
      PhoneSettingsSubpage(title: "Appearance") {
        if let library = app.library {
          VStack(alignment: .leading, spacing: 14) {
            PhoneHomePreview(library: library)
            HStack(alignment: .top, spacing: 10) {
              ForEach(AppTheme.allCases) { theme in tile(theme, library: library) }
            }
          }
        }
        PhoneCard(
          title: "Streaming services",
          footer: "Service colours tint each service's Home page. Turn logo colours off for plain white logos on glass."
        ) {
          PhoneSwitch(title: "Service colours", isOn: $serviceAccents)
          PhoneSwitch(title: "Coloured logos", isOn: $logoColors)
        }
      }
    }

    private func tile(_ theme: AppTheme, library: LibraryStore) -> some View {
      let isOn = theme == appearance.appTheme
      return Button {
        astraWithAnimation(Astra.Motion.page) { appearance.setTheme(theme) }
      } label: {
        VStack(spacing: 8) {
          ThemeSwatch(library: library, palette: theme.palette, width: nil, height: 64, radius: 12)
            .padding(3)
            .overlay(
              RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(isOn ? Astra.Color.ink : .clear, lineWidth: 2))
          Text(theme.title)
            .astraFont(size: 14, weight: isOn ? .semibold : .medium)
            .foregroundStyle(isOn ? Astra.Color.ink : Astra.Color.muted)
            .lineLimit(2)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(theme.title)
      .accessibilityAddTraits(isOn ? .isSelected : [])
    }
  }

  /// Home's real hero in the theme in use (artwork, logo, badges, buttons),
  /// laid out at Home's own size and drawn at 60 %, so the page stays short.
  /// Not tappable.
  private struct PhoneHomePreview: View {
    var library: LibraryStore
    private static let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
    /// Home's hero height the preview is laid out at, and how much it is scaled down.
    private static let layoutHeight: CGFloat = 420
    private static let scale: CGFloat = 0.6

    var body: some View {
      GeometryReader { proxy in
        let width = proxy.size.width
        hero
          .frame(width: width / Self.scale, height: Self.layoutHeight)
          .scaleEffect(Self.scale, anchor: .topLeading)
          .frame(width: width, height: Self.layoutHeight * Self.scale, alignment: .topLeading)
      }
      .frame(height: Self.layoutHeight * Self.scale)
      .clipShape(Self.shape)
      .astraGlassEdge(Self.shape, strength: 0.5)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Preview of Home in this theme")
    }

    private var hero: some View {
      ZStack(alignment: .bottom) {
        Astra.Color.bg
        if let item = library.homeHero.first {
          // Sized by the box, never by the picture: a filled image would widen the page.
          Color.clear.overlay(alignment: .top) {
            ArtworkImage(
              library: library, item: item, kind: .heroBackdrop, width: 1280, height: 720, placeholder: Color.clear)
          }
          .clipped()
          LinearGradient(
            stops: [
              .init(color: Astra.Color.bg.opacity(0), location: 0.3),
              .init(color: Astra.Color.bg.opacity(0.8), location: 0.62),
              .init(color: Astra.Color.bg, location: 0.9),
            ], startPoint: .top, endPoint: .bottom)
          HeroInfo(library: library, item: item)
            .padding(.horizontal, 16)
            .padding(.bottom, 22)
            .allowsHitTesting(false)
        } else {
          Text("Your Home appears here once it loads.")
            .astraFont(.meta)
            .foregroundStyle(Astra.Color.muted)
            .padding(24)
        }
      }
    }
  }

  // MARK: - Playback

  private struct PhonePlaybackPage: View {
    @AppStorage(PlaybackQuality.storageKey) private var quality: PlaybackQuality = .auto
    @AppStorage(Preferences.nextEpisodeKey) private var nextEpisode = true
    @AppStorage(Preferences.swipeGesturesKey) private var swipe = true
    @AppStorage(Preferences.twoFingerPauseKey) private var twoFinger = true
    @AppStorage(Preferences.skipSecondsKey) private var skipSeconds = 10

    var body: some View {
      PhoneSettingsSubpage(title: "Playback") {
        PhoneCard(
          footer: "Astra always plays the original file. When a title has an HD and a 4K file on the server, this picks which one. Auto follows Library quality."
        ) {
          PhoneRow(title: "Preferred version") {
            Picker("Preferred version", selection: $quality) {
              ForEach(PlaybackQuality.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden().pickerStyle(.segmented).fixedSize()
          }
        }
        PhoneCard(footer: "Shows in the last 15 seconds of an episode. It never plays on its own.") {
          PhoneSwitch(title: "Next Episode button", isOn: $nextEpisode)
        }
        PhoneCard(
          title: "Gestures in the player",
          footer: "Double-tap the right side to skip forward, the left to go back. Swipe on the left for brightness, on the right for volume."
        ) {
          PhoneRow(title: "Double-tap skips") {
            Picker("Double-tap skips", selection: $skipSeconds) {
              Text("10 s").tag(10)
              Text("15 s").tag(15)
              Text("30 s").tag(30)
            }
            .labelsHidden().pickerStyle(.segmented).fixedSize()
          }
          PhoneSwitch(title: "Swipe for brightness and volume", isOn: $swipe)
          PhoneSwitch(title: "Two-finger tap to pause", isOn: $twoFinger)
        }
      }
    }
  }

  // MARK: - Subtitles

  /// When subtitles show, and how they look (KP, 2026-11-13: font, size,
  /// colour, background, with a live sample).
  private struct PhoneSubtitlesPage: View {
    @Environment(AppModel.self) private var app
    @AppStorage(SubtitlePreference.storageKey) private var subtitles: SubtitlePreference = .automatic
    @State private var style = SubtitleStyle.current()

    var body: some View {
      PhoneSettingsSubpage(title: "Subtitles") {
        if let library = app.library {
          SubtitleSample(library: library, style: style, scale: 1.1)
        }
        PhoneCard(footer: "Automatic shows what the file marks as forced or default. Always picks your language.") {
          PhoneRow(title: "When to show") {
            Picker("When to show", selection: $subtitles) {
              ForEach(SubtitlePreference.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden().pickerStyle(.segmented).fixedSize()
          }
        }
        PhoneCard(title: "Style") {
          PhoneRow(title: "Font") {
            Picker("Font", selection: $style.font) {
              ForEach(SubtitleFont.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden().pickerStyle(.menu).tint(Astra.Color.muted)
          }
          PhoneRow(title: "Size") {
            Picker("Size", selection: $style.size) {
              ForEach(SubtitleSize.allCases) { Text($0.shortTitle).tag($0) }
            }
            .labelsHidden().pickerStyle(.segmented).fixedSize()
          }
          // 32 pt dots + 3 pt rings: about 44 pt to tap (design-audit B-20).
          PhoneRow(title: "Colour") { SubtitleColorPicker(selection: $style.color, size: 32) }
          PhoneRow(title: "Background") {
            Picker("Background", selection: $style.background) {
              ForEach(SubtitleBackground.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden().pickerStyle(.segmented).fixedSize()
          }
        }
      }
      .onChange(of: style) {
        style.save()
        app.player.applySubtitleStyle()
      }
    }
  }

  // MARK: - Library

  private struct PhoneLibraryPage: View {
    @Environment(AppModel.self) private var app
    @AppStorage(LibraryQuality.storageKey) private var libraryQuality: LibraryQuality = .deviceDefault
    @AppStorage(Preferences.qualityBadgesKey) private var qualityBadges = true
    @AppStorage(Preferences.ratingsKey) private var ratings = true
    /// A change waiting for the reload to be confirmed (design-audit B-02).
    @State private var pending: LibraryQuality?

    var body: some View {
      PhoneSettingsSubpage(title: "Library") {
        PhoneCard(footer: footer) {
          PhoneRow(title: "Library quality") {
            Picker("Library quality", selection: choice) {
              ForEach(LibraryQuality.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden().pickerStyle(.segmented).fixedSize()
          }
        }
        PhoneCard(
          title: "Badges",
          footer: "Quality badges (HD, 4K, HDR, Dolby Vision, Dolby Atmos) come from the file on your server. The boxed rating (PG-13, TV-MA) is the age rating."
        ) {
          PhoneSwitch(title: "HD and 4K badges", isOn: $qualityBadges)
          PhoneSwitch(title: "Age ratings", isOn: $ratings)
        }
      }
      .confirmationDialog(
        pending.map { "Switch to \($0.title)?" } ?? "", isPresented: isConfirming, titleVisibility: .visible
      ) {
        Button("Switch and Reload") {
          if let pending { libraryQuality = pending }
          pending = nil
          app.libraryQualityChanged()
        }
        Button("Cancel", role: .cancel) { pending = nil }
      } message: {
        Text("Astra reloads your library with the new choice. Home and your libraries refresh in a moment.")
      }
    }

    /// The picker asks first instead of writing the setting straight away.
    private var choice: Binding<LibraryQuality> {
      Binding(get: { libraryQuality }, set: { if $0 != libraryQuality { pending = $0 } })
    }

    private var isConfirming: Binding<Bool> {
      Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })
    }

    private var footer: String {
      libraryQuality == .hd
        ? "One copy of each title, in HD. 4K libraries are hidden on this iPhone."
        : "One copy of each title: the 4K one when there is one, otherwise HD."
    }
  }

  // MARK: - Downloads

  private struct PhoneDownloadsPage: View {
    @Environment(AppModel.self) private var app
    @AppStorage(Preferences.wifiOnlyKey) private var wifiOnly = false

    var body: some View {
      PhoneSettingsSubpage(title: "Downloads") {
        PhoneCard(footer: "Downloads wait for Wi-Fi instead of using cellular data.") {
          PhoneSwitch(title: "Wi-Fi only", isOn: $wifiOnly)
          PhoneRow(title: "Saved titles") {
            PhoneValue(
              text: "\(app.downloads.index.records.count) · "
                + ByteCountFormatter.string(fromByteCount: app.downloads.storageUsed, countStyle: .file))
          }
        }
        // The same list as Library → Downloads, so titles can be managed here too.
        DownloadsContent()
      }
    }
  }

#endif
