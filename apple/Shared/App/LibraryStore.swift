import AstraKit
import Foundation
import Observation

/// Home rows, libraries and a small metadata cache for the connected server.
@MainActor
@Observable
final class LibraryStore {
  let client: PlexServerClient

  private(set) var continueWatching: [PlexMetadata] = []
  private(set) var hubs: [PlexHub] = []
  private(set) var hero: [PlexMetadata] = []
  private(set) var sections: [PlexLibrarySection] = []
  private(set) var isLoadingHome = false
  private(set) var homeError: String?

  private var detailCache: [String: PlexMetadata] = [:]

  // MARK: Streaming-service switcher

  /// Nil when the build has no TMDB token; the switcher is hidden then.
  let tmdb: TMDBClient?
  /// Nil is "For You", the Plex home.
  private(set) var selectedService: StreamingService?
  private(set) var isLoadingService = false
  private var serviceContent: [String: (hero: [PlexMetadata], hubs: [PlexHub])] = [:]
  /// Every movie and show on the server by TMDB key ("movie:603"), built on first use.
  private var libraryIndex: [String: PlexMetadata]?

  static let serviceKey = "astra.home.service"

  init(client: PlexServerClient, tmdbToken: String? = LibraryStore.bundledTMDBToken) {
    self.client = client
    tmdb = tmdbToken.flatMap { $0.isEmpty || $0.hasPrefix("$(") ? nil : TMDBClient(token: $0) }
    if tmdb != nil { selectedService = StreamingService.byID(UserDefaults.standard.string(forKey: Self.serviceKey)) }
  }

  /// The TMDB read token the build put in Info.plist (`TMDB_TOKEN` build setting).
  nonisolated static var bundledTMDBToken: String? {
    Bundle.main.object(forInfoDictionaryKey: "AstraTMDBToken") as? String
  }

  /// What Home shows for the current switcher choice. Only titles on the Plex server.
  var homeHero: [PlexMetadata] {
    guard let selectedService else { return hero }
    return serviceContent[selectedService.id]?.hero ?? []
  }

  var homeContinueWatching: [PlexMetadata] { selectedService == nil ? continueWatching : [] }

  var homeRows: [PlexHub] {
    guard let selectedService else { return hubs }
    return serviceContent[selectedService.id]?.hubs ?? []
  }

  func select(_ service: StreamingService?) async {
    guard service != selectedService else { return }
    selectedService = service
    UserDefaults.standard.set(service?.id, forKey: Self.serviceKey)
    await loadService()
  }

  /// A service's rows: what TMDB lists on that service (the first 100 by
  /// popularity and 60 by rating, per kind), kept only when the title is on
  /// the Plex server, shown as the Plex item.
  func loadService(force: Bool = false) async {
    guard let tmdb, let service = selectedService else { return }
    if !force, serviceContent[service.id] != nil { return }
    isLoadingService = true
    defer { isLoadingService = false }
    let index = await loadLibraryIndex()

    func pages(_ kind: TMDBItem.Kind, topRated: Bool, count: Int) async -> [TMDBItem] {
      await withTaskGroup(of: (Int, [TMDBItem]).self) { group in
        for page in 1...count {
          group.addTask { (page, (try? await tmdb.onService(service, kind, topRated: topRated, page: page)) ?? []) }
        }
        var byPage: [Int: [TMDBItem]] = [:]
        for await (page, items) in group { byPage[page] = items }
        return (1...count).flatMap { byPage[$0] ?? [] }
      }
    }
    func onServer(_ items: [TMDBItem]) -> [PlexMetadata] {
      items.compactMap { index["\($0.kind.rawValue):\($0.tmdbID)"] }
    }

    async let m = pages(.movie, topRated: false, count: 5)
    async let t = pages(.tv, topRated: false, count: 5)
    async let tm = pages(.movie, topRated: true, count: 3)
    async let ts = pages(.tv, topRated: true, count: 3)
    let movies = onServer(await m)
    let shows = onServer(await t)
    let top = Self.interleave(onServer(await ts), onServer(await tm))
    let popular = Self.interleave(shows, movies)

    // Each title once across the service's rows, in row order.
    var dedup = HomeDeduplicator()
    let rows = [
      PlexHub(hubIdentifier: "\(service.id).popular", title: "Popular on \(service.label)", items: dedup.filter(popular)),
      PlexHub(hubIdentifier: "\(service.id).tv", title: "TV Shows on \(service.label)", items: dedup.filter(shows)),
      PlexHub(hubIdentifier: "\(service.id).movies", title: "Movies on \(service.label)", items: dedup.filter(movies)),
      PlexHub(hubIdentifier: "\(service.id).top", title: "Top Rated on \(service.label)", items: dedup.filter(top)),
    ].filter { !$0.items.isEmpty }
    // The hero shows the most popular ones, loaded in full for their versions.
    var hero: [PlexMetadata] = []
    for item in popular.prefix(6) {
      hero.append((try? await details(item.ratingKey)) ?? item)
    }
    serviceContent[service.id] = (hero, rows)
  }

