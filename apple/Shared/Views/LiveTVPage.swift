import AstraKit
import SwiftUI

/// Live TV (KP, 2026-11-16: "make it look like YouTube TV"): the channel in
/// focus fills the top with what's on, a LIVE tag and time left; under it the
/// category chips (Live Guide, Favorites, then the provider's categories)
/// and the guide, one row per channel: the channel, a wide "On now" tile
/// with progress, then what's next. Choosing a tile plays the channel full
/// screen. The same page on iPhone, Mac and Apple TV, sized for each.
struct LiveTVPage: View {
  @Environment(AppModel.self) private var app
  /// Apple TV: bumped when Down is pressed on the top bar, so the guide takes focus.
  var focusTrigger = 0

  @State private var filter: LiveTVStore.Filter = .all
  /// The channel the header shows: focused (TV), hovered (Mac) or last played.
  @State private var shownID: LiveChannel.ID?
  #if os(tvOS)
    @FocusState private var focused: LiveChannel.ID?
  #endif

  private var store: LiveTVStore { app.liveTV }
  private var list: [LiveChannel] { store.channels(for: filter) }
  private var shown: LiveChannel? {
    shownID.flatMap { id in store.channels.first { $0.id == id } } ?? list.first ?? store.channels.first
  }

  var body: some View {
    Group {
      switch store.phase {
      case .ready where !store.channels.isEmpty: content
      case .failed(let message):
        LiveMessage(title: "Live TV couldn't load", message: message) { store.reload() }
      case .loading:
        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
      default:
        LiveMessage(
          title: "No channels yet",
          message: "Add your Xtream login or an M3U link in Settings → Live TV.", retry: nil)
      }
    }
    .background(Astra.Color.bg.ignoresSafeArea())
    .task { store.start() }
  }

  private var content: some View {
    VStack(alignment: .leading, spacing: 0) {
      LiveHeader(store: store, channel: shown)
      chips
        .padding(.top, LiveMetrics.chipsTop)
        .padding(.bottom, LiveMetrics.chipsBottom)
      guide
    }
    .ignoresSafeArea(edges: .top)
  }

  // MARK: Chips

  private var chips: some View {
    ScrollView(.horizontal) {
      HStack(spacing: LiveMetrics.chipGap) {
        chip("Live Guide", .all)
        chip("Favorites", .favorites, symbol: "star.fill")
        ForEach(store.groups, id: \.self) { chip($0, .group($0)) }
      }
      .padding(.horizontal, LiveMetrics.leading)
      #if os(tvOS)
        .padding(.vertical, 16)
      #endif
    }
    .scrollIndicators(.never)
    #if os(tvOS)
      .scrollClipDisabled()
      .focusSection()
    #endif
  }

  private func chip(_ title: String, _ value: LiveTVStore.Filter, symbol: String? = nil) -> some View {
    Button {
      filter = value
    } label: {
      HStack(spacing: 6) {
        if let symbol { Image(systemName: symbol) }
        Text(title).lineLimit(1)
      }
    }
    .buttonStyle(LiveChipStyle(selected: filter == value))
    .accessibilityAddTraits(filter == value ? .isSelected : [])
  }

  // MARK: Guide

  private var guide: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: LiveMetrics.rowGap) {
        if list.isEmpty {
          Text(filter == .favorites ? "Long-press a channel to add it to Favorites." : "No channels here.")
            .astraFont(size: 15)
            .foregroundStyle(Astra.Color.muted)
            .padding(.vertical, 30)
        }
        ForEach(list) { channel in
          #if os(tvOS)
            LiveGuideRow(
              store: store, channel: channel, play: { play(channel) }, hover: {}, focus: $focused)
          #else
            LiveGuideRow(store: store, channel: channel, play: { play(channel) }, hover: { shownID = channel.id })
          #endif
        }
      }
      .padding(.horizontal, LiveMetrics.leading)
      .padding(.bottom, LiveMetrics.bottomRoom)
      #if os(tvOS)
        .padding(.vertical, 12)
      #endif
    }
    .scrollIndicators(.never)
    #if os(tvOS)
      .scrollClipDisabled()
      .focusSection()
      .onChange(of: focused) { if let focused { shownID = focused } }
      .onChange(of: focusTrigger) { focused = list.first?.id }
    #endif
  }
}

extension LiveTVPage {
  fileprivate func play(_ channel: LiveChannel) {
    shownID = channel.id
    app.playLive(channel)
  }
}

// MARK: - Header

