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
  /// Astra 4.0: For You's Recently Released and All-Time Greats, from the library.
  private(set) var forYouRecent: HomeShelf = .empty
  private(set) var forYouGreats: HomeShelf = .empty
  /// Every library on the server.
  private(set) var allSections: [PlexLibrarySection] = []
  /// Settings → Content → Library Quality, read when the store is made; a
  /// change makes a new store (AppModel.libraryQualityChanged).
  let libraryQuality = LibraryQuality.stored()
  /// One copy of each title for this device's Library Quality.
  var filter: LibraryFilter { LibraryFilter(quality: libraryQuality, sections: allSections) }
  /// The libraries the Movies and Shows tabs browse.
  var sections: [PlexLibrarySection] { filter.browseSections(allSections) }
  /// True while the For You rows are being asked for.
  private var homeRowsLoading = false
  /// The centred spinner: only while For You has nothing at all to show.
  /// Saved Continue Watching, hero and For You rows mean no spinner
  /// (KP, 2026-11-08: no buffer in the middle of Home).
  var isLoadingHome: Bool {
    homeRowsLoading && hubs.isEmpty && continueWatching.isEmpty && hero.isEmpty && !isLoadingHero
      && forYouRecent.isEmpty && forYouGreats.isEmpty
  }
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
  /// Astra 4.0: one service tab's Home, the same five sections as For You.
  struct ServiceHome {
    var hero: [PlexMetadata]
    var topTen: (movies: [PlexMetadata], shows: [PlexMetadata])
    var recent: HomeShelf
    var greats: HomeShelf
  }
  private var serviceContent: [String: ServiceHome] = [:]
  @ObservationIgnored private var serviceGeneration = Generation()
  @ObservationIgnored private var serviceTask: Task<Void, Never>?
  /// Every movie and show on the server by TMDB key ("movie:603"), built once, on first use.
  @ObservationIgnored private var libraryIndex: [String: PlexMetadata]?
  /// Observed stand-in for `libraryIndex`: flips when an index is in memory.
  private(set) var indexReady = false
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
    cinebyRowsRefresh?.cancel()
    trendingRefresh?.cancel()
    background.values.forEach { $0.cancel() }
    background.removeAll()
    loadingServiceID = nil
    homeRowsLoading = false
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

  /// Astra 4.0: Recently Released for the current tab (release dates, newest first).
  /// Titles already in Top Trending are left out (KP: no title in two rows).
  var homeRecent: HomeShelf {
    let shelf = selectedService.map { serviceContent[$0.id]?.recent ?? .empty } ?? forYouRecent
    let split = homeTopTenSplit
    return shelf.excluding(Set((split.movies + split.shows).map(HomeSections.key)))
  }

  /// Astra 4.0: All-Time Greats for the current tab, without titles in Top
  /// Trending or Recently Released.
  var homeGreats: HomeShelf {
    let shelf = selectedService.map { serviceContent[$0.id]?.greats ?? .empty } ?? forYouGreats
    let split = homeTopTenSplit
    return shelf.excluding(Set((split.movies + split.shows).map(HomeSections.key)).union(homeRecent.keys))
  }

  /// Whether the current tab has anything below Continue Watching.
  var homeHasSections: Bool {
    let split = homeTopTenSplit
    return !(split.movies.isEmpty && split.shows.isEmpty && homeRecent.isEmpty && homeGreats.isEmpty)
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
    let specs = ServiceCatalog.homeRows(for: service)
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
    func shown(_ item: TMDBItem) -> PlexMetadata { index.match(item) ?? item.asMetadata }
    // KP (2026-11-08, "bring back cineby"): every section is the service's
    // whole TMDB list in its order; titles on the server play, the rest
    // show with Play greyed.
    func list(_ suffix: String) -> [PlexMetadata] {
      HomeSections.unique((lists.first { $0.0.id.hasSuffix(suffix) }?.1 ?? []).map(shown))
    }
    let popular = list(".trending")
    // Every list's titles, in row order, so both Movies and Series fill to 10.
    let pool = HomeSections.unique(lists.flatMap { $0.1.map(shown) })
    let topTen = (
      movies: TrendingHero.serviceTopTen(
        trending: trending.filter { $0.kind == .movie }, service: pool.filter { $0.type == .movie }),
      shows: TrendingHero.serviceTopTen(
        trending: trending.filter { $0.kind == .tv }, service: pool.filter { $0.type == .show })
    )
    // Newest first by release / first-air date (TMDB already sorted them so).
    let recent = HomeSections.shelf(Array(list(".new").prefix(40)))
    let greats = HomeSections.shelf(Array(list(".top").prefix(40)))
    // The hero: this service's titles trending now.
    let picks = TrendingHero.pick(trending: trending, service: popular, currentYear: Self.currentYear)
    let hero = await loadInFull(Array(picks.prefix(6))).filter { $0.backdrop != nil }
    guard !isClosed else { return }
    serviceContent[service.id] = ServiceHome(
      hero: hero, topTen: (Array(topTen.movies.prefix(10)), Array(topTen.shows.prefix(10))),
      recent: HomeShelf(movies: Array(recent.movies.prefix(20)), shows: Array(recent.shows.prefix(20))),
      greats: HomeShelf(movies: Array(greats.movies.prefix(20)), shows: Array(greats.shows.prefix(20))))
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
      await loadInFull(TrendingHero.today(trending: trending, index: index, limit: 6)).filter { $0.backdrop != nil }
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
    let shown = await loadInFull(TrendingHero.today(trending: trending, index: index, limit: 6)).filter { $0.backdrop != nil }
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
    let quality = libraryQuality
    let url = indexURL
    let task = Task.detached(priority: .userInitiated) { () throws -> (items: [String: PlexMetadata], stale: Bool) in
      // The saved copy first: tabs open at once.
      // Title-and-year aliases are added here, off the main actor (a big
      // library has thousands of titles); the saved file never has them.
      if let saved = LibraryIndexSnapshot.load(from: url), !saved.items.isEmpty {
        return (LibraryMatch.withAliases(saved.items), !saved.isFresh())
      }
      let items = try await Self.buildIndex(client: client, sections: sections, quality: quality)
      try? LibraryIndexSnapshot(savedAt: Date(), items: items).save(to: url)
      return (LibraryMatch.withAliases(items), false)
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
    topUpLibraryIndex(client: client, sections: sections, url: url)
    return libraryIndex ?? result.items
  }

  /// Bumped whenever the index changes; a service built with an older one is rebuilt.
  @ObservationIgnored private var indexVersion = 0
  /// The index version each service's rows were matched with.
  @ObservationIgnored private var serviceIndexVersion: [String: Int] = [:]

  /// `aliased` already has its title-and-year aliases (`LibraryMatch.withAliases`).
  private func setLibraryIndex(_ aliased: [String: PlexMetadata]) {
    let replacing = libraryIndex != nil
    libraryIndex = aliased
    // Titles remembered as missing get another look with the new index.
    resolveCache = resolveCache.filter { $0.value != nil }
    if !indexReady { indexReady = true }
    indexVersion += 1
    // Tabs already built with an older (or no) index get matched again.
    for (id, version) in serviceIndexVersion where version != indexVersion {
      guard let service = StreamingService.byID(id), let lists = serviceLists[id] else { continue }
      let trending = trendingTask
      spawn { [weak self] in
        guard let self else { return }
        await self.publishService(service, lists: lists, index: aliased, trending: await trending?.value ?? [])
      }
    }
    // For You's Recently Released and All-Time Greats are matched again too,
    // so titles on the server show as the server's items (watched state, progress).
    spawn { [weak self] in
      await self?.publishForYou { [weak self] in self.map { !$0.isClosed } ?? false }
    }
    // A newer index (the background re-read) also re-matches the hero and
    // Top Trending, so a title just added to Plex shows as playable there.
    // The first index is handled by loadHero itself.
    if replacing, let weekTrendingTask {
      spawn { [weak self] in
        let trending = await weekTrendingTask.value
        guard let self, !trending.isEmpty else { return }
        await self.showTrending(trending)
      }
    }
  }

  /// Adds each library's 100 newest titles to the index, one quick request
  /// per library, so a title added since the saved index was read is found
  /// at once (KP, 2026-11-08: new titles took 8 s to open because only the
  /// slow server search found them). The full re-read still runs when the
  /// saved index is old.
  private func topUpLibraryIndex(client: PlexServerClient, sections: [PlexLibrarySection], url: URL) {
    spawn { [weak self] in
      let wanted = sections.filter { $0.type == "movie" || $0.type == "show" }
      guard !wanted.isEmpty else { return }
      let newest = await withTaskGroup(of: [PlexMetadata].self) { group in
        for section in wanted {
          group.addTask {
            let items = (try? await client.libraryItems(sectionKey: section.key, sort: "addedAt:desc", size: 100)) ?? []
            return items.map {
              var item = $0
              if item.librarySectionID == nil { item.librarySectionID = Int(section.key) }
              return item
            }
          }
        }
        var all: [PlexMetadata] = []
        for await items in group { all += items }
        return all
      }
      guard let self, !self.isClosed, !newest.isEmpty, let current = self.libraryIndex else { return }
      let base = current.filter { !$0.key.hasPrefix(LibraryMatch.aliasPrefix) }
      let merged = LibraryIndexer.merging(base, newest)
      // Nothing new: leave the index (and every row matched with it) alone.
      let known = Set(base.values.map(\.ratingKey))
      guard newest.contains(where: { !known.contains($0.ratingKey) }) else { return }
      self.setLibraryIndex(LibraryMatch.withAliases(merged))
      Task.detached(priority: .utility) {
        try? LibraryIndexSnapshot(savedAt: LibraryIndexSnapshot.load(from: url)?.savedAt ?? Date(), items: merged).save(to: url)
      }
    }
  }

  /// Reads the library again in the background and saves it; open tabs are
  /// matched again with it. A failure keeps the saved one.
  private func refreshLibraryIndex(client: PlexServerClient, sections: [PlexLibrarySection], url: URL) {
    let quality = libraryQuality
    let task = Task.detached(priority: .utility) {
      let items = try await Self.buildIndex(client: client, sections: sections, quality: quality)
      try? LibraryIndexSnapshot(savedAt: Date(), items: items).save(to: url)
      return LibraryMatch.withAliases(items)
    }
    refreshTask = task
    spawn { [weak self] in
      guard let fresh = try? await task.value, let self, !self.isClosed else { return }
      self.setLibraryIndex(fresh)
    }
  }

  /// Reads the library. Asked before the server's sections were known (a
  /// streaming tab or Search can start first), it reads them itself: an
  /// index built from no sections was empty, which left For You without
  /// Recently Released and All-Time Greats and marked every Search result
  /// "not on the server" (KP, 2026-11-08). An empty result is an error, never
  /// saved or shown.
  nonisolated private static func buildIndex(
    client: PlexServerClient, sections: [PlexLibrarySection], quality: LibraryQuality
  ) async throws -> [String: PlexMetadata] {
    var wanted = sections
    if wanted.isEmpty {
      let all = try await client.librarySections()
      wanted = LibraryFilter(quality: quality, sections: all).indexSections(all)
    }
    let items = try await LibraryIndexer.build(client: client, sections: wanted)
    guard !items.isEmpty else { throw URLError(.zeroByteResource) }
    return items
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
    return shown(items.compactMap { index.match($0) }.filter { seen.insert($0.ratingKey).inserted })
  }

  /// Every TMDB title, as this server's item where it has it, else as a
  /// catalog title (Play greyed out); in TMDB's order, each once.
  /// The same without waiting: matched with the index already in memory
  /// (search can't wait for a library read). The index starts loading if it isn't.
  func withServerNow(_ items: [TMDBItem]) -> [PlexMetadata] {
    if libraryIndex == nil { spawn { [weak self] in _ = try? await self?.loadLibraryIndex() } }
    let index = libraryIndex ?? [:]
    var seen = Set<String>()
    return items.filter { seen.insert($0.id).inserted }.map { index.match($0) ?? $0.asMetadata }
  }

  func withServer(_ items: [TMDBItem]) async -> [PlexMetadata] {
    let index = (try? await loadLibraryIndex()) ?? [:]
    var seen = Set<String>()
    return items.filter { seen.insert($0.id).inserted }.map { item in
      index.match(item) ?? item.asMetadata
    }
  }

  /// Watchlist items (from Plex's catalog) as this server's items where it has
  /// them, else as catalog titles that open with Play greyed out.
  /// Astra 4.0: Watchlist titles matched to the server with what is already
  /// in memory, never waiting on the network. Re-runs when the index arrives
  /// (`indexReady` is observed).
  func matchWatchlist(_ items: [PlexMetadata]) -> [PlexMetadata] {
    _ = indexReady
    return WatchlistMatch.match(items, index: libraryIndex ?? [:])
  }

  /// Astra 4.0 (KP: hero Play greyed when playable): whether Play can work.
  /// A streaming-list title counts as playable as soon as the library index
  /// has it, and is only "not on server" once the index has loaded without
  /// it. While the index is still loading, Play stays enabled (a tap looks
  /// the title up).
  enum PlayAvailability { case playable, checking, notOnServer }

  /// The server's copy of a catalog title from the index in memory, without
  /// waiting: Details shows it (Play enabled) while the full details load.
  func indexMatch(_ item: PlexMetadata) -> PlexMetadata? {
    guard item.isCatalogOnly else { return nil }
    return libraryIndex?.match(item)
  }

  func availability(of item: PlexMetadata) -> PlayAvailability {
    guard item.isCatalogOnly else { return .playable }
    _ = indexReady
    guard let index = libraryIndex else { return .checking }
    if index.match(item) != nil { return .playable }
    return .notOnServer
  }

  /// Starts reading the library index (saved copy first) if nothing has yet.
  func warmLibraryIndex() async {
    _ = try? await loadLibraryIndex()
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
    return LocalSearch.rank(libraryIndex.libraryItems, text: text, limit: limit)
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
    // The library index already knows: no search needed (by TMDB id, or title and year).
    // Never wait for the index here: with no saved copy, reading it means
    // reading the whole library from the server, which over a remote
    // connection never finished and left Details stuck with Play greyed
    // (KP, 2026-11-09). Use what is in memory, start a read, and search.
    if libraryIndex == nil { spawn { [weak self] in _ = try? await self?.loadLibraryIndex() } }
    if let hit = libraryIndex?.match(item) { return hit }
    // Not in the index (added since it was read, or titled differently on
    // the server): ask the server.
    return try await searchMatch(item)
  }

  /// Finds `item` on the server by searching its title.
  private func searchMatch(_ item: PlexMetadata) async throws -> PlexMetadata {
    let tmdbID = item.guids.first?.id
    // A failed search (server slow or still connecting) is not "not on the
    // server": it throws, isn't remembered, and the next open asks again.
    // Before, a pre-cache that ran while the server was connecting marked
    // hero and Top Trending titles missing for the whole session (KP, 2026-11-08).
    // Astra 4.0 (QA P2-2): with the server known to be down, don't search at
    // all; a failed search says the server couldn't be checked, never a raw
    // network error and never "not on your server".
    guard serverReachable() else { throw CatalogError.serverUnavailable(item.title) }
    let results: [PlexMetadata]
    do {
      results = try await search(item.title).filter { $0.type == item.type }
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw CatalogError.serverUnavailable(item.title)
    }
    // The same title rules as the library index ("Fire & Ash" is "Fire and
    // Ash", accents and punctuation ignored, a year either side).
    var found: [String: PlexMetadata] = [:]
    for result in results {
      guard let key = result.titleMatchKey, found[LibraryMatch.aliasPrefix + key] == nil else { continue }
      found[LibraryMatch.aliasPrefix + key] = result
    }
    let title = item.title.lowercased()
    let match =
      results.first { $0.guids.contains { $0.id == tmdbID } }
      ?? found.match(item)
      ?? (item.year == nil ? results.first { $0.title.lowercased() == title } : nil)
    guard let match else { throw CatalogError.notOnServer(item.title) }
    return match
  }

  /// Whether the server can be asked right now. AppModel points it at
  /// `ServerHealthMonitor` (`state.allowsStreaming`); true until it does.
  @ObservationIgnored var serverReachable: @MainActor () -> Bool = { true }

  enum CatalogError: LocalizedError {
    case notOnServer(String)
    /// The search couldn't reach the server; not remembered, asked again next time.
    case serverUnavailable(String)
    var errorDescription: String? {
      switch self {
      case .notOnServer(let title): "“\(title)” isn't on your Plex server."
      case .serverUnavailable: "Couldn't check your server. Try again when it's back."
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
    homeRowsLoading = true
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
    // Recently Released and All-Time Greats don't wait for the server's rows.
    spawn { [weak self] in await self?.buildForYou(isCurrent: isCurrent) }
    async let continueTask = client.continueWatching()
    async let hubsTask = client.homeHubs()
    async let sectionsTask = client.librarySections()
    // Astra (KP, 2026-11-08): the saved Continue Watching shows before Plex
    // answers (a quick disk read, while the requests above are in flight).
    if continueWatching.isEmpty {
      let url = continueURL
      let saved = await Task.detached(priority: .userInitiated) { ContinueWatchingSnapshot.load(from: url) }.value
      if let saved, !saved.items.isEmpty, continueWatching.isEmpty, isCurrent() { continueWatching = saved.items }
    }

    // A failed request keeps the row on screen (saved or earlier), never empties it.
    var loadedContinue: [PlexMetadata] = []
    var continueLoaded = false
    do {
      loadedContinue = try await continueTask
      continueLoaded = true
    } catch {}
    guard isCurrent() else { return }
    // Shown as soon as it arrives, not after the slower home rows. It claims
    // its titles first in the page-wide de-duplication either way.
    if continueLoaded {
      var dedup = HomeDeduplicator()
      setContinueWatching(dedup.filter(filter.apply(loadedContinue, swap: false)))
    }
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
      if continueLoaded || !rows.continueWatching.isEmpty { setContinueWatching(rows.continueWatching) }
      // A failed reload keeps the rows already on screen.
      if !hubsFailed || hubs.isEmpty { hubs = rows.hubs }
      homeRowsLoading = false
      await loadHero(fallback: rows.hubs, isCurrent: isCurrent)
    }
    homeRowsLoading = false
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

  /// Astra 4.0 (KP, 2026-11-08): For You's Top 10 is TMDB's trending order
  /// with only the titles on the server, movies and series apart. Ranks are
  /// positions in that list, never invented.
  static func playableTopTen(
    _ trending: [TMDBItem], _ index: [String: PlexMetadata]
  ) -> (movies: [PlexMetadata], shows: [PlexMetadata]) {
    (
      TrendingHero.pick(trending: trending.filter { $0.kind == .movie }, index: index, limit: 10),
      TrendingHero.pick(trending: trending.filter { $0.kind == .tv }, index: index, limit: 10)
    )
  }

  /// Astra 4.0: For You's Recently Released (release dates from the library,
  /// last year, newest first) and All-Time Greats (TMDB's all-time top rated
  /// that are on the server, in TMDB's order; the library's own ratings when
  /// TMDB isn't there or too few match). Recommended For You, Because You
  /// Watched and Hidden Gems are no longer on Home (`ForYou` still has them).
  private func buildForYou(isCurrent: @escaping () -> Bool) async {
    // KP (2026-11-08, "For You still doesn't have the sections"): never wait
    // on the library or on cineby. TMDB's lists show as soon as they arrive,
    // cineby's rows replace them when its page has them (KP: "from cineby"),
    // and setLibraryIndex matches them again when the index is read or changes.
    if libraryIndex == nil { spawn { [weak self] in _ = try? await self?.loadLibraryIndex() } }
    // The saved cineby rows (a quick disk read) are in the first publish.
    await primeCinebyRows()
    await publishForYou(isCurrent: isCurrent)
    let rows = await loadCinebyRows()
    guard !rows.recent.isEmpty || !rows.greats.isEmpty else { return }
    await publishForYou(isCurrent: isCurrent)
  }

  /// Cineby's rows once read this session (nil until then).
  @ObservationIgnored private var cinebyRows: (recent: [TMDBItem], greats: [TMDBItem])?

  /// Builds both shelves from the session's cached lists and the index in
  /// memory now. Every await comes first, so the newest index is used. Never
  /// waits on cineby: its rows are used once they've arrived.
  private func publishForYou(isCurrent: @escaping () -> Bool) async {
    async let recentTMDB = loadRecentReleases()
    async let ratedTMDB = loadTopRated()
    let rows = cinebyRows ?? ([], [])
    let recent = rows.recent.isEmpty ? await recentTMDB : rows.recent
    let rated = rows.greats.isEmpty ? await ratedTMDB : rows.greats
    guard isCurrent() else { return }
    let index = libraryIndex ?? [:]
    let library = index.libraryItems
    let movies = library.filter { $0.type == .movie }
    let shows = library.filter { $0.type == .show }
    func recentShelf(_ kind: TMDBItem.Kind, _ items: [PlexMetadata]) -> [PlexMetadata] {
      let fromTMDB = HomeSections.catalog(recent.filter { $0.kind == kind }, index: index)
      return fromTMDB.count >= 5 ? fromTMDB : HomeSections.recentlyReleased(items)
    }
    func greats(_ kind: TMDBItem.Kind, _ items: [PlexMetadata]) -> [PlexMetadata] {
      let ranked = HomeSections.catalog(rated.filter { $0.kind == kind }, index: index)
      return ranked.count >= 5 ? ranked : HomeSections.greatsFromLibrary(items)
    }
    forYouRecent = HomeShelf(movies: recentShelf(.movie, movies), shows: recentShelf(.tv, shows))
    forYouGreats = HomeShelf(movies: greats(.movie, movies), shows: greats(.tv, shows))
  }

  @ObservationIgnored private var topRatedTask: Task<[TMDBItem], Never>?
  @ObservationIgnored private var recentTask: Task<[TMDBItem], Never>?
  @ObservationIgnored private var cinebyRowsTask: Task<(recent: [TMDBItem], greats: [TMDBItem]), Never>?

  nonisolated static var cinebyRowsURL: URL { CinebyRowsSnapshot.url(in: indexFolder.deletingLastPathComponent()) }
  @ObservationIgnored private var cinebyRowsRefresh: Task<Void, Never>?

  /// The saved cineby rows, read from disk before For You's first publish so
  /// the page opens with them (no swap from TMDB's rows). A stale copy is
  /// shown and refreshed behind.
  private func primeCinebyRows() async {
    guard let tmdb, cinebyRows == nil, cinebyRowsTask == nil else { return }
    let url = Self.cinebyRowsURL
    let saved = await Task.detached(priority: .userInitiated) { CinebyRowsSnapshot.load(from: url) }.value
    guard let saved, !saved.isEmpty, cinebyRows == nil, cinebyRowsTask == nil else { return }
    let rows = (recent: saved.recent, greats: saved.greats)
    cinebyRows = rows
    cinebyRowsTask = Task { rows }
    if !saved.isFresh() { refreshCinebyRows(tmdb: tmdb, saved: saved) }
  }

  /// Reads cineby's rows again behind the saved ones; For You updates when they differ.
  private func refreshCinebyRows(tmdb: TMDBClient, saved: CinebyRowsSnapshot) {
    guard cinebyRowsRefresh == nil else { return }
    cinebyRowsRefresh = Task { [weak self] in
      let fresh = await Task.detached(priority: .utility) { await Self.fetchCinebyRows(tmdb: tmdb, saved: saved) }.value
      guard let self, !self.isClosed else { return }
      self.cinebyRowsRefresh = nil
      guard !(fresh.recent.isEmpty && fresh.greats.isEmpty),
        fresh.recent.map(\.id) != saved.recent.map(\.id) || fresh.greats.map(\.id) != saved.greats.map(\.id)
      else { return }
      self.cinebyRows = fresh
      self.cinebyRowsTask = Task { fresh }
      await self.publishForYou { [weak self] in self.map { !$0.isClosed } ?? false }
    }
  }

  /// Cineby's Recently Released and All-Time Greats style rows (by their
  /// headings), as TMDB titles: the saved copy when there is one (see
  /// `primeCinebyRows`), else read once a session. Empty when the page
  /// can't be read or has no such row.
  private func loadCinebyRows() async -> (recent: [TMDBItem], greats: [TMDBItem]) {
    guard let tmdb else { return ([], []) }
    if let cinebyRowsTask { return await cinebyRowsTask.value }
    let task = Task.detached(priority: .utility) { await Self.fetchCinebyRows(tmdb: tmdb, saved: nil) }
    // Kept even when empty: a page without these rows isn't read again this session.
    cinebyRowsTask = task
    let result = await task.value
    cinebyRows = result
    return result
  }

  /// Reads cineby's page, looks up only the titles `saved` doesn't already
  /// have (8 at a time, so TMDB doesn't answer 429), and saves the rows.
  private nonisolated static func fetchCinebyRows(
    tmdb: TMDBClient, saved: CinebyRowsSnapshot?
  ) async -> (recent: [TMDBItem], greats: [TMDBItem]) {
    guard let html = try? await CinebyTrending.fetchHTML() else { return ([], []) }
    let sections = CinebyTrending.sections(html)
    let known = saved?.known ?? [:]
    func items(_ keywords: [String]) async -> [TMDBItem] {
      let entries = Array((CinebyTrending.section(sections, matching: keywords) ?? []).prefix(40))
      return await withTaskGroup(of: (Int, TMDBItem?).self) { group in
        var next = 0, finished = 0
        var out: [Int: TMDBItem] = [:]
        for (i, entry) in entries.enumerated() {
          if let hit = known[entry.id], hit.year != nil { out[i] = hit }
        }
        let missing = entries.indices.filter { out[$0] == nil }
        repeat {
          while next < missing.count, next < finished + 8 {
            let i = missing[next], entry = entries[i]
            next += 1
            group.addTask { (i, (try? await tmdb.item(id: entry.tmdbID, kind: entry.kind)) ?? entry.item) }
          }
          guard let result = await group.next() else { break }
          finished += 1
          if let item = result.1 { out[result.0] = item }
        } while true
        return entries.indices.compactMap { out[$0] }
      }
    }
    let rows = (recent: await items(CinebyTrending.recentKeywords), greats: await items(CinebyTrending.greatsKeywords))
    let snapshot = CinebyRowsSnapshot(savedAt: Date(), recent: rows.recent, greats: rows.greats)
    if !snapshot.isEmpty { try? snapshot.save(to: cinebyRowsURL) }
    return rows
  }

  /// TMDB's popular titles released in the last four months, movies and
  /// shows, two pages each, read once a session.
  private func loadRecentReleases() async -> [TMDBItem] {
    guard let tmdb else { return [] }
    if let recentTask { return await recentTask.value }
    let task = Task.detached(priority: .utility) { () -> [TMDBItem] in
      let requests = (1...2).flatMap { page in
        [DiscoverRequest(.movie, .recent, page: page), DiscoverRequest(.tv, .recent, page: page)]
      }
      return await withTaskGroup(of: (Int, [TMDBItem]).self) { group in
        for (i, request) in requests.enumerated() {
          group.addTask { (i, (try? await tmdb.discover(request)) ?? []) }
        }
        var byIndex: [Int: [TMDBItem]] = [:]
        for await (i, items) in group { byIndex[i] = items }
        return requests.indices.flatMap { byIndex[$0] ?? [] }
      }
    }
    recentTask = task
    let result = await task.value
    if result.isEmpty { recentTask = nil }
    return result
  }

  /// TMDB's all-time top rated movies and shows, five pages each, read once a session.
  private func loadTopRated() async -> [TMDBItem] {
    guard let tmdb else { return [] }
    if let topRatedTask { return await topRatedTask.value }
    let task = Task.detached(priority: .utility) { () -> [TMDBItem] in
      let requests = (1...5).flatMap { page in [(TMDBItem.Kind.movie, page), (TMDBItem.Kind.tv, page)] }
      return await withTaskGroup(of: (Int, [TMDBItem]).self) { group in
        for (i, request) in requests.enumerated() {
          group.addTask { (i, (try? await tmdb.topRated(request.0, page: request.1)) ?? []) }
        }
        var byIndex: [Int: [TMDBItem]] = [:]
        for await (i, items) in group { byIndex[i] = items }
        return requests.indices.flatMap { byIndex[$0] ?? [] }
      }
    }
    topRatedTask = task
    let result = await task.value
    if result.isEmpty { topRatedTask = nil }
    return result
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

  /// Astra (KP, 2026-11-08: "full details should be instant"): the server's
  /// full item for every title in the Home rows, read ahead three at a time,
  /// so a tap opens Details complete. Only the server item (no artwork,
  /// seasons or related rows, which `prewarmDetails` does for the hero and
  /// Top Trending); titles not on the server are skipped without a search.
  func prewarmServerItems(_ items: [PlexMetadata]) async {
    var keys: [String] = []
    var seen = Set<String>()
    for item in items {
      let key = item.isCatalogOnly ? indexMatch(item)?.ratingKey : item.ratingKey
      guard let key, detailCache[key] == nil, seen.insert(key).inserted else { continue }
      keys.append(key)
    }
    // Three at a time, so a tap's own request is never stuck behind them.
    for start in stride(from: 0, to: keys.count, by: 3) {
      guard !isClosed, !Task.isCancelled else { return }
      let batch = Array(keys[start..<min(start + 3, keys.count)])
      await withTaskGroup(of: Void.self) { group in
        for key in batch {
          group.addTask { @MainActor in _ = try? await self.details(key) }
        }
      }
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
    setContinueWatching(continueWatching.filter { $0.ratingKey != item.ratingKey })
    do {
      try await client.removeFromContinueWatching(ratingKey: item.ratingKey)
    } catch {
      setContinueWatching(before)
      homeError = describe(error)
    }
  }

  // MARK: Saved Continue Watching

  /// This server's saved row (see `ContinueWatchingSnapshot`).
  private var continueURL: URL {
    ContinueWatchingSnapshot.url(serverID: serverID, in: Self.indexFolder.deletingLastPathComponent())
  }

  /// The last save; each new one waits for it, so saves land in order.
  @ObservationIgnored private var continueSave: Task<Void, Never>?

  /// Shows the row and saves it for the next launch (off the main thread).
  private func setContinueWatching(_ items: [PlexMetadata]) {
    continueWatching = items
    let url = continueURL
    let snapshot = ContinueWatchingSnapshot(savedAt: Date(), items: items)
    let previous = continueSave
    continueSave = Task.detached(priority: .utility) {
      await previous?.value
      try? snapshot.save(to: url)
    }
  }

  /// Sign-out: deletes every server's saved Continue Watching row.
  nonisolated static func clearSavedContinueWatching() {
    ContinueWatchingSnapshot.removeAll(in: indexFolder.deletingLastPathComponent())
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
