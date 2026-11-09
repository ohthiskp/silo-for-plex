// Apple TV look, adapted from Silo Apple's tvOS "Skyline" layout
// (https://github.com/Silo-Server/silo-apple, AGPL-3.0-or-later,
// Copyright (C) 2026 Silo Media L.L.C. and contributors). KP (2026-11-09):
// "make it exactly like Silo", keeping Astra's own badges and no Silo logo.

import AstraKit
import SwiftUI

/// Silo's 1920 × 1080 metrics for the top bar, the Home marquee and rows,
/// Details and the library grid.
enum TVMetrics {
  // Top bar
  static let safeAreaX: CGFloat = 88
  static let barTopInset: CGFloat = 56
  static let barHeight: CGFloat = 64
  static let tabSpacing: CGFloat = 8
  static let tabLabelSize: CGFloat = 26
  static let tabPaddingHorizontal: CGFloat = 29
  static let tabPaddingVertical: CGFloat = 12
  static let barIconSize: CGFloat = 58
  static let barDimmedOpacity: Double = 0.7
  /// Pages without a marquee (grids, search, settings) start under the bar.
  static let pageTopInset: CGFloat = 170

  // Home marquee + row band
  static let landingOffset: CGFloat = 56
  static let marqueeBottomInset: CGFloat = 590
  static let marqueeContentWidth: CGFloat = 880
  static let marqueeTitleSize: CGFloat = 84
  static let marqueeMetaSize: CGFloat = 20
  static let marqueeSynopsisSize: CGFloat = 22
  static let marqueeSynopsisMaxWidth: CGFloat = 780
  static let marqueeLogoMaxWidth: CGFloat = 880
  static let marqueeLogoMaxHeight: CGFloat = 200
  static let rowBandHeightFraction: CGFloat = 0.5
  static let rowBandPreviewSpacing: CGFloat = 10
  static let rowCardVerticalPadding: CGFloat = 14
  static let posterWidth: CGFloat = 176
  static let landscapeWidth: CGFloat = 400

  // Details
  static let detailInset: CGFloat = 100
  static let heroHeight: CGFloat = 690
  static let heroTopInset: CGFloat = 116
  static let heroContentWidth: CGFloat = 1080
  static let bodySectionSpacing: CGFloat = 64
  static let sectionHeaderSpacing: CGFloat = 14

  // Library grid
  static let gridColumns = 6
  static let gridColumnSpacing: CGFloat = 40
  static let gridRowSpacing: CGFloat = 60
}

/// Silo's monochrome palette: white text on black, colour only from artwork.
enum TVColor {
  static let background = Color.black
  static let onSurface = Color(white: 0.93)
  static let secondaryText = Color(white: 0.93).opacity(0.6)
  static let selectedFill = Color.white.opacity(0.14)
  static let selectedBorder = Color.white.opacity(0.10)
  static let restingFill = Color.white.opacity(0.07)
  static let surface = Color(white: 0.08)
}

// MARK: - Backdrop

/// The artwork block anchored to the top-right corner: 64% of the width and
/// 70% of a 16:9 screen, fading out toward the left and the bottom.
enum TVBackdropLayout {
  static func size(forWidth width: CGFloat) -> CGSize {
    CGSize(width: width * 0.64, height: width * 9 / 16 * 0.70)
  }
}

struct TVBackdropFadeMask: View {
  var body: some View {
    LinearGradient(
      stops: [
        .init(color: .black, location: 0.0),
        .init(color: .black, location: 0.32),
        .init(color: .clear, location: 1.0),
      ],
      startPoint: .trailing,
      endPoint: .leading
    )
    .mask {
      LinearGradient(
        stops: [
          .init(color: .black, location: 0.0),
          .init(color: .black, location: 0.38),
          .init(color: .black.opacity(0.88), location: 0.52),
          .init(color: .black.opacity(0.58), location: 0.68),
          .init(color: .black.opacity(0.24), location: 0.81),
          .init(color: .clear, location: 0.90),
        ],
        startPoint: .top,
        endPoint: .bottom
      )
    }
  }
}

