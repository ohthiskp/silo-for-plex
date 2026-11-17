import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

// MARK: - Index (saved per source)

/// One video file found on a share.
public struct ShareFile: Codable, Sendable, Hashable {
  /// The `SourceFolder` it was found under.
  public var folder: String
  /// The path inside the share.
  public var path: String
  public var size: Int64
  public var modified: Date?
  public var name: MediaFileName

  public init(folder: String, path: String, size: Int64, modified: Date?, name: MediaFileName) {
    self.folder = folder
    self.path = path
    self.size = size
    self.modified = modified
    self.name = name
  }
}

/// What TMDB says a title is.
public struct ShareTitle: Codable, Sendable, Hashable {
  public var tmdbID: Int
  public var title: String
  public var year: Int?
  public var overview: String?
  public var posterPath: String?
  public var backdropPath: String?
  public var rating: Double?
  /// Season number → its episodes (shows only).
  public var seasons: [String: ShareSeason]

  public init(
    tmdbID: Int, title: String, year: Int? = nil, overview: String? = nil, posterPath: String? = nil,
    backdropPath: String? = nil, rating: Double? = nil, seasons: [String: ShareSeason] = [:]
  ) {
    self.tmdbID = tmdbID
    self.title = title
    self.year = year
    self.overview = overview
    self.posterPath = posterPath
    self.backdropPath = backdropPath
    self.rating = rating
    self.seasons = seasons
  }
}

public struct ShareSeason: Codable, Sendable, Hashable {
  public var posterPath: String?
  /// Episode number → details.
  public var episodes: [String: ShareEpisode]

  public init(posterPath: String? = nil, episodes: [String: ShareEpisode] = [:]) {
    self.posterPath = posterPath
    self.episodes = episodes
  }
}

public struct ShareEpisode: Codable, Sendable, Hashable {
  public var title: String?
  public var overview: String?
  public var stillPath: String?
  public var airDate: String?
  public var runtimeMinutes: Int?

  public init(title: String? = nil, overview: String? = nil, stillPath: String? = nil, airDate: String? = nil, runtimeMinutes: Int? = nil) {
    self.title = title
    self.overview = overview
    self.stillPath = stillPath
    self.airDate = airDate
    self.runtimeMinutes = runtimeMinutes
  }
}

/// Everything Astra knows about a share source's files, saved between launches.
public struct ShareIndex: Codable, Sendable, Hashable {
  public var version = 1
  public var files: [ShareFile] = []
  /// `MediaFileName.matchKey` → TMDB's answer. A key with no entry wasn't found (or wasn't looked up).
  public var titles: [String: ShareTitle] = [:]
  /// Keys TMDB had no answer for, so they aren't asked again every scan.
  public var unmatched: Set<String> = []
  /// Folder id → when it was last read.
  public var scannedAt: [String: Date] = [:]

  public init() {}
}

/// Watched state and progress for files on a share, kept on the device.
public struct ShareWatchState: Codable, Sendable, Hashable {
  public struct Entry: Codable, Sendable, Hashable {
    public var offsetMs: Int?
    public var durationMs: Int?
    public var watched: Bool
    /// Seconds since 1970, like Plex's `lastViewedAt`.
    public var lastViewedAt: Int?
  }

  /// Native item id ("m/…" or "e/…") → state.
  public var entries: [String: Entry] = [:]

  public init() {}
}

// MARK: - Matching titles

/// Finds what a file is on TMDB. The app's uses `TMDBClient`; tests use a table.
public protocol TitleMatcher: Sendable {
  func movie(_ title: String, year: Int?) async throws -> ShareTitle?
  func show(_ title: String, year: Int?) async throws -> ShareTitle?
  func season(show tmdbID: Int, number: Int) async throws -> ShareSeason?
}

extension TMDBClient: TitleMatcher {
  public func movie(_ title: String, year: Int?) async throws -> ShareTitle? {
    try await search("/search/movie", title: title, year: year, yearKey: "year")
  }

  public func show(_ title: String, year: Int?) async throws -> ShareTitle? {
    try await search("/search/tv", title: title, year: year, yearKey: "first_air_date_year")
  }

  /// The best result for `title`, with the year when there is one; without it if that finds nothing.
  func search(_ path: String, title: String, year: Int?, yearKey: String) async throws -> ShareTitle? {
    var query = ["query": title, "include_adult": "false"]
    if let year { query[yearKey] = String(year) }
    var results = try JSONDecoder().decode(Page.self, from: try await get(path, query)).results
    if results.isEmpty, year != nil {
      query[yearKey] = nil
      results = try JSONDecoder().decode(Page.self, from: try await get(path, query)).results
    }
    guard let raw = results.first, let id = raw.id else { return nil }
    let date = raw.release_date ?? raw.first_air_date
    return ShareTitle(
      tmdbID: id, title: raw.title ?? raw.name ?? title, year: date.flatMap { Int($0.prefix(4)) },
      overview: raw.overview, posterPath: raw.poster_path, backdropPath: raw.backdrop_path,
      rating: (raw.vote_average ?? 0) > 0 ? raw.vote_average : nil)
  }

