import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// A share source's index and watched state, shared by its client, the
/// scanner and the file server. Saved as JSON in Application Support.
public final class ShareLibraryState: @unchecked Sendable {
  private let lock = NSLock()
  private var _index: ShareIndex
  private var _watch: ShareWatchState
  private var _catalog: ShareCatalog?
  let indexURL: URL?
  let watchURL: URL?

  public init(index: ShareIndex = ShareIndex(), watch: ShareWatchState = ShareWatchState(), indexURL: URL? = nil, watchURL: URL? = nil) {
    _index = index
    _watch = watch
    self.indexURL = indexURL
    self.watchURL = watchURL
  }

  /// The saved state of source `id` in `directory` (empty when there is none yet).
  public static func load(sourceID id: String, directory: URL) -> ShareLibraryState {
    let indexURL = directory.appendingPathComponent("\(id)-index.json")
    let watchURL = directory.appendingPathComponent("\(id)-watched.json")
    let decoder = JSONDecoder()
    let index = (try? Data(contentsOf: indexURL)).flatMap { try? decoder.decode(ShareIndex.self, from: $0) } ?? ShareIndex()
    let watch = (try? Data(contentsOf: watchURL)).flatMap { try? decoder.decode(ShareWatchState.self, from: $0) }
      ?? ShareWatchState()
    return ShareLibraryState(index: index, watch: watch, indexURL: indexURL, watchURL: watchURL)
  }

  public var index: ShareIndex { lock.withLock { _index } }
  public var watch: ShareWatchState { lock.withLock { _watch } }

  public func setIndex(_ index: ShareIndex) {
    lock.withLock {
      _index = index
      _catalog = nil
    }
    save(index, to: indexURL)
  }

  public func updateWatch(_ change: (inout ShareWatchState) -> Void) {
    let watch = lock.withLock {
      change(&_watch)
      _catalog = nil
      return _watch
    }
    save(watch, to: watchURL)
  }

  /// The titles built from the index, rebuilt only after a change.
  func catalog(_ config: SourceConfig) -> ShareCatalog {
    lock.withLock {
      if let catalog = _catalog, catalog.configID == config.id, catalog.folders == config.folders { return catalog }
      let catalog = ShareCatalog(config: config, index: _index, watch: _watch)
      _catalog = catalog
      return catalog
    }
  }

  private func save<T: Encodable>(_ value: T, to url: URL?) {
    guard let url else { return }
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? JSONEncoder().encode(value).write(to: url, options: .atomic)
  }
}

/// A share's files as Plex items: one movie per title (each file a version),
/// shows with seasons and episodes. Built from the index and watched state.
struct ShareCatalog: Sendable {
  struct Entry: Sendable {
    var item: PlexMetadata
    /// When the newest file was changed, for "Recently Added".
    var addedAt: Date
    var library: String
  }

  let configID: String
  let folders: [SourceFolder]
  /// Native id → entry (movies, shows, seasons, episodes).
  var entries: [String: Entry] = [:]
  /// Library (folder id) → its movies or shows, by title.
  var libraries: [String: [String]] = [:]
  /// Show or season id → children ids in order.
  var children: [String: [String]] = [:]
  /// Episode id → its show id, for Continue Watching.
  var showOf: [String: String] = [:]