/// Page background behind Home and Details: black, a soft blurred wash of the
/// artwork's colours across the page (Silo samples the art's tints; a blurred
/// copy gives the same colours), the crisp art top-right, and a dark ramp
/// under the top bar.
struct TVPageBackdrop: View {
  var library: LibraryStore
  var item: PlexMetadata?
  var showsTopScrim = true
  /// Details uses `.scenery` (TMDB's best text-free shot).
  var kind: LibraryStore.ArtKind = .heroBackdrop

  var body: some View {
    GeometryReader { geo in
      let art = TVBackdropLayout.size(forWidth: geo.size.width)
      ZStack(alignment: .topTrailing) {
        TVColor.background
        if let item {
          ZStack {
            ArtworkImage(
              library: library, item: item, kind: .backdrop, width: 480, height: 270,
              placeholder: Color.clear
            )
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .blur(radius: 90)
            .opacity(0.45)
            .overlay(Color.black.opacity(0.35))

            ArtworkImage(
              library: library, item: item, kind: kind, width: art.width, height: art.height,
              placeholder: Color.clear
            )
            .frame(width: art.width, height: art.height)
            .clipped()
            .mask { TVBackdropFadeMask() }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topTrailing)
          }
          .id(item.id)
          .transition(.opacity.animation(.easeInOut(duration: 0.24)))
        }
        if showsTopScrim {
          LinearGradient(colors: [.black.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom)
            .frame(height: 190)
            .frame(maxHeight: .infinity, alignment: .top)
        }
      }
    }
    .ignoresSafeArea()
    .allowsHitTesting(false)
  }
}

// MARK: - Badges

/// Silo's outlined chip: the content rating (PG-13, R, TV-MA) and Astra's
/// format badges (4K, HDR, Dolby Vision, Dolby Atmos) share it.
struct TVChip<Content: View>: View {
  var fontSize: CGFloat = 18
  @ViewBuilder var content: Content

  var body: some View {
    content
      .font(.system(size: fontSize, weight: .bold))
      .tracking(fontSize * 0.04)
      .foregroundStyle(.white)
      .padding(.horizontal, fontSize * 0.55)
      .frame(height: fontSize * 1.6)
      .overlay(
        RoundedRectangle(cornerRadius: 5, style: .continuous)
          .strokeBorder(Color.white.opacity(0.78), lineWidth: 1.5)
      )
      .fixedSize()
  }
}

/// Astra's own badges, kept on Apple TV (KP, 2026-11-09): content rating
/// first, then 4K/HD, Dolby Atmos, and Dolby Vision or HDR.
struct TVFormatChips: View {
  var item: PlexMetadata
  var fontSize: CGFloat = 18
  var showsRating = true
  /// TMDB's certification for titles Plex has no rating for.
  var fallbackRating: String? = nil

  @AppStorage(PlaybackQuality.storageKey) private var quality: PlaybackQuality = .auto
  @AppStorage(Preferences.qualityBadgesKey) private var showQuality = true
  @AppStorage(Preferences.ratingsKey) private var showRatings = true

  private var pick: PlaybackQuality { quality == .auto ? .current() : quality }

  var body: some View {
    HStack(spacing: 10) {
      if showsRating, showRatings, let rating = item.officialRating ?? fallbackRating {
        RatingBox(text: rating, fontSize: fontSize)
      }
      if showQuality, let badge = item.resolutionBadge(for: pick) {
        TVChip(fontSize: fontSize) { Text(badge == "4K UHD" ? "4K" : badge) }
      }
      if item.hasAtmos(for: pick) {
        TVChip(fontSize: fontSize) { logo("format-dolby-atmos") }.accessibilityLabel("Dolby Atmos")
      }
      switch item.dynamicRange(for: pick) {
      case .dolbyVision?:
        TVChip(fontSize: fontSize) { logo("format-dolby-vision") }.accessibilityLabel("Dolby Vision")
      case .hdr10Plus?, .hdr10?, .hlg?:
        TVChip(fontSize: fontSize) { Text("HDR") }
      case nil:
        EmptyView()
      }
    }
  }

  private func logo(_ name: String) -> some View {
    Image(name)
      .renderingMode(.template)
      .resizable()
      .scaledToFit()
      .frame(height: fontSize * 1.1)
  }
}