  private func loadLibraryIndex() async -> [String: PlexMetadata] {
    if let libraryIndex { return libraryIndex }
    var index: [String: PlexMetadata] = [:]
    for section in sections {
      let items = (try? await client.libraryItems(sectionKey: section.key, start: 0, size: 20_000)) ?? []
      for item in items {
        if let key = item.tmdbKey, index[key] == nil { index[key] = item }
      }
    }
    libraryIndex = index
    return index
  }

  static func interleave(_ a: [PlexMetadata], _ b: [PlexMetadata]) -> [PlexMetadata] {
    var out: [PlexMetadata] = []
    var seen = Set<String>()
    for i in 0..<max(a.count, b.count) {
      for list in [a, b] where i < list.count && seen.insert(list[i].id).inserted {
        out.append(list[i])
      }
    }
    return out
  }

  // MARK: Artwork from TMDB

  enum ArtKind { case poster, backdrop, heroBackdrop, logo }

  private var artwork: [String: TMDBArtwork] = [:]
  private var artworkTasks: [String: Task<TMDBArtwork?, Never>] = [:]

  /// TMDB's artwork for a movie or show, fetched once per title.
  func tmdbArtwork(for item: PlexMetadata) async -> TMDBArtwork? {
    guard let tmdb, let key = item.tmdbKey else { return nil }
    if let hit = artwork[key] { return hit }
    if let running = artworkTasks[key] { return await running.value }
    let parts = key.split(separator: ":")
    guard parts.count == 2, let id = Int(parts[1]), let kind = TMDBItem.Kind(rawValue: String(parts[0])) else {
      return nil
    }
    let task = Task { try? await tmdb.artwork(id: id, kind: kind) }
    artworkTasks[key] = task
    let result = await task.value
    artworkTasks[key] = nil
    if let result { artwork[key] = result }
    return result
  }

  /// The artwork URL for a card or header: TMDB's when it has one, else Plex's.
  /// Episodes keep Plex's stills.
  func artworkURL(for item: PlexMetadata, _ kind: ArtKind, width: CGFloat, height: CGFloat) async -> URL? {
    if let art = await tmdbArtwork(for: item) {
      let url: URL? =
        switch kind {
        case .poster: TMDBArtwork.url(art.posterPath, size: "w500")
        case .backdrop: TMDBArtwork.url(art.backdropPath, size: "w1280")
        case .heroBackdrop: TMDBArtwork.url(art.backdropPath, size: "original")
        case .logo: TMDBArtwork.url(art.logoPath, size: "w500")
        }
      if let url { return url }
    }
    let plexPath: String? =
      switch kind {
      case .poster: item.poster
      case .backdrop, .heroBackdrop: item.backdrop
      case .logo: item.clearLogo
      }
    return imageURL(plexPath, width: width, height: height)
  }

  /// Finds a TMDB title on the Plex server: TMDB id first, then title and year.
  func resolve(_ item: PlexMetadata) async throws -> PlexMetadata {
    guard item.isCatalogOnly else { return item }
    let tmdbID = item.guids.first?.id
    let results = ((try? await client.search(item.title)) ?? []).filter { $0.type == item.type }
    let title = item.title.lowercased()
    let match =
      results.first { $0.guids.contains { $0.id == tmdbID } }
      ?? results.first { $0.title.lowercased() == title && abs(($0.year ?? 0) - (item.year ?? 0)) <= 1 }
      ?? (item.year == nil ? results.first { $0.title.lowercased() == title } : nil)
    guard let match else { throw CatalogError.notOnServer(item.title) }
    return match
  }

  enum CatalogError: LocalizedError {
    case notOnServer(String)
    var errorDescription: String? {
      switch self {
      case .notOnServer(let title): "“\(title)” isn't on your Plex server."
      }
    }
  }

  func loadHome() async {
    isLoadingHome = hubs.isEmpty
    homeError = nil
    async let continueTask = client.continueWatching()
    async let hubsTask = client.homeHubs()
    async let sectionsTask = client.librarySections()

    let loadedContinue = (try? await continueTask) ?? []
    let loadedSections = (try? await sectionsTask) ?? []
    do {
      let loadedHubs = try await hubsTask
      let rows = await Self.deduplicatedRows(
        continueWatching: loadedContinue.isEmpty
          ? loadedHubs.first(where: \.isContinueWatching)?.items ?? [] : loadedContinue,
        hubs: loadedHubs.filter { !$0.isContinueWatching },
        more: { [client] key, start in (try? await client.hubItems(key: key, start: start)) ?? [] })
      continueWatching = rows.continueWatching
      hubs = rows.hubs
      sections = loadedSections
      hero = await pickHero(from: hubs)
      await loadService()
    } catch {
      homeError = error.localizedDescription
    }
    isLoadingHome = false
  }

