import AstraKit
import SwiftUI

/// Download, progress and delete for one movie, episode, season or show.
struct DownloadButton: View {
  var item: PlexMetadata
  /// Icon only, for episode cards.
  var compact = false
  /// A round glass icon, for the iPhone details actions.
  var round = false
  /// A capsule as wide as it's allowed, beside Resume on Details (KP's mockup).
  var wide = false

  @Environment(AppModel.self) private var app
  @State private var confirmDelete = false
  @State private var confirmCancel = false

  private var downloads: DownloadStore { app.downloads }
  private var isGroup: Bool { item.type == .show || item.type == .season }

  private var state: DownloadStore.State {
    isGroup ? downloads.state(forEpisodesOf: item) : downloads.state(for: item.ratingKey)
  }

  var body: some View {
    Group {
      if compact {
        Button(action: tap) { icon.font(.system(size: 15, weight: .semibold)) }
          .buttonStyle(.plain)
          .foregroundStyle(Astra.Color.ink)
          .frame(width: 30, height: 30)
          .contentShape(Rectangle())
      } else if wide {
        Button(action: tap) {
          Label { Text(title).lineLimit(1) } icon: { icon }
            .frame(maxWidth: .infinity)
        }
        .astraSecondaryButton()
      } else if round {
        Button(action: tap) { icon }
          .modifier(ActionButtonShape(round: true))
      } else {
        Button(action: tap) { Label { Text(title) } icon: { icon } }
          .astraSecondaryButton()
      }
    }
    .help(helpText)
    .accessibilityLabel(title)
    .confirmationDialog("Stop downloading \(item.displayTitle)?", isPresented: $confirmCancel) {
      Button("Stop Download", role: .destructive) {
        if isGroup { downloads.cancelEpisodes(of: item) } else { downloads.cancel(item.ratingKey) }
      }
      Button("Keep Downloading", role: .cancel) {}
    }
    .confirmationDialog("Delete the download of \(item.displayTitle)?", isPresented: $confirmDelete) {
      Button("Delete Download", role: .destructive) {
        if isGroup { downloads.deleteEpisodes(of: item) } else { downloads.delete(item.ratingKey) }
      }
    }
  }

  @ViewBuilder private var icon: some View {
    switch state {
    case .none: Image(systemName: "arrow.down.circle")
    case .failed: Image(systemName: "exclamationmark.arrow.circlepath")
    case .queued: Image(systemName: "clock")
    case .downloading(let fraction): DownloadRing(fraction: fraction)
    case .done: Image(systemName: "checkmark.circle.fill")
    }
  }

  /// The tooltip: for a failed download, why it failed.
  private var helpText: String {
    if case .failed(let reason) = state { return "Retry Download: \(reason)" }
    return title
  }

  private var title: String {
    switch state {
    case .none: isGroup ? (item.type == .show ? "Download Show" : "Download Season") : "Download"
    case .failed: "Retry Download"
    case .queued: "Waiting…"
    case .downloading(let fraction): "Downloading \(Int(fraction * 100))%"
    case .done: "Downloaded"
    }
  }

  private func tap() {
    switch state {
    case .none:
      downloads.download(item)
    case .failed:
      downloads.retry(item.ratingKey)
    case .queued, .downloading:
      // Never stop a download on a stray click: ask first.
      confirmCancel = true
    case .done:
      confirmDelete = true
    }
  }
}

/// A small progress ring in place of the download glyph.
struct DownloadRing: View {
  var fraction: Double

  var body: some View {
    ZStack {
      Circle().stroke(.white.opacity(0.25), lineWidth: 2)
      Circle().trim(from: 0, to: max(0.02, fraction))
        .stroke(.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
        .rotationEffect(.degrees(-90))
      RoundedRectangle(cornerRadius: 1).fill(.white).frame(width: 5, height: 5)
    }
    .frame(width: 16, height: 16)
    .astraAnimation(Astra.Motion.base, value: fraction)
  }
}

/// The Downloads page: what is downloading, then saved movies and shows.
struct DownloadsView: View {
  var body: some View {
    AstraPage {
      AstraSectionHeader(title: "Downloads")
      DownloadsContent()
    }
  }
}

/// The Downloads page's lists without its page and title (iPhone Libraries shows them under its tabs).
struct DownloadsContent: View {
  @Environment(AppModel.self) private var app

  private var downloads: DownloadStore { app.downloads }

