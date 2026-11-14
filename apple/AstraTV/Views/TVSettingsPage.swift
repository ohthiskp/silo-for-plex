import AstraKit
import SwiftUI

/// Apple TV Settings, Direction C (KP picked it 2026-11-14 from
/// design-audit/05): under the usual top bar, the server and library index
/// band, then a category list on the left and the chosen category on the
/// right. Every choice is its own focusable pill, so Left and Right walk the
/// options and Select saves one (nothing cycles out of sight). Focus is the
/// only white fill on the page; a saved choice is a tick and an outline.
/// Changing Library quality asks before it reloads the library.
struct TVSettingsPage: View {
  @Environment(AppModel.self) private var app
  @Environment(\.tvScrolledDown) private var scrolledDown
  @State private var category: TVSettingsCategory = .appearance
  @FocusState private var listFocus: TVSettingsCategory?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 40) {
        Text("Settings")
          .font(.system(size: 76, weight: .bold))
          .foregroundStyle(Astra.Color.ink)
        TVServerBand()
        HStack(alignment: .top, spacing: 56) {
          categoryList
          pane
        }
      }
      .padding(.horizontal, TVLayout.leading)
      .padding(.top, 20)
      .padding(.bottom, 80)
    }
    .scrollClipDisabled()
    // The top bar fades away once the page scrolls, as on every other page.
    .onScrollGeometryChange(for: Bool.self, of: { $0.contentOffset.y > 60 }) { _, down in scrolledDown(down) }
    .onChange(of: listFocus) { if let listFocus { category = listFocus } }
    .task {
      // CI screenshots (`-AstraDemoSettings playback`): show that category.
      guard Demo.isOn, let name = UserDefaults.standard.string(forKey: "AstraDemoSettings"),
        let shown = TVSettingsCategory(rawValue: name)
      else { return }
      category = shown
    }
  }

  /// The categories; moving focus onto one shows it on the right.
  private var categoryList: some View {
    VStack(spacing: 0) {
      ForEach(TVSettingsCategory.allCases) { item in
        Button {
          category = item
        } label: {
          TVSettingLine(title: item.title) {
            if item == category { TVChevron() }
          }
        }
        .buttonStyle(TVSettingRowStyle())
        .focused($listFocus, equals: item)
        .accessibilityAddTraits(item == category ? .isSelected : [])
      }
    }
    .background(TVSettingsCard<EmptyView>.shape.fill(Astra.Color.ink.opacity(0.07)))
    .overlay(TVSettingsCard<EmptyView>.shape.strokeBorder(Astra.Color.hairline, lineWidth: 1))
    .frame(width: 400)
    .focusSection()
  }

  @ViewBuilder private var pane: some View {
    Group {
      switch category {
      case .appearance: TVAppearancePane()
      case .playback: TVPlaybackPane()
      case .subtitles: TVSubtitlesPane()
      case .library: TVLibraryPane()
      case .about: TVAboutPane()
      }
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .focusSection()
    // Menu inside the pane goes back to the category list, not out of Settings.
    .onExitCommand { listFocus = category }
    .id(category)
  }
}

enum TVSettingsCategory: String, CaseIterable, Identifiable {
  case appearance, playback, subtitles, library, about

  var id: String { rawValue }

  var title: String {
    switch self {
    case .appearance: "Appearance"
    case .playback: "Playback"
    case .subtitles: "Subtitles"
    case .library: "Library"
    case .about: "About"
    }
  }
}

// MARK: - Building blocks

/// A group of rows on quiet glass, with an optional title and a footer that
/// explains a consequence.
private struct TVSettingsCard<Content: View>: View {
  var title: String?
  var footer: String?
  @ViewBuilder var content: Content

  static var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 26, style: .continuous) }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      if let title {
        Text(title)
          .font(.system(size: 32, weight: .bold))
          .foregroundStyle(Astra.Color.ink)
      }
      VStack(spacing: 0) { content }
        .background(Self.shape.fill(Astra.Color.ink.opacity(0.07)))
        .overlay(Self.shape.strokeBorder(Astra.Color.hairline, lineWidth: 1))
      if let footer {
        Text(footer)
          .font(.system(size: 25))
          .foregroundStyle(Astra.Color.muted)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.horizontal, 8)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// A row's insides: the name on the left, its value on the right.