  /// Rows with every title shown once across the whole page, in Plex's row
  /// order. Continue Watching claims its titles first. A row left short by
  /// de-duplication loads more of its own items (up to three more pages)
  /// instead of repeating titles; a row left empty is dropped.
  static func deduplicatedRows(
    continueWatching: [PlexMetadata], hubs: [PlexHub], minimumPerRow: Int = 10,
    more: (String, Int) async -> [PlexMetadata]
  ) async -> (continueWatching: [PlexMetadata], hubs: [PlexHub]) {
    var dedup = HomeDeduplicator()
    let keptContinue = dedup.filter(continueWatching)
    var keptHubs: [PlexHub] = []
    for var hub in hubs {
      var items = dedup.filter(hub.items)
      var offset = hub.items.count
      var pages = 0
      while items.count < minimumPerRow, hub.more == true, let key = hub.key, pages < 3 {
        let page = await more(key, offset)
        if page.isEmpty { break }
        offset += page.count
        pages += 1
        items += dedup.filter(page)
      }
      hub.items = items
      if !items.isEmpty { keptHubs.append(hub) }
    }
    return (keptContinue, keptHubs)
  }

  /// Up to five recent movies or shows with backdrops, loaded in full so the
  /// hero can show clear logos.
  private func pickHero(from hubs: [PlexHub]) async -> [PlexMetadata] {
    let recent = hubs.filter { $0.hubIdentifier.contains("recentlyadded") || $0.hubIdentifier.contains("recentlyAdded") }
    let pool = (recent.isEmpty ? hubs : recent).flatMap(\.items)
    var seen = Set<String>()
    let candidates = pool.compactMap { item -> PlexMetadata? in
      // Show the show, not one of its episodes.
      if item.type == .episode || item.type == .season {
        guard let key = item.grandparentRatingKey ?? item.parentRatingKey else { return nil }
        return seen.insert(key).inserted ? PlexMetadata(ratingKey: key, type: .show, title: item.displayTitle) : nil
      }
      guard item.type == .movie || item.type == .show else { return nil }
      return seen.insert(item.ratingKey).inserted ? item : nil
    }
    .prefix(5)

    var full: [PlexMetadata] = []
    for item in candidates {
      if let loaded = try? await details(item.ratingKey), loaded.backdrop != nil { full.append(loaded) }
    }
    return full
  }

  func details(_ ratingKey: String, refresh: Bool = false) async throws -> PlexMetadata {
    if !refresh, let cached = detailCache[ratingKey] { return cached }
    let item = try await client.metadata(ratingKey: ratingKey)
    detailCache[ratingKey] = item
    return item
  }

  func children(of ratingKey: String) async throws -> [PlexMetadata] {
    try await client.children(ratingKey: ratingKey)
  }

  func related(_ ratingKey: String) async -> [PlexHub] {
    (try? await client.relatedHubs(ratingKey: ratingKey)) ?? []
  }

  /// The item Play should start: the movie or episode itself, or for a show
  /// or season the next unwatched episode (Plex's On Deck), else the first.
  func playable(for item: PlexMetadata) async throws -> PlexMetadata {
    switch item.type {
    case .movie, .episode:
      return item.media.isEmpty ? try await details(item.ratingKey, refresh: true) : item
    case .show, .season:
      var episodes: [PlexMetadata] = []
      if item.type == .show {
        let seasons = try await children(of: item.ratingKey).filter { $0.type == .season }
        for season in seasons where (season.index ?? 1) > 0 || seasons.count == 1 {
          episodes += try await children(of: season.ratingKey)
          if episodes.contains(where: { !$0.isWatched }) { break }
        }
      } else {
        episodes = try await children(of: item.ratingKey)
      }
      let next = episodes.first { ($0.viewOffset ?? 0) > 0 } ?? episodes.first { !$0.isWatched } ?? episodes.first
      guard let next else { throw PlexError.nothingToPlay }
      return try await details(next.ratingKey, refresh: true)
    default:
      throw PlexError.nothingToPlay
    }
  }

  func setWatched(_ item: PlexMetadata, watched: Bool) async {
    do {
      if watched {
        try await client.markWatched(ratingKey: item.ratingKey)
      } else {
        try await client.markUnwatched(ratingKey: item.ratingKey)
      }
      detailCache[item.ratingKey] = nil
      await loadHome()
    } catch {
      homeError = error.localizedDescription
    }
  }

  /// Called when the player closes, so Continue Watching shows the new position.
  func playbackEnded(ratingKey: String) {
    detailCache[ratingKey] = nil
    Task { await loadHome() }
  }

  /// Plex artwork sized for a frame, in steps (see `ImageSize.bucketed`) so a
  /// resizing window or an animating layout doesn't refetch on every frame.
  func imageURL(_ path: String?, width: CGFloat, height: CGFloat, scale: CGFloat = 2) -> URL? {
    // TMDB artwork is already a full URL at a fixed size.
    if let path, path.hasPrefix("https://") { return URL(string: path) }
    guard let size = ImageSize.bucketed(width: Double(width * scale), height: Double(height * scale)) else {
      return nil
    }
    return client.imageURL(path, width: size.width, height: size.height)
  }
}