  init(config: SourceConfig, index: ShareIndex, watch: ShareWatchState) {
    configID = config.id
    folders = config.folders
    let key = { SourceKey.make(config.id, $0) }
    let poster = { (path: String?) in path.flatMap { TMDBItem.image($0, size: "w500") } }
    let backdrop = { (path: String?) in path.flatMap { TMDBItem.image($0, size: "w1280") } }
    let folderIDs = Set(config.folders.map(\.id))

    func media(_ files: [ShareFile]) -> [PlexMedia] {
      files.sorted { ($0.name.height ?? 0, $0.size) > ($1.name.height ?? 0, $1.size) }.map { file in
        let partKey = key("f/" + file.path)
        var stream = PlexStream(id: SourceKey.number(partKey + "#v"), streamType: 1, displayTitle: file.name.dynamicRange)
        if file.name.dynamicRange == "Dolby Vision" { stream.DOVIPresent = true }
        if file.name.dynamicRange == "HDR" { stream.colorTrc = "smpte2084" }
        let container = MediaFiles.fileExtension(file.path)
        let height = file.name.height
        let part = PlexPart(
          id: SourceKey.number(partKey), key: partKey, file: file.path, size: file.size, container: container,
          streams: [stream])
        return PlexMedia(
          id: SourceKey.number(partKey + "#m"), width: height.map { $0 * 16 / 9 }, height: height, container: container,
          parts: [part])
      }
    }

    func applyWatch(_ item: inout PlexMetadata, id: String) {
      guard let state = watch.entries[id] else { return }
      if state.watched {
        item.viewCount = 1
      } else if let offset = state.offsetMs, offset > 0 {
        item.viewOffset = offset
      }
      if item.duration == nil { item.duration = state.durationMs }
      item.lastViewedAt = state.lastViewedAt
    }

    let byFolder = Dictionary(grouping: index.files.filter { folderIDs.contains($0.folder) }, by: \.folder)
    for folder in config.folders {
      let sectionID = SourceKey.number(key(folder.id))
      let files = byFolder[folder.id] ?? []
      var titles: [(String, String)] = []
      switch folder.content {
      case .movies:
        for (matchKey, group) in Dictionary(grouping: files.filter { $0.name.kind == .movie }, by: \.name.matchKey) {
          let match = index.titles[matchKey]
          let id = "m/\(folder.id)/\(SourceKey.slug(matchKey))"
          var item = PlexMetadata(
            ratingKey: key(id), type: .movie, title: match?.title ?? group[0].name.title, summary: match?.overview,
            year: match?.year ?? group[0].name.year, thumb: poster(match?.posterPath), art: backdrop(match?.backdropPath))
          item.key = item.ratingKey
          item.guid = "share://\(config.id)/\(matchKey)"
          item.guids = match.map { [PlexGuid(id: "tmdb://\($0.tmdbID)")] } ?? []
          item.audienceRating = match?.rating
          item.librarySectionID = sectionID
          item.media = media(group)
          applyWatch(&item, id: id)
          let added = group.compactMap(\.modified).max() ?? .distantPast
          entries[id] = Entry(item: item, addedAt: added, library: folder.id)
          titles.append((id, item.title))
        }
      case .shows:
        for (matchKey, group) in Dictionary(grouping: files.filter { $0.name.kind == .episode }, by: \.name.matchKey) {
          let match = index.titles[matchKey]
          let slug = SourceKey.slug(matchKey)
          let showID = "s/\(folder.id)/\(slug)"
          let showTitle = match?.title ?? group[0].name.title
          var show = PlexMetadata(
            ratingKey: key(showID), type: .show, title: showTitle, summary: match?.overview,
            year: match?.year ?? group[0].name.year, thumb: poster(match?.posterPath), art: backdrop(match?.backdropPath))
          show.key = show.ratingKey
          show.guid = "share://\(config.id)/\(matchKey)"
          show.guids = match.map { [PlexGuid(id: "tmdb://\($0.tmdbID)")] } ?? []
          show.audienceRating = match?.rating
          show.librarySectionID = sectionID
          var seasonIDs: [String] = []
          var showLeaves = 0
          var showWatched = 0
          let bySeason = Dictionary(grouping: group, by: { $0.name.season ?? 1 })
          for season in bySeason.keys.sorted(by: { ($0 == 0 ? Int.max : $0) < ($1 == 0 ? Int.max : $1) }) {
            let seasonID = "n/\(folder.id)/\(slug)/\(season)"
            let seasonInfo = match?.seasons[String(season)]
            var episodeIDs: [String] = []
            var watched = 0
            let byEpisode = Dictionary(grouping: bySeason[season]!, by: { $0.name.episode ?? 0 })
            for number in byEpisode.keys.sorted() {
              let episodeFiles = byEpisode[number]!
              let info = seasonInfo?.episodes[String(number)]
              let episodeID = "e/\(folder.id)/\(slug)/\(season)/\(number)"
              var episode = PlexMetadata(
                ratingKey: key(episodeID), type: .episode, title: info?.title ?? "Episode \(number)",
                summary: info?.overview, thumb: info?.stillPath.flatMap { TMDBItem.image($0, size: "w780") })
              episode.key = episode.ratingKey
              episode.index = number
              episode.parentIndex = season
              episode.parentRatingKey = key(seasonID)
              episode.parentTitle = season == 0 ? "Specials" : "Season \(season)"
              episode.grandparentRatingKey = show.ratingKey
              episode.grandparentTitle = showTitle
              episode.grandparentGuid = show.guid
              episode.grandparentThumb = show.thumb
              episode.grandparentArt = show.art
              episode.parentThumb = poster(seasonInfo?.posterPath) ?? show.thumb
              episode.originallyAvailableAt = info?.airDate
              episode.duration = info?.runtimeMinutes.map { $0 * 60_000 }
              episode.librarySectionID = sectionID
              episode.media = media(episodeFiles)
              applyWatch(&episode, id: episodeID)
              if episode.isWatched { watched += 1 }
              let added = episodeFiles.compactMap(\.modified).max() ?? .distantPast
              entries[episodeID] = Entry(item: episode, addedAt: added, library: folder.id)
              episodeIDs.append(episodeID)
              showOf[episodeID] = showID
            }
            var seasonItem = PlexMetadata(
              ratingKey: key(seasonID), type: .season, title: season == 0 ? "Specials" : "Season \(season)",
              thumb: poster(seasonInfo?.posterPath) ?? show.thumb, art: show.art)
            seasonItem.key = seasonItem.ratingKey
            seasonItem.index = season
            seasonItem.parentRatingKey = show.ratingKey
            seasonItem.parentTitle = showTitle
            seasonItem.parentGuid = show.guid
            seasonItem.parentThumb = show.thumb
            seasonItem.leafCount = episodeIDs.count
            seasonItem.viewedLeafCount = watched
            seasonItem.librarySectionID = sectionID
            let added = episodeIDs.compactMap { entries[$0]?.addedAt }.max() ?? .distantPast
            entries[seasonID] = Entry(item: seasonItem, addedAt: added, library: folder.id)
            children[seasonID] = episodeIDs
            seasonIDs.append(seasonID)
            showLeaves += episodeIDs.count
            showWatched += watched
          }
          show.childCount = seasonIDs.count
          show.leafCount = showLeaves
          show.viewedLeafCount = showWatched
          let added = seasonIDs.compactMap { entries[$0]?.addedAt }.max() ?? .distantPast
          entries[showID] = Entry(item: show, addedAt: added, library: folder.id)
          children[showID] = seasonIDs
          titles.append((showID, showTitle))
        }
      }
      libraries[folder.id] = titles.sorted { $0.1.localizedStandardCompare($1.1) == .orderedAscending }.map(\.0)
    }
  }