private struct TVSettingLine<Value: View>: View {
  var title: String
  @ViewBuilder var value: Value

  var body: some View {
    HStack(spacing: 20) {
      Text(title).font(.system(size: 29, weight: .medium)).lineLimit(1)
      Spacer(minLength: 12)
      value
    }
  }
}

/// White and lifted when focused (the remote's focus), plain glass otherwise.
struct TVSettingRowStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    TVSettingRowBody(configuration: configuration)
  }
}

private struct TVSettingRowBody: View {
  let configuration: ButtonStyleConfiguration
  @Environment(\.isFocused) private var focused

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
    configuration.label
      .foregroundStyle(focused ? Color.black : Astra.Color.ink)
      .padding(.horizontal, 30)
      .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
      .background {
        if focused {
          shape.fill(.white).shadow(color: .black.opacity(0.45), radius: 22, y: 12)
        }
      }
      .overlay(alignment: .top) {
        if !focused { Rectangle().fill(Astra.Color.hairline).frame(height: 1).padding(.horizontal, 8) }
      }
      .contentShape(shape)
      .scaleEffect(configuration.isPressed ? 0.98 : (focused ? 1.04 : 1))
      .zIndex(focused ? 1 : 0)
      .focusEffectDisabled()
      .animation(.snappy(duration: 0.22), value: focused)
  }
}

/// Capsule buttons for the band and About: glass at rest, white only while focused.
private struct TVPillStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    TVPillBody(configuration: configuration)
  }
}

private struct TVPillBody: View {
  let configuration: ButtonStyleConfiguration
  @Environment(\.isFocused) private var focused
  @Environment(\.isEnabled) private var isEnabled

  var body: some View {
    configuration.label
      .font(.system(size: 26, weight: .semibold))
      .foregroundStyle(focused ? Color.black : Astra.Color.ink)
      .padding(.horizontal, 32)
      .frame(height: 64)
      .background(Capsule().fill(focused ? Color.white : Astra.Color.ink.opacity(0.12)))
      .contentShape(Capsule())
      .opacity(isEnabled ? 1 : 0.45)
      .scaleEffect(configuration.isPressed ? 0.96 : (focused ? 1.08 : 1))
      .shadow(color: .black.opacity(focused ? 0.4 : 0), radius: 16, y: 8)
      .focusEffectDisabled()
      .animation(.snappy(duration: 0.22), value: focused)
  }
}

/// One choice of a setting. Focused: white with black text, lifted. Saved
/// but not focused: a tick and a 2 pt outline, no fill. Others: plain text.
private struct TVOptionStyle: ButtonStyle {
  var isOn: Bool

  func makeBody(configuration: Configuration) -> some View {
    TVOptionBody(configuration: configuration, isOn: isOn)
  }
}

private struct TVOptionBody: View {
  let configuration: ButtonStyleConfiguration
  var isOn: Bool
  @Environment(\.isFocused) private var focused

  var body: some View {
    HStack(spacing: 8) {
      if isOn {
        Image(systemName: "checkmark").font(.system(size: 21, weight: .bold)).accessibilityHidden(true)
      }
      configuration.label
    }
    .font(.system(size: 26, weight: isOn ? .semibold : .medium))
    .foregroundStyle(focused ? Color.black : (isOn ? Astra.Color.ink : Astra.Color.muted))
    .padding(.horizontal, 24)
    .frame(height: 58)
    .background {
      Capsule().fill(focused ? Color.white : Color.clear)
    }
    .overlay {
      Capsule().strokeBorder(isOn && !focused ? Astra.Color.ink : Astra.Color.hairline, lineWidth: isOn && !focused ? 2 : 1)
    }
    .contentShape(Capsule())
    .scaleEffect(configuration.isPressed ? 0.96 : (focused ? 1.08 : 1))
    .shadow(color: .black.opacity(focused ? 0.4 : 0), radius: 14, y: 7)
    .zIndex(focused ? 1 : 0)
    .focusEffectDisabled()
    .animation(.snappy(duration: 0.2), value: focused)
  }
}

