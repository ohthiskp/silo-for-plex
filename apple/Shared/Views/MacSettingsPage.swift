import AstraKit
import SwiftUI

#if os(macOS)

  /// Mac Settings (KP's mockup, 2026-11-13): the server and library index on
  /// top, Appearance as a live preview of Home with the themes beside it, then
  /// Playback, Subtitles and Library side by side, and one quiet footer line.
  /// The deeper pages (server details, licenses, diagnostics) push in place.
  struct MacSettingsPage: View {
    @Environment(AppModel.self) private var app
    @Environment(\.contentLeading) private var leading

    var body: some View {
      NavigationStack {
        ScrollViewReader { proxy in
        ScrollView {
          VStack(alignment: .leading, spacing: 28) {
            Text("Settings")
              .astraFont(.display(Astra.Layout.pageTitleSize))
              .foregroundStyle(Astra.Color.ink)
            ServerStatusBand()
            if let library = app.library {
              AppearanceBlock(library: library)
              // Three columns in a wide window, fewer as it narrows.
              LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 330), spacing: 24, alignment: .top)],
                alignment: .leading, spacing: 24
              ) {
                VStack(alignment: .leading, spacing: 24) {
                  PlaybackBlock()
                  DownloadsBlock()
                }
                SubtitleBlock(library: library)
                LibraryBlock()
              }
              .id("lower")
            }
            SettingsFooter()
          }
          .frame(maxWidth: 1240, alignment: .leading)
          .padding(.leading, leading)
          .padding(.trailing, 40)
          .padding(.top, Astra.Spacing.pageTop)
          .padding(.bottom, 40)
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .task {
          // CI screenshots (`-AstraDemoScroll`): show the lower half.
          guard Demo.homeScroll != nil else { return }
          try? await Task.pause(2)
          proxy.scrollTo("lower", anchor: .top)
        }
        }
        .astraPageBackground()
        .navigationDestination(for: SettingsPane.self) { pane in
          Group {
            switch pane {
            case .sources: SourcesSettings()
            default: AboutSettings()
            }
          }
          .navigationTitle(pane.title)
        }
      }
    }
  }

  // MARK: - Building blocks

  /// A grouped list: rows separated by hairlines on a quiet glass card.
  private struct SettingsCard<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    var body: some View {
      VStack(alignment: .leading, spacing: 8) {
        if let title {
          Text(title)
            .astraFont(size: 13, weight: .semibold)
            .foregroundStyle(Astra.Color.muted)
            .padding(.leading, 4)
        }
        // Each row draws a hairline along its top; the first one sits under the card's edge.
        VStack(spacing: 0) { content }
        .background(Self.shape.fill(Astra.Color.ink.opacity(0.06)))
        .overlay(Self.shape.strokeBorder(Astra.Color.hairline, lineWidth: 1))
        .clipShape(Self.shape)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }

    static var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 14, style: .continuous) }
  }

  /// One row: a name on the left, its control on the right.
  private struct SettingRow<Control: View>: View {
    var title: String
    @ViewBuilder var control: Control

    var body: some View {
      HStack(spacing: 12) {
        Text(title)
          .astraFont(size: 14.5, weight: .medium)
          .foregroundStyle(Astra.Color.ink)
          .lineLimit(1)
        Spacer(minLength: 8)
        control
      }
      .padding(.horizontal, 16)
      .frame(minHeight: 46)
      .settingsRowSeparator()
    }
  }

  private struct SettingSwitch: View {
    var title: String
    @Binding var isOn: Bool

    var body: some View {
      SettingRow(title: title) {
        Toggle(title, isOn: $isOn).labelsHidden().toggleStyle(.switch).tint(Astra.Color.switchOn)
      }
    }
  }

  extension View {
    fileprivate func settingsRowSeparator() -> some View {
      overlay(alignment: .top) { Rectangle().fill(Astra.Color.hairline).frame(height: 1) }
    }
  }

  // MARK: - Server and library index

  private struct ServerStatusBand: View {
    @Environment(AppModel.self) private var app
    private static let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

    var body: some View {
      HStack(spacing: 36) {
        NavigationLink(value: SettingsPane.sources) {
          VStack(alignment: .leading, spacing: 4) {
            Text(app.server?.serverName ?? "Not connected")
              .astraFont(size: 20, weight: .bold)
              .foregroundStyle(Astra.Color.ink)
            HStack(spacing: 8) {
              Circle()
                .fill(app.health?.state == .connected ? Astra.Color.ink : Astra.Color.muted)
                .frame(width: 7, height: 7)
              Text(connectionLine)
                .astraFont(size: 13)
                .foregroundStyle(Astra.Color.muted)
                .lineLimit(1)
            }
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Server details")
        if let library = app.library {
          IndexProgress(library: library)
        } else {
          Spacer()
        }
        HStack(spacing: 10) {
          Button("Change Server") { Task { await app.chooseServer() } }
            .buttonStyle(SettingsPillStyle(prominent: false))
          if let library = app.library {
            Button("Index Now") { library.reindexNow() }
              .buttonStyle(SettingsPillStyle(prominent: true))
              .disabled(library.indexStatus.phase == .indexing)
          }
        }
      }
      .padding(.horizontal, 22)
      .padding(.vertical, 16)
      .background(Self.shape.fill(Astra.Color.ink.opacity(0.08)))
      .overlay(Self.shape.strokeBorder(Astra.Color.hairline, lineWidth: 1))
    }

    private var connectionLine: String {
      guard let url = app.server?.baseURL else { return "Plex Media Server" }
      let state = app.health?.state.title ?? "Connected"
      let host = url.host() ?? ""
      return "\(state) · \(ConnectionKind.classify(url).title) · \(host)"
    }
  }

  /// Capsule buttons for the band: white for the main action, glass for the other.
  private struct SettingsPillStyle: ButtonStyle {
    var prominent: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
      configuration.label
        .astraFont(size: 13.5, weight: .semibold)
        .foregroundStyle(prominent ? Astra.Color.bg : Astra.Color.ink)
        .padding(.horizontal, 15)
        .frame(height: 34)
        .background(Capsule().fill(prominent ? Astra.Color.ink : Astra.Color.ink.opacity(0.1)))
        .overlay(Capsule().strokeBorder(prominent ? .clear : Astra.Color.hairline, lineWidth: 1))
        .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
        .contentShape(Capsule())
    }
  }

  // MARK: - Appearance

  private struct AppearanceBlock: View {
    var library: LibraryStore
    @AppStorage(Preferences.serviceAccentsKey) private var serviceAccents = true
    @AppStorage(Preferences.serviceLogoColorsKey) private var logoColors = true
    private var appearance: AstraAppearance { .shared }
    private static let previewShape = RoundedRectangle(cornerRadius: 20, style: .continuous)

    var body: some View {
      VStack(alignment: .leading, spacing: 12) {
        Text("Appearance").astraFont(size: 22, weight: .bold).foregroundStyle(Astra.Color.ink)
        ViewThatFits(in: .horizontal) {
          HStack(alignment: .top, spacing: 24) {
            preview.frame(minWidth: 480)
            side.frame(width: 300)
          }
          VStack(alignment: .leading, spacing: 16) {
            preview
            side
          }
        }
      }
    }

    private var side: some View {
          VStack(spacing: 12) {
            SettingsCard {
              ForEach(AppTheme.allCases) { theme in themeRow(theme) }
            }
            SettingsCard {
              SettingSwitch(title: "Service colours", isOn: $serviceAccents)
              SettingSwitch(title: "Coloured logos", isOn: $logoColors)
            }
          }
    }

    /// Home's real hero, in the theme in use: the same artwork, logo, badges
    /// and buttons, so a theme is judged on the page it changes.
    private var preview: some View {
      ZStack(alignment: .bottomLeading) {
        Astra.Color.bg
        if let item = library.homeHero.first {
          // Sized by the box, never by the picture: a filled image would widen the page.
          Color.clear.overlay {
            ArtworkImage(
              library: library, item: item, kind: .heroBackdrop, width: 1280, height: 720, placeholder: Color.clear)
          }
          .clipped()
          HeroScrim()
          HeroInfo(library: library, item: item)
            .padding(28)
        } else {
          Text("Your Home appears here once it loads.")
            .astraFont(.meta)
            .foregroundStyle(Astra.Color.muted)
            .padding(28)
        }
      }
      .frame(maxWidth: .infinity)
      .frame(height: 400)
      .clipShape(Self.previewShape)
      .astraGlassEdge(Self.previewShape, strength: 0.5)
      .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
      .accessibilityElement(children: .contain)
      .accessibilityLabel("Preview of Home")
    }

    private func themeRow(_ theme: AppTheme) -> some View {
      let isOn = theme == appearance.appTheme
      return Button {
        astraWithAnimation(Astra.Motion.page) { appearance.setTheme(theme) }
      } label: {
        HStack(spacing: 12) {
          ThemeSwatch(library: library, palette: theme.palette)
          Text(theme.title).astraFont(size: 14.5, weight: .medium).foregroundStyle(Astra.Color.ink)
          Spacer()
          if isOn {
            Image(systemName: "checkmark").astraFont(size: 13, weight: .bold).foregroundStyle(Astra.Color.ink)
          }
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
        .background(isOn ? Astra.Color.ink.opacity(0.07) : .clear)
        .settingsRowSeparator()
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(theme.title)
      .accessibilityAddTraits(isOn ? .isSelected : [])
    }
  }

  // MARK: - Playback, Library, Downloads

  private struct PlaybackBlock: View {
    @AppStorage(PlaybackQuality.storageKey) private var quality: PlaybackQuality = .auto
    @AppStorage(SubtitlePreference.storageKey) private var subtitles: SubtitlePreference = .automatic
    @AppStorage(Preferences.nextEpisodeKey) private var nextEpisode = true

    var body: some View {
      SettingsCard(title: "Playback") {
        SettingRow(title: "Quality") {
          Picker("Quality", selection: $quality) {
            ForEach(PlaybackQuality.allCases) { Text($0.title).tag($0) }
          }
          .labelsHidden().pickerStyle(.segmented).fixedSize()
        }
        SettingRow(title: "Subtitles") {
          Picker("Subtitles", selection: $subtitles) {
            ForEach(SubtitlePreference.allCases) { Text($0.title).tag($0) }
          }
          .labelsHidden().fixedSize()
        }
        SettingSwitch(title: "Next Episode button", isOn: $nextEpisode)
      }
      .help("Astra always plays the original file. Quality picks between the versions on your server.")
    }
  }

  private struct LibraryBlock: View {
    @Environment(AppModel.self) private var app
    @AppStorage(LibraryQuality.storageKey) private var libraryQuality: LibraryQuality = .deviceDefault
    @AppStorage(Preferences.qualityBadgesKey) private var qualityBadges = true
    @AppStorage(Preferences.ratingsKey) private var ratings = true

    var body: some View {
      SettingsCard(title: "Library") {
        SettingRow(title: "Library quality") {
          Picker("Library quality", selection: $libraryQuality) {
            ForEach(LibraryQuality.allCases) { Text($0.title).tag($0) }
          }
          .labelsHidden().pickerStyle(.segmented).fixedSize()
          .onChange(of: libraryQuality) { app.libraryQualityChanged() }
        }
        SettingSwitch(title: "HD and 4K badges", isOn: $qualityBadges)
        SettingSwitch(title: "Age ratings", isOn: $ratings)
      }
    }
  }

  private struct DownloadsBlock: View {
    @Environment(AppModel.self) private var app

    var body: some View {
      SettingsCard(title: "Downloads") {
        SettingRow(title: "Saved titles") {
          Text(
            "\(app.downloads.index.records.count) · "
              + ByteCountFormatter.string(fromByteCount: app.downloads.storageUsed, countStyle: .file)
          )
          .astraFont(size: 14.5)
          .monospacedDigit()
          .foregroundStyle(Astra.Color.muted)
        }
      }
    }
  }

  // MARK: - Footer

  /// "Astra 0.1.0 (202611121354) · Check for Updates · About · Sign Out", quiet.
  private struct SettingsFooter: View {
    @Environment(AppModel.self) private var app
    @Environment(\.checkForUpdates) private var checkForUpdates

    var body: some View {
      HStack(spacing: 6) {
        Text("Astra \(SettingsView.versionText)")
        if let checkForUpdates {
          dot
          Button("Check for Updates", action: checkForUpdates).buttonStyle(.plain)
        }
        dot
        NavigationLink("About and Licenses", value: SettingsPane.about).buttonStyle(.plain)
        dot
        SignOutButton().buttonStyle(.plain)
      }
      .astraFont(size: 12.5)
      .foregroundStyle(Astra.Color.ink.opacity(0.42))
    }

    private var dot: some View { Text("·") }
  }

  // MARK: - Subtitles

  /// KP (2026-11-13): a subtitle editor with a live sample.
  private struct SubtitleBlock: View {
    var library: LibraryStore
    @Environment(AppModel.self) private var app
    @State private var style = SubtitleStyle.current()

    var body: some View {
      VStack(alignment: .leading, spacing: 8) {
        Text("Subtitles")
          .astraFont(size: 13, weight: .semibold)
          .foregroundStyle(Astra.Color.muted)
          .padding(.leading, 4)
        SubtitleSample(library: library, style: style)
        SettingsCard {
          SettingRow(title: "Font") {
            Picker("Font", selection: $style.font) {
              ForEach(SubtitleFont.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden().fixedSize()
          }
          SettingRow(title: "Size") {
            Picker("Size", selection: $style.size) {
              ForEach(SubtitleSize.allCases) { Text($0.shortTitle).tag($0) }
            }
            .labelsHidden().pickerStyle(.segmented).fixedSize()
          }
          SettingRow(title: "Colour") { SubtitleColorPicker(selection: $style.color) }
          SettingRow(title: "Background") {
            Picker("Background", selection: $style.background) {
              ForEach(SubtitleBackground.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden().pickerStyle(.segmented).fixedSize()
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .onChange(of: style) {
        style.save()
        app.player.applySubtitleStyle()
      }
    }
  }

  #endif

/// "Reading TV Shows 61 %" with a white bar, or the last full read once done.
struct IndexProgress<Accessory: View>: View {
  var library: LibraryStore
  /// 1 on the Mac; larger on iPhone and Apple TV.
  var scale: CGFloat = 1
  /// Shown at the end of the detail line (Index Now on iPhone).
  @ViewBuilder var accessory: Accessory

  var body: some View {
    let status = library.indexStatus
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(headline(status)).astraFont(size: 13 * scale, weight: .semibold).foregroundStyle(Astra.Color.ink)
        Spacer()
        if let fraction = fraction(status) {
          Text(fraction.formatted(.percent.precision(.fractionLength(0))))
            .astraFont(size: 13 * scale)
            .monospacedDigit()
            .foregroundStyle(Astra.Color.muted)
        }
      }
      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          Capsule().fill(Astra.Color.ink.opacity(0.12))
          Capsule().fill(Astra.Color.ink).frame(width: proxy.size.width * (fraction(status) ?? (status.complete ? 1 : 0)))
        }
      }
      .frame(height: 5 * scale)
      HStack(spacing: 12) {
        Text(detail(status))
          .astraFont(size: 12 * scale)
          .foregroundStyle(Astra.Color.muted)
          .lineLimit(1)
        Spacer(minLength: 0)
        accessory
      }
    }
    .frame(maxWidth: .infinity)
    .astraAnimation(Astra.Motion.base, value: status.itemCount)
  }

  private func headline(_ status: LibraryIndexStatus) -> String {
    switch status.phase {
    case .indexing:
      if let current = status.libraries.first(where: { !$0.complete }) { return "Reading \(current.title)" }
      return "Checking for changes"
    case .complete: return "Library indexed"
    case .failed: return status.complete ? "Library indexed, last check failed" : "Paused, will retry"
    case .idle: return status.complete ? "Library indexed" : "Not indexed yet"
    }
  }

  /// Share read of the libraries with a known size, while reading.
  private func fraction(_ status: LibraryIndexStatus) -> Double? {
    guard status.phase == .indexing else { return nil }
    let known = status.libraries.compactMap { lib in lib.total.map { (lib.fetched, $0) } }
    let total = known.reduce(0) { $0 + $1.1 }
    guard total > 0 else { return nil }
    return min(1, Double(known.reduce(0) { $0 + $1.0 }) / Double(total))
  }

  private func detail(_ status: LibraryIndexStatus) -> String {
    let titles = "\(status.itemCount.formatted()) titles open instantly"
    if status.phase == .indexing { return titles }
    if let last = status.lastSuccess {
      return "\(titles) · read \(last.formatted(.relative(presentation: .named)))"
    }
    return status.lastError ?? titles
  }
}

extension IndexProgress where Accessory == EmptyView {
  init(library: LibraryStore, scale: CGFloat = 1) {
    self.init(library: library, scale: scale) { EmptyView() }
  }
}

/// A theme as a thumbnail: Home's artwork under that theme's own ground.
struct ThemeSwatch: View {
  var library: LibraryStore
  var palette: ThemePalette
  /// nil fills the width it is given.
  var width: CGFloat? = 52
  var height: CGFloat = 32
  var radius: CGFloat = 7

  var body: some View {
    ZStack {
      palette.bg
      if let item = library.homeHero.first {
        Color.clear.overlay {
          ArtworkImage(library: library, item: item, kind: .heroBackdrop, width: 320, height: 180, placeholder: Color.clear)
        }
        .clipped()
        .opacity(palette.ambient > 0 ? 1 : 0.85)
      }
      LinearGradient(
        stops: [.init(color: palette.bg.opacity(0), location: 0.3), .init(color: palette.bg, location: 0.95)],
        startPoint: .top, endPoint: .bottom)
      if let tint = palette.glassTint { tint }
    }
    .frame(width: width, height: height)
    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Astra.Color.hairline, lineWidth: 1))
    .accessibilityHidden(true)
  }
}

/// A line of dialogue over Home's artwork, drawn the way mpv will draw it.
struct SubtitleSample: View {
  var library: LibraryStore
  var style: SubtitleStyle
  /// 1 on the Mac; larger on iPhone and Apple TV.
  var scale: CGFloat = 1

  var body: some View {
    ZStack(alignment: .bottom) {
      Color.black
      if let item = library.homeHero.first {
        Color.clear.overlay {
          ArtworkImage(library: library, item: item, kind: .scenery, width: 640, height: 360, placeholder: Color.clear)
        }
        .clipped()
        .opacity(0.8)
      }
      Text("I'll be right back. Don't go anywhere.")
        .font(.custom(style.font.family, size: 17 * scale * style.size.scale))
        .foregroundStyle(Color(hex: style.color.rgb))
        .multilineTextAlignment(.center)
        .shadow(color: .black.opacity(style.background == .outline ? 0.95 : 0), radius: 1.2)
        .shadow(color: .black.opacity(style.background == .outline ? 0.8 : 0), radius: 2.5, y: 1)
        .padding(.horizontal, style.background == .box ? 8 : 0)
        .padding(.vertical, style.background == .box ? 3 : 0)
        .background(
          RoundedRectangle(cornerRadius: 4).fill(.black.opacity(style.background == .box ? 0.7 : 0)))
        .padding(.bottom, 16 * scale)
        .padding(.horizontal, 12 * scale)
    }
    .frame(maxWidth: .infinity)
    .frame(height: 132 * scale)
    .clipShape(RoundedRectangle(cornerRadius: 14 * scale, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 14 * scale, style: .continuous).strokeBorder(Astra.Color.hairline, lineWidth: 1))
    .astraAnimation(Astra.Motion.fast, value: style)
    .accessibilityElement()
    .accessibilityLabel("Subtitle sample")
  }
}

/// The subtitle colours as small round swatches; the chosen one has a ring.
struct SubtitleColorPicker: View {
  @Binding var selection: SubtitleColor
  var size: CGFloat = 20

  var body: some View {
    HStack(spacing: 8) {
      ForEach(SubtitleColor.allCases) { color in
        let isOn = color == selection
        Button {
          selection = color
        } label: {
          Circle()
            .fill(Color(hex: color.rgb))
            .frame(width: size, height: size)
            .padding(3)
            .overlay(Circle().strokeBorder(isOn ? Astra.Color.ink : .clear, lineWidth: 2))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(color.title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
      }
    }
  }
}

extension SubtitleSize {
  /// "S", "M", "L", "XL" for a segmented control.
  var shortTitle: String {
    switch self {
    case .small: "S"
    case .medium: "M"
    case .large: "L"
    case .extraLarge: "XL"
    }
  }
}
