import AstraKit
import Foundation
import Observation

/// Home rows, libraries and a small metadata cache for one server session.
///
/// A store belongs to exactly one validated `ServerSession`. Switching servers
/// makes a new store and closes this one: `close()` cancels its work and every
/// late response is dropped, so an old server can never overwrite the new one.
@MainActor
@Observable
final class LibraryStore {
  let client: PlexServerClient
  /// The session this store belongs to (see `ServerSession.generation`).
  let generation: Int
  private(set) var isClosed = false

  private(set) var continueWatching: [PlexMetadata] = []
  private(set) var hubs: [PlexHub] = []
  private(set) var hero: [PlexMetadata] = []
  private(set) var sections: [PlexLibrarySection] = []
  private(set) var isLoadingHome = false
  /// True while the For You hero's trending titles are being matched to the server.
  private(set) var isLoadingHero = false
  private(set) var homeError: String?

  private var detailCache: [String: PlexMetadata] = [:]
  /// The newest Home load; an older one that finishes late is ignored.
  @ObservationIgnored private var homeGeneration = Generation()
  @ObservationIgnored private var background: [Int: Task<Void, Never>] = [:]
  @ObservationIgnored private var nextBackgroundID = 0

  // MARK: Streaming-service switcher

  /// Nil when the build has no TMDB token; the switcher is hidden then.
  let tmdb: TMDBClient?
  /// Nil is "For You", the Plex home.
  private(set) var selectedService: StreamingService?
  /// The service whose rows are loading right now.
  private(set) var loadingServiceID: String?
  private(set) var serviceErrors: [String: String] = [:]
  private var serviceContent: [String: (hero: [PlexMetadata], hubs: [PlexHub])] = [:]
  @ObservationIgnored private var serviceGeneration = Generation()
  @ObservationIgnored private var serviceTask: Task<Void, Never>?
  /// Every movie and show on the server by TMDB key ("movie:603"), built once, on first use.
  @ObservationIgnored private var libraryIndex: [String: PlexMetadata]?
  /// The read in progress; every service waiting for the index shares it.
  @ObservationIgnored private var indexTask: Task<[String: PlexMetadata], Error>?
  /// TMDB's trending titles (today, then this week), fetched once per session.
  @ObservationIgnored private var trendingTask: Task<[TMDBItem], Never>?
  /// Poster and backdrop paths that came with TMDB's lists, so cards need no extra lookup.
  @ObservationIgnored private var seededArt: [String: TMDBArtwork] = [:]

  static let serviceKey = "astra.home.service"

  init(session: ServerSession, tmdbToken: String? = LibraryStore.bundledTMDBToken) {
    client = session.client
    generation = session.generation
    // Movies and Shows work straight away, whatever happens to the Home rows.
    sections = session.sections
    tmdb = tmdbToken.flatMap { $0.isEmpty || $0.hasPrefix("$(") ? nil : TMDBClient(token: $0) }
    if tmdb != nil { selectedService = StreamingService.byID(UserDefaults.standard.string(forKey: Self.serviceKey)) }
    // A saved service starts loading now, so Home never flashes "Nothing from…" first.
    startService(force: false)
  }

  /// Stops everything this store started. Called when another server replaces it.
  func close() {
    isClosed = true
    serviceTask?.cancel()
    indexTask?.cancel()
    background.values.forEach { $0.cancel() }
    background.removeAll()
    loadingServiceID = nil
    isLoadingHome = false
  }

  /// The TMDB read token the build put in Info.plist (`TMDB_TOKEN` build setting).
  nonisolated static var bundledTMDBToken: String? {
    Bundle.main.object(forInfoDictionaryKey: "AstraTMDBToken") as? String
  }

  private func describe(_ error: Error) -> String {
    PlexError.describe(error, server: client.serverName)
  }