/// A setting's name with its choices as pills on the right.
private struct TVOptionRow<Choice: Hashable, Label: View>: View {
  var title: String
  var choices: [Choice]
  var selection: Choice
  var choose: (Choice) -> Void
  @ViewBuilder var label: (Choice) -> Label

  var body: some View {
    HStack(spacing: 20) {
      Text(title)
        .font(.system(size: 29, weight: .medium))
        .foregroundStyle(Astra.Color.ink)
        .lineLimit(1)
      Spacer(minLength: 12)
      HStack(spacing: 12) {
        ForEach(choices, id: \.self) { choice in
          Button {
            choose(choice)
          } label: {
            label(choice)
          }
          .buttonStyle(TVOptionStyle(isOn: choice == selection))
          .accessibilityHint(title)
          .accessibilityAddTraits(choice == selection ? .isSelected : [])
        }
      }
      .focusSection()
    }
    .padding(.horizontal, 30)
    .frame(minHeight: 96)
    .overlay(alignment: .top) { Rectangle().fill(Astra.Color.hairline).frame(height: 1).padding(.horizontal, 8) }
  }
}

extension TVOptionRow where Label == Text {
  init(title: String, choices: [Choice], selection: Choice, name: @escaping (Choice) -> String, choose: @escaping (Choice) -> Void) {
    self.init(title: title, choices: choices, selection: selection, choose: choose) { Text(name($0)) }
  }
}

/// On / Off as two pills.
private struct TVSwitchRow: View {
  var title: String
  @Binding var isOn: Bool

  var body: some View {
    TVOptionRow(title: title, choices: [true, false], selection: isOn, name: { $0 ? "On" : "Off" }) { isOn = $0 }
  }
}

private struct TVChevron: View {
  var body: some View {
    Image(systemName: "chevron.right").font(.system(size: 22, weight: .semibold)).opacity(0.6)
  }
}

// MARK: - Server and library index

private struct TVServerBand: View {
  @Environment(AppModel.self) private var app
  private static let shape = RoundedRectangle(cornerRadius: 30, style: .continuous)

  var body: some View {
    HStack(spacing: 56) {
      VStack(alignment: .leading, spacing: 8) {
        Text(app.server?.serverName ?? "Not connected")
          .font(.system(size: 36, weight: .bold))
          .foregroundStyle(Astra.Color.ink)
        HStack(spacing: 12) {
          Circle()
            .fill(app.health?.state == .connected ? Astra.Color.ink : Astra.Color.muted)
            .frame(width: 11, height: 11)
          Text(connectionLine)
            .font(.system(size: 25))
            .foregroundStyle(Astra.Color.muted)
            .lineLimit(1)
        }
      }
      if let library = app.library {
        IndexProgress(library: library, scale: 1.95)
      } else {
        Spacer()
      }
      HStack(spacing: 16) {
        Button("Change Server") { Task { await app.chooseServer() } }
          .buttonStyle(TVPillStyle())
        if let library = app.library {
          Button("Index Now") { library.reindexNow() }
            .buttonStyle(TVPillStyle())
            .disabled(library.indexStatus.phase == .indexing)
        }
      }
      .focusSection()
    }
    .padding(.horizontal, 40)
    .padding(.vertical, 30)
    .background(Self.shape.fill(Astra.Color.ink.opacity(0.08)))
    .overlay(Self.shape.strokeBorder(Astra.Color.hairline, lineWidth: 1))
  }

  private var connectionLine: String {
    guard let url = app.server?.baseURL else { return "Plex Media Server" }
    let state = app.health?.state.title ?? "Connected"
    return "\(state) · \(ConnectionKind.classify(url).title)"
  }
}

// MARK: - Appearance

private struct TVAppearancePane: View {
  @Environment(AppModel.self) private var app
  @AppStorage(Preferences.serviceAccentsKey) private var serviceAccents = true
  @AppStorage(Preferences.serviceLogoColorsKey) private var logoColors = true
  private var appearance: AstraAppearance { .shared }