  /// "Connecting…", or "120 MB of 2.3 GB · 5%".
  static func receivedText(_ job: DownloadStore.Job) -> String {
    guard let received = job.received, received > 0 else { return "Connecting…" }
    let got = ByteCountFormatter.string(fromByteCount: received, countStyle: .file)
    guard let total = job.record.bytes, total > 0 else { return got }
    let speed = job.speed.map { " · \(ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file))/s" } ?? ""
    return "\(got) of \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file)) · \(Int(job.fraction * 100))%\(speed)"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Astra.Spacing.l) {
      if !downloads.hasAnything {
        EmptyState(
          symbol: "arrow.down.circle", title: "No downloads",
          message: "Choose Download on any movie, show or episode to watch it without a connection.")
      }

      if !downloads.jobs.isEmpty {
        section("Downloading") {
          ForEach(downloads.jobs) { job in
            DownloadRow(record: job.record, image: nil) {
              HStack(spacing: Astra.Spacing.s) {
                if job.running {
                  VStack(alignment: .trailing, spacing: 4) {
                    ProgressView(value: job.fraction).tint(.white).frame(width: 120)
                    // Astra: how much has arrived, so a stalled download is visible.
                    Text(Self.receivedText(job)).monospacedDigit()
                  }
                } else {
                  Text("Waiting")
                }
                Button {
                  downloads.cancel(job.id)
                } label: {
                  Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel Download")
              }
              .astraFont(.meta)
              .foregroundStyle(Astra.Color.muted)
            }
          }
        }
      }

      if !downloads.failedList.isEmpty {
        section("Didn't download") {
          ForEach(downloads.failedList, id: \.job.id) { entry in
            DownloadRow(record: entry.job.record, image: nil) {
              HStack(spacing: Astra.Spacing.s) {
                Text(entry.reason)
                  .lineLimit(2)
                  .multilineTextAlignment(.trailing)
                  .frame(maxWidth: 320, alignment: .trailing)
                Button("Retry") { downloads.retry(entry.job.id) }
                  .astraSecondaryButton()
                Button {
                  downloads.dismissFailure(entry.job.id)
                } label: {
                  Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove")
              }
              .astraFont(.meta)
              .foregroundStyle(Astra.Color.muted)
            }
          }
        }
      }

      let movies = downloads.index.movies
      if !movies.isEmpty {
        section("Movies") {
          ForEach(movies) { savedRow($0) }
        }
      }
      ForEach(downloads.index.shows) { show in
        section(show.title) {
          ForEach(show.episodes) { savedRow($0) }
        }
      }
    }
  }

  private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: Astra.Spacing.s) {
      Text(title).astraFont(.rowTitle).foregroundStyle(Astra.Color.ink).lineLimit(1)
      VStack(spacing: 2) { content() }
    }
  }

  private func savedRow(_ record: DownloadRecord) -> some View {
    Button {
      app.playDownload(record)
    } label: {
      DownloadRow(record: record, image: downloads.imageURL(record)) {
        HStack(spacing: Astra.Spacing.m) {
          if let badge = record.resolutionBadge { Badge(text: badge) }
          if let bytes = record.bytes {
            Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
              .astraFont(.meta).foregroundStyle(Astra.Color.muted)
          }
          Image(systemName: "play.fill").foregroundStyle(Astra.Color.ink)
        }
      }
    }
    .buttonStyle(AstraCardButtonStyle())
    .contextMenu {
      Button("Play") { app.playDownload(record) }
      Button("Delete Download", role: .destructive) { downloads.delete(record.ratingKey) }
    }
  }
}

/// One row on the Downloads page: artwork, titles, then trailing controls.
struct DownloadRow<Trailing: View>: View {
  var record: DownloadRecord
  var image: URL?
  @ViewBuilder var trailing: () -> Trailing

  var body: some View {
    let landscape = record.type == .episode
    HStack(spacing: Astra.Spacing.m) {
      RemoteImage(url: image)
        .frame(width: landscape ? 112 : 56, height: landscape ? 63 : 84)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Astra.Color.hairline))
      VStack(alignment: .leading, spacing: 3) {
        Text(record.type == .episode ? record.title : record.displayTitle)
          .astraFont(size: 15, weight: .semibold).foregroundStyle(Astra.Color.ink).lineLimit(1)
        if let sub = record.episodeLabel ?? record.year.map(String.init) {
          Text(sub).astraFont(.meta).foregroundStyle(Astra.Color.muted).lineLimit(1)
        }
      }
      Spacer(minLength: Astra.Spacing.m)
      trailing()
    }
    .padding(.vertical, 8)
    .contentShape(Rectangle())
  }
}
