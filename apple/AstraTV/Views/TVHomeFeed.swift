// Home on Apple TV, adapted from Silo Apple's tvOS "Skyline" feed
// (https://github.com/Silo-Server/silo-apple, AGPL-3.0-or-later,
// Copyright (C) 2026 Silo Media L.L.C. and contributors).

import AstraKit
import SwiftUI

/// One Home row.
struct TVHomeRow: Identifiable {
  enum Style { case landscape, poster }
  var id: String
  var title: String
  var style: Style
  var items: [PlexMetadata]
}

/// Silo's Home (KP, 2026-11-09): the focused title's artwork top right, its
/// logo, rating, facts, synopsis and badges on the left of the upper half,
/// and the rows in the lower half. Moving through a row previews each title
/// above; selecting opens its Details.
struct TVHomeFeed: View {
  var library: LibraryStore

  @State private var preview: PlexMetadata?
  /// The previewed title's full details (badges, rating, cast), once loaded.
  @State private var full: PlexMetadata?
  @State private var backdropItem: PlexMetadata?

  var body: some View {
    let rows = self.rows
    ZStack(alignment: .top) {
      TVPageBackdrop(library: library, item: backdropItem)
        .animation(.easeInOut(duration: 0.24), value: backdropItem?.id)

      if rows.isEmpty {
        emptyState
      } else {
        band(rows)
        if let preview {
          TVMarquee(library: library, item: full?.ratingKey == preview.ratingKey ? full! : preview)
            .id(preview.id)
            .offset(y: TVMetrics.landingOffset)
        }
      }
    }
    .ignoresSafeArea()
    .onAppear { seed(rows) }
    .onChange(of: rows.first?.items.first?.id) { _, _ in seed(rows) }
    // Text follows focus at once; the backdrop and details wait until focus rests.
    .task(id: preview?.id) {
      guard let preview else { return }
      try? await Task.pause(0.15)
      guard !Task.isCancelled else { return }
      backdropItem = preview
      if preview.isCatalogOnly {
        full = library.indexMatch(preview).flatMap { $0.media.isEmpty ? nil : $0 }
      } else if let detail = try? await library.details(preview.ratingKey), !Task.isCancelled {
        full = detail
      }
    }
    .task(id: prewarmKey(rows)) {
      await library.prewarmDetails(rows.flatMap { $0.items.prefix(8) })
    }
  }

  private func seed(_ rows: [TVHomeRow]) {
    guard preview == nil, let first = rows.first?.items.first else { return }
    preview = first
    backdropItem = first
  }

  private func prewarmKey(_ rows: [TVHomeRow]) -> String {
    rows.map { "\($0.id):\($0.items.count)" }.joined(separator: "|")
  }

  // MARK: Rows

  /// Continue Watching, Top Trending, Recently Released and All-Time Greats
  /// (movies and series each), then the server's own hubs.
  private var rows: [TVHomeRow] {
    var rows: [TVHomeRow] = []
    if !library.homeContinueWatching.isEmpty {
      rows.append(.init(id: "continue", title: "Continue Watching", style: .landscape, items: library.homeContinueWatching))
    }
    if !library.homeTopTen.isEmpty {
      rows.append(.init(id: "top", title: "Top Trending", style: .poster, items: library.homeTopTen))
    }
    let recent = library.homeRecent
    if !recent.movies.isEmpty {
      rows.append(.init(id: "recent-movies", title: "Recently Released Movies", style: .poster, items: recent.movies))
    }
    if !recent.shows.isEmpty {
      rows.append(.init(id: "recent-shows", title: "Recently Released Series", style: .poster, items: recent.shows))
    }
    let greats = library.homeGreats
    if !greats.movies.isEmpty {
      rows.append(.init(id: "greats-movies", title: "All-Time Great Movies", style: .poster, items: greats.movies))
    }
    if !greats.shows.isEmpty {
      rows.append(.init(id: "greats-shows", title: "All-Time Great Series", style: .poster, items: greats.shows))
    }
    for hub in library.hubs where !hub.items.isEmpty {
      if rows.contains(where: { $0.title == hub.title }) { continue }
      let landscape = hub.items.first?.type == .episode
      rows.append(.init(id: "hub-\(hub.id)", title: hub.title, style: landscape ? .landscape : .poster, items: hub.items))
    }
    return rows
  }

  /// The rows live only in the lower half of the screen, clipped at its top,
  /// so they never run over the marquee. Each move up or down brings the
  /// next row to the top of the band.
  private func band(_ rows: [TVHomeRow]) -> some View {
    GeometryReader { proxy in
      let bandHeight = proxy.size.height * TVMetrics.rowBandHeightFraction
      let bandTop = min(proxy.size.height, max(0, proxy.size.height - bandHeight + TVMetrics.landingOffset))
      let visible = max(0, proxy.size.height - bandTop)

      ScrollView(.vertical, showsIndicators: false) {
        LazyVStack(alignment: .leading, spacing: TVMetrics.rowBandPreviewSpacing) {
          ForEach(rows) { row in
            TVHomeRowView(library: library, row: row) { preview = $0 }
              .id(row.id)
          }
        }
        .scrollTargetLayout()
        // The last row can still rise to the top of the band.
        .padding(.bottom, max(0, visible - 20))
      }
      .scrollTargetBehavior(.viewAligned)
      .scrollClipDisabled(false)
      .frame(width: proxy.size.width, height: visible, alignment: .topLeading)
      .clipped()
      .padding(.top, bandTop)
      .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
    }
  }