/// The top of the page: what's on the channel in focus, over its artwork.
private struct LiveHeader: View {
  var store: LiveTVStore
  var channel: LiveChannel?

  var body: some View {
    let program = channel.flatMap { store.nowOn($0) }
    ZStack(alignment: .bottomLeading) {
      backdrop(program?.image ?? channel?.logo)
      VStack(alignment: .leading, spacing: LiveMetrics.headerGap) {
        if let channel { LiveChannelBadge(channel: channel) }
        Text(program?.title ?? channel?.name ?? "")
          .font(.system(size: LiveMetrics.headerTitle, weight: .heavy))
          .foregroundStyle(.white)
          .lineLimit(2)
          .minimumScaleFactor(0.7)
        HStack(spacing: 10) {
          LiveTag()
          if let program {
            Text(LiveTime.range(program))
            Text("·")
            Text(program.remainingText(at: store.now))
          } else if let group = channel?.group {
            Text(group)
          }
        }
        .font(.system(size: LiveMetrics.headerMeta, weight: .medium))
        .foregroundStyle(.white.opacity(0.75))
        #if !os(iOS)
          if let summary = program?.summary {
            Text(summary)
              .font(.system(size: LiveMetrics.headerMeta))
              .foregroundStyle(.white.opacity(0.62))
              .lineLimit(2)
              .frame(maxWidth: LiveMetrics.summaryWidth, alignment: .leading)
          }
        #endif
        if let program {
          LiveProgress(value: program.progress(at: store.now))
            .frame(width: LiveMetrics.headerProgress, height: LiveMetrics.progressHeight * 1.5)
            .padding(.top, 4)
        }
      }
      .padding(.horizontal, LiveMetrics.leading)
      .padding(.bottom, LiveMetrics.headerBottom)
      .animation(Astra.Motion.base, value: channel?.id)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .frame(height: LiveMetrics.headerHeight)
    .clipped()
  }

  /// The art large and soft on the right, fading into the page.
  private func backdrop(_ url: URL?) -> some View {
    ZStack {
      Astra.Color.bg
      if let url {
        RemoteImage(url: url, contentMode: .fit, placeholder: Color.clear)
          .frame(maxWidth: LiveMetrics.backdropWidth, maxHeight: LiveMetrics.headerHeight * 0.7)
          .blur(radius: 50)
          .opacity(0.7)
          .frame(maxWidth: .infinity, alignment: .trailing)
          .padding(.trailing, LiveMetrics.leading)
      }
      LinearGradient(colors: [Astra.Color.bg, Astra.Color.bg.opacity(0)], startPoint: .bottom, endPoint: .center)
      LinearGradient(colors: [Astra.Color.bg.opacity(0.9), Astra.Color.bg.opacity(0)], startPoint: .leading, endPoint: .trailing)
    }
    .animation(Astra.Motion.base, value: url)
  }
}

// MARK: - Guide row

/// One channel: its badge, the wide "On now" tile, then what's next.
private struct LiveGuideRow: View {
  var store: LiveTVStore
  var channel: LiveChannel
  var play: () -> Void
  var hover: () -> Void
  #if os(tvOS)
    /// Every tile of the row reports its channel, so the header follows focus.
    var focus: FocusState<LiveChannel.ID?>.Binding
  #endif

  var body: some View {
    let lineup = store.lineup(channel, count: 1 + LiveMetrics.nextCount)
    let current = lineup.first.flatMap { $0.isOn(at: store.now) ? $0 : nil }
    let upcoming = Array(lineup.drop(while: { $0.isOn(at: store.now) }).prefix(LiveMetrics.nextCount))
    HStack(spacing: LiveMetrics.cellGap) {
      LiveChannelTile(channel: channel, favorite: store.favorites.contains(channel.id))
      Button(action: play) {
        LiveNowTile(channel: channel, program: current, now: store.now)
      }
      .buttonStyle(LiveTileStyle(prominent: true))
      .contextMenu { favoriteButton }
      #if os(tvOS)
        .focused(focus, equals: channel.id)
      #endif
      #if os(macOS)
        .onHover { if $0 { hover() } }
      #endif
      ForEach(upcoming, id: \.start) { next in
        Button(action: play) {
          LiveNextTile(program: next)
        }
        .buttonStyle(LiveTileStyle(prominent: false))
        .contextMenu { favoriteButton }
        #if os(tvOS)
          .focused(focus, equals: channel.id)
        #endif
      }
    }
    .frame(height: LiveMetrics.rowHeight)
    .accessibilityElement(children: .contain)
  }

