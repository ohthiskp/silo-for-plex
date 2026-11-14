import AstraKit
import SwiftUI

#if os(iOS)

  /// iPhone Settings (KP's mockup, 2026-11-14): one scrolling page. The
  /// server and library index on top, Appearance as a live preview of Home
  /// with the themes under it, then the subtitle editor and the rest as quiet
  /// grouped cards. No icon tiles and no line under every row.
  struct PhoneSettingsPage: View {
    /// The Settings tab draws its own large title; the sheet from Library
    /// has a navigation bar that already says "Settings".
    var showsTitle: Bool
    @Environment(AppModel.self) private var app

    var body: some View {
      ScrollViewReader { proxy in
        ScrollView {
          VStack(alignment: .leading, spacing: 28) {
            if showsTitle {
              Text("Settings")
                .astraFont(.display(Astra.Layout.pageTitleSize))
                .foregroundStyle(Astra.Color.ink)
            }
            PhoneServerCard()
            if let library = app.library {
              PhoneAppearance(library: library)
              PhoneStreamingCard()
              PhoneSubtitles(library: library).id("subtitles")
            }
            PhonePlayback()
            PhoneGestures().id("gestures")
            PhoneLibraryCard()
            PhoneDownloadsCard()
            PhoneLinksCard()
            PhoneFooter()
          }
          .padding(.horizontal, 16)
          .padding(.top, showsTitle ? Astra.Spacing.pageTop : 12)
          .padding(.bottom, 24)
        }
        .scrollIndicators(.never)
        .contentMargins(.bottom, Astra.Layout.tabBarRoom, for: .scrollContent)
        .task {
          // CI screenshots: `-AstraDemoScroll 1` shows Subtitles, `2` Gestures.
          guard let step = Demo.homeScroll, (try? await Task.pause(3)) != nil else { return }
          proxy.scrollTo(step >= 2 ? "gestures" : "subtitles", anchor: .top)
        }
      }
      .astraPageBackground()
    }
  }

  // MARK: - Building blocks

  /// A titled group of rows on a quiet glass card, hairlines between rows.
  private struct PhoneCard<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    static var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 18, style: .continuous) }

    var body: some View {
      VStack(alignment: .leading, spacing: 8) {
        if let title {
          Text(title)
            .astraFont(size: 15, weight: .semibold)
            .foregroundStyle(Astra.Color.muted)
            .padding(.leading, 6)
        }
        // Each row draws a hairline along its top; the first sits under the card's edge.
        VStack(spacing: 0) { content }
          .background(Self.shape.fill(Astra.Color.ink.opacity(0.06)))
          .overlay(Self.shape.strokeBorder(Astra.Color.hairline, lineWidth: 1))
          .clipShape(Self.shape)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private struct PhoneRow<Control: View>: View {
    var title: String
    @ViewBuilder var control: Control

    var body: some View {
      HStack(spacing: 12) {
        Text(title)
          .astraFont(size: 17, weight: .medium)
          .foregroundStyle(Astra.Color.ink)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
        Spacer(minLength: 8)
        control
      }
      .padding(.horizontal, 16)
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

  /// A row that pushes a page, with its value and a chevron.
  private struct PhoneLinkRow: View {
    var title: String
    var value: String = ""
    var pane: SettingsPane

    var body: some View {
      NavigationLink {
        SettingsPaneView(pane: pane)
      } label: {
        PhoneRow(title: title) {
          HStack(spacing: 6) {
            if !value.isEmpty {
              Text(value).astraFont(size: 16).foregroundStyle(Astra.Color.muted).lineLimit(1)
            }
            Image(systemName: "chevron.right")
              .astraFont(size: 14, weight: .semibold)
              .foregroundStyle(Astra.Color.muted)
          }
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
    }
  }

  extension View {
    fileprivate func phoneHairline() -> some View {
      overlay(alignment: .top) { Rectangle().fill(Astra.Color.hairline).frame(height: 1) }
    }
  }

  // MARK: - Server and library index

  private struct PhoneServerCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
      VStack(spacing: 0) {
        NavigationLink {
          SettingsPaneView(pane: .sources)
        } label: {
          HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
              Text(app.server?.serverName ?? "Not connected")
                .astraFont(size: 21, weight: .bold)
                .foregroundStyle(Astra.Color.ink)
              HStack(spacing: 7) {
                Circle()
                  .fill(app.health?.state == .connected ? Astra.Color.ink : Astra.Color.muted)
                  .frame(width: 7, height: 7)
                Text(connectionLine)
                  .astraFont(size: 15)
                  .foregroundStyle(Astra.Color.muted)
                  .lineLimit(1)
              }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
              .astraFont(size: 15, weight: .semibold)
              .foregroundStyle(Astra.Color.muted)
          }
          .padding(16)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Server details and Change Server")
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

    private var connectionLine: String {
      guard let url = app.server?.baseURL else { return "Plex Media Server" }
      let state = app.health?.state.title ?? "Connected"
      return "\(state) · \(ConnectionKind.classify(url).title)"
    }
  }

  // MARK: - Appearance

  private struct PhoneAppearance: View {
    var library: LibraryStore
    private var appearance: AstraAppearance { .shared }
    private static let previewShape = RoundedRectangle(cornerRadius: 24, style: .continuous)
    private static let previewHeight: CGFloat = 420

    var body: some View {
      VStack(alignment: .leading, spacing: 14) {
        Text("Appearance").astraFont(size: 26, weight: .bold).foregroundStyle(Astra.Color.ink)
        preview
        HStack(alignment: .top, spacing: 10) {
          ForEach(AppTheme.allCases) { theme in tile(theme) }
        }
      }
    }

    /// Home's real hero in the theme in use: its artwork, logo, badges and
    /// buttons, so a theme is judged on the page it changes. Not tappable.
    private var preview: some View {
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
      .frame(maxWidth: .infinity)
      .frame(height: Self.previewHeight)
      .clipShape(Self.previewShape)
      .astraGlassEdge(Self.previewShape, strength: 0.5)
      .accessibilityElement(children: .contain)
      .accessibilityLabel("Preview of Home")
    }

    private func tile(_ theme: AppTheme) -> some View {
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
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(theme.title)
      .accessibilityAddTraits(isOn ? .isSelected : [])
    }
  }

  private struct PhoneStreamingCard: View {
    @AppStorage(Preferences.serviceAccentsKey) private var serviceAccents = true
    @AppStorage(Preferences.serviceLogoColorsKey) private var logoColors = true

    var body: some View {
      PhoneCard(title: "Streaming services") {
        PhoneSwitch(title: "Service colours", isOn: $serviceAccents)
        PhoneSwitch(title: "Coloured logos", isOn: $logoColors)
      }
    }
  }

  // MARK: - Subtitles

  /// KP (2026-11-13): a subtitle editor with a live sample.
  private struct PhoneSubtitles: View {
    var library: LibraryStore
    @Environment(AppModel.self) private var app
    @State private var style = SubtitleStyle.current()

    var body: some View {
      VStack(alignment: .leading, spacing: 8) {
        Text("Subtitles")
          .astraFont(size: 15, weight: .semibold)
          .foregroundStyle(Astra.Color.muted)
          .padding(.leading, 6)
        SubtitleSample(library: library, style: style, scale: 1.1)
        PhoneCard {
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
          PhoneRow(title: "Colour") { SubtitleColorPicker(selection: $style.color, size: 24) }
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

  // MARK: - Playback, gestures, library, downloads

  private struct PhonePlayback: View {
    @AppStorage(PlaybackQuality.storageKey) private var quality: PlaybackQuality = .auto
    @AppStorage(SubtitlePreference.storageKey) private var subtitles: SubtitlePreference = .automatic
    @AppStorage(Preferences.nextEpisodeKey) private var nextEpisode = true

    var body: some View {
      PhoneCard(title: "Playback") {
        PhoneRow(title: "Quality") {
          Picker("Quality", selection: $quality) {
            ForEach(PlaybackQuality.allCases) { Text($0.title).tag($0) }
          }
          .labelsHidden().pickerStyle(.segmented).fixedSize()
        }
        PhoneRow(title: "Subtitles") {
          Picker("Subtitles", selection: $subtitles) {
            ForEach(SubtitlePreference.allCases) { Text($0.title).tag($0) }
          }
          .labelsHidden().pickerStyle(.menu).tint(Astra.Color.muted)
        }
        PhoneSwitch(title: "Next Episode button", isOn: $nextEpisode)
      }
    }
  }

  private struct PhoneGestures: View {
    @AppStorage(Preferences.swipeGesturesKey) private var swipe = true
    @AppStorage(Preferences.twoFingerPauseKey) private var twoFinger = true
    @AppStorage(Preferences.skipSecondsKey) private var skipSeconds = 10

    var body: some View {
      PhoneCard(title: "Gestures") {
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

  private struct PhoneLibraryCard: View {
    @Environment(AppModel.self) private var app
    @AppStorage(LibraryQuality.storageKey) private var libraryQuality: LibraryQuality = .deviceDefault
    @AppStorage(Preferences.qualityBadgesKey) private var qualityBadges = true
    @AppStorage(Preferences.ratingsKey) private var ratings = true

    var body: some View {
      PhoneCard(title: "Library") {
        PhoneRow(title: "Library quality") {
          Picker("Library quality", selection: $libraryQuality) {
            ForEach(LibraryQuality.allCases) { Text($0.title).tag($0) }
          }
          .labelsHidden().pickerStyle(.segmented).fixedSize()
          .onChange(of: libraryQuality) { app.libraryQualityChanged() }
        }
        PhoneSwitch(title: "HD and 4K badges", isOn: $qualityBadges)
        PhoneSwitch(title: "Age ratings", isOn: $ratings)
      }
    }
  }

  private struct PhoneDownloadsCard: View {
    @Environment(AppModel.self) private var app
    @AppStorage(Preferences.wifiOnlyKey) private var wifiOnly = false

    var body: some View {
      PhoneCard(title: "Downloads") {
        PhoneSwitch(title: "Wi-Fi only", isOn: $wifiOnly)
        PhoneRow(title: "Saved titles") {
          Text(
            "\(app.downloads.index.records.count) · "
              + ByteCountFormatter.string(fromByteCount: app.downloads.storageUsed, countStyle: .file)
          )
          .astraFont(size: 16)
          .monospacedDigit()
          .foregroundStyle(Astra.Color.muted)
        }
      }
    }
  }

  private struct PhoneLinksCard: View {
    @AppStorage(TabLayout.storageKey) private var storedTabs = ""

    var body: some View {
      PhoneCard {
        PhoneLinkRow(
          title: "Tab bar", value: TabLayout.tabs(from: storedTabs).map(\.title).joined(separator: ", "), pane: .tabs)
        PhoneLinkRow(title: "About and licenses", pane: .about)
      }
    }
  }

  /// "Astra 3.1.0 (202611131822) · Sign Out", quiet and centred.
  private struct PhoneFooter: View {
    @Environment(AppModel.self) private var app

    var body: some View {
      HStack(spacing: 6) {
        Text("Astra \(SettingsView.versionText)")
        Text("·")
        Button("Sign Out") { app.signOut() }.buttonStyle(.plain)
      }
      .astraFont(size: 13.5)
      .foregroundStyle(Astra.Color.ink.opacity(0.42))
      .frame(maxWidth: .infinity)
    }
  }

#endif
