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

/// Download progress and checks, kept apart from URLSession so they are tested.
public enum DownloadCheck {
  /// The fraction done. Plex often sends originals without a Content-Length
  /// (URLSession then reports -1 as the total), so the file size from the
  /// item's metadata is used instead. Nil when neither is known.
  public static func fraction(written: Int64, reportedTotal: Int64, expected: Int64?) -> Double? {
    let total = reportedTotal > 0 ? reportedTotal : (expected ?? 0)
    guard total > 0 else { return nil }
    return min(1, max(0, Double(written) / Double(total)))
  }

  public enum Failure: LocalizedError, Equatable {
    case server(Int)
    case notAVideo(String)
    case incomplete(got: Int64, expected: Int64)

    public var errorDescription: String? {
      switch self {
      case .server(401), .server(403): "The server refused the download. Sign in again or check sharing permissions."
      case .server(let code): "The server answered with an error (\(code))."
      case .notAVideo(let type): "The server sent \(type) instead of the video file."
      case .incomplete(let got, let expected):
        "The download stopped early (\(ByteCountFormatter.string(fromByteCount: got, countStyle: .file)) of \(ByteCountFormatter.string(fromByteCount: expected, countStyle: .file)))."
      }
    }
  }

  /// Whether a finished response really is the whole original file.
  public static func validate(status: Int, mimeType: String?, fileSize: Int64, expected: Int64?) -> Failure? {
    guard (200..<300).contains(status) else { return .server(status) }
    if let mimeType, mimeType.hasPrefix("text/") || mimeType == "application/json" || mimeType == "application/xml" {
      return .notAVideo(mimeType)
    }
    // A few bytes off is fine (Plex's size is the file's; it's never larger).
    if let expected, expected > 0, fileSize < expected - max(1024, expected / 1000) {
      return .incomplete(got: fileSize, expected: expected)
    }
    return nil
  }
}

/// Astra: a large file is fetched over several connections at once (the
/// aria2 / Tiercel approach), each asking for its own byte range, then joined.
public enum DownloadSegments {
  /// Files smaller than this download over one connection.
  public static let minimumBytes: Int64 = 50_000_000

  /// `count` contiguous ranges covering `0..<total`, the last taking the remainder.
  public static func ranges(total: Int64, count: Int) -> [ClosedRange<Int64>] {
    guard total > 0, count > 0 else { return [] }
    let n = Int64(min(count, Int(max(1, total))))
    let size = total / n
    return (0..<n).map { i in
      let start = i * size
      let end = i == n - 1 ? total - 1 : start + size - 1
      return start...end
    }
  }

  /// The `Range` header value for one range.
  public static func header(_ range: ClosedRange<Int64>) -> String {
    "bytes=\(range.lowerBound)-\(range.upperBound)"
  }
}