  private var favoriteButton: some View {
    let isFavorite = store.favorites.contains(channel.id)
    return Button {
      store.toggleFavorite(channel)
    } label: {
      Label(isFavorite ? "Remove from Favorites" : "Add to Favorites", systemImage: isFavorite ? "star.slash" : "star")
    }
  }
}

private struct LiveChannelTile: View {
  var channel: LiveChannel
  var favorite: Bool

  var body: some View {
    VStack(spacing: 4) {
      if let logo = channel.logo {
        RemoteImage(url: logo, contentMode: .fit, placeholder: LiveChannelName(channel: channel))
          .frame(height: LiveMetrics.rowHeight * 0.42)
      } else {
        LiveChannelName(channel: channel)
      }
      HStack(spacing: 4) {
        if favorite { Image(systemName: "star.fill").font(.system(size: LiveMetrics.small * 0.8)) }
        if let number = channel.number { Text(String(number)) }
      }
      .font(.system(size: LiveMetrics.small, weight: .semibold))
      .foregroundStyle(Astra.Color.muted)
    }
    .padding(8)
    .frame(width: LiveMetrics.channelWidth)
    .frame(maxHeight: .infinity)
    .background(LiveMetrics.tileShape.fill(Astra.Color.ink.opacity(0.07)))
    .accessibilityElement(children: .combine)
  }
}

private struct LiveChannelName: View {
  var channel: LiveChannel

  var body: some View {
    Text(channel.name.uppercased())
      .font(.system(size: LiveMetrics.small, weight: .heavy))
      .foregroundStyle(Astra.Color.ink)
      .multilineTextAlignment(.center)
      .lineLimit(2)
      .minimumScaleFactor(0.7)
  }
}

private struct LiveNowTile: View {
  var channel: LiveChannel
  var program: LiveProgram?
  var now: Date

  var body: some View {
    HStack(spacing: LiveMetrics.cellGap + 4) {
      #if !os(iOS)
        thumbnail
      #endif
      VStack(alignment: .leading, spacing: 4) {
        Text(program?.title ?? channel.name)
          .font(.system(size: LiveMetrics.tileTitle, weight: .semibold))
          .lineLimit(1)
        Text(program?.remainingText(at: now) ?? (channel.group ?? "Live"))
          .font(.system(size: LiveMetrics.small, weight: .medium))
          .opacity(0.6)
          .lineLimit(1)
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, LiveMetrics.tilePadding)
    .frame(width: LiveMetrics.nowWidth, alignment: .leading)
    .frame(maxHeight: .infinity)
    .overlay(alignment: .bottom) {
      if let program {
        LiveProgress(value: program.progress(at: now))
          .frame(height: LiveMetrics.progressHeight)
      }
    }
    .clipShape(LiveMetrics.tileShape)
  }

  private var thumbnail: some View {
    let shape = RoundedRectangle(cornerRadius: LiveMetrics.corner * 0.6, style: .continuous)
    return ZStack {
      shape.fill(Astra.Color.ink.opacity(0.08))
      if let url = program?.image ?? channel.logo {
        RemoteImage(url: url, contentMode: program?.image == nil ? .fit : .fill, placeholder: Color.clear)
          .padding(program?.image == nil ? 10 : 0)
      } else {
        Image(systemName: "dot.radiowaves.left.and.right").font(.system(size: LiveMetrics.tileTitle)).opacity(0.5)
      }
    }
    .frame(width: LiveMetrics.thumbWidth, height: LiveMetrics.rowHeight - LiveMetrics.tilePadding * 1.4)
    .clipShape(shape)
  }
}

private struct LiveNextTile: View {
  var program: LiveProgram

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(program.title)
        .font(.system(size: LiveMetrics.tileTitle, weight: .semibold))
        .lineLimit(1)
      Text(LiveTime.start(program))
        .font(.system(size: LiveMetrics.small, weight: .medium))
        .opacity(0.5)
    }
    .padding(.horizontal, LiveMetrics.tilePadding)
    .frame(width: LiveMetrics.nextWidth, alignment: .leading)
    .frame(maxHeight: .infinity)
  }
}

// MARK: - Small pieces

/// The red LIVE tag.
struct LiveTag: View {
  var body: some View {
    Text("LIVE")
      .font(.system(size: LiveMetrics.small * 0.85, weight: .heavy))
      .foregroundStyle(.white)
      .padding(.horizontal, 7)
      .padding(.vertical, 3)
      .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Astra.Color.live))
  }
}

