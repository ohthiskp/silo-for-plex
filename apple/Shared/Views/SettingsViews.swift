import AstraKit
import SwiftUI

/// Astra 4.0 Settings (KP, 2026-11-08: "make settings prettier … easy to
/// read … different categories"): a short list of categories, each with an
/// icon in the theme colour, opening its own page.
enum SettingsPane: String, CaseIterable, Identifiable, Hashable {
  case appearance, tabs, playback, library, downloads, sources, about

  var id: String { rawValue }

  var title: String {
    switch self {
    case .appearance: "Appearance"
    case .tabs: "Navigation"
    case .playback: "Playback"
    case .library: "Library"
    case .downloads: "Downloads"
    case .sources: "Sources"
    case .about: "About"
    }
  }

  var subtitle: String {
    switch self {
    case .appearance: "Accent, theme, streaming services"
    case .tabs: "Tab bar: which tabs, in what order"
    case .playback: "Quality, subtitles, gestures"
    case .library: "Library quality, badges"
    case .downloads: "Wi-Fi, storage"
    case .sources: "Your Plex server"
    case .about: "Version, updates, licenses"
    }
  }

  var symbol: String {
    switch self {
    case .appearance: "paintbrush.fill"
    case .tabs: "rectangle.3.group.fill"
    case .playback: "play.rectangle.fill"
    case .library: "books.vertical.fill"
    case .downloads: "arrow.down.circle.fill"
    case .sources: "server.rack"
    case .about: "info.circle.fill"
    }
  }

  /// Navigation is iPhone only (the Mac has its sidebar); Apple TV has no downloads.
  static var shown: [SettingsPane] {
    #if os(iOS)
      allCases
    #elseif os(tvOS)
      allCases.filter { $0 != .tabs && $0 != .downloads }
    #else
      allCases.filter { $0 != .tabs }
    #endif
  }
}

struct SettingsView: View {
  /// The Settings tab draws its own large title (its bar is hidden).
  var showsTitle = false
  @Environment(AppModel.self) private var app

  var body: some View {
    #if os(macOS)
      NavigationStack { root }
    #else
      root
    #endif
  }

  private var root: some View {
    Form {
      if showsTitle {
        Section {
        } header: {
          Text("Settings")
            .astraFont(.display(Astra.Layout.pageTitleSize))
            .foregroundStyle(Astra.Color.ink)
            .textCase(nil)
        }
      }
      // The server at a glance, like the account card in Apple's Settings.
      Section {
        NavigationLink {
          SourcesSettings()
        } label: {
          HStack(spacing: 14) {
            SettingsIcon(symbol: "server.rack", size: 46)
            VStack(alignment: .leading, spacing: 3) {
              Text(app.server?.serverName ?? "Not connected")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Astra.Color.ink)
              HStack(spacing: 6) {
                Circle()
                  .fill(app.health?.state == .connected ? Astra.Color.ink : Astra.Color.muted)
                  .frame(width: 7, height: 7)
                Text(app.health?.state.title ?? "Plex Media Server")
                  .astraFont(.meta)
                  .foregroundStyle(Astra.Color.muted)
              }
            }
          }
          .padding(.vertical, 4)
        }
      }
      Section {
        ForEach(SettingsPane.shown.filter { $0 != .sources && $0 != .about }) { pane in
          NavigationLink { page(pane) } label: { SettingsRow(pane: pane) }
        }
      }
      Section {
        ForEach([SettingsPane.sources, .about]) { pane in
          NavigationLink { page(pane) } label: { SettingsRow(pane: pane) }
        }
      }
    }
    .formStyle(.grouped)
    #if !os(tvOS)
      .scrollContentBackground(.hidden)
    #endif
    // Same background as every Settings page (it showed the system grey before).
    .astraPageBackground()
    .settingsBottomRoom()
  }

  @ViewBuilder private func page(_ pane: SettingsPane) -> some View {
    Group {
      switch pane {
      case .appearance: AppearanceSettings()
      case .tabs:
        #if os(iOS)
          TabsSettings()
        #endif
      case .playback: PlaybackSettings()
      case .library: LibrarySettings()
      case .downloads: DownloadSettings()
      case .sources: SourcesSettings()
      case .about: AboutSettings()
      }
    }
    .navigationTitle(pane.title)
    #if os(iOS)
      .navigationBarTitleDisplayMode(.large)
      .toolbar(.visible, for: .navigationBar)
    #endif
  }

  /// "0.1.0 (202611070245)": the marketing version and the build that updates compare.
  static var versionText: String {
    let info = Bundle.main.infoDictionary ?? [:]
    let short = info["CFBundleShortVersionString"] as? String ?? ""
    let build = info["CFBundleVersion"] as? String ?? ""
    return build.isEmpty ? short : "\(short) (\(build))"
  }
}

