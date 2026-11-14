import AstraKit
import SwiftUI

/// Apple TV Settings (KP's mockup, 2026-11-14), under the usual top bar:
/// the server and library index band, Appearance as a live preview of Home
/// with the themes beside it, then Subtitles next to Playback, Library and
/// About. Every row is one focusable button: Select turns a switch or steps
/// to the next choice, like Apple's own TV Settings. No Downloads, gestures
/// or tab bar here, because the TV app has none.
struct TVSettingsPage: View {
  @Environment(AppModel.self) private var app

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: 44) {
          Text("Settings")
            .font(.system(size: 76, weight: .bold))
            .foregroundStyle(Astra.Color.ink)
          TVServerBand()
          if let library = app.library {
            TVAppearance(library: library)
            HStack(alignment: .top, spacing: 48) {
              TVSubtitles(library: library)
              VStack(alignment: .leading, spacing: 44) {
                TVPlaybackCard()
                TVLibraryCard()
                TVSettingsCard {
                  NavigationLink {
                    SettingsPaneView(pane: .about)
                  } label: {
                    TVSettingLine(title: "About and licenses") { TVChevron() }
                  }
                  .buttonStyle(TVSettingRowStyle())
                }
              }
            }
            .id("lower")
          }
          TVSettingsFooter()
        }
        .padding(.horizontal, TVLayout.leading)
        .padding(.top, 20)
        .padding(.bottom, 80)
      }
      .scrollClipDisabled()
      .task {
        // CI screenshots (`-AstraDemoScroll 1`): the lower half.
        guard Demo.homeScroll != nil, (try? await Task.pause(3)) != nil else { return }
        proxy.scrollTo("lower", anchor: .top)
      }
    }
  }
}

// MARK: - Building blocks

/// A titled group of rows on quiet glass.
private struct TVSettingsCard<Content: View>: View {
  var title: String?
  @ViewBuilder var content: Content

  static var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 26, style: .continuous) }

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      if let title {
        Text(title)
          .font(.system(size: 36, weight: .bold))
          .foregroundStyle(Astra.Color.ink)
      }
      VStack(spacing: 0) { content }
        .background(Self.shape.fill(Astra.Color.ink.opacity(0.07)))
        .overlay(Self.shape.strokeBorder(Astra.Color.hairline, lineWidth: 1))
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
      Text(title).font(.system(size: 28, weight: .medium)).lineLimit(1)
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
      .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
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

/// Capsule buttons for the band: white when focused, glass otherwise; Index
/// Now is white even at rest, as the band's main action.
private struct TVPillStyle: ButtonStyle {
  var prominent: Bool

  func makeBody(configuration: Configuration) -> some View {
    TVPillBody(configuration: configuration, prominent: prominent)
  }
}

private struct TVPillBody: View {
  let configuration: ButtonStyleConfiguration
  var prominent: Bool
  @Environment(\.isFocused) private var focused
  @Environment(\.isEnabled) private var isEnabled

  var body: some View {
    let white = focused || prominent
    configuration.label
      .font(.system(size: 25, weight: .semibold))
      .foregroundStyle(white ? Color.black : Astra.Color.ink)
      .padding(.horizontal, 32)
      .frame(height: 64)
      .background(Capsule().fill(white ? Color.white : Astra.Color.ink.opacity(0.12)))
      .contentShape(Capsule())
      .opacity(isEnabled ? 1 : 0.45)
      .scaleEffect(configuration.isPressed ? 0.96 : (focused ? 1.08 : 1))
      .shadow(color: .black.opacity(focused ? 0.4 : 0), radius: 16, y: 8)
      .focusEffectDisabled()
      .animation(.snappy(duration: 0.22), value: focused)
  }
}

/// The chosen choice of a few, drawn like a segmented control; Select on the
/// row steps to the next one.
private struct TVSegments: View {
  var options: [String]
  var selected: Int
  @Environment(\.isFocused) private var focused

  var body: some View {
    HStack(spacing: 0) {
      ForEach(Array(options.enumerated()), id: \.offset) { i, title in
        let on = i == selected
        Text(title)
          .font(.system(size: 23, weight: .semibold))
          .foregroundStyle(on ? (focused ? Color.white : Color.black) : (focused ? Color.black.opacity(0.55) : Astra.Color.muted))
          .padding(.horizontal, 22)
          .frame(height: 48)
          .background {
            if on { RoundedRectangle(cornerRadius: 12, style: .continuous).fill(focused ? Color.black : Color.white) }
          }
      }
    }
    .padding(4)
    .background(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(focused ? Color.black.opacity(0.08) : Astra.Color.ink.opacity(0.1)))
  }
}

private struct TVSwitch: View {
  var isOn: Bool
  @Environment(\.isFocused) private var focused