  var body: some View {
    VStack(alignment: .leading, spacing: 28) {
      if let library = app.library {
        TVHomePreview(library: library)
      }
      TVSettingsCard(
        footer: "Service colours tint each service's Home page. Turn logo colours off for plain white logos on glass."
      ) {
        TVOptionRow(title: "Theme", choices: AppTheme.allCases, selection: appearance.appTheme, name: \.title) { theme in
          astraWithAnimation(Astra.Motion.page) { appearance.setTheme(theme) }
        }
        TVSwitchRow(title: "Service colours", isOn: $serviceAccents)
        TVSwitchRow(title: "Coloured logos", isOn: $logoColors)
      }
    }
  }
}

/// Home's hero as it looks in the theme in use: its artwork, logo, meta line,
/// badges and the Play and + buttons, drawn only (it takes no focus).
private struct TVHomePreview: View {
  var library: LibraryStore
  @State private var full: PlexMetadata?
  private static let shape = RoundedRectangle(cornerRadius: 30, style: .continuous)

  var body: some View {
    ZStack(alignment: .bottomLeading) {
      Astra.Color.bg
      if let item = library.homeHero.first {
        let shown = full ?? library.indexMatch(item) ?? item
        // Sized by the box, never by the picture.
        Color.clear.overlay {
          ArtworkImage(library: library, item: item, kind: .heroBackdrop, width: 1920, height: 1080, placeholder: Color.clear)
        }
        .clipped()
        HeroScrim()
        VStack(spacing: 16) {
          TVLogoTitle(library: library, item: item, maxWidth: 380, maxHeight: 110, textSize: 52, centered: true)
            .frame(maxWidth: .infinity)
          HStack(spacing: 12) {
            DetailMetaLine(item: shown, library: library, fontSize: 22, genreLimit: 1, ratingAfter: true)
            TVFormatChips(item: shown, fontSize: 16, showsRating: false)
          }
          HStack(spacing: 16) {
            Label("Play", systemImage: "play.fill")
              .font(.system(size: 24, weight: .semibold))
              .foregroundStyle(Color.black)
              .frame(maxWidth: .infinity)
              .frame(height: 60)
              .background(Capsule().fill(Color.white))
            Image(systemName: "plus")
              .font(.system(size: 26, weight: .semibold))
              .foregroundStyle(Color.white)
              .frame(width: 60, height: 60)
              .background(Circle().fill(Color.white.opacity(0.18)))
          }
        }
        .frame(width: 460)
        .padding(40)
        .task(id: item.id) {
          full = nil
          let key = item.isCatalogOnly ? library.indexMatch(item)?.ratingKey : item.ratingKey
          guard let key else { return }
          let found = try? await library.details(key)
          guard !Task.isCancelled else { return }
          full = found
        }
      } else {
        Text("Your Home appears here once it loads.")
          .font(.system(size: 25))
          .foregroundStyle(Astra.Color.muted)
          .padding(44)
      }
    }
    .frame(maxWidth: .infinity)
    .frame(height: 420)
    .clipShape(Self.shape)
    .overlay(Self.shape.strokeBorder(Astra.Color.hairline, lineWidth: 1))
    .shadow(color: .black.opacity(0.35), radius: 30, y: 16)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Preview of Home in this theme")
  }
}

// MARK: - Playback

private struct TVPlaybackPane: View {
  @AppStorage(PlaybackQuality.storageKey) private var quality: PlaybackQuality = .auto
  @AppStorage(Preferences.nextEpisodeKey) private var nextEpisode = true

  var body: some View {
    VStack(alignment: .leading, spacing: 28) {
      TVSettingsCard(
        footer: "Astra always plays the original file. When a title has an HD and a 4K file on the server, this picks which one. Auto follows Library quality."
      ) {
        TVOptionRow(title: "Preferred version", choices: PlaybackQuality.allCases, selection: quality, name: \.title) {
          quality = $0
        }
      }
      TVSettingsCard(footer: "Shows in the last 15 seconds of an episode. It never plays on its own.") {
        TVSwitchRow(title: "Next Episode button", isOn: $nextEpisode)
      }
    }
  }
}