/// A rounded square in the theme colour with a symbol, like Apple's Settings.
struct SettingsIcon: View {
  var symbol: String
  var size: CGFloat = 30

  var body: some View {
    Image(systemName: symbol)
      .font(.system(size: size * 0.5, weight: .semibold))
      .foregroundStyle(Astra.Color.onTheme)
      .frame(width: size, height: size)
      .background(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous).fill(Astra.Color.theme))
  }
}

struct SettingsRow: View {
  var pane: SettingsPane

  var body: some View {
    HStack(spacing: 14) {
      SettingsIcon(symbol: pane.symbol)
      VStack(alignment: .leading, spacing: 2) {
        Text(pane.title)
          .astraFont(size: 16, weight: .semibold)
          .foregroundStyle(Astra.Color.ink)
        Text(pane.subtitle)
          .astraFont(size: 13)
          .foregroundStyle(Astra.Color.muted)
      }
    }
    .padding(.vertical, 3)
  }
}

/// A Form page with Astra's background.
private struct SettingsForm<Content: View>: View {
  @ViewBuilder var content: Content

  var body: some View {
    Form { content }
      .formStyle(.grouped)
      #if !os(tvOS)
        .scrollContentBackground(.hidden)
      #endif
      .astraPageBackground()
      .settingsBottomRoom()
  }
}

extension View {
  /// iPhone: room under the last row for the floating tab bar, which is an
  /// overlay and not a safe-area inset, so About and Reset to Default never
  /// end up behind it when Settings is a tab.
  @ViewBuilder func settingsBottomRoom() -> some View {
    #if os(iOS)
      contentMargins(.bottom, Astra.Layout.tabBarRoom, for: .scrollContent)
    #else
      self
    #endif
  }
}

// MARK: - Appearance

struct AppearanceSettings: View {
  @AppStorage(Preferences.serviceAccentsKey) private var serviceAccents = true
  @AppStorage(Preferences.serviceLogoColorsKey) private var logoColors = true
  private var appearance: AstraAppearance { .shared }

  var body: some View {
    SettingsForm {
      Section {
        ThemePicker(selected: appearance.appTheme) { theme in
          astraWithAnimation(Astra.Motion.page) { appearance.setTheme(theme) }
        }
      } header: {
        Text("Theme")
      } footer: {
        Text("Changes the whole app: backgrounds, glass, text and buttons.")
      }
      Section {
        Toggle("Service Accent Colours", isOn: $serviceAccents).tint(Astra.Color.switchOn)
        Toggle("Service Logo Colours", isOn: $logoColors).tint(Astra.Color.switchOn)
      } header: {
        Text("Streaming Services")
      } footer: {
        Text("Accents tint a service's Home page in its colour. Turn logo colours off for plain white logos on glass.")
      }
    }
  }
}

/// The four whole-app themes as little previews of a page in that theme
/// (KP, 2026-11-09): its background, a card, a line of text and its accent.
struct ThemePicker: View {
  var selected: AppTheme
  var set: (AppTheme) -> Void

  #if os(tvOS)
    private let columns = [GridItem(.adaptive(minimum: 260), spacing: 24)]
  #else
    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 12)]
  #endif

  var body: some View {
    LazyVGrid(columns: columns, spacing: 12 * Astra.Layout.controlScale) {
      ForEach(AppTheme.allCases) { theme in
        let isOn = theme == selected
        Button { set(theme) } label: {
          VStack(alignment: .leading, spacing: 8) {
            ThemePreview(palette: theme.palette)
              .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                  .stroke(isOn ? Astra.Color.accent : Astra.Color.hairline, lineWidth: isOn ? 2.5 : 1)
              )
            HStack(spacing: 6) {
              Text(theme.title).astraFont(size: 14, weight: .semibold).foregroundStyle(Astra.Color.ink)
              if isOn {
                Image(systemName: "checkmark.circle.fill")
                  .astraFont(size: 13, weight: .semibold)
                  .foregroundStyle(Astra.Color.accent)
              }
            }
            Text(theme.subtitle).astraFont(size: 12).foregroundStyle(Astra.Color.muted).lineLimit(1)
          }
          .contentShape(Rectangle())
          .tvFocusLift(1.05)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(theme.title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
      }
    }
    .padding(.vertical, 6)
  }
}

