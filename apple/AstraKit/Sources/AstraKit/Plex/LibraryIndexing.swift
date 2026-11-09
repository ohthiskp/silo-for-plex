import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

// Astra (KP, 2026-11-09): the Omega library index made reliable on a big
// remote server. The Cineby → TMDB → Plex pipeline is unchanged; only how the
// Plex side is read, saved and trusted:
//
// - Every page round that arrives in order is saved at once (a checkpoint
//   per library), so an interrupted read resumes where it stopped.
// - What has been read is usable straight away, before the read finishes.
// - The last complete index is kept while a new read runs.
// - A title missing from an unfinished index is "not yet verified", never
//   "not on the server".

/// What the app knows about a catalog (TMDB) title on the Plex server.
public enum LibraryAvailability: String, Sendable, Equatable {
  /// In the index, or found by a search: playable.
  case available
  /// Not in a complete index, or a search found nothing: not on the server.
  case notFound
  /// The index is still being read and no search has answered yet.
  case unverified

  /// The one rule for a title's state (KP's requirement 6: never "not on the
  /// server" just because indexing hasn't finished).
  public static func decide(
    inIndex: Bool, searchFound: Bool?, indexComplete: Bool
  ) -> LibraryAvailability {
    if inIndex || searchFound == true { return .available }
    if searchFound == false || indexComplete { return .notFound }
    return .unverified
  }
}

/// A read that hasn't finished: what each library has read so far, saved
/// after every round so it survives the app being closed.
public struct LibraryIndexCheckpoint: Codable, Sendable, Equatable {
  public struct Library: Codable, Sendable, Equatable {
    public var key: String
    public var title: String
    /// The library's size, from Plex, when it answered.
    public var total: Int?
    /// Items read so far, in title order, with no gaps.
    public var fetched: Int
    public var complete: Bool
    /// Keyed like the index ("movie:603", "title:…").
    public var items: [String: PlexMetadata]
    public var updatedAt: Date

    public init(key: String, title: String, total: Int? = nil, fetched: Int = 0, complete: Bool = false,
      items: [String: PlexMetadata] = [:], updatedAt: Date) {
      self.key = key
      self.title = title
      self.total = total
      self.fetched = fetched
      self.complete = complete
      self.items = items
      self.updatedAt = updatedAt
    }
  }

  public var libraries: [String: Library]
  public var startedAt: Date

  public init(libraries: [String: Library] = [:], startedAt: Date) {
    self.libraries = libraries
    self.startedAt = startedAt
  }

  public static func load(from url: URL) -> LibraryIndexCheckpoint? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(LibraryIndexCheckpoint.self, from: data)
  }

  public func save(to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONEncoder().encode(self).write(to: url, options: .atomic)
  }

  /// Every library's items in `order`, the first library's copy of a title winning.
  public func index(order: [String]) -> [String: PlexMetadata] {
    var out: [String: PlexMetadata] = [:]
    for key in order {
      guard let library = libraries[key] else { continue }
      out.merge(library.items) { first, _ in first }
    }
    return out
  }
}

/// Settings → Sources → Library Index.
public struct LibraryIndexStatus: Sendable, Equatable {
  public enum Phase: String, Sendable, Equatable {
    case idle, indexing, complete, failed
  }

  public struct Library: Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var fetched: Int
    public var total: Int?
    public var complete: Bool

    public init(id: String, title: String, fetched: Int, total: Int?, complete: Bool) {
      self.id = id
      self.title = title
      self.fetched = fetched
      self.total = total
      self.complete = complete
    }
  }

  public var phase: Phase = .idle
  public var libraries: [Library] = []
  /// Titles in the index in use right now.
  public var itemCount = 0
  /// Whether the index in use is a finished read (requirement 5).
  public var complete = false
  public var lastSuccess: Date?
  public var lastDuration: TimeInterval?
  public var lastError: String?
  /// Page retries in the current or last read.
  public var retries = 0
  public var startedAt: Date?

  public init() {}
}

/// Reads the server's movie and show libraries into the index.
public enum LibraryIndexRun {
  public struct Progress: Sendable {
    public var libraries: [LibraryIndexStatus.Library]
    /// Everything read so far in this read (resumed libraries included).
    public var items: [String: PlexMetadata]
    public var retries: Int
    public var lastError: String?
  }