/// The channel's logo on a quiet pill, or its name.
private struct LiveChannelBadge: View {
  var channel: LiveChannel

  var body: some View {
    Group {
      if let logo = channel.logo {
        RemoteImage(url: logo, contentMode: .fit, placeholder: Text(channel.name))
          .frame(width: LiveMetrics.badgeLogo.width, height: LiveMetrics.badgeLogo.height)
      } else {
        Text(channel.name.uppercased())
      }
    }
    .font(.system(size: LiveMetrics.small, weight: .heavy))
    .foregroundStyle(.white)
    .padding(.horizontal, 12)
    .padding(.vertical, 7)
    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.14)))
  }
}

private struct LiveProgress: View {
  var value: Double

  var body: some View {
    GeometryReader { geo in
      ZStack(alignment: .leading) {
        Rectangle().fill(.white.opacity(0.22))
        Rectangle().fill(.white).frame(width: geo.size.width * value)
      }
    }
    .clipShape(Capsule())
    .accessibilityHidden(true)
  }
}

private struct LiveMessage: View {
  var title: String
  var message: String
  var retry: (() -> Void)?

  var body: some View {
    VStack(spacing: 14) {
      Image(systemName: "dot.radiowaves.left.and.right")
        .font(.system(size: LiveMetrics.headerTitle))
        .foregroundStyle(Astra.Color.muted)
      Text(title)
        .font(.system(size: LiveMetrics.tileTitle * 1.2, weight: .bold))
        .foregroundStyle(Astra.Color.ink)
      Text(message)
        .font(.system(size: LiveMetrics.small * 1.1))
        .foregroundStyle(Astra.Color.muted)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 520)
      if let retry {
        Button("Try Again", action: retry).buttonStyle(LiveChipStyle(selected: true))
      }
    }
    .padding(40)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

enum LiveTime {
  /// "5:20 – 8:30 PM".
  static func range(_ program: LiveProgram) -> String {
    "\(program.start.formatted(date: .omitted, time: .shortened)) – \(program.end.formatted(date: .omitted, time: .shortened))"
  }

  /// "8:30 PM".
  static func start(_ program: LiveProgram) -> String {
    program.start.formatted(date: .omitted, time: .shortened)
  }
}

// MARK: - Styles

/// A chip: white when chosen, quiet glass otherwise; white and lifted under TV focus.
private struct LiveChipStyle: ButtonStyle {
  var selected: Bool

  func makeBody(configuration: Configuration) -> some View {
    LiveChipBody(configuration: configuration, selected: selected)
  }
}

private struct LiveChipBody: View {
  let configuration: ButtonStyleConfiguration
  var selected: Bool
  @Environment(\.isFocused) private var focused

  var body: some View {
    let lit = selected || focused
    configuration.label
      .font(.system(size: LiveMetrics.chip, weight: .semibold))
      .foregroundStyle(lit ? Color.black : Astra.Color.ink.opacity(0.8))
      .padding(.horizontal, LiveMetrics.chip * 1.1)
      .padding(.vertical, LiveMetrics.chip * 0.5)
      .background(Capsule().fill(lit ? Color.white : Astra.Color.ink.opacity(0.1)))
      .contentShape(Capsule())
      .scaleEffect(configuration.isPressed ? 0.95 : (focused ? 1.08 : 1))
      #if os(tvOS)
        .shadow(color: .black.opacity(focused ? 0.35 : 0), radius: 10, y: 5)
        .focusEffectDisabled()
      #endif
      .animation(.snappy(duration: 0.2), value: focused)
  }
}

/// A guide tile: quiet glass; the "On now" one a little brighter. White with
/// black text under TV focus or the Mac pointer.
private struct LiveTileStyle: ButtonStyle {
  var prominent: Bool

  func makeBody(configuration: Configuration) -> some View {
    LiveTileBody(configuration: configuration, prominent: prominent)
  }
}

private struct LiveTileBody: View {
  let configuration: ButtonStyleConfiguration
  var prominent: Bool
  @Environment(\.isFocused) private var focused
  @State private var hovering = false