/// "2014 · 2h 49m · Sci-Fi, Adventure"; a show gives its seasons.
enum TVFacts {
  static func line(_ item: PlexMetadata, genres: Int = 2) -> String {
    [
      item.year.map(String.init),
      item.type == .show ? item.childCount.map { "\($0) Season\($0 == 1 ? "" : "s")" } : item.durationLabel,
      item.genres.prefix(genres).map(\.tag).joined(separator: ", ").nilIfEmpty,
    ]
    .compactMap { $0 }
    .joined(separator: " · ")
  }
}

// MARK: - Logo or title

/// The title's logo art, or its name in heavy type while there is none.
/// The logo hugs the left edge at its own aspect ratio (Silo's title slot).
struct TVLogoTitle: View {
  var library: LibraryStore
  var item: PlexMetadata
  var maxWidth: CGFloat
  var maxHeight: CGFloat
  var textSize: CGFloat

  @State private var logo: PlatformImage?
  @State private var resolved = false

  var body: some View {
    ZStack(alignment: .bottomLeading) {
      if let logo {
        Image(platformImage: logo)
          .resizable()
          .interpolation(.high)
          .aspectRatio(contentMode: .fit)
          .frame(maxWidth: maxWidth, maxHeight: maxHeight, alignment: .bottomLeading)
          .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
          .accessibilityLabel(item.displayTitle)
          .transition(.opacity)
      } else if resolved {
        Text(item.displayTitle)
          .font(.system(size: textSize, weight: .heavy).leading(.tight))
          .foregroundStyle(.white)
          .lineLimit(2)
          .minimumScaleFactor(0.6)
          .shadow(color: .black.opacity(0.5), radius: 10, y: 4)
          .frame(maxWidth: maxWidth, alignment: .leading)
      }
    }
    .frame(maxWidth: maxWidth, minHeight: maxHeight, maxHeight: maxHeight, alignment: .bottomLeading)
    .task(id: item.id) {
      logo = nil
      resolved = false
      if let url = await library.artworkURL(for: item, .logo, width: maxWidth, height: maxHeight) {
        logo = await ImagePipeline.shared.image(for: url)
      }
      resolved = true
    }
  }
}

// MARK: - Cards

/// Silo's card focus: a small lift, a shadow and a white outline, no system glass.
struct TVCardButtonStyle: ButtonStyle {
  var scale: CGFloat = 1.05

  func makeBody(configuration: Configuration) -> some View {
    TVCardButtonBody(configuration: configuration, scale: scale)
  }
}

private struct TVCardButtonBody: View {
  let configuration: ButtonStyleConfiguration
  let scale: CGFloat
  @Environment(\.isFocused) private var focused

  var body: some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? (focused ? scale : 1) * 0.97 : (focused ? scale : 1))
      .shadow(color: .black.opacity(focused ? 0.45 : 0.3), radius: focused ? 18 : 8, y: focused ? 8 : 4)
      .focusEffectDisabled()
      .animation(.easeOut(duration: 0.15), value: focused)
      .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
  }
}

/// The artwork part of a card, with the focus outline.
private struct TVCardArt<Content: View>: View {
  var width: CGFloat
  var height: CGFloat
  @ViewBuilder var content: Content
  @Environment(\.isFocused) private var focused

  var body: some View {
    content
      .frame(width: width, height: height)
      .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .strokeBorder(Color.white.opacity(focused ? 0.7 : 0.06), lineWidth: focused ? 4 : 1)
      )
  }
}

/// Caption under a card: bright while focused, dimmed back otherwise.
private struct TVCardCaption: View {
  var title: String
  var subtitle: String?
  var width: CGFloat
  @Environment(\.isFocused) private var focused

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title)
        .font(.system(size: 22, weight: .semibold))
        .foregroundStyle(.white.opacity(focused ? 1 : 0.6))
        .lineLimit(1)
      Text(subtitle ?? " ")
        .font(.system(size: 19, weight: .regular))
        .foregroundStyle(.white.opacity(focused ? 0.6 : 0.4))
        .lineLimit(1)
    }
    .frame(width: width, alignment: .leading)
    .offset(y: focused ? 8 : 0)
    .animation(.easeOut(duration: 0.15), value: focused)
  }
}

