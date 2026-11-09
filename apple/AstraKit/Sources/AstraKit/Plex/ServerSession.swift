import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// A connection to one server that has been checked end to end: an address
/// answered, and the server accepted the token by listing its libraries.
///
/// `generation` is the session's identity. Every switch makes a new one, so
/// work started for an older session can tell it is stale and drop its result.
public struct ServerSession: Sendable {
  public let generation: Int
  public let serverID: String
  public let client: PlexServerClient
  public let sections: [PlexLibrarySection]

  public init(generation: Int, serverID: String, client: PlexServerClient, sections: [PlexLibrarySection]) {
    self.generation = generation
    self.serverID = serverID
    self.client = client
    self.sections = sections
  }
}

/// Opens and validates server sessions. Nothing is committed here: the caller
/// swaps to the new session only when `connect` returns, so a failed switch
/// leaves the current server working.
public struct ServerConnector: Sendable {
  let info: PlexClientInfo
  let transport: HTTPTransport
  let probeTimeout: TimeInterval

  public init(info: PlexClientInfo, transport: HTTPTransport = URLSessionTransport(), probeTimeout: TimeInterval = 4) {
    self.info = info
    self.transport = transport
    self.probeTimeout = probeTimeout
  }

  public func connect(
    to resource: PlexServerResource, accountToken: String, generation: Int
  ) async throws -> ServerSession {
    let picker = ConnectionPicker(info: info, transport: transport, probeTimeout: probeTimeout)
    let url = try await picker.pick(for: resource, accountToken: accountToken)
    try Task.checkCancellation()
    let client = PlexServerClient(
      baseURL: url, token: resource.accessToken ?? accountToken, serverName: resource.name, info: info,
      transport: transport)
    // /identity answers without a valid token; listing libraries proves the token works.
    let sections = try await client.librarySections()
    try Task.checkCancellation()
    return ServerSession(
      generation: generation, serverID: resource.clientIdentifier, client: client, sections: sections)
  }
}

/// Hands out increasing tokens and says whether one is still the latest.
/// Used to drop responses that arrive after a newer request replaced them.
public struct Generation: Sendable, Equatable {
  public private(set) var current = 0

  public init() {}

  /// Starts a new request; every earlier token is stale from now on.
  public mutating func next() -> Int {
    current += 1
    return current
  }

  public func isCurrent(_ token: Int) -> Bool { token == current }
}

/// Every movie and show on a server by TMDB key ("movie:603"), for matching
/// TMDB's streaming lists to the library.
public enum LibraryIndexer {
  /// Reads every movie and show section in pages (a single 20,000-item
  /// request times out on slow servers), up to `parallel` pages at once. Throws when any page fails, so a partial or
  /// empty index is never mistaken for the real one and saved.
  public static func build(
    client: PlexServerClient, sections: [PlexLibrarySection], pageSize: Int = 250, parallel: Int = 4
  ) async throws -> [String: PlexMetadata] {
    let wanted = sections.filter { $0.type == "movie" || $0.type == "show" }
    // One section at a time, so at most `parallel` requests are ever in flight
    // (URLSession queues the rest, and queued requests time out on slow servers).
    var perSection: [[PlexMetadata]] = []
    for section in wanted {
      // Astra: a section's own listing leaves each item's library out; Library Quality needs it.
      let sectionID = Int(section.key)
      perSection.append(
        try await items(in: section, client: client, pageSize: pageSize, parallel: parallel).map {
          var item = $0
          if item.librarySectionID == nil { item.librarySectionID = sectionID }
          return item
        })
    }
    var index: [String: PlexMetadata] = [:]
    for item in perSection.joined() {
      if let key = item.tmdbKey {
        if index[key] == nil { index[key] = item.slimmed }
      } else if let title = item.titleMatchKey, index[LibraryMatch.titlePrefix + title] == nil {
        // No TMDB guid: still in the index, found by title and year.
        index[LibraryMatch.titlePrefix + title] = item.slimmed
      }
    }
    return index
  }

  /// `index` with `items` added (a section's newest titles, read in one quick
  /// request): a saved index from before a title was added still finds it,
  /// without waiting for the whole library to be read again (KP, 2026-11-08:
  /// new titles on Plex took 8 s to open). Keys as in `build`; an item
  /// already in the index under the same key is replaced by the newer copy.
  /// `items` must already carry their `librarySectionID`.
  public static func merging(_ index: [String: PlexMetadata], _ items: [PlexMetadata]) -> [String: PlexMetadata] {
    var out = index
    for item in items {
      if let key = item.tmdbKey {
        out[key] = item.slimmed
      } else if let title = item.titleMatchKey {
        out[LibraryMatch.titlePrefix + title] = item.slimmed
      }
    }
    return out
  }