  /// Reads every movie and show library in `parallel` pages of `pageSize`,
  /// saving a checkpoint after every round. A failed page is retried after
  /// each of `retryDelays` (seconds); when it still fails, the pages before it
  /// are kept and the error is thrown, and the next run resumes from there.
  /// Libraries in a checkpoint younger than `maxAge` are reused (finished) or
  /// resumed (unfinished). The checkpoint is removed once every library is read.
  public static func run(
    client: PlexServerClient, sections: [PlexLibrarySection], checkpointURL: URL,
    maxAge: TimeInterval = 24 * 60 * 60, pageSize: Int = 250, parallel: Int = 3,
    retryDelays: [Double] = [1, 3, 9], now: @escaping @Sendable () -> Date = { Date() },
    onProgress: @escaping @Sendable (Progress) async -> Void = { _ in }
  ) async throws -> [String: PlexMetadata] {
    let wanted = sections.filter { $0.type == "movie" || $0.type == "show" }
    let order = wanted.map(\.key)
    var checkpoint = LibraryIndexCheckpoint.load(from: checkpointURL) ?? LibraryIndexCheckpoint(startedAt: now())
    let start = now()
    checkpoint.libraries = checkpoint.libraries.filter {
      order.contains($0.key) && start.timeIntervalSince($0.value.updatedAt) < maxAge
    }
    let retries = Counter()
    var lastError: String?

    func report() async {
      let libraries = wanted.map { section in
        let library = checkpoint.libraries[section.key]
        return LibraryIndexStatus.Library(
          id: section.key, title: section.title, fetched: library?.fetched ?? 0, total: library?.total,
          complete: library?.complete ?? false)
      }
      await onProgress(
        Progress(libraries: libraries, items: checkpoint.index(order: order), retries: retries.value, lastError: lastError))
    }

    await report()
    for section in wanted {
      var library = checkpoint.libraries[section.key]
        ?? LibraryIndexCheckpoint.Library(key: section.key, title: section.title, updatedAt: now())
      if library.complete { continue }
      if library.total == nil {
        library.total = try? await client.libraryCount(sectionKey: section.key)
      }
      let sectionID = Int(section.key)
      while !library.complete {
        try Task.checkCancellation()
        let first = library.fetched
        let pages = await withTaskGroup(of: (Int, Result<[PlexMetadata], Error>).self) { group in
          for i in 0..<max(1, parallel) {
            let offset = first + i * pageSize
            group.addTask {
              (i, await page(client: client, section: section.key, offset: offset, size: pageSize,
                retryDelays: retryDelays, retries: retries))
            }
          }
          var out = [Result<[PlexMetadata], Error>](repeating: .success([]), count: max(1, parallel))
          for await (i, result) in group { out[i] = result }
          return out
        }
        // Only pages that arrived in order, with no gap before them, count.
        var failure: Error?
        for result in pages {
          switch result {
          case .success(let items):
            for var item in items {
              if item.librarySectionID == nil { item.librarySectionID = sectionID }
              let key = item.tmdbKey ?? item.titleMatchKey.map { LibraryMatch.titlePrefix + $0 }
              if let key, library.items[key] == nil { library.items[key] = item.slimmed }
            }
            library.fetched += items.count
            if items.count < pageSize { library.complete = true }
          case .failure(let error):
            failure = error
          }
          if library.complete || failure != nil { break }
        }
        library.updatedAt = now()
        checkpoint.libraries[section.key] = library
        try? checkpoint.save(to: checkpointURL)
        if let failure {
          if failure is CancellationError { throw failure }
          lastError = PlexError.describe(failure)
          await report()
          throw failure
        }
        await report()
      }
    }
    let index = checkpoint.index(order: order)
    guard !index.isEmpty else { throw URLError(.zeroByteResource) }
    try? FileManager.default.removeItem(at: checkpointURL)
    return index
  }

  /// One page, retried after each delay; cancellation is never retried.
  static func page(
    client: PlexServerClient, section: String, offset: Int, size: Int, retryDelays: [Double], retries: Counter
  ) async -> Result<[PlexMetadata], Error> {
    var attempt = 0
    while true {
      do {
        return .success(try await client.libraryItems(sectionKey: section, sort: "titleSort", start: offset, size: size))
      } catch {
        if error is CancellationError || (error as? URLError)?.code == .cancelled || Task.isCancelled {
          return .failure(CancellationError())
        }
        guard attempt < retryDelays.count else { return .failure(error) }
        retries.increment()
        do { try await Task.pause(retryDelays[attempt]) } catch { return .failure(CancellationError()) }
        attempt += 1
      }
    }
  }

  /// A count that pages running at once can add to.
  final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
  }
}

/// How long opening a title took until its full details showed, for
/// Settings → Sources (KP's requirement 14: measure before and after).
public struct OpenTimings: Codable, Sendable, Equatable {
  public private(set) var seconds: [Double] = []
  public static let keep = 30

  public init() {}

  public mutating func record(_ value: Double) {
    seconds.append(max(0, value))
    if seconds.count > Self.keep { seconds.removeFirst(seconds.count - Self.keep) }
  }

  public var last: Double? { seconds.last }

  public var median: Double? {
    guard !seconds.isEmpty else { return nil }
    let sorted = seconds.sorted()
    let mid = sorted.count / 2
    return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
  }

  public static let storageKey = "astra.openTimings"

  public static func load(_ defaults: UserDefaults = .standard) -> OpenTimings {
    guard let data = defaults.data(forKey: storageKey),
      let timings = try? JSONDecoder().decode(OpenTimings.self, from: data)
    else { return OpenTimings() }
    return timings
  }

  public func save(_ defaults: UserDefaults = .standard) {
    if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.storageKey) }
  }
}

/// When a read in progress publishes what it has (each publish re-matches
/// every row, so not after every page): at once the first time when there is
/// no earlier index (`eager`), whenever another library finishes, and
/// otherwise at most every `interval` seconds while titles keep arriving.
public final class PublishGate: @unchecked Sendable {
  private let lock = NSLock()
  private let eager: Bool
  private let interval: TimeInterval
  private let now: @Sendable () -> Date
  private var completed = 0
  private var count = 0
  private var last: Date?

  public init(eager: Bool, interval: TimeInterval = 8, now: @escaping @Sendable () -> Date = { Date() }) {
    self.eager = eager
    self.interval = interval
    self.now = now
  }

  public func shouldPublish(completed: Int, count: Int) -> Bool {
    lock.withLock {
      let time = now()
      var publish = completed > self.completed
      if !publish, eager, count > self.count {
        publish = last.map { time.timeIntervalSince($0) >= interval } ?? true
      }
      if publish {
        self.completed = completed
        self.count = count
        last = time
      }
      return publish
    }
  }
}

/// Each library's newest titles, read in one quick request, kept in every
/// index a read in progress publishes.
public final class IndexExtras: @unchecked Sendable {
  private let lock = NSLock()
  private var stored: [PlexMetadata] = []

  public init() {}

  public var items: [PlexMetadata] {
    get { lock.withLock { stored } }
    set { lock.withLock { stored = newValue } }
  }
}