/// A 2:3 poster with its title and year underneath.
struct TVPosterCard: View {
  var library: LibraryStore
  var item: PlexMetadata
  var width: CGFloat = TVMetrics.posterWidth
  var onFocus: ((PlexMetadata) -> Void)? = nil

  @Environment(\.openItem) private var openItem

  var body: some View {
    Button {
      openItem(item)
    } label: {
      VStack(alignment: .leading, spacing: 14) {
        TVCardArt(width: width, height: width * 1.5) {
          ArtworkImage(library: library, item: item, kind: .poster, width: width, height: width * 1.5)
        }
        .overlay(alignment: .topTrailing) {
          if library.isWatched(item) {
            Image(systemName: "checkmark.circle.fill")
              .symbolRenderingMode(.palette)
              .foregroundStyle(.black, .white)
              .font(.system(size: 26))
              .padding(10)
          }
        }
        .overlay(alignment: .bottom) {
          if let progress = item.progress { TVProgressLine(value: progress).padding(10) }
        }
        TVCardCaption(title: item.displayTitle, subtitle: item.year.map(String.init), width: width)
      }
    }
    .buttonStyle(TVCardButtonStyle())
    .itemMenu(library: library, item: item)
    .onTVFocus { if $0 { onFocus?(item) } }
  }
}

/// A 16:9 card: Continue Watching, episodes. Shows an episode's own still.
struct TVLandscapeCard: View {
  var library: LibraryStore
  var item: PlexMetadata
  var width: CGFloat = TVMetrics.landscapeWidth
  var title: String? = nil
  var subtitle: String? = nil
  var inContinueWatching = false
  var action: (() -> Void)? = nil
  var onFocus: ((PlexMetadata) -> Void)? = nil

  @Environment(\.openItem) private var openItem

  var body: some View {
    let height = width * 9 / 16
    Button {
      if let action { action() } else { openItem(item) }
    } label: {
      VStack(alignment: .leading, spacing: 14) {
        TVCardArt(width: width, height: height) {
          if item.type == .episode, item.thumb != nil {
            RemoteImage(url: library.imageURL(item.thumb, width: width, height: height), placeholder: TVColor.surface)
          } else {
            ArtworkImage(library: library, item: item, kind: .backdrop, width: width, height: height)
          }
        }
        .overlay(alignment: .bottom) {
          if let progress = item.progress { TVProgressLine(value: progress).padding(12) }
        }
        TVCardCaption(
          title: title ?? item.displayTitle,
          subtitle: subtitle ?? (item.episodeLabel.map { "\($0) · \(item.title)" } ?? item.year.map(String.init)),
          width: width)
      }
    }
    .buttonStyle(TVCardButtonStyle())
    .itemMenu(library: library, item: item, inContinueWatching: inContinueWatching)
    .onTVFocus { if $0 { onFocus?(item) } }
  }
}

/// A thin white progress line on a dark track (no accent colour).
struct TVProgressLine: View {
  var value: Double

  var body: some View {
    Capsule()
      .fill(.white.opacity(0.3))
      .frame(height: 5)
      .overlay(alignment: .leading) {
        GeometryReader { geo in
          Capsule().fill(.white).frame(width: max(5, geo.size.width * value))
        }
      }
  }
}

/// A row header in Silo's size.
struct TVRowHeader: View {
  var title: String
  var size: CGFloat = 34

  var body: some View {
    Text(title)
      .font(.system(size: size, weight: .semibold))
      .foregroundStyle(TVColor.onSurface)
      .lineLimit(1)
  }
}

// MARK: - Focus helper

extension View {
  /// Calls `action` when this view (or a control inside it) gains or loses focus.
  func onTVFocus(_ action: @escaping (Bool) -> Void) -> some View {
    modifier(TVFocusReporter(action: action))
  }
}

private struct TVFocusReporter: ViewModifier {
  var action: (Bool) -> Void
  @FocusState private var focused: Bool

  func body(content: Content) -> some View {
    content
      .focused($focused)
      .onChange(of: focused) { _, new in action(new) }
  }
}