/// A miniature page in a theme's colours.
struct ThemePreview: View {
  var palette: ThemePalette

  var body: some View {
    ZStack(alignment: .bottomLeading) {
      RoundedRectangle(cornerRadius: 14, style: .continuous).fill(palette.bg)
      if palette.ambient > 0 {
        // A hint of the frosted artwork the theme lays its glass over.
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .fill(
            LinearGradient(
              colors: [palette.ink.opacity(0.18 * palette.ambient), (palette.glassTint ?? .clear)],
              startPoint: .topTrailing, endPoint: .bottomLeading))
      }
      VStack(alignment: .leading, spacing: 6) {
        Capsule().fill(palette.ink).frame(width: 46, height: 6)
        Capsule().fill(palette.ink.opacity(0.5)).frame(width: 30, height: 5)
        HStack(spacing: 6) {
          RoundedRectangle(cornerRadius: 5, style: .continuous).fill(palette.surface2).frame(width: 34, height: 22)
          RoundedRectangle(cornerRadius: 5, style: .continuous).fill(palette.surface2).frame(width: 34, height: 22)
          Circle().fill(SwiftUI.Color(hex: palette.accentHex.value)).frame(width: 12, height: 12)
        }
      }
      .padding(12)
    }
    .frame(height: 96 * Astra.Layout.controlScale)
    .accessibilityHidden(true)
  }
}

#if os(iOS)
// MARK: - Tabs

/// The iPhone's bottom bar: drag to reorder, switch tabs on or off.
struct TabsSettings: View {
  @AppStorage(TabLayout.storageKey) private var storedTabs = ""

  var body: some View {
    let tabs = TabLayout.tabs(from: storedTabs)
    SettingsForm {
      Section {
        ForEach(tabs) { tab in
          HStack(spacing: 14) {
            SettingsIcon(symbol: tab.symbol)
            Text(tab.title).astraFont(size: 16, weight: .semibold)
            Spacer()
            if !TabLayout.required.contains(tab) {
              Button {
                storedTabs = TabLayout.stored(TabLayout.toggled(tabs, tab, on: false))
              } label: {
                Image(systemName: "minus.circle.fill").font(.system(size: 20)).foregroundStyle(Astra.Color.muted)
              }
              .buttonStyle(.plain)
              .accessibilityLabel("Remove \(tab.title)")
            }
          }
        }
        .onMove { from, to in storedTabs = TabLayout.stored(TabLayout.moved(tabs, from: from, to: to)) }
      } header: {
        Text("In the Tab Bar")
      } footer: {
        Text("Drag to reorder. Home and Library always stay; up to \(TabLayout.maximum) tabs.")
      }
      let more = PhoneTab.allCases.filter { !tabs.contains($0) }
      if !more.isEmpty {
        Section("Add a Tab") {
          ForEach(more) { tab in
            Button {
              storedTabs = TabLayout.stored(TabLayout.toggled(tabs, tab, on: true))
            } label: {
              HStack(spacing: 14) {
                SettingsIcon(symbol: tab.symbol)
                Text(tab.title).astraFont(size: 16, weight: .semibold).foregroundStyle(Astra.Color.ink)
                Spacer()
                Image(systemName: "plus.circle.fill").font(.system(size: 20)).foregroundStyle(Astra.Color.ink)
              }
            }
            .buttonStyle(.plain)
            .disabled(tabs.count >= TabLayout.maximum)
          }
        }
      }
      Section {
        Button("Reset to Default") { storedTabs = "" }
          .disabled(tabs == TabLayout.defaultTabs)
      }
    }
    #if os(iOS)
      // Drag handles always showing, so reordering is one drag.
      .environment(\.editMode, .constant(.active))
    #endif
  }
}
#endif