  public func season(show tmdbID: Int, number: Int) async throws -> ShareSeason? {
    struct Body: Decodable {
      struct Episode: Decodable {
        var episode_number: Int?
        var name: String?
        var overview: String?
        var still_path: String?
        var air_date: String?
        var runtime: Int?
      }
      var poster_path: String?
      var episodes: [Episode]?
    }
    let body = try JSONDecoder().decode(Body.self, from: try await get("/tv/\(tmdbID)/season/\(number)", [:]))
    var episodes: [String: ShareEpisode] = [:]
    for episode in body.episodes ?? [] {
      guard let n = episode.episode_number else { continue }
      episodes[String(n)] = ShareEpisode(
        title: episode.name, overview: episode.overview, stillPath: episode.still_path, airDate: episode.air_date,
        runtimeMinutes: episode.runtime)
    }
    return ShareSeason(posterPath: body.poster_path, episodes: episodes)
  }
}

// MARK: - Scanning

public enum ShareScanner {
  /// Progress for Settings: files found so far, titles matched so far.
  public struct Progress: Sendable, Equatable {
    public var folder: String
    public var files: Int
    public var matched: Int
  }

  /// Reads `folder` on `share` again and matches new titles. Files from other
  /// folders, and matches already made, are kept.
  public static func scan(
    _ folder: SourceFolder, share: any FileShare, into previous: ShareIndex, matcher: (any TitleMatcher)?,
    now: Date = Date(), onProgress: @escaping @Sendable (Progress) async -> Void = { _ in }
  ) async throws -> ShareIndex {
    let root = folder.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    let found = try await MediaFiles.videos(in: share, root: root)
    var index = previous
    let prefix = root.isEmpty ? "" : root + "/"
    let files = found.map { entry in
      let relative = entry.path.hasPrefix(prefix) ? String(entry.path.dropFirst(prefix.count)) : entry.path
      return ShareFile(
        folder: folder.id, path: entry.path, size: entry.size, modified: entry.modified,
        name: MediaFileName.parse(relative, content: folder.content))
    }
    index.files = index.files.filter { $0.folder != folder.id } + files
    index.scannedAt[folder.id] = now
    await onProgress(Progress(folder: folder.id, files: files.count, matched: 0))
    guard let matcher else { return index }
    index = await match(index, files: files, matcher: matcher, folder: folder.id, onProgress: onProgress)
    return index
  }

  /// Looks up every title not matched yet (4 at a time), then the seasons
  /// episodes need. A failed lookup is left for the next scan.
  static func match(
    _ start: ShareIndex, files: [ShareFile], matcher: any TitleMatcher, folder: String,
    onProgress: @escaping @Sendable (Progress) async -> Void
  ) async -> ShareIndex {
    var index = start
    var wanted: [String: MediaFileName] = [:]
    for file in files where index.titles[file.name.matchKey] == nil && !index.unmatched.contains(file.name.matchKey) {
      wanted[file.name.matchKey] = file.name
    }
    let keys = wanted.keys.sorted()
    var matched = 0
    for batch in stride(from: 0, to: keys.count, by: 4).map({ Array(keys[$0..<min($0 + 4, keys.count)]) }) {
      if Task.isCancelled { break }
      let results = await withTaskGroup(of: (String, Result<ShareTitle?, Error>).self) { group in
        for key in batch {
          let name = wanted[key]!
          group.addTask {
            do {
              let title = name.kind == .movie
                ? try await matcher.movie(name.title, year: name.year)
                : try await matcher.show(name.title, year: name.year)
              return (key, .success(title))
            } catch {
              return (key, .failure(error))
            }
          }
        }
        var out: [(String, Result<ShareTitle?, Error>)] = []
        for await result in group { out.append(result) }
        return out
      }
      for (key, result) in results {
        switch result {
        case .success(let title?): index.titles[key] = title; matched += 1
        case .success(nil): index.unmatched.insert(key)
        case .failure: break
        }
      }
      await onProgress(Progress(folder: folder, files: files.count, matched: matched))
    }
    // Episode names and stills, one season at a time.
    var seasonsWanted: [String: Set<Int>] = [:]
    for file in files where file.name.kind == .episode {
      guard let season = file.name.season, let title = index.titles[file.name.matchKey],
        title.seasons[String(season)] == nil
      else { continue }
      seasonsWanted[file.name.matchKey, default: []].insert(season)
    }
    for (key, seasons) in seasonsWanted.sorted(by: { $0.key < $1.key }) {
      guard let id = index.titles[key]?.tmdbID else { continue }
      for season in seasons.sorted() {
        if Task.isCancelled { break }
        if let details = try? await matcher.season(show: id, number: season) {
          index.titles[key]?.seasons[String(season)] = details
        }
      }
    }
    return index
  }
}