  /// Runs work tied to this store's lifetime; `close()` cancels it.
  private func spawn(_ work: @escaping @MainActor () async -> Void) {
    guard !isClosed else { return }
    nextBackgroundID += 1
    let id = nextBackgroundID
    background[id] = Task { [weak self] in
      await work()
      self?.background[id] = nil
    }
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

  var isLoadingService: Bool { selectedService != nil && loadingServiceID == selectedService?.id }

  /// Why the selected service's rows didn't load, if they didn't.
  var serviceError: String? { selectedService.flatMap { serviceErrors[$0.id] } }

  /// Switches Home to a service. Returns at once: the rows load behind, and a
  /// service already loaded shows its rows immediately.
  func select(_ service: StreamingService?) {
    guard service != selectedService else { return }
    selectedService = service
    UserDefaults.standard.set(service?.id, forKey: Self.serviceKey)
    startService(force: false)
  }

  /// Loads the selected service again; its current rows stay on screen meanwhile.
  func retryService() {
    startService(force: true)
  }

  private func startService(force: Bool) {
    // A newer choice replaces the older request instead of queueing behind it.
    serviceTask?.cancel()
    let token = serviceGeneration.next()
    guard !isClosed, tmdb != nil, let service = selectedService,
      force || serviceContent[service.id] == nil
    else {
      loadingServiceID = nil
      return
    }
    loadingServiceID = service.id
    serviceErrors[service.id] = nil
    serviceTask = Task { [weak self] in
      await self?.loadService(service, token: token)
    }
  }

  /// A service's rows: what TMDB lists on that service (the first 100 by
  /// popularity and 60 by rating, per kind), kept only when the title is on
  /// the Plex server, shown as the Plex item.
  private func loadService(_ service: StreamingService, token: Int) async {
    defer {
      if serviceGeneration.isCurrent(token) { loadingServiceID = nil }
    }
    guard let tmdb else { return }
    let index: [String: PlexMetadata]
    do {
      index = try await loadLibraryIndex()
    } catch {
      if !Task.isCancelled, !isClosed {
        serviceErrors[service.id] = "Couldn't read your Plex libraries. \(describe(error))"
      }
      return
    }
    guard !Task.isCancelled, !isClosed else { return }

    func pages(_ kind: TMDBItem.Kind, topRated: Bool, count: Int) async -> (items: [TMDBItem], failed: Int) {
      await withTaskGroup(of: (Int, [TMDBItem]?).self) { group in
        for page in 1...count {
          group.addTask { (page, try? await tmdb.onService(service, kind, topRated: topRated, page: page)) }
        }
        var byPage: [Int: [TMDBItem]] = [:]
        var failed = 0
        for await (page, items) in group {
          if let items { byPage[page] = items } else { failed += 1 }
        }
        return ((1...count).flatMap { byPage[$0] ?? [] }, failed)
      }
    }
    func onServer(_ items: [TMDBItem]) -> [PlexMetadata] {
      items.compactMap { tmdbItem in
        let key = "\(tmdbItem.kind.rawValue):\(tmdbItem.tmdbID)"
        guard let item = index[key] else { return nil }
        if seededArt[key] == nil {
          seededArt[key] = TMDBArtwork(
            posterPath: tmdbItem.posterPath, backdropPath: tmdbItem.backdropPath, logoPath: nil)
        }
        return item
      }
    }

    async let m = pages(.movie, topRated: false, count: 5)
    async let t = pages(.tv, topRated: false, count: 5)
    async let tm = pages(.movie, topRated: true, count: 3)
    async let ts = pages(.tv, topRated: true, count: 3)
    let lists = await [m, t, tm, ts]
    guard !Task.isCancelled, !isClosed else { return }
    if lists.allSatisfy({ $0.items.isEmpty }) && lists.contains(where: { $0.failed > 0 }) {
      serviceErrors[service.id] = "TMDB didn't answer, so \(service.label)'s lists couldn't load. Try again in a moment."
      return
    }
    let movies = onServer(lists[0].items)
    let shows = onServer(lists[1].items)
    let top = Self.interleave(onServer(lists[3].items), onServer(lists[2].items))
    let popular = Self.interleave(shows, movies)

    // Each title once across the service's rows, in row order.
    var dedup = HomeDeduplicator()
    let rows = [
      PlexHub(hubIdentifier: "\(service.id).popular", title: "Popular on \(service.label)", items: dedup.filter(popular)),
      PlexHub(hubIdentifier: "\(service.id).tv", title: "TV Shows on \(service.label)", items: dedup.filter(shows)),
      PlexHub(hubIdentifier: "\(service.id).movies", title: "Movies on \(service.label)", items: dedup.filter(movies)),
      PlexHub(hubIdentifier: "\(service.id).top", title: "Top Rated on \(service.label)", items: dedup.filter(top)),
    ].filter { !$0.items.isEmpty }
    // The hero: this service's titles that are trending now, else its recent
    // popular ones; loaded in full (in parallel) for their versions.
    let trending = await loadTrending()
    let heroPicks = TrendingHero.pick(trending: trending, service: popular, currentYear: Self.currentYear)
    let hero = await loadInFull(heroPicks)
    guard !Task.isCancelled, !isClosed else { return }
    serviceContent[service.id] = (hero, rows)
  }

  static var currentYear: Int { Calendar.current.component(.year, from: Date()) }

  /// What's trending on TMDB, today first, then this week; each title once.
  private func loadTrending() async -> [TMDBItem] {
    guard let tmdb else { return [] }
    if let trendingTask { return await trendingTask.value }
    let task = Task { () -> [TMDBItem] in
      let requests: [(TMDBClient.TrendingWindow, Int)] = [(.day, 1), (.day, 2), (.week, 1), (.week, 2), (.week, 3), (.week, 4), (.week, 5)]
      let pages = await withTaskGroup(of: (Int, [TMDBItem]).self) { group in
        for (i, request) in requests.enumerated() {
          group.addTask { (i, (try? await tmdb.trending(request.0, page: request.1)) ?? []) }
        }
        var byIndex: [Int: [TMDBItem]] = [:]
        for await (i, items) in group { byIndex[i] = items }
        return requests.indices.flatMap { byIndex[$0] ?? [] }
      }
      var seen = Set<String>()
      return pages.filter { seen.insert($0.id).inserted }
    }
    trendingTask = task
    let result = await task.value
    // A failed fetch isn't kept, so the next load tries again.
    if result.isEmpty { trendingTask = nil }
    return result
  }

  /// The For You hero: trending titles that are on the server. Without TMDB,
  /// or when none match, recent additions released in the last two years.
  private func loadHero(fallback hubs: [PlexHub], isCurrent: @escaping () -> Bool) async {
    isLoadingHero = hero.isEmpty
    // Cleared whatever happens: a newer load that fails never reaches here.
    defer { isLoadingHero = false }
    var picks: [PlexMetadata] = []
    if tmdb != nil, let index = try? await loadLibraryIndex() {
      picks = await loadInFull(TrendingHero.pick(trending: await loadTrending(), index: index))
        .filter { $0.backdrop != nil }
    }
    if picks.isEmpty { picks = await pickHero(from: hubs) }
    guard isCurrent() else { return }
    if !picks.isEmpty || hero.isEmpty { hero = picks }
  }

  /// The library index, read once. Concurrent callers share one read; a
  /// failed read is not cached, so the next service tries again.
  private func loadLibraryIndex() async throws -> [String: PlexMetadata] {
    if let libraryIndex { return libraryIndex }
    if let indexTask { return try await indexTask.value }
    let client = client
    let sections = sections
    let task = Task { try await LibraryIndexer.build(client: client, sections: sections) }
    indexTask = task
    defer { indexTask = nil }
    let index = try await task.value
    if !isClosed { libraryIndex = index }
    return index
  }

  /// Full metadata (versions, logos) for a few items, fetched in parallel, kept in order.
  private func loadInFull(_ items: [PlexMetadata]) async -> [PlexMetadata] {
    await withTaskGroup(of: (Int, PlexMetadata).self) { group in
      for (i, item) in items.enumerated() {
        group.addTask { [self] in (i, (try? await details(item.ratingKey)) ?? item) }
      }
      var out = [PlexMetadata?](repeating: nil, count: items.count)
      for await (i, item) in group { out[i] = item }
      return out.compactMap { $0 }
    }
  }

  /// Looks up TMDB artwork for the titles on screen ahead of time, eight at
  /// a time, so cards fade in together instead of one by one.
  func prefetchArtwork(_ items: [PlexMetadata]) async {
    var seen = Set<String>()
    let targets = items.filter { item in
      guard let key = item.tmdbKey, artwork[key] == nil, seededArt[key] == nil else { return false }
      return seen.insert(key).inserted
    }
    for start in stride(from: 0, to: targets.count, by: 8) {
      guard !Task.isCancelled else { return }
      let chunk = targets[start..<min(start + 8, targets.count)]
      await withTaskGroup(of: Void.self) { group in
        for item in chunk {
          group.addTask { [self] in _ = await tmdbArtwork(for: item) }
        }
      }
    }
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
    // Full artwork if fetched; else the poster and backdrop TMDB's lists gave
    // (no logo in those); else one lookup.
    var art = item.tmdbKey.flatMap { artwork[$0] }
    if art == nil, kind != .logo { art = item.tmdbKey.flatMap { seededArt[$0] } }
    if art == nil { art = await tmdbArtwork(for: item) }
    if let art {
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

  /// Loads the For You rows. The page shows what it has as soon as the rows
  /// arrive; artwork, the library index and the chosen service load behind it.
  /// A newer call (pull to refresh, playback ended) supersedes an older one.
  func loadHome() async {
    guard !isClosed else { return }
    let token = homeGeneration.next()
    let isCurrent = { [weak self] in self.map { !$0.isClosed && $0.homeGeneration.isCurrent(token) } ?? false }
    // The spinner only covers an empty page; a reload keeps the rows on screen.
    isLoadingHome = hubs.isEmpty && continueWatching.isEmpty
    homeError = nil
    // A saved streaming service loads alongside, not after, the For You rows.
    if let service = selectedService, serviceContent[service.id] == nil, loadingServiceID == nil {
      startService(force: false)
    }
    async let continueTask = client.continueWatching()
    async let hubsTask = client.homeHubs()
    async let sectionsTask = client.librarySections()

    let loadedContinue = (try? await continueTask) ?? []
    let loadedSections = (try? await sectionsTask) ?? []
    guard isCurrent() else { return }
    // Movies and Shows keep working even when the Home rows fail.
    if !loadedSections.isEmpty { sections = loadedSections }
    do {
      let loadedHubs = try await hubsTask
      let rows = await Self.deduplicatedRows(
        continueWatching: loadedContinue.isEmpty
          ? loadedHubs.first(where: \.isContinueWatching)?.items ?? [] : loadedContinue,
        hubs: loadedHubs.filter { !$0.isContinueWatching },
        more: { [client] key, start in (try? await client.hubItems(key: key, start: start)) ?? [] })
      guard isCurrent() else { return }
      continueWatching = rows.continueWatching
      hubs = rows.hubs
      isLoadingHome = false
      await loadHero(fallback: rows.hubs, isCurrent: isCurrent)
    } catch {
      guard isCurrent() else { return }
      isLoadingHero = false
      homeError = describe(error)
    }
    isLoadingHome = false
    spawn { [weak self] in
      guard let self else { return }
      await prefetchArtwork(hero + continueWatching + hubs.flatMap(\.items))
    }
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

  /// The fallback hero: up to five recently added movies or shows released in
  /// the last two years, with backdrops, loaded in full for their logos.
  private func pickHero(from hubs: [PlexHub]) async -> [PlexMetadata] {
    let recent = hubs.filter { $0.hubIdentifier.contains("recentlyadded") || $0.hubIdentifier.contains("recentlyAdded") }
    let pool = (recent.isEmpty ? hubs : recent).flatMap(\.items)
    var seen = Set<String>()
    let candidates = pool.compactMap { item -> PlexMetadata? in
      // Show the show, not one of its episodes.
      if item.type == .episode || item.type == .season {
        guard let key = item.grandparentRatingKey ?? item.parentRatingKey,
          let year = item.year, year >= Self.currentYear - 2
        else { return nil }
        return seen.insert(key).inserted ? PlexMetadata(ratingKey: key, type: .show, title: item.displayTitle) : nil
      }
      guard item.type == .movie || item.type == .show else { return nil }
      guard let year = item.year, year >= Self.currentYear - 2 else { return nil }
      return seen.insert(item.ratingKey).inserted ? item : nil
    }
    .prefix(5)

    return await loadInFull(Array(candidates)).filter { $0.backdrop != nil }
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
      homeError = describe(error)
    }
  }

  /// Called when the player closes, so Continue Watching shows the new position.
  func playbackEnded(ratingKey: String) {
    detailCache[ratingKey] = nil
    spawn { [weak self] in await self?.loadHome() }
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