  var body: some View {
    let track: Color = isOn ? (focused ? .black : .white) : (focused ? Color.black.opacity(0.15) : Astra.Color.ink.opacity(0.2))
    let knob: Color = isOn ? (focused ? .white : .black) : .white
    Capsule()
      .fill(track)
      .frame(width: 66, height: 40)
      .overlay(alignment: isOn ? .trailing : .leading) {
        Circle().fill(knob).frame(width: 34, height: 34).padding(3)
      }
      .animation(.snappy(duration: 0.2), value: isOn)
  }
}

private struct TVChevron: View {
  var body: some View {
    Image(systemName: "chevron.right").font(.system(size: 22, weight: .semibold)).opacity(0.6)
  }
}

private struct TVValueText: View {
  var text: String

  var body: some View {
    HStack(spacing: 10) {
      Text(text).font(.system(size: 26))
      Image(systemName: "chevron.up.chevron.down").font(.system(size: 18, weight: .semibold))
    }
    .opacity(0.6)
  }
}

/// A switch row: Select turns it on or off.
private struct TVSwitchRow: View {
  var title: String
  @Binding var isOn: Bool

  var body: some View {
    Button {
      isOn.toggle()
    } label: {
      TVSettingLine(title: title) { TVSwitch(isOn: isOn) }
    }
    .buttonStyle(TVSettingRowStyle())
    .accessibilityValue(isOn ? "On" : "Off")
  }
}

/// A row of a few choices: Select steps to the next.
private struct TVChoiceRow<Choice: Hashable>: View {
  var title: String
  var choices: [Choice]
  var label: (Choice) -> String
  @Binding var selection: Choice
  /// Segments for a few short choices, else the name with an up-down mark.
  var segmented = true

  var body: some View {
    let index = choices.firstIndex(of: selection) ?? 0
    Button {
      selection = choices[(index + 1) % choices.count]
    } label: {
      TVSettingLine(title: title) {
        if segmented {
          TVSegments(options: choices.map(label), selected: index)
        } else {
          TVValueText(text: label(selection))
        }
      }
    }
    .buttonStyle(TVSettingRowStyle())
    .accessibilityValue(label(selection))
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
            .font(.system(size: 24))
            .foregroundStyle(Astra.Color.muted)
            .lineLimit(1)
        }
      }
      if let library = app.library {
        IndexProgress(library: library, scale: 1.9)
      } else {
        Spacer()
      }
      HStack(spacing: 16) {
        Button("Change Server") { Task { await app.chooseServer() } }
          .buttonStyle(TVPillStyle(prominent: false))
        if let library = app.library {
          Button("Index Now") { library.reindexNow() }
            .buttonStyle(TVPillStyle(prominent: true))
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

private struct TVAppearance: View {
  var library: LibraryStore
  @AppStorage(Preferences.serviceAccentsKey) private var serviceAccents = true
  @AppStorage(Preferences.serviceLogoColorsKey) private var logoColors = true
  private var appearance: AstraAppearance { .shared }

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      Text("Appearance")
        .font(.system(size: 36, weight: .bold))
        .foregroundStyle(Astra.Color.ink)
      HStack(alignment: .top, spacing: 40) {
        TVHomePreview(library: library)
        VStack(spacing: 24) {
          TVSettingsCard {
            ForEach(AppTheme.allCases) { theme in themeRow(theme) }
          }
          TVSettingsCard {
            TVSwitchRow(title: "Service colours", isOn: $serviceAccents)
            TVSwitchRow(title: "Coloured logos", isOn: $logoColors)
          }
        }
        .frame(width: 520)
        .focusSection()
      }
    }
  }

  private func themeRow(_ theme: AppTheme) -> some View {
    let isOn = theme == appearance.appTheme
    return Button {
      astraWithAnimation(Astra.Motion.page) { appearance.setTheme(theme) }
    } label: {
      HStack(spacing: 22) {
        ThemeSwatch(library: library, palette: theme.palette, width: 96, height: 56, radius: 10)
        Text(theme.title).font(.system(size: 28, weight: .medium))
        Spacer()
        if isOn { Image(systemName: "checkmark").font(.system(size: 24, weight: .bold)) }
      }
    }
    .buttonStyle(TVSettingRowStyle())
    .accessibilityLabel(theme.title)
    .accessibilityAddTraits(isOn ? .isSelected : [])
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
        VStack(spacing: 18) {
          TVLogoTitle(library: library, item: item, maxWidth: 420, maxHeight: 120, textSize: 56, centered: true)
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
              .frame(height: 64)
              .background(Capsule().fill(Color.white))
            Image(systemName: "plus")
              .font(.system(size: 26, weight: .semibold))
              .foregroundStyle(Color.white)
              .frame(width: 64, height: 64)
              .background(Circle().fill(Color.white.opacity(0.18)))
          }
        }
        .frame(width: 500)
        .padding(44)
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
          .font(.system(size: 24))
          .foregroundStyle(Astra.Color.muted)
          .padding(44)
      }
    }
    .frame(maxWidth: .infinity)
    .frame(height: 520)
    .clipShape(Self.shape)
    .overlay(Self.shape.strokeBorder(Astra.Color.hairline, lineWidth: 1))
    .shadow(color: .black.opacity(0.35), radius: 30, y: 16)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Preview of Home")
  }
}