  /// A show's or season's episodes, all of them.
  func episodes(under id: String) -> [String] {
    if id.hasPrefix("e/") { return [id] }
    return (children[id] ?? []).flatMap { episodes(under: $0) }
  }
}

/// A network share as a source: its folders are libraries, matched to TMDB,
/// with watched state on the device. Files play through `LoopbackFileServer`.
public struct ShareClient: MediaSourceClient {
  public let config: SourceConfig
  public let state: ShareLibraryState
  /// "http://127.0.0.1:<port>/<secret>/<source>/" from the file server, nil until it runs.
  let streamBase: @Sendable () -> URL?
  let now: @Sendable () -> Date

  public init(
    config: SourceConfig, state: ShareLibraryState, streamBase: @escaping @Sendable () -> URL?,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.config = config
    self.state = state
    self.streamBase = streamBase
    self.now = now
  }

  var catalog: ShareCatalog { state.catalog(config) }

  public func libraries() async throws -> [SourceLibrary] {
    config.folders.map { SourceLibrary(id: $0.id, title: $0.title, type: $0.content.sectionType) }
  }

  public func items(library: String, sort: String, start: Int, size: Int, filters: [URLQueryItem]) async throws -> [PlexMetadata] {
    let list = filtered(library: library, filters: filters)
    let sorted = SourceListing.sort(list, by: sort)
    guard start < sorted.count else { return [] }
    return Array(sorted[start..<min(sorted.count, start + max(0, size))]).map(\.item)
  }

  public func count(library: String, filters: [URLQueryItem]) async throws -> Int? {
    filtered(library: library, filters: filters).count
  }

  func filtered(library: String, filters: [URLQueryItem]) -> [ShareCatalog.Entry] {
    let catalog = catalog
    var list = (catalog.libraries[library] ?? []).compactMap { catalog.entries[$0] }
    for filter in filters {
      switch filter.name {
      case "unwatched" where filter.value == "1": list = list.filter { !$0.item.isWatched }
      case "guid":
        if let value = filter.value { list = list.filter { $0.item.guids.contains(PlexGuid(id: value)) } }
      default: break
      }
    }
    return list
  }

  public func genres(library: String) async throws -> [PlexFilterValue] { [] }

  public func metadata(_ id: String) async throws -> PlexMetadata {
    guard let entry = catalog.entries[id] else { throw SourceError.notFound }
    return entry.item
  }

  public func children(_ id: String) async throws -> [PlexMetadata] {
    let catalog = catalog
    return (catalog.children[id] ?? []).compactMap { catalog.entries[$0]?.item }
  }

