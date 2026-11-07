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
  /// The server's clientIdentifier; names its saved library index.
  let serverID: String
  private(set) var isClosed = false

  private(set) var continueWatching: [PlexMetadata] = []
  private(set) var hubs: [PlexHub] = []
  private(set) var hero: [PlexMetadata] = []
  /// For You's numbered Top 10 rows (TMDB trending this week), playable ones from the server.
  private(set) var topTen: (movies: [PlexMetadata], shows: [PlexMetadata]) = ([], [])
  /// Astra (KP, 2026-11-07): For You's single "Top 10 This Week" row, movies
  /// and series together in trending order, like the streaming apps.
  private(set) var topTenAll: [PlexMetadata] = []
  /// For You's rows after the Top 10: Recommended For You, Because You
  /// Watched… and Hidden Gems, all from the library (see `ForYou`).
  private(set) var forYouRows: [PlexHub] = []
  /// Every library on the server.
  private(set) var allSections: [PlexLibrarySection] = []
  /// Settings → Content → Library Quality, read when the store is made; a
  /// change makes a new store (AppModel.libraryQualityChanged).
  let libraryQuality = LibraryQuality.stored()
  /// One copy of each title for this device's Library Quality.
  var filter: LibraryFilter { LibraryFilter(quality: libraryQuality, sections: allSections) }
  /// The libraries the Movies and Shows tabs browse.
  var sections: [PlexLibrarySection] { filter.browseSections(allSections) }
  private(set) var isLoadingHome = false
  /// True while the For You hero's trending titles are being matched to the server.
  private(set) var isLoadingHero = false
  private(set) var homeError: String?

  private var detailCache: [String: PlexMetadata] = [:]
  /// Astra (KP, 2026-11-07): what a Details card needs besides the item,
  /// read ahead for the hero and Top 10 so their Details open at once.
  /// Cleared whenever watched state changes.
  @ObservationIgnored private var childrenCache: [String: [PlexMetadata]] = [:]
  @ObservationIgnored private var relatedCache: [String: [PlexHub]] = [:]
  /// A streaming title's server ratingKey, or nil when it isn't on the server.
  @ObservationIgnored private var resolveCache: [String: String?] = [:]
  @ObservationIgnored private var prewarmed: Set<String> = []
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
  private var serviceContent: [String: (hero: [PlexMetadata], topTen: (movies: [PlexMetadata], shows: [PlexMetadata]), hubs: [PlexHub])] = [:]
  @ObservationIgnored private var serviceGeneration = Generation()
  @ObservationIgnored private var serviceTask: Task<Void, Never>?
  /// Every movie and show on the server by TMDB key ("movie:603"), built once, on first use.
  @ObservationIgnored private var libraryIndex: [String: PlexMetadata]?
  /// The read in progress; every service waiting for the index shares it.
  @ObservationIgnored private var indexTask: Task<[String: PlexMetadata], Error>?
  /// The first read of the index; cancelled by `close()`.
  @ObservationIgnored private var indexBuild: Task<(items: [String: PlexMetadata], stale: Bool), Error>?
  /// The background re-read of a stale saved index; cancelled by `close()`.
  @ObservationIgnored private var refreshTask: Task<[String: PlexMetadata], Error>?
  /// Each built service's TMDB lists, kept so they can be matched again when the index changes.
  @ObservationIgnored private var serviceLists: [String: [(ServiceCatalog.Row, [TMDBItem])]] = [:]
  /// TMDB's trending titles (today, then this week), fetched once per session.
  @ObservationIgnored private var trendingTask: Task<[TMDBItem], Never>?
  /// Poster and backdrop paths that came with TMDB's lists, so cards need no extra lookup.
  @ObservationIgnored private var seededArt: [String: TMDBArtwork] = [:]

  static let serviceKey = "astra.home.service"

  init(session: ServerSession, tmdbToken: String? = LibraryStore.bundledTMDBToken) {
    client = session.client
    generation = session.generation
    serverID = session.serverID
    // Movies and Shows work straight away, whatever happens to the Home rows.
    allSections = session.sections
    tmdb = tmdbToken.flatMap { $0.isEmpty || $0.hasPrefix("$(") ? nil : TMDBClient(token: $0) }
    // Astra (KP, 2026-11-07): Home always opens on For You, never the last service.
    UserDefaults.standard.removeObject(forKey: Self.serviceKey)
  }

  /// Stops everything this store started. Called when another server replaces it.
  func close() {
    isClosed = true
    serviceTask?.cancel()
    indexTask?.cancel()
    refreshTask?.cancel()
    indexBuild?.cancel()
    trendingRefresh?.cancel()
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

  /// What Home shows for the current switcher choice.
  var homeHero: [PlexMetadata] {
    guard let selectedService else { return hero }
    return serviceContent[selectedService.id]?.hero ?? []
  }

  /// The numbered Top 10 for the current tab: For You ranks trending titles
  /// on the server; a service tab ranks what's trending on that service.
  var homeTopTen: [PlexMetadata] {
    let split = homeTopTenSplit
    return split.movies.isEmpty ? split.shows : split.movies
  }

  /// The Top 10 as Movies and Series (KP, 2026-11-07: the Movies / Series
  /// switch on every tab, For You and each service).
  var homeTopTenSplit: (movies: [PlexMetadata], shows: [PlexMetadata]) {
    guard let selectedService else { return topTen }
    return serviceContent[selectedService.id]?.topTen ?? ([], [])
  }

  /// The same on every tab (KP, 2026-11-07).
  var homeContinueWatching: [PlexMetadata] { continueWatching }

  var homeRows: [PlexHub] {
    // Astra (KP, 2026-11-07): For You is the hero, Continue Watching, the
    // Top 10, then rows built from the library; never Plex's own hubs
    // (Recently Added…).
    guard let selectedService else { return forYouRows }
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

  /// A service's rows (see `ServiceCatalog`): everything TMDB lists on that
  /// service, from that service only. A title on the Plex server is shown as
  /// the Plex item (playable); the rest stay TMDB titles, shown with their
  /// play button greyed out. Rows appear as soon as TMDB answers; titles are
  /// matched to the server with the saved library index, or once it is read.
  private func loadService(_ service: StreamingService, token: Int) async {
    defer {
      if serviceGeneration.isCurrent(token) { loadingServiceID = nil }
    }
    guard let tmdb else { return }
    // The index is read alongside TMDB, never before it.
    // Starts reading the index alongside TMDB (shared with every other caller).
    spawn { [weak self] in _ = try? await self?.loadLibraryIndex() }
    let specs = ServiceCatalog.rows(for: service)
    let requests = specs.flatMap(\.requests)
    let fetched = await Self.fetch(requests, on: service, tmdb: tmdb)
    guard !Task.isCancelled, !isClosed else { return }
    if fetched.allSatisfy({ $0.value.isEmpty }) {
      serviceErrors[service.id] = "TMDB didn't answer, so \(service.label)'s lists couldn't load. Try again in a moment."
      return
    }
    let lists = specs.map { spec in
      (spec, ServiceCatalog.merge(spec.requests.map { ($0, fetched[$0] ?? []) }))
    }
    for (_, items) in lists {
      for item in items where seededArt[item.id] == nil {
        seededArt[item.id] = TMDBArtwork(posterPath: item.posterPath, backdropPath: item.backdropPath, logoPath: nil)
      }
    }
    let trending = await loadTrending()
    serviceLists[service.id] = lists
    // Shown now with whatever index is in memory (often the saved one); when
    // the index arrives or changes, setLibraryIndex matches the rows again,
    // even if this tab was left in the meantime.
    await publishService(service, lists: lists, index: libraryIndex ?? [:], trending: trending)
  }

  private func publishService(
    _ service: StreamingService, lists: [(ServiceCatalog.Row, [TMDBItem])], index: [String: PlexMetadata],
    trending: [TMDBItem]
  ) async {
    // Which index these rows are matched with (-1: none yet).
    let usedVersion = !index.isEmpty && index.count == libraryIndex?.count ? indexVersion : -1
    func shown(_ item: TMDBItem) -> PlexMetadata { index[item.id] ?? item.asMetadata }
    // The Top 10 first, then each title once across the service's rows, in row order.
    let popular = lists.first.map { $0.1.map(shown) } ?? []
    // Every list's titles, in row order, so both Movies and Series fill to 10.
    let pool = lists.flatMap { $0.1.map(shown) }
    let topTen = (
      movies: TrendingHero.serviceTopTen(
        trending: trending.filter { $0.kind == .movie }, service: pool.filter { $0.type == .movie }),
      shows: TrendingHero.serviceTopTen(
        trending: trending.filter { $0.kind == .tv }, service: pool.filter { $0.type == .show })
    )
    var dedup = HomeDeduplicator()
    _ = dedup.filter(topTen.movies + topTen.shows)
    let rows = lists.map { spec, items in
      PlexHub(hubIdentifier: spec.id, title: spec.title, items: Array(dedup.filter(items.map(shown)).prefix(30)))
    }
    .filter { !$0.items.isEmpty }
    // The hero: this service's titles trending now, playable ones first.
    let picks = TrendingHero.pick(trending: trending, service: popular, currentYear: Self.currentYear)
    let playable = picks.filter { !$0.isCatalogOnly }
    let heroPicks = playable.count >= 3 ? playable : Array((playable + picks.filter(\.isCatalogOnly)).prefix(8))
    let hero = await loadInFull(heroPicks)
    guard !isClosed else { return }
    serviceContent[service.id] = (hero, topTen, rows)
    serviceIndexVersion[service.id] = usedVersion
    // The index arrived while these rows were being built: match them again.
    if usedVersion != indexVersion, let current = libraryIndex, !current.isEmpty {
      spawn { [weak self] in
        guard let self else { return }
        await self.publishService(service, lists: lists, index: current, trending: trending)
      }
    }
  }

  /// Every discover page, 10 at a time (TMDB rate-limits bursts). A failed page is empty.
  private static func fetch(
    _ requests: [DiscoverRequest], on service: StreamingService, tmdb: TMDBClient
  ) async -> [DiscoverRequest: [TMDBItem]] {
    var out: [DiscoverRequest: [TMDBItem]] = [:]
    for start in stride(from: 0, to: requests.count, by: 10) {
      if Task.isCancelled { break }
      let chunk = requests[start..<min(start + 10, requests.count)]
      await withTaskGroup(of: (DiscoverRequest, [TMDBItem]).self) { group in
        for request in chunk {
          group.addTask { (request, (try? await tmdb.discover(request, on: service)) ?? []) }
        }
        for await (request, items) in group { out[request] = items }
      }
    }
    return out
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

  /// The For You hero: cineby's trending titles in cineby's order (KP,
  /// 2026-11-07: "it should match Cineby specifically"), whether or not
  /// they're on the server; titles not on it get a greyed-out Play. Without
  /// TMDB, recent additions released in the last two years.
  private func loadHero(fallback hubs: [PlexHub], isCurrent: @escaping () -> Bool) async {
    isLoadingHero = hero.isEmpty
    // Cleared whatever happens: a newer load that fails never reaches here.
    defer { isLoadingHero = false }
    // Astra: titles not on the server get a greyed-out Play.
    // Cineby's trending list first (KP's choice), filled out with TMDB's
    // trending this week; TMDB alone when cineby can't be read.
    // The saved library index is a quick disk read: use it so playable titles are marked at once.
    if libraryIndex == nil,
      FileManager.default.fileExists(atPath: indexURL.path)
    {
      _ = try? await loadLibraryIndex()
    }
    let trending = tmdb == nil ? [] : await loadWeekTrending()
    func picks(_ index: [String: PlexMetadata]) async -> [PlexMetadata] {
      await loadInFull(TrendingHero.today(trending: trending, index: index, limit: 5)).filter { $0.backdrop != nil }
    }
    var shown = await picks(libraryIndex ?? [:])
    if shown.isEmpty { shown = await pickHero(from: hubs) }
    guard isCurrent() else { return }
    if !shown.isEmpty || hero.isEmpty { hero = shown }
    topTen = TrendingHero.topTen(trending: trending, index: libraryIndex ?? [:])
    topTenAll = TrendingHero.today(trending: trending, index: libraryIndex ?? [:], limit: 10)
    isLoadingHero = false
    // Once the library index is ready, the titles on the server become playable.
    guard !trending.isEmpty, libraryIndex == nil, let index = try? await loadLibraryIndex(), !index.isEmpty
    else { return }
    let matched = await picks(index)
    guard isCurrent(), !matched.isEmpty else { return }
    hero = matched
    topTen = TrendingHero.topTen(trending: trending, index: index)
    topTenAll = TrendingHero.today(trending: trending, index: index, limit: 10)
  }

  @ObservationIgnored private var weekTrendingTask: Task<[TMDBItem], Never>?
  @ObservationIgnored private var weekTrendingFetched = Date.distantPast
  @ObservationIgnored private var trendingRefresh: Task<Void, Never>?

  nonisolated static var trendingURL: URL { TrendingSnapshot.url(in: indexFolder.deletingLastPathComponent()) }

  /// For You's trending list: cineby's titles first, then TMDB's trending this
  /// week. Astra (KP: "load instantly"): the copy saved on disk is returned at
  /// once and refreshed in the background; Home updates when the new one lands.
  private func loadWeekTrending() async -> [TMDBItem] {
    guard let tmdb else { return [] }
    if let weekTrendingTask, Date().timeIntervalSince(weekTrendingFetched) < TrendingSnapshot.freshFor {
      return await weekTrendingTask.value
    }
    weekTrendingFetched = Date()
    let url = Self.trendingURL
    let saved = await Task.detached(priority: .userInitiated) { TrendingSnapshot.load(from: url) }.value
    if let saved, !saved.items.isEmpty {
      weekTrendingTask = Task { saved.items }
      if !saved.isFresh() { refreshTrending(tmdb: tmdb, saved: saved) }
      return saved.items
    }
    let task = Task.detached(priority: .userInitiated) { await Self.fetchTrending(tmdb: tmdb, saved: nil).items }
    weekTrendingTask = task
    let result = await task.value
    if result.isEmpty { weekTrendingTask = nil }
    return result
  }

  /// Fetches a new list behind the saved one and shows it when it's ready.
  private func refreshTrending(tmdb: TMDBClient, saved: TrendingSnapshot) {
    guard trendingRefresh == nil else { return }
    trendingRefresh = Task { [weak self] in
      let fresh = await Task.detached(priority: .utility) { await Self.fetchTrending(tmdb: tmdb, saved: saved) }.value
      guard let self, !self.isClosed else { return }
      self.trendingRefresh = nil
      guard !fresh.items.isEmpty, fresh.items.map(\.id) != saved.items.map(\.id) else { return }
      self.weekTrendingTask = Task { fresh.items }
      await self.showTrending(fresh.items)
    }
  }

  /// Rebuilds the hero and the Top 10 from a new trending list.
  private func showTrending(_ trending: [TMDBItem]) async {
    let index = libraryIndex ?? [:]
    let shown = await loadInFull(TrendingHero.today(trending: trending, index: index, limit: 5)).filter { $0.backdrop != nil }
    guard !isClosed else { return }
    if !shown.isEmpty { hero = shown }
    topTen = TrendingHero.topTen(trending: trending, index: index)
    topTenAll = TrendingHero.today(trending: trending, index: index, limit: 10)
  }

  /// Reads cineby's page and TMDB's trending in parallel, looks up only the
  /// cineby titles not seen before, and saves the result.
  private nonisolated static func fetchTrending(tmdb: TMDBClient, saved: TrendingSnapshot?) async -> TrendingSnapshot {
    var details = saved?.details ?? [:]
    let entriesTask = Task { (try? await CinebyTrending.fetch()) ?? [] }
    let pages = await withTaskGroup(of: (Int, [TMDBItem]).self) { group in
      for page in 1...3 {
        group.addTask { (page, (try? await tmdb.trending(.week, page: page)) ?? []) }
      }
      var byPage: [Int: [TMDBItem]] = [:]
      for await (page, items) in group { byPage[page] = items }
      return (1...3).flatMap { byPage[$0] ?? [] }
    }
    let entries = Array(await entriesTask.value.prefix(30))
    // TMDB's own trending results already carry full details.
    for item in pages where details[item.id] == nil { details[item.id] = item }
    let missing = entries.filter { details[$0.id]?.backdropPath == nil }
    let looked = await withTaskGroup(of: (String, TMDBItem?).self) { group in
      for entry in missing {
        group.addTask { (entry.id, try? await tmdb.item(id: entry.tmdbID, kind: entry.kind)) }
      }
      var out: [String: TMDBItem] = [:]
      for await (id, item) in group { if let item { out[id] = item } }
      return out
    }
    details.merge(looked) { _, new in new }
    // A title TMDB didn't answer for still shows with the page's own title and poster.
    let cineby = entries.compactMap { details[$0.id] ?? $0.item }
    let items = CinebyTrending.merge(cineby, fill: pages)
    let snapshot = TrendingSnapshot(
      savedAt: Date(), items: items, details: TrendingSnapshot.trimmed(details, keeping: items.map(\.id)))
    if !items.isEmpty { try? snapshot.save(to: trendingURL) }
    return snapshot
  }

  /// The library index, read once. Concurrent callers share one read; a
  /// failed read is not cached, so the next service tries again.
  private func loadLibraryIndex() async throws -> [String: PlexMetadata] {
    if let libraryIndex { return libraryIndex }
    if let indexTask { return try await indexTask.value }
    // Set before any await, so every caller shares this one read.
    let client = client
    let sections = filter.indexSections(allSections)
    let url = indexURL
    let task = Task.detached(priority: .userInitiated) { () throws -> (items: [String: PlexMetadata], stale: Bool) in
      // The saved copy first: tabs open at once.
      if let saved = LibraryIndexSnapshot.load(from: url), !saved.items.isEmpty {
        return (saved.items, !saved.isFresh())
      }
      let items = try await LibraryIndexer.build(client: client, sections: sections)
      try? LibraryIndexSnapshot(savedAt: Date(), items: items).save(to: url)
      return (items, false)
    }
    indexBuild = task
    let shared = Task { try await task.value.items }
    indexTask = shared
    defer { indexTask = nil }
    // Not cancelled with the caller: other tabs may be waiting on the same read.
    let result = try await task.value
    guard !isClosed else { return result.items }
    setLibraryIndex(result.items)
    if result.stale { refreshLibraryIndex(client: client, sections: sections, url: url) }
    return result.items
  }

  /// Bumped whenever the index changes; a service built with an older one is rebuilt.
  @ObservationIgnored private var indexVersion = 0
  /// The index version each service's rows were matched with.
  @ObservationIgnored private var serviceIndexVersion: [String: Int] = [:]

  private func setLibraryIndex(_ index: [String: PlexMetadata]) {
    libraryIndex = index
    indexVersion += 1
    // Tabs already built with an older (or no) index get matched again.
    for (id, version) in serviceIndexVersion where version != indexVersion {
      guard let service = StreamingService.byID(id), let lists = serviceLists[id] else { continue }
      let trending = trendingTask
      spawn { [weak self] in
        guard let self else { return }
        await self.publishService(service, lists: lists, index: index, trending: await trending?.value ?? [])
      }
    }
  }

  /// Reads the library again in the background and saves it; open tabs are
  /// matched again with it. A failure keeps the saved one.
  private func refreshLibraryIndex(client: PlexServerClient, sections: [PlexLibrarySection], url: URL) {
    let task = Task.detached(priority: .utility) {
      let items = try await LibraryIndexer.build(client: client, sections: sections)
      try? LibraryIndexSnapshot(savedAt: Date(), items: items).save(to: url)
      return items
    }
    refreshTask = task
    spawn { [weak self] in
      guard let fresh = try? await task.value, let self, !self.isClosed else { return }
      self.setLibraryIndex(fresh)
    }
  }

  /// One saved index per server and Library Quality ("-v2": items carry their library).
  private var indexURL: URL {
    LibraryIndexSnapshot.url(serverID: "\(serverID)-\(libraryQuality.rawValue)-v2", in: Self.indexFolder)
  }

  /// `items` with Library Quality applied: one copy of each title (see LibraryFilter).
  /// Uses the index for 4K copies when it is already loaded; never waits for it.
  func shown(_ items: [PlexMetadata], swap: Bool = true) -> [PlexMetadata] {
    filter.apply(items, twins: libraryIndex ?? [:], swap: swap)
  }

  /// The TMDB titles that are on this server, as the server's items, in order
  /// (Search's people pages). Waits for the library index.
  func onServer(_ items: [TMDBItem]) async -> [PlexMetadata] {
    let index = (try? await loadLibraryIndex()) ?? [:]
    var seen = Set<String>()
    return shown(items.compactMap { index[$0.id] }.filter { seen.insert($0.ratingKey).inserted })
  }

  /// Every TMDB title, as this server's item where it has it, else as a
  /// catalog title (Play greyed out); in TMDB's order, each once.
  /// The same without waiting: matched with the index already in memory
  /// (search can't wait for a library read). The index starts loading if it isn't.
  func withServerNow(_ items: [TMDBItem]) -> [PlexMetadata] {
    if libraryIndex == nil { spawn { [weak self] in _ = try? await self?.loadLibraryIndex() } }
    let index = libraryIndex ?? [:]
    var seen = Set<String>()
    return items.filter { seen.insert($0.id).inserted }.map { index[$0.id] ?? $0.asMetadata }
  }

  func withServer(_ items: [TMDBItem]) async -> [PlexMetadata] {
    let index = (try? await loadLibraryIndex()) ?? [:]
    var seen = Set<String>()
    return items.filter { seen.insert($0.id).inserted }.map { item in
      index[item.id] ?? item.asMetadata
    }
  }

  /// Watchlist items (from Plex's catalog) as this server's items where it has
  /// them, else as catalog titles that open with Play greyed out.
  func matchWatchlist(_ items: [PlexMetadata]) async -> [PlexMetadata] {
    let index = (try? await loadLibraryIndex()) ?? [:]
    return items.compactMap { item in
      guard let key = item.tmdbKey else { return nil }
      if let onServer = index[key] { return onServer }
      var catalog = item
      catalog.ratingKey = "tmdb:\(key)"
      return catalog
    }
  }

  /// Search, with one copy of each title.
  func search(_ text: String) async throws -> [PlexMetadata] {
    shown(try await client.search(text))
  }

  /// Movies and shows from the library index whose title matches, with no
  /// network: titles starting with the text first, then a word starting with
  /// it, then containing it. Empty until the index has loaded.
  func localSearch(_ text: String, limit: Int = 30) -> [PlexMetadata] {
    guard let libraryIndex else { return [] }
    return LocalSearch.rank(Array(libraryIndex.values), text: text, limit: limit)
  }

  /// `first` then whatever `more` adds, each title once (by TMDB id, else rating key).
  static func merged(_ first: [PlexMetadata], _ more: [PlexMetadata]) -> [PlexMetadata] {
    var seen = Set<String>()
    return (first + more).filter { seen.insert($0.tmdbKey ?? $0.ratingKey).inserted }
  }

  /// Application Support/Astra/LibraryIndex.
  nonisolated static var indexFolder: URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    return base.appendingPathComponent("Astra/LibraryIndex", isDirectory: true)
  }

  /// Full metadata (versions, logos) for a few items, fetched in parallel, kept in order.
  private func loadInFull(_ items: [PlexMetadata]) async -> [PlexMetadata] {
    await withTaskGroup(of: (Int, PlexMetadata).self) { group in
      for (i, item) in items.enumerated() {
        // A TMDB-only title has nothing on the server to fetch.
        group.addTask { [self] in (i, item.isCatalogOnly ? item : ((try? await details(item.ratingKey)) ?? item)) }
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
    if let cached = resolveCache[item.ratingKey] {
      guard let key = cached else { throw CatalogError.notOnServer(item.title) }
      if let full = detailCache[key] { return full }
      return try await details(key)
    }
    do {
      let match = try await resolveUncached(item)
      resolveCache[item.ratingKey] = .some(match.ratingKey)
      return match
    } catch CatalogError.notOnServer(let title) {
      resolveCache[item.ratingKey] = .some(nil)
      throw CatalogError.notOnServer(title)
    }
  }

  private func resolveUncached(_ item: PlexMetadata) async throws -> PlexMetadata {
    let tmdbID = item.guids.first?.id
    let results = ((try? await search(item.title)) ?? []).filter { $0.type == item.type }
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
    // Astra: the saved hero and Top 10 show before Plex has even answered.
    if hero.isEmpty, tmdb != nil {
      spawn { [weak self] in
        guard let self else { return }
        let url = Self.trendingURL
        let saved = await Task.detached(priority: .userInitiated) { TrendingSnapshot.load(from: url) }.value
        guard let saved, !saved.items.isEmpty, self.hero.isEmpty else { return }
        await self.showTrending(saved.items)
      }
    }
    async let continueTask = client.continueWatching()
    async let hubsTask = client.homeHubs()
    async let sectionsTask = client.librarySections()

    let loadedContinue = (try? await continueTask) ?? []
    let loadedSections = (try? await sectionsTask) ?? []
    guard isCurrent() else { return }
    // Movies and Shows keep working even when the Home rows fail.
    if !loadedSections.isEmpty { allSections = loadedSections }
    do {
      // Astra (KP, 2026-11-07, "Home didn't load … took too long"): a big
      // server can be slow to build its home rows. Ask once more for fewer
      // rows before giving up; if that fails too, the page still shows
      // Continue Watching, the hero, Top 10 and For You, and tries again later.
      let loadedHubs: [PlexHub]
      var hubsFailed = false
      do {
        loadedHubs = try await hubsTask
      } catch {
        guard isCurrent() else { return }
        do {
          loadedHubs = try await client.homeHubs(count: 8)
        } catch {
          guard isCurrent() else { return }
          loadedHubs = []
          hubsFailed = true
          homeError = describe(error)
          retryHomeLater()
        }
      }
      // Astra: Library Quality first (HD drops 4K libraries; 4K keeps one copy, the 4K one).
      let filter = self.filter
      let twins = libraryIndex ?? [:]
      let rows = await Self.deduplicatedRows(
        continueWatching: filter.apply(
          loadedContinue.isEmpty ? loadedHubs.first(where: \.isContinueWatching)?.items ?? [] : loadedContinue,
          swap: false),
        hubs: loadedHubs.filter { !$0.isContinueWatching }.map { hub in
          var hub = hub
          hub.items = filter.apply(hub.items, twins: twins)
          return hub
        },
        more: { [client] key, start in
          filter.apply((try? await client.hubItems(key: key, start: start)) ?? [], twins: twins)
        })
      guard isCurrent() else { return }
      continueWatching = rows.continueWatching
      // A failed reload keeps the rows already on screen.
      if !hubsFailed || hubs.isEmpty { hubs = rows.hubs }
      isLoadingHome = false
      await loadHero(fallback: rows.hubs, isCurrent: isCurrent)
      await buildForYou(isCurrent: isCurrent)
    }
    isLoadingHome = false
    spawn { [weak self] in
      guard let self else { return }
      await prefetchArtwork(hero + continueWatching + hubs.flatMap(\.items))
    }
    // Astra (KP: "all the content should be instantaneous"): every streaming
    // tab is built in the background, one at a time, so switching is instant.
    spawn { [weak self] in await self?.preloadServices() }
  }

  /// After a slow or failed Home load: one quiet retry 20 s later (a newer
  /// load, or one already scheduled, makes it a no-op).
  @ObservationIgnored private var homeRetryScheduled = false
  private func retryHomeLater() {
    guard !homeRetryScheduled else { return }
    homeRetryScheduled = true
    spawn { [weak self] in
      try? await Task.pause(20)
      guard let self, !self.isClosed else { return }
      self.homeRetryScheduled = false
      if self.homeError != nil { await self.loadHome() }
    }
  }

  /// Builds each service's rows that aren't built yet, without touching the
  /// selected tab's loading state.
  private func preloadServices() async {
    guard tmdb != nil else { return }
    for service in StreamingService.all {
      guard !isClosed, !Task.isCancelled else { return }
      guard serviceContent[service.id] == nil, loadingServiceID != service.id else { continue }
      // -1 is never the current generation, so the selected tab's spinner is left alone.
      await loadService(service, token: -1)
      if serviceErrors[service.id] != nil, selectedService != service { serviceErrors[service.id] = nil }
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

  /// Every copy of a movie or episode on the server: its own versions plus
  /// the same title in other libraries (a "Movies 4K" library), found by its
  /// Plex guid. All libraries are searched, whatever Library Quality hides.
  func versions(of item: PlexMetadata) async -> [PlexMetadata] {
    guard let guid = item.guid, item.type == .movie || item.type == .episode else { return [item] }
    let kind = item.type == .movie ? "movie" : "show"
    var filters = [URLQueryItem(name: "guid", value: guid)]
    if item.type == .episode { filters.append(URLQueryItem(name: "type", value: "4")) }
    var out = [item]
    for section in allSections where section.type == kind && Int(section.key) != item.librarySectionID {
      let found = (try? await client.libraryItems(sectionKey: section.key, size: 5, filters: filters)) ?? []
      // Only the same title (a server that ignores the filter returns the whole library).
      out += found.filter { $0.guid == guid && $0.ratingKey != item.ratingKey }
    }
    return out
  }

  /// Recommended For You, Because You Watched… and Hidden Gems from the
  /// library index. Titles already in the hero, Continue Watching or the Top
  /// 10 are left out, and each title shows in one row only.
  private func buildForYou(isCurrent: @escaping () -> Bool) async {
    guard let index = try? await loadLibraryIndex(), !index.isEmpty, isCurrent() else { return }
    let library = Array(index.values)
    let popular = Set(tmdb == nil ? [] : await loadWeekTrending().map(\.id))
    var exclude = Set((hero + continueWatching + topTen.movies + topTen.shows).flatMap(ForYou.keys))
    var rows: [PlexHub] = []
    func add(_ id: String, _ title: String, _ items: [PlexMetadata]) {
      guard items.count >= 3 else { return }
      rows.append(PlexHub(hubIdentifier: "astra.\(id)", title: title, items: items))
      exclude.formUnion(items.flatMap(ForYou.keys))
    }
    add("recommended", "Recommended For You", ForYou.recommended(library: library, exclude: exclude))
    if let seed = ForYou.becauseSeed(library: library, continueWatching: continueWatching) {
      // Plex's related titles, kept only when they are in this library (and its quality).
      let owned = Dictionary(library.map { ($0.ratingKey, $0) }, uniquingKeysWith: { a, _ in a })
      let related = ((try? await client.relatedHubs(ratingKey: seed.ratingKey)) ?? []).flatMap(\.items)
      var seen = Set<String>()
      let items = related.compactMap { owned[$0.ratingKey] }
        .filter { !ForYou.keys($0).contains(where: exclude.contains) && seen.insert($0.ratingKey).inserted }
      add("because", "Because You Watched \(seed.displayTitle)", Array(items.prefix(15)))
    }
    add("gems", "Hidden Gems", ForYou.hiddenGems(library: library, exclude: exclude, popular: popular))
    guard isCurrent() else { return }
    forYouRows = rows
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
    if let cached = childrenCache[ratingKey] { return cached }
    let items = try await client.children(ratingKey: ratingKey)
    childrenCache[ratingKey] = items
    return items
  }

  func related(_ ratingKey: String) async -> [PlexHub] {
    if let cached = relatedCache[ratingKey] { return cached }
    let hubs = ((try? await client.relatedHubs(ratingKey: ratingKey)) ?? []).compactMap { hub in
      var hub = hub
      hub.items = shown(hub.items)
      return hub.items.isEmpty ? nil : hub
    }
    if !hubs.isEmpty { relatedCache[ratingKey] = hubs }
    return hubs
  }

  /// Astra (KP, 2026-11-07): reads ahead everything the Details card for
  /// these titles shows (server match, item, seasons and first episodes,
  /// related rows, rating, backdrop and logo), so a tap opens it filled in.
  /// One title at a time in the background; each title only once.
  func prewarmDetails(_ items: [PlexMetadata]) async {
    for item in items {
      guard !isClosed, !Task.isCancelled else { return }
      guard prewarmed.insert(item.id).inserted else { continue }
      _ = await tmdbArtwork(for: item)
      for kind in [ArtKind.heroBackdrop, .logo] {
        if let url = await artworkURL(for: item, kind, width: 1920, height: 1080) {
          _ = await ImagePipeline.shared.image(for: url)
        }
      }
      guard let resolved = try? await resolve(item), let full = try? await details(resolved.ratingKey) else {
        continue
      }
      if full.type == .show, let seasons = try? await children(of: full.ratingKey) {
        let list = seasons.filter { $0.type == .season }
        if let start = list.first(where: { !$0.isWatched && ($0.index ?? 0) > 0 }) ?? list.first {
          _ = try? await children(of: start.ratingKey)
        }
      }
      _ = await related(full.ratingKey)
    }
  }

  /// Astra (KP, 2026-11-07): the episode that plays after `episode` ends,
  /// read fresh from the server (the next in its season, else the first of
  /// the next season). Nil after a show's last episode.
  func nextEpisode(after episode: PlexMetadata) async -> PlexMetadata? {
    guard episode.type == .episode, let seasonKey = episode.parentRatingKey else { return nil }
    let episodes = (try? await client.children(ratingKey: seasonKey)) ?? []
    if let next = UpNext.nextInSeason(after: episode, episodes: episodes) { return next }
    guard let showKey = episode.grandparentRatingKey, let seasonIndex = episode.parentIndex,
      let seasons = try? await client.children(ratingKey: showKey),
      let season = UpNext.nextSeason(after: seasonIndex, seasons: seasons)
    else { return nil }
    return UpNext.first(of: (try? await client.children(ratingKey: season.ratingKey)) ?? [])
  }

  /// Seasons and episodes change when something is watched.
  private func forgetChildren() {
    childrenCache = [:]
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

  /// Watched state changed in this session, shown at once while the server catches up.
  private(set) var watchedOverrides: [String: Bool] = [:]

  /// The watched state to show: a change made here wins over the server's copy.
  func isWatched(_ item: PlexMetadata) -> Bool {
    watchedOverrides[item.ratingKey] ?? item.isWatched
  }

  /// Astra: flips the checkmark immediately (KP: Mark Watched felt delayed),
  /// then tells the server; Home refreshes in the background. On failure the
  /// old state comes back.
  func setWatched(_ item: PlexMetadata, watched: Bool) async {
    let before = watchedOverrides[item.ratingKey]
    watchedOverrides[item.ratingKey] = watched
    do {
      if watched {
        try await client.markWatched(ratingKey: item.ratingKey)
      } else {
        try await client.markUnwatched(ratingKey: item.ratingKey)
      }
      detailCache[item.ratingKey] = nil
      if let parent = item.parentRatingKey { detailCache[parent] = nil }
      if let show = item.grandparentRatingKey { detailCache[show] = nil }
      forgetChildren()
      spawn { [weak self] in await self?.loadHome() }
    } catch {
      watchedOverrides[item.ratingKey] = before
      homeError = describe(error)
    }
  }

  /// Astra (KP, 2026-11-07): the card goes at once; Plex is told after. On
  /// failure it comes back.
  func removeFromContinueWatching(_ item: PlexMetadata) async {
    let before = continueWatching
    continueWatching.removeAll { $0.ratingKey == item.ratingKey }
    do {
      try await client.removeFromContinueWatching(ratingKey: item.ratingKey)
    } catch {
      continueWatching = before
      homeError = describe(error)
    }
  }

  /// Called when the player closes, so Continue Watching shows the new position.
  func playbackEnded(ratingKey: String) {
    detailCache[ratingKey] = nil
    forgetChildren()
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

/// Astra: TMDB search answers kept for the session, so typing back to an
/// earlier query (or reopening Search) shows its results at once.
@MainActor
final class SearchCache {
  static let shared = SearchCache()
  private var entries: [String: (items: [TMDBItem], people: [TMDBPerson])] = [:]
  private var order: [String] = []

  subscript(query: String) -> (items: [TMDBItem], people: [TMDBPerson])? {
    get { entries[query.lowercased()] }
    set {
      let key = query.lowercased()
      entries[key] = newValue
      order.removeAll { $0 == key }
      order.append(key)
      if order.count > 60 { entries[order.removeFirst()] = nil }
    }
  }
}