  @ViewBuilder private var emptyState: some View {
    VStack(spacing: 18) {
      if library.isLoadingHome {
        ProgressView()
      } else {
        Text(library.homeError ?? "Nothing to show yet")
          .font(.system(size: 28, weight: .semibold))
          .foregroundStyle(TVColor.onSurface)
        Button("Try Again") { Task { await library.loadHome() } }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

/// A titled row of cards inside the band.
private struct TVHomeRowView: View {
  var library: LibraryStore
  var row: TVHomeRow
  var onFocus: (PlexMetadata) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      TVRowHeader(title: row.title)
        .padding(.leading, TVMetrics.safeAreaX)
      ScrollView(.horizontal, showsIndicators: false) {
        LazyHStack(alignment: .top, spacing: row.style == .poster ? 40 : 48) {
          ForEach(row.items) { item in
            switch row.style {
            case .poster:
              TVPosterCard(library: library, item: item, onFocus: onFocus)
            case .landscape:
              TVLandscapeCard(
                library: library, item: item, inContinueWatching: row.id == "continue", onFocus: onFocus)
            }
          }
        }
        .padding(.horizontal, TVMetrics.safeAreaX)
        .padding(.vertical, TVMetrics.rowCardVerticalPadding)
      }
      .scrollClipDisabled()
      .focusSection()
    }
  }
}

/// The preview above the rows: logo (or title), rating chip and facts,
/// synopsis, top-billed cast, then Astra's format badges. Never focusable.
struct TVMarquee: View {
  var library: LibraryStore
  var item: PlexMetadata

  @State private var certification: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      TVLogoTitle(
        library: library, item: item, maxWidth: TVMetrics.marqueeLogoMaxWidth,
        maxHeight: TVMetrics.marqueeLogoMaxHeight, textSize: TVMetrics.marqueeTitleSize)

      HStack(spacing: 10) {
        if let rating = item.officialRating ?? certification {
          RatingBox(text: rating, fontSize: 15)
        }
        Text(facts)
          .font(.system(size: TVMetrics.marqueeMetaSize, weight: .medium))
          .foregroundStyle(TVColor.secondaryText)
          .lineLimit(1)
      }
      .frame(height: 27, alignment: .leading)

      if let summary = item.summary, !summary.isEmpty {
        Text(summary)
          .font(.system(size: TVMetrics.marqueeSynopsisSize))
          .lineSpacing(6)
          .foregroundStyle(TVColor.secondaryText)
          .lineLimit(2)
          .frame(maxWidth: TVMetrics.marqueeSynopsisMaxWidth, alignment: .leading)
      }

      Text(cast)
        .font(.system(size: TVMetrics.marqueeMetaSize, weight: .medium))
        .foregroundStyle(TVColor.onSurface.opacity(0.5))
        .lineLimit(1)
        .frame(maxWidth: TVMetrics.marqueeSynopsisMaxWidth, alignment: .leading)
        .frame(height: 27, alignment: .leading)

      TVFormatChips(item: item, fontSize: 15, showsRating: false)
        .frame(height: 27, alignment: .leading)
    }
    .frame(maxWidth: TVMetrics.marqueeContentWidth, alignment: .leading)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    .padding(.leading, TVMetrics.safeAreaX)
    .padding(.bottom, TVMetrics.marqueeBottomInset)
    .allowsHitTesting(false)
    .accessibilityElement(children: .combine)
    .task(id: item.id) {
      certification = nil
      guard item.officialRating == nil, item.type == .movie || item.type == .show else { return }
      certification = await library.tmdbArtwork(for: item)?.certification
    }
  }

  /// "2014 · Sci-Fi · 2h 49m · 1h 10m left", or an episode's label.
  private var facts: String {
    var parts: [String] = []
    if let label = item.episodeLabel { parts.append(label) }
    if let year = item.year { parts.append(String(year)) }
    if let genre = item.genres.first?.tag { parts.append(genre) }
    if item.type == .show, let seasons = item.childCount {
      parts.append("\(seasons) Season\(seasons == 1 ? "" : "s")")
    } else if let length = item.durationLabel {
      parts.append(length)
    }
    if let offset = item.viewOffset, let duration = item.duration, duration > offset, offset > 0 {
      let minutes = max(1, (duration - offset) / 60_000)
      parts.append(minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m left" : "\(minutes)m left")
    }
    return parts.joined(separator: " · ")
  }

  private var cast: String {
    item.roles.prefix(3).map(\.tag).joined(separator: ", ")
  }
}