// MARK: - Subtitles, Playback, Library

/// KP (2026-11-13): the subtitle editor with a live sample.
private struct TVSubtitles: View {
  var library: LibraryStore
  @Environment(AppModel.self) private var app
  @State private var style = SubtitleStyle.current()

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      Text("Subtitles")
        .font(.system(size: 36, weight: .bold))
        .foregroundStyle(Astra.Color.ink)
      SubtitleSample(library: library, style: style, scale: 1.9)
      TVSettingsCard {
        TVChoiceRow(
          title: "Font", choices: SubtitleFont.allCases, label: \.title, selection: $style.font, segmented: false)
        TVChoiceRow(title: "Size", choices: SubtitleSize.allCases, label: \.shortTitle, selection: $style.size)
        colourRow
        TVChoiceRow(
          title: "Background", choices: SubtitleBackground.allCases, label: \.title, selection: $style.background)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .focusSection()
    .onChange(of: style) {
      style.save()
      app.player.applySubtitleStyle()
    }
  }

  private var colourRow: some View {
    let all = SubtitleColor.allCases
    let index = all.firstIndex(of: style.color) ?? all.startIndex
    return Button {
      let next = all.index(after: index)
      style.color = next == all.endIndex ? all[all.startIndex] : all[next]
    } label: {
      TVSettingLine(title: "Colour") { TVColourDots(selected: style.color) }
    }
    .buttonStyle(TVSettingRowStyle())
    .accessibilityValue(style.color.title)
  }
}

private struct TVColourDots: View {
  var selected: SubtitleColor
  @Environment(\.isFocused) private var focused

  var body: some View {
    HStack(spacing: 14) {
      ForEach(SubtitleColor.allCases) { color in
        Circle()
          .fill(Color(hex: color.rgb))
          .frame(width: 38, height: 38)
          .overlay(Circle().strokeBorder(focused ? Color.black.opacity(0.2) : .clear, lineWidth: 1))
          .padding(5)
          .overlay(Circle().strokeBorder(color == selected ? (focused ? Color.black : Color.white) : .clear, lineWidth: 3))
      }
    }
  }
}

private struct TVPlaybackCard: View {
  @AppStorage(PlaybackQuality.storageKey) private var quality: PlaybackQuality = .auto
  @AppStorage(SubtitlePreference.storageKey) private var subtitles: SubtitlePreference = .automatic
  @AppStorage(Preferences.nextEpisodeKey) private var nextEpisode = true

  var body: some View {
    TVSettingsCard(title: "Playback") {
      TVChoiceRow(title: "Quality", choices: PlaybackQuality.allCases, label: \.title, selection: $quality)
      TVChoiceRow(
        title: "Subtitles", choices: SubtitlePreference.allCases, label: \.title, selection: $subtitles,
        segmented: false)
      TVSwitchRow(title: "Next Episode button", isOn: $nextEpisode)
    }
  }
}

private struct TVLibraryCard: View {
  @Environment(AppModel.self) private var app
  @AppStorage(LibraryQuality.storageKey) private var libraryQuality: LibraryQuality = .deviceDefault
  @AppStorage(Preferences.qualityBadgesKey) private var qualityBadges = true
  @AppStorage(Preferences.ratingsKey) private var ratings = true

  var body: some View {
    TVSettingsCard(title: "Library") {
      TVChoiceRow(title: "Library quality", choices: LibraryQuality.allCases, label: \.title, selection: $libraryQuality)
      TVSwitchRow(title: "HD and 4K badges", isOn: $qualityBadges)
      TVSwitchRow(title: "Age ratings", isOn: $ratings)
    }
    .onChange(of: libraryQuality) { app.libraryQualityChanged() }
  }
}

/// "Astra 3.1.0 (202611131822)" and Sign Out, quiet, at the bottom.
private struct TVSettingsFooter: View {
  @Environment(AppModel.self) private var app

  var body: some View {
    HStack(spacing: 24) {
      Text("Astra \(SettingsView.versionText)")
        .font(.system(size: 23))
        .foregroundStyle(Astra.Color.ink.opacity(0.42))
      Button("Sign Out") { app.signOut() }
        .buttonStyle(TVPillStyle(prominent: false))
    }
    .frame(maxWidth: .infinity)
  }
}
