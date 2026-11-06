import Foundation

/// A movie or episode saved for offline viewing: the original file, exactly as
/// the server has it (never transcoded), plus what the Downloads page shows.
public struct DownloadRecord: Codable, Sendable, Hashable, Identifiable {
  public var ratingKey: String
  public var metadataKey: String
  public var type: PlexItemType
  public var title: String
  public var showTitle: String?
  public var showRatingKey: String?
  public var seasonNumber: Int?
  public var episodeNumber: Int?
  public var year: Int?
  public var summary: String?
  public var durationMs: Int
  /// The video file's name inside the downloads folder.
  public var fileName: String
  /// The poster's (or episode still's) name inside the downloads folder, once saved.
  public var imageName: String?
  public var bytes: Int64?
  public var width: Int?
  public var height: Int?
  public var addedAt: Date

  public var id: String { ratingKey }

  /// "Title" for a movie, "Show" for an episode.
  public var displayTitle: String { type == .episode ? (showTitle ?? title) : title }

  /// "S1 · E3" for an episode.
  public var episodeLabel: String? {
    guard type == .episode, let seasonNumber, let episodeNumber else { return nil }
    return "S\(seasonNumber) · E\(episodeNumber)"
  }

  /// "4K UHD" or "HD" for the saved file.
  public var resolutionBadge: String? {
    guard let width, let height else { return nil }
    return VideoTier.badge(for: VideoTier.tier(width: width, height: height))
  }

  /// The record for the version `quality` picks, or nil when the item has no file.
  public static func make(
    for item: PlexMetadata, quality: PlaybackQuality, now: Date = Date()
  ) -> (record: DownloadRecord, partKey: String)? {
    guard item.type == .movie || item.type == .episode,
      let media = PlaybackResolver.preferredMedia(item.media, quality: quality),
      let part = media.parts.first, let partKey = part.key
    else { return nil }
    let ext = (part.container ?? media.container ?? URL(fileURLWithPath: part.file ?? "").pathExtension)
      .lowercased().filter { $0.isLetter || $0.isNumber }
    let record = DownloadRecord(
      ratingKey: item.ratingKey,
      metadataKey: item.key ?? "/library/metadata/\(item.ratingKey)",
      type: item.type,
      title: item.title,
      showTitle: item.type == .episode ? item.grandparentTitle : nil,
      showRatingKey: item.type == .episode ? item.grandparentRatingKey : nil,
      seasonNumber: item.type == .episode ? item.parentIndex : nil,
      episodeNumber: item.type == .episode ? item.index : nil,
      year: item.year,
      summary: item.summary,
      durationMs: item.duration ?? part.duration ?? media.duration ?? 0,
      fileName: "\(Self.safeName(item.ratingKey)).\(ext.isEmpty ? "mkv" : ext)",
      imageName: nil,
      bytes: part.size,
      width: media.width,
      height: media.height,
      addedAt: now)
    return (record, partKey)
  }

  /// Rating keys are digits, but never let one escape the folder.
  public static func safeName(_ key: String) -> String {
    let cleaned = key.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    return cleaned.isEmpty ? "item" : cleaned
  }
}

/// The list of finished downloads, saved as JSON next to the files.
public struct DownloadIndex: Codable, Sendable, Equatable {
  public private(set) var records: [DownloadRecord] = []

  public init(records: [DownloadRecord] = []) {
    self.records = records
  }

  public static func load(from url: URL) -> DownloadIndex {
    guard let data = try? Data(contentsOf: url) else { return DownloadIndex() }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return (try? decoder.decode(DownloadIndex.self, from: data)) ?? DownloadIndex()
  }

  public func save(to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(self).write(to: url, options: .atomic)
  }

  public func record(_ ratingKey: String) -> DownloadRecord? {
    records.first { $0.ratingKey == ratingKey }
  }

  /// Adds or replaces the record with the same rating key.
  public mutating func upsert(_ record: DownloadRecord) {
    records.removeAll { $0.ratingKey == record.ratingKey }
    records.append(record)
  }

  @discardableResult
  public mutating func remove(_ ratingKey: String) -> DownloadRecord? {
    guard let i = records.firstIndex(where: { $0.ratingKey == ratingKey }) else { return nil }
    return records.remove(at: i)
  }

  /// Movies, newest first.
  public var movies: [DownloadRecord] {
    records.filter { $0.type == .movie }.sorted { $0.addedAt > $1.addedAt }
  }

  /// Episodes grouped by show (shows by title), each in season and episode order.
  public var shows: [DownloadShowGroup] {
    let groups = Dictionary(grouping: records.filter { $0.type == .episode }) { $0.showTitle ?? $0.title }
    return groups.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }.map { title in
      DownloadShowGroup(
        title: title,
        episodes: groups[title]!.sorted {
          ($0.seasonNumber ?? 0, $0.episodeNumber ?? 0) < ($1.seasonNumber ?? 0, $1.episodeNumber ?? 0)
        })
    }
  }
}

/// One show's downloaded episodes.
public struct DownloadShowGroup: Sendable, Hashable, Identifiable {
  public var title: String
  public var episodes: [DownloadRecord]
  public var id: String { title }
}

extension PlaybackResolver {
  /// Plays a downloaded file from disk. Progress still reports to Plex by rating key.
  public static func local(
    _ record: DownloadRecord, fileURL: URL, resumeMs: Int?, media: PlexMedia? = nil
  ) -> PlaybackSource {
    let offset = Double(resumeMs ?? 0) / 1000
    let duration = Double(record.durationMs) / 1000
    let fallbackPart = PlexPart(id: 0, key: nil, duration: record.durationMs, file: fileURL.path, size: record.bytes, container: fileURL.pathExtension, streams: [])
    return PlaybackSource(
      url: fileURL,
      headers: [:],
      startSeconds: offset > 0 && duration - offset > 30 ? offset : 0,
      ratingKey: record.ratingKey,
      metadataKey: record.metadataKey,
      durationMs: record.durationMs,
      title: record.displayTitle,
      subtitle: record.type == .episode
        ? [record.episodeLabel.map { $0.replacingOccurrences(of: " · ", with: "") }, record.title].compactMap { $0 }
          .joined(separator: "  ") : nil,
      media: media ?? PlexMedia(id: 0, width: record.width, height: record.height, parts: [fallbackPart]),
      part: media?.parts.first ?? fallbackPart)
  }

  /// The original file's download URL; the token goes in a header.
  public static func downloadRequest(partKey: String, client: PlexServerClient) -> URLRequest {
    var request = URLRequest(url: client.baseURL.appending(plexPath: partKey + (partKey.contains("?") ? "&" : "?") + "download=1"))
    request.setValue(client.token, forHTTPHeaderField: "X-Plex-Token")
    request.setValue(client.info.clientIdentifier, forHTTPHeaderField: "X-Plex-Client-Identifier")
    request.setValue(client.info.product, forHTTPHeaderField: "X-Plex-Product")
    return request
  }
}