  public func search(_ text: String, limit: Int) async throws -> [PlexMetadata] {
    let needle = text.trimmingCharacters(in: .whitespaces)
    guard !needle.isEmpty else { return [] }
    let catalog = catalog
    return catalog.libraries.values.joined().compactMap { catalog.entries[$0]?.item }
      .filter { $0.title.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
      .prefix(limit).map { $0 }
  }

  /// Movies and episodes started and not finished, most recent first; one per show.
  public func continueWatching(count: Int) async throws -> [PlexMetadata] {
    let catalog = catalog
    var seenShows = Set<String>()
    return state.watch.entries
      .filter { !$0.value.watched && ($0.value.offsetMs ?? 0) > 0 && catalog.entries[$0.key] != nil }
      .sorted { ($0.value.lastViewedAt ?? 0) > ($1.value.lastViewedAt ?? 0) }
      .compactMap { id, _ -> PlexMetadata? in
        if let show = catalog.showOf[id], !seenShows.insert(show).inserted { return nil }
        return catalog.entries[id]?.item
      }
      .prefix(count).map { $0 }
  }

  public func setWatched(_ id: String, watched: Bool) async throws {
    let ids = id.hasPrefix("m/") ? [id] : catalog.episodes(under: id)
    let time = Int(now().timeIntervalSince1970)
    state.updateWatch { state in
      for id in ids {
        var entry = state.entries[id] ?? .init(watched: false)
        entry.watched = watched
        entry.offsetMs = nil
        if watched { entry.lastViewedAt = time }
        state.entries[id] = entry
      }
    }
  }

  public func removeFromContinueWatching(_ id: String) async throws {
    state.updateWatch { $0.entries[id]?.offsetMs = nil }
  }

  /// Saves the position; 90% through counts as watched, as on Plex.
  public func report(_ report: TimelineReport, id: String) async throws {
    let time = Int(now().timeIntervalSince1970)
    state.updateWatch { state in
      var entry = state.entries[id] ?? .init(watched: false)
      if report.durationMs > 0 { entry.durationMs = report.durationMs }
      entry.lastViewedAt = time
      if report.durationMs > 0, Double(report.timeMs) >= 0.9 * Double(report.durationMs) {
        entry.watched = true
        entry.offsetMs = nil
      } else if report.timeMs > 0 {
        entry.watched = false
        entry.offsetMs = report.timeMs
      }
      state.entries[id] = entry
    }
  }

  /// "f/<path in share>" → the file server's URL for it.
  public func stream(_ key: String) -> StreamRequest? {
    guard key.hasPrefix("f/"), let streamBase = streamBase() else { return nil }
    let path = String(key.dropFirst(2))
    let encoded = path.split(separator: "/", omittingEmptySubsequences: false)
      .map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#;"))) ?? String($0) }
      .joined(separator: "/")
    return URL(string: streamBase.absoluteString + encoded).map { StreamRequest(url: $0) }
  }

  /// Share artwork comes from TMDB, already as full URLs.
  public func imageURL(_ path: String, width: Int, height: Int) -> URL? {
    path.hasPrefix("https://") ? URL(string: path) : nil
  }
}

/// Sorting for sources that list from memory, with Plex's sort names.
enum SourceListing {
  static func sort(_ list: [ShareCatalog.Entry], by sort: String) -> [ShareCatalog.Entry] {
    let parts = sort.split(separator: ":")
    let field = parts.first.map(String.init) ?? "titleSort"
    let descending = parts.count > 1 && parts[1] == "desc"
    let ordered = list.sorted { a, b in
      let byTitle = a.item.title.localizedStandardCompare(b.item.title) == .orderedAscending
      switch field {
      case "addedAt": return a.addedAt != b.addedAt ? a.addedAt < b.addedAt : byTitle
      case "year", "originallyAvailableAt":
        return (a.item.year ?? 0) != (b.item.year ?? 0) ? (a.item.year ?? 0) < (b.item.year ?? 0) : byTitle
      case "audienceRating", "rating":
        return (a.item.audienceRating ?? 0) != (b.item.audienceRating ?? 0)
          ? (a.item.audienceRating ?? 0) < (b.item.audienceRating ?? 0) : byTitle
      case "duration":
        return (a.item.duration ?? 0) != (b.item.duration ?? 0) ? (a.item.duration ?? 0) < (b.item.duration ?? 0) : byTitle
      case "lastViewedAt":
        return (a.item.lastViewedAt ?? 0) != (b.item.lastViewedAt ?? 0)
          ? (a.item.lastViewedAt ?? 0) < (b.item.lastViewedAt ?? 0) : byTitle
      default: return byTitle
      }
    }
    return descending ? ordered.reversed() : ordered
  }
}