  /// One section's items in order, `parallel` pages per round, until a short page.
  static func items(
    in section: PlexLibrarySection, client: PlexServerClient, pageSize: Int, parallel: Int
  ) async throws -> [PlexMetadata] {
    var all: [PlexMetadata] = []
    var start = 0
    while true {
      try Task.checkCancellation()
      let round = try await withThrowingTaskGroup(of: (Int, [PlexMetadata]).self) { group in
        for i in 0..<max(1, parallel) {
          let offset = start + i * pageSize
          group.addTask {
            // A page of 1,000 over a remote connection could take longer than
            // the 60 s a request may run, so no index was ever saved and every
            // new title waited on a server search (KP, 2026-11-09). Pages are
            // 250 now, and a failed page is asked for once more.
            do {
              return (i, try await client.libraryItems(sectionKey: section.key, sort: "titleSort", start: offset, size: pageSize))
            } catch is CancellationError {
              throw CancellationError()
            } catch {
              return (i, try await client.libraryItems(sectionKey: section.key, sort: "titleSort", start: offset, size: pageSize))
            }
          }
        }
        var pages = [[PlexMetadata]](repeating: [], count: max(1, parallel))
        for try await (i, page) in group { pages[i] = page }
        return pages
      }
      for page in round {
        all += page
        if page.count < pageSize { return all }
      }
      start += round.count * pageSize
    }
  }
}

extension PlexMetadata {
  /// The fields a card and a TMDB match need; cast, crew and images are
  /// fetched with the details. Keeps the saved index small.
  var slimmed: PlexMetadata {
    var item = self
    item.roles = []
    item.directors = []
    item.images = []
    return item
  }
}

/// The library index saved on disk per server, so streaming tabs open at once
/// after the first time; it is refreshed in the background.
public struct LibraryIndexSnapshot: Codable, Sendable {
  public var savedAt: Date
  public var items: [String: PlexMetadata]

  public init(savedAt: Date, items: [String: PlexMetadata]) {
    self.savedAt = savedAt
    self.items = items
  }

  /// `…/Astra/LibraryIndex/<server>.json`.
  public static func url(serverID: String, in folder: URL) -> URL {
    let safe = serverID.filter { $0.isLetter || $0.isNumber || $0 == "-" }
    return folder.appendingPathComponent("\(safe.isEmpty ? "server" : safe).json")
  }

  public static func load(from url: URL) -> LibraryIndexSnapshot? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(LibraryIndexSnapshot.self, from: data)
  }

  public func save(to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONEncoder().encode(self).write(to: url, options: .atomic)
  }

  /// Older than this, the saved index is used but read again in the background.
  public static let freshFor: TimeInterval = 30 * 60

  public func isFresh(now: Date = Date()) -> Bool { now.timeIntervalSince(savedAt) < Self.freshFor }
}

/// Astra (KP, 2026-11-07: "why does it take so long to connect each time,
/// when Plex or Infuse open immediately"): the last server that worked,
/// saved so the next launch opens straight onto it while plex.tv and the
/// address are re-checked behind. The server's token is not in here: it
/// stays in the Keychain.
public struct SavedConnection: Codable, Sendable, Equatable {
  public var serverID: String
  public var serverName: String
  public var baseURL: URL
  public var sections: [PlexLibrarySection]

  public init(serverID: String, serverName: String, baseURL: URL, sections: [PlexLibrarySection]) {
    self.serverID = serverID
    self.serverName = serverName
    self.baseURL = baseURL
    self.sections = sections
  }

  public init(_ session: ServerSession) {
    self.init(
      serverID: session.serverID, serverName: session.client.serverName, baseURL: session.client.baseURL,
      sections: session.sections)
  }

  public static let defaultsKey = "astra.plex.savedConnection"

  /// Nil when nothing is saved, or the saved address is plain HTTP across
  /// the internet (an older build could pick one): the token is never sent
  /// there, so launch goes through `ConnectionPicker` instead.
  public static func load(from defaults: UserDefaults = .standard) -> SavedConnection? {
    guard let data = defaults.data(forKey: defaultsKey),
      let saved = try? JSONDecoder().decode(SavedConnection.self, from: data),
      ConnectionPicker.isSafeForToken(saved.baseURL)
    else { return nil }
    return saved
  }

  public func save(to defaults: UserDefaults = .standard) {
    if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.defaultsKey) }
  }

  public static func clear(from defaults: UserDefaults = .standard) {
    defaults.removeObject(forKey: defaultsKey)
  }
}

extension ServerConnector {
  /// A session on the saved server with no network request: used at launch
  /// so Home opens at once. The caller checks it right after (`isReachable`).
  public func resume(_ saved: SavedConnection, token: String, generation: Int) -> ServerSession {
    let client = PlexServerClient(
      baseURL: saved.baseURL, token: token, serverName: saved.serverName, info: info, transport: transport)
    return ServerSession(generation: generation, serverID: saved.serverID, client: client, sections: saved.sections)
  }

  /// Whether the saved address still answers with this token (its libraries list).
  public func check(_ session: ServerSession) async -> [PlexLibrarySection]? {
    try? await session.client.librarySections()
  }
}