// MARK: - Subtitles

/// When subtitles show, and how they look (KP, 2026-11-13), with a live sample.
private struct TVSubtitlesPane: View {
  @Environment(AppModel.self) private var app
  @AppStorage(SubtitlePreference.storageKey) private var subtitles: SubtitlePreference = .automatic
  @State private var style = SubtitleStyle.current()

  var body: some View {
    VStack(alignment: .leading, spacing: 28) {
      if let library = app.library {
        SubtitleSample(library: library, style: style, scale: 1.7)
      }
      TVSettingsCard(footer: "Automatic shows what the file marks as forced or default. Always picks your language.") {
        TVOptionRow(title: "When to show", choices: SubtitlePreference.allCases, selection: subtitles, name: \.title) {
          subtitles = $0
        }
      }
      TVSettingsCard(title: "Style") {
        TVOptionRow(title: "Font", choices: SubtitleFont.allCases, selection: style.font, name: \.title) { style.font = $0 }
        TVOptionRow(title: "Size", choices: SubtitleSize.allCases, selection: style.size, name: \.shortTitle) {
          style.size = $0
        }
        TVOptionRow(title: "Colour", choices: SubtitleColor.allCases, selection: style.color, choose: { style.color = $0 }) {
          color in
          HStack(spacing: 10) {
            Circle().fill(Color(hex: color.rgb)).frame(width: 24, height: 24)
              .overlay(Circle().strokeBorder(Color.black.opacity(0.25), lineWidth: 1))
            Text(color.title)
          }
        }
        TVOptionRow(title: "Background", choices: SubtitleBackground.allCases, selection: style.background, name: \.title) {
          style.background = $0
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

private struct TVLibraryPane: View {
  @Environment(AppModel.self) private var app
  @AppStorage(LibraryQuality.storageKey) private var libraryQuality: LibraryQuality = .deviceDefault
  @AppStorage(Preferences.qualityBadgesKey) private var qualityBadges = true
  @AppStorage(Preferences.ratingsKey) private var ratings = true
  /// A change waiting for the reload to be confirmed (design-audit B-02).
  @State private var pending: LibraryQuality?

  var body: some View {
    VStack(alignment: .leading, spacing: 28) {
      TVSettingsCard(footer: footer) {
        TVOptionRow(title: "Library quality", choices: LibraryQuality.allCases, selection: libraryQuality, name: \.title) {
          if $0 != libraryQuality { pending = $0 }
        }
      }
      TVSettingsCard(
        footer: "Quality badges (HD, 4K, HDR, Dolby Vision, Dolby Atmos) come from the file on your server. The boxed rating (PG-13, TV-MA) is the age rating."
      ) {
        TVSwitchRow(title: "HD and 4K badges", isOn: $qualityBadges)
        TVSwitchRow(title: "Age ratings", isOn: $ratings)
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

  private var isConfirming: Binding<Bool> {
    Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })
  }

  private var footer: String {
    libraryQuality == .hd
      ? "One copy of each title, in HD. 4K libraries are hidden on this Apple TV."
      : "One copy of each title: the 4K one when there is one, otherwise HD."
  }
}

// MARK: - About

private struct TVAboutPane: View {
  @Environment(AppModel.self) private var app

  var body: some View {
    VStack(alignment: .leading, spacing: 28) {
      TVSettingsCard {
        NavigationLink {
          SettingsPaneView(pane: .about)
        } label: {
          TVSettingLine(title: "Version, licenses and diagnostics") { TVChevron() }
        }
        .buttonStyle(TVSettingRowStyle())
      }
      HStack(spacing: 24) {
        Text("Astra \(SettingsView.versionText)")
          .font(.system(size: 25))
          .foregroundStyle(Astra.Color.ink.opacity(0.5))
        Spacer()
        SignOutButton()
          .buttonStyle(TVPillStyle())
      }
      .padding(.horizontal, 8)
      .focusSection()
    }
  }
}