  var body: some View {
    let lit = focused || hovering
    configuration.label
      .foregroundStyle(lit ? Color.black : Astra.Color.ink)
      .background(
        LiveMetrics.tileShape.fill(lit ? Color.white : Astra.Color.ink.opacity(prominent ? 0.11 : 0.06)))
      .contentShape(LiveMetrics.tileShape)
      .scaleEffect(configuration.isPressed ? 0.97 : (focused ? 1.05 : 1))
      #if os(tvOS)
        .shadow(color: .black.opacity(focused ? 0.45 : 0), radius: 18, y: 10)
        .focusEffectDisabled()
      #endif
      #if os(macOS)
        .onHover { hovering = $0 }
      #endif
      .animation(.snappy(duration: 0.22), value: lit)
  }
}

// MARK: - Sizes

enum LiveMetrics {
  #if os(tvOS)
    static let leading: CGFloat = TVLayout.leading
    static let headerHeight: CGFloat = 560
    static let headerTitle: CGFloat = 62
    static let headerMeta: CGFloat = 25
    static let headerGap: CGFloat = 14
    static let headerBottom: CGFloat = 10
    static let headerProgress: CGFloat = 420
    static let summaryWidth: CGFloat = 820
    static let backdropWidth: CGFloat = 1100
    static let badgeLogo = CGSize(width: 150, height: 44)
    static let chip: CGFloat = 23
    static let chipGap: CGFloat = 14
    static let chipsTop: CGFloat = 26
    static let chipsBottom: CGFloat = 16
    static let rowHeight: CGFloat = 118
    static let rowGap: CGFloat = 14
    static let cellGap: CGFloat = 12
    static let channelWidth: CGFloat = 190
    static let nowWidth: CGFloat = 620
    static let nextWidth: CGFloat = 430
    static let nextCount = 2
    static let thumbWidth: CGFloat = 150
    static let tileTitle: CGFloat = 25
    static let small: CGFloat = 19
    static let tilePadding: CGFloat = 16
    static let corner: CGFloat = 16
    static let progressHeight: CGFloat = 5
    static let bottomRoom: CGFloat = 60
  #elseif os(macOS)
    static let leading: CGFloat = Astra.Layout.leading - 40
    static let headerHeight: CGFloat = 400
    static let headerTitle: CGFloat = 44
    static let headerMeta: CGFloat = 16
    static let headerGap: CGFloat = 10
    static let headerBottom: CGFloat = 6
    static let headerProgress: CGFloat = 300
    static let summaryWidth: CGFloat = 620
    static let backdropWidth: CGFloat = 800
    static let badgeLogo = CGSize(width: 100, height: 28)
    static let chip: CGFloat = 14
    static let chipGap: CGFloat = 8
    static let chipsTop: CGFloat = 20
    static let chipsBottom: CGFloat = 14
    static let rowHeight: CGFloat = 76
    static let rowGap: CGFloat = 8
    static let cellGap: CGFloat = 8
    static let channelWidth: CGFloat = 124
    static let nowWidth: CGFloat = 400
    static let nextWidth: CGFloat = 260
    static let nextCount = 3
    static let thumbWidth: CGFloat = 96
    static let tileTitle: CGFloat = 16
    static let small: CGFloat = 12.5
    static let tilePadding: CGFloat = 12
    static let corner: CGFloat = 12
    static let progressHeight: CGFloat = 3
    static let bottomRoom: CGFloat = 40
  #else
    static let leading: CGFloat = 16
    static let headerHeight: CGFloat = 300
    static let headerTitle: CGFloat = 26
    static let headerMeta: CGFloat = 13
    static let headerGap: CGFloat = 7
    static let headerBottom: CGFloat = 4
    static let headerProgress: CGFloat = 180
    static let summaryWidth: CGFloat = 340
    static let backdropWidth: CGFloat = 340
    static let badgeLogo = CGSize(width: 70, height: 20)
    static let chip: CGFloat = 14
    static let chipGap: CGFloat = 8
    static let chipsTop: CGFloat = 14
    static let chipsBottom: CGFloat = 10
    static let rowHeight: CGFloat = 66
    static let rowGap: CGFloat = 6
    static let cellGap: CGFloat = 6
    static let channelWidth: CGFloat = 76
    static let nowWidth: CGFloat = 190
    static let nextWidth: CGFloat = 150
    static let nextCount = 1
    static let thumbWidth: CGFloat = 0
    static let tileTitle: CGFloat = 14
    static let small: CGFloat = 11.5
    static let tilePadding: CGFloat = 10
    static let corner: CGFloat = 10
    static let progressHeight: CGFloat = 3
    static let bottomRoom: CGFloat = Astra.Layout.tabBarRoom + 20
  #endif

  static var tileShape: RoundedRectangle { RoundedRectangle(cornerRadius: corner, style: .continuous) }
}