// MARK: - Playback

struct PlaybackSettings: View {
  @AppStorage(PlaybackQuality.storageKey) private var quality: PlaybackQuality = .auto
  @AppStorage(SubtitlePreference.storageKey) private var subtitles: SubtitlePreference = .automatic
  @AppStorage(Preferences.nextEpisodeKey) private var nextEpisode = true
  @AppStorage(Preferences.swipeGesturesKey) private var swipe = true
  @AppStorage(Preferences.twoFingerPauseKey) private var twoFinger = true
  @AppStorage(Preferences.skipSecondsKey) private var skipSeconds = 10

  var body: some View {
    SettingsForm {
      Section {
        Picker("Preferred Quality", selection: $quality) {
          ForEach(PlaybackQuality.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
      } header: {
        Text("Quality")
      } footer: {
        Text("Astra always plays the original file. When a title has several versions, this picks which one.")
      }
      Section {
        Picker("Subtitles", selection: $subtitles) {
          ForEach(SubtitlePreference.allCases) { Text($0.title).tag($0) }
        }
      } header: {
        Text("Subtitles")
      } footer: {
        Text("Automatic shows what the file marks as forced or default. Always picks your language.")
      }
      Section {
        Toggle("Next Episode Button", isOn: $nextEpisode).tint(Astra.Color.switchOn)
      } header: {
        Text("Shows")
      } footer: {
        Text("A Next Episode button in the last 15 seconds of an episode. It never plays on its own.")
      }
      #if os(iOS)
        Section {
          Picker("Double-Tap Skips", selection: $skipSeconds) {
            Text("10 s").tag(10)
            Text("15 s").tag(15)
            Text("30 s").tag(30)
          }
          Toggle("Swipe for Brightness and Volume", isOn: $swipe).tint(Astra.Color.switchOn)
          Toggle("Two-Finger Tap to Pause", isOn: $twoFinger).tint(Astra.Color.switchOn)
        } header: {
          Text("Gestures")
        } footer: {
          Text("Double-tap the right side to skip forward, the left to go back. Swipe up or down on the left for brightness, on the right for volume.")
        }
      #endif
    }
  }
}

// MARK: - Library

struct LibrarySettings: View {
  @Environment(AppModel.self) private var app
  @AppStorage(LibraryQuality.storageKey) private var libraryQuality: LibraryQuality = .deviceDefault
  @AppStorage(Preferences.qualityBadgesKey) private var qualityBadges = true
  @AppStorage(Preferences.ratingsKey) private var ratings = true

  var body: some View {
    SettingsForm {
      Section {
        Picker("Library Quality", selection: $libraryQuality) {
          ForEach(LibraryQuality.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .onChange(of: libraryQuality) { app.libraryQualityChanged() }
      } header: {
        Text("Library Quality")
      } footer: {
        Text(
          libraryQuality == .hd
            ? "One copy of each title, in HD. 4K libraries are hidden on this device."
            : "One copy of each title: the 4K one when there is one, otherwise HD.")
      }
      Section("Badges") {
        Toggle("HD and 4K Badges", isOn: $qualityBadges).tint(Astra.Color.switchOn)
        Toggle("Age Ratings", isOn: $ratings).tint(Astra.Color.switchOn)
      }
    }
  }
}

// MARK: - Downloads

struct DownloadSettings: View {
  @Environment(AppModel.self) private var app
  @AppStorage(Preferences.wifiOnlyKey) private var wifiOnly = false

  var body: some View {
    SettingsForm {
      #if os(iOS)
        Section {
          Toggle("Wi-Fi Only", isOn: $wifiOnly).tint(Astra.Color.switchOn)
        } footer: {
          Text("Downloads wait for Wi-Fi instead of using cellular data.")
        }
      #endif
      Section {
        LabeledContent(
          "Storage Used", value: ByteCountFormatter.string(fromByteCount: app.downloads.storageUsed, countStyle: .file))
        LabeledContent("Saved Titles", value: "\(app.downloads.index.records.count)")
      } footer: {
        Text("Manage downloads in Library → Downloads.")
      }
    }
  }
}

// MARK: - Sources

struct SourcesSettings: View {
  @Environment(AppModel.self) private var app

  var body: some View {
    SettingsForm {
      Section {
        LabeledContent("Name", value: app.server?.serverName ?? "Not connected")
        LabeledContent("Type", value: "Plex Media Server")
        if let health = app.health {
          SourceHealthRow(health: health)
        }
      } header: {
        Text("Server")
      }
      Section {
        LabeledContent("Address", value: app.server?.baseURL.host() ?? "—")
        if let url = app.server?.baseURL {
          LabeledContent("Connection", value: ConnectionKind.classify(url).title)
        }
      } header: {
        Text("Connection")
      } footer: {
        Text("Downloads and streams are fastest on your local network. Remote speed depends on the server's upload; Plex Relay is capped by Plex.")
      }
      if let library = app.library {
        LibraryIndexSection(library: library)
      }
      Section {
        Button("Change Server…") { Task { await app.chooseServer() } }
        Button("Sign Out", role: .destructive) { app.signOut() }
      }
    }
  }
}

/// Settings → Sources → Library Index (KP, 2026-11-09): how much of the
/// server Astra has read, when the last full read finished and how long it
/// took, retries and the last error, and how long titles take to open.
struct LibraryIndexSection: View {
  var library: LibraryStore

  var body: some View {
    let status = library.indexStatus
    Section {
      LabeledContent("Status", value: phaseText(status))
      LabeledContent("Titles Indexed", value: status.itemCount.formatted())
      ForEach(status.libraries) { section in
        LabeledContent(section.title, value: progressText(section))
      }
      LabeledContent("Last Full Sync", value: status.lastSuccess.map { $0.formatted(.relative(presentation: .named)) } ?? "Never")
      if let duration = status.lastDuration {
        LabeledContent("Sync Took", value: Self.seconds(duration))
      }
      if status.retries > 0 {
        LabeledContent("Retries", value: "\(status.retries)")
      }
      if let error = status.lastError {
        LabeledContent("Last Error", value: error)
      }
      LabeledContent("Opening a Title", value: openText(library.openTimings))
      Button("Index Now") { library.reindexNow() }
        .disabled(status.phase == .indexing)
    } header: {
      Text("Library Index")
    } footer: {
      Text("Astra reads your library in the background and saves as it goes, so titles it has read open at once and an interrupted read carries on where it stopped.")
    }
  }

  private func phaseText(_ status: LibraryIndexStatus) -> String {
    switch status.phase {
    case .idle: "Not started"
    case .indexing: status.complete ? "Up to date, checking for changes" : "Indexing"
    case .complete: "Complete"
    case .failed: status.complete ? "Complete, last check failed" : "Paused, will retry"
    }
  }

  private func progressText(_ section: LibraryIndexStatus.Library) -> String {
    if section.complete { return "\(section.fetched.formatted()) titles" }
    if let total = section.total { return "\(section.fetched.formatted()) of \(total.formatted())" }
    return "\(section.fetched.formatted()) so far"
  }

  private func openText(_ timings: OpenTimings) -> String {
    guard let last = timings.last, let median = timings.median else { return "Not measured yet" }
    return "Last \(Self.seconds(last)), typical \(Self.seconds(median))"
  }

  static func seconds(_ value: TimeInterval) -> String {
    value < 60 ? String(format: "%.1f s", value) : "\(Int(value / 60)) min \(Int(value) % 60) s"
  }
}

// MARK: - About

struct AboutSettings: View {
  @Environment(\.checkForUpdates) private var checkForUpdates

  var body: some View {
    SettingsForm {
      Section {
        LabeledContent("Version", value: SettingsView.versionText)
        if let checkForUpdates {
          Button("Check for Updates…", action: checkForUpdates)
        }
      }
      Section {
        Text(
          "Astra is free software under the GNU General Public License, version 3. "
            + "Playback uses mpv and FFmpeg (LGPL/GPL); Mac updates use Sparkle (MIT).")
          .astraFont(.meta)
          .foregroundStyle(Astra.Color.muted)
        if let url = URL(string: "https://www.gnu.org/licenses/gpl-3.0.html") {
          Link("GNU GPL v3", destination: url)
        }
      } header: {
        Text("Licenses")
      }
      Section {
        NetworkDiagnosticsView()
      } header: {
        Text("Diagnostics")
      } footer: {
        Text("The last requests Astra made, newest first. Tokens are never shown or saved.")
      }
    }
  }
}
