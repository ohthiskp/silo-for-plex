import AstraKit
import SwiftUI

/// A titled horizontal row.
struct ContentRow<Content: View>: View {
  var title: String
  @ViewBuilder var content: () -> Content

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(title)
        .font(Astra.Font.rowTitle)
        .foregroundStyle(Astra.Color.ink)
        .padding(.leading, Astra.Layout.leading)
      ScrollView(.horizontal) {
        LazyHStack(alignment: .top, spacing: 14) {
          content()
        }
        .padding(.horizontal, Astra.Layout.leading)
        // Room for the hover scale so cards never clip.
        .padding(.vertical, 8)
      }
      .scrollIndicators(.never)
      .padding(.vertical, -8)
    }
  }
}

/// Landscape art card with the title underneath.
struct ArtCard: View {
  var library: LibraryStore
  var item: PlexMetadata
  var width: CGFloat = 240
  var height: CGFloat = 135

  @Environment(\.openItem) private var openItem

  var body: some View {
    Button {
      openItem(item)
    } label: {
      VStack(alignment: .leading, spacing: 8) {
        RemoteImage(url: library.imageURL(item.art ?? item.backdrop ?? item.thumb, width: width, height: height))
          .frame(width: width, height: height)
          .clipShape(RoundedRectangle(cornerRadius: Astra.Radius.card, style: .continuous))
          .overlay(alignment: .bottomLeading) {
            if let progress = item.progress { ProgressBar(value: progress).padding(10) }
          }
          .overlay(
            RoundedRectangle(cornerRadius: Astra.Radius.card, style: .continuous).stroke(Astra.Color.hairline))
          .pressable()
        Text(item.displayTitle)
          .font(Astra.Font.card)
          .foregroundStyle(Astra.Color.ink)
          .lineLimit(1)
        if let sub = item.episodeLabel ?? item.year.map(String.init) {
          Text(sub).font(.system(size: 12)).foregroundStyle(Astra.Color.muted).lineLimit(1)
        }
      }
      .frame(width: width, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

/// Continue Watching: a wider card with the episode or title inside it and a progress line.
struct ContinueCard: View {
  var library: LibraryStore
  var item: PlexMetadata
  var width: CGFloat = 360
  var height: CGFloat = 202

  @Environment(\.playItem) private var playItem
  @Environment(\.openItem) private var openItem

  var body: some View {
    Button {
      playItem(item)
    } label: {
      ZStack(alignment: .bottomLeading) {
        RemoteImage(url: library.imageURL(item.type == .episode ? item.thumb : item.backdrop, width: width, height: height))
        LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .center, endPoint: .bottom)
        VStack(alignment: .leading, spacing: 6) {
          Text(item.displayTitle)
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(.white)
            .lineLimit(1)
          if let sub = [item.episodeLabel, item.type == .episode ? item.title : nil].compactMap({ $0 }).joined(
            separator: "  ·  "
          ).nilIfEmpty {
            Text(sub).font(.system(size: 13.5, weight: .medium)).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
          }
          ProgressBar(value: item.progress ?? 0)
        }
        .padding(14)
        Image(systemName: "play.fill")
          .font(.system(size: 18, weight: .bold))
          .foregroundStyle(.white)
          .frame(width: 48, height: 48)
          .background(.black.opacity(0.4), in: Circle())
          .overlay(Circle().stroke(.white.opacity(0.25)))
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      .frame(width: width, height: height)
      .clipShape(RoundedRectangle(cornerRadius: Astra.Radius.card, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: Astra.Radius.card, style: .continuous).stroke(Astra.Color.hairline))
      .contentShape(Rectangle())
      .pressable(hoverScale: 1.03)
    }
    .buttonStyle(.plain)
    .contextMenu {
      Button("Details") { openItem(item) }
      Button("Mark as Watched") { Task { await library.setWatched(item, watched: true) } }
    }
  }
}

/// Poster card for library grids.
struct PosterCard: View {
  var library: LibraryStore
  var item: PlexMetadata
  var width: CGFloat = 170

  @Environment(\.openItem) private var openItem

  var body: some View {
    let height = width * 1.5
    Button {
      openItem(item)
    } label: {
      VStack(alignment: .leading, spacing: 8) {
        RemoteImage(url: library.imageURL(item.poster, width: width, height: height))
          .frame(width: width, height: height)
          .clipShape(RoundedRectangle(cornerRadius: Astra.Radius.card, style: .continuous))
          .overlay(alignment: .topTrailing) {
            if item.isWatched {
              Image(systemName: "checkmark.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Astra.Color.purple)
                .font(.system(size: 18))
                .padding(8)
            }
          }
          .overlay(
            RoundedRectangle(cornerRadius: Astra.Radius.card, style: .continuous).stroke(Astra.Color.hairline))
          .pressable()
        Text(item.displayTitle).font(Astra.Font.card).foregroundStyle(Astra.Color.ink).lineLimit(1)
        if let year = item.year {
          Text(String(year)).font(.system(size: 12)).foregroundStyle(Astra.Color.muted)
        }
      }
      .frame(width: width, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

struct ProgressBar: View {
  var value: Double

  var body: some View {
    Capsule()
      .fill(.white.opacity(0.25))
      .frame(height: 4)
      .overlay(alignment: .leading) {
        GeometryReader { geo in
          Capsule().fill(Astra.Color.purple).frame(width: max(4, geo.size.width * value))
        }
      }
  }
}
