import AstraKit
import Foundation
import Observation

/// Live TV (KP, 2026-11-16): the IPTV source (an Xtream login or an M3U
/// link), its channels and guide, favourites and hidden categories. It is
/// separate from Plex: signing out of Plex leaves it alone, and the Live tab
/// only shows once a source is saved (and Settings → Live TV → Show Live tab
/// is on).
@MainActor
@Observable
final class LiveTVStore {
  enum Phase: Equatable {
    case idle
    case loading
    case ready
    case failed(String)
  }

  /// What the chips filter the guide to.
  enum Filter: Hashable {
    case all
    case favorites
    case group(String)
  }

  private(set) var source: LiveTVSource?
  private(set) var channels: [LiveChannel] = []
  private(set) var guide = LiveGuide()
  private(set) var phase: Phase = .idle
  private(set) var guideUpdated: Date?
  private(set) var loadingGuide = false
  /// Moves on every 30 s so progress bars and "11 min left" stay current.
  private(set) var now = Date()
  private(set) var favorites: Set<String>
  private(set) var hiddenGroups: Set<String>

  static let shownKey = "astra.liveTV.shown"
  private static let favoritesKey = "astra.liveTV.favorites"
  private static let hiddenKey = "astra.liveTV.hiddenGroups"
  /// The login sits in the Keychain (it holds a password).
  private let keychain: TokenStore
  @ObservationIgnored private var clock: Task<Void, Never>?
  @ObservationIgnored private var loadTask: Task<Void, Never>?

  init(keychain: TokenStore = KeychainTokenStore(service: "app.astra.livetv", account: "source")) {
    self.keychain = keychain
    let defaults = UserDefaults.standard
    favorites = Set(defaults.stringArray(forKey: Self.favoritesKey) ?? [])
    hiddenGroups = Set(defaults.stringArray(forKey: Self.hiddenKey) ?? [])
    if Demo.isOn {
      source = .m3u(playlist: "http://demo.astra/live.m3u", guide: nil)
      channels = LiveTVDemo.channels
      guide = LiveTVDemo.guide(now: now)
      guideUpdated = now
      phase = .ready
      if favorites.isEmpty { favorites = ["205", "101"] }
    } else {
      source = keychain.load().flatMap { try? JSONDecoder().decode(LiveTVSource.self, from: Data($0.utf8)) }
      if source != nil, let cached = Self.readCache() {
        channels = cached.channels
        guide = LiveGuide(cached.programs)
        guideUpdated = cached.saved
        phase = .ready
      }
    }
  }

  // MARK: - Loading

  /// Called when the Live page appears: starts the clock and refreshes a
  /// guide older than an hour (or never loaded).
  func start() {
    if clock == nil {
      clock = Task { [weak self] in
        while !Task.isCancelled {
          try? await Task.pause(30)
          self?.now = Date()
        }
      }
    }
    now = Date()
    guard source != nil, !Demo.isOn, loadTask == nil else { return }
    let stale = guideUpdated.map { Date().timeIntervalSince($0) > 3600 } ?? true
    if channels.isEmpty || stale { reload() }
  }

  /// Channels, then the guide in the background.
  func reload() {
    guard let source, !Demo.isOn else { return }
    loadTask?.cancel()
    if channels.isEmpty { phase = .loading }
    loadTask = Task { [weak self] in
      defer { self?.loadTask = nil }
      do {
        let loaded = try await LiveTVLoader.channels(for: source)
        guard let self, !Task.isCancelled, self.source == source else { return }
        self.channels = loaded.channels
        self.phase = .ready
        if let url = loaded.guide { await self.loadGuide(url) }
        self.writeCache()
      } catch {
        guard let self, !Task.isCancelled else { return }
        // Keep showing the saved channels when a refresh fails.
        if self.channels.isEmpty { self.phase = .failed(error.localizedDescription) }
      }
    }
  }

  private func loadGuide(_ url: URL) async {
    loadingGuide = true
    defer { loadingGuide = false }
    let channels = channels
    // Parsing a big XMLTV file is slow: off the main actor.
    let result = await Task.detached(priority: .utility) {
      try? await LiveTVLoader.guide(from: url, channels: channels)
    }.value
    if let result {
      guide = result
      guideUpdated = Date()
    }
  }

  /// Checks a new source (its channels must load), then saves it.
  func connect(_ new: LiveTVSource) async throws {
    let loaded = try await LiveTVLoader.channels(for: new)
    let data = try JSONEncoder().encode(new)
    keychain.save(String(decoding: data, as: UTF8.self))
    source = new
    channels = loaded.channels
    guide = LiveGuide()
    phase = .ready
    if let url = loaded.guide { await loadGuide(url) }
    writeCache()
  }

  /// Settings → Live TV → Remove: forgets the login, channels and guide.
  func remove() {
    loadTask?.cancel()
    keychain.clear()
    source = nil
    channels = []
    guide = LiveGuide()
    guideUpdated = nil
    phase = .idle
    try? FileManager.default.removeItem(at: Self.cacheURL)
  }

  // MARK: - What the page shows

  func channels(for filter: Filter) -> [LiveChannel] {
    switch filter {
    case .all: channels.filter { !hiddenGroups.contains($0.group ?? "") }
    case .favorites: channels.filter { favorites.contains($0.id) }
    case .group(let name): channels.filter { $0.group == name }
    }
  }

  var groups: [String] { LiveCategories.groups(in: channels, hidden: hiddenGroups) }
  var allGroups: [String] { LiveCategories.groups(in: channels) }

  func lineup(_ channel: LiveChannel, count: Int = 4) -> [LiveProgram] {
    guide.lineup(for: channel, at: now, count: count)
  }

  func nowOn(_ channel: LiveChannel) -> LiveProgram? { guide.now(on: channel, at: now) }

  func toggleFavorite(_ channel: LiveChannel) {
    if favorites.contains(channel.id) { favorites.remove(channel.id) } else { favorites.insert(channel.id) }
    UserDefaults.standard.set(Array(favorites), forKey: Self.favoritesKey)
  }

  func setHidden(_ group: String, _ hidden: Bool) {
    if hidden { hiddenGroups.insert(group) } else { hiddenGroups.remove(group) }
    UserDefaults.standard.set(Array(hiddenGroups), forKey: Self.hiddenKey)
  }

  // MARK: - Cache (so the page opens at once next launch)

  private struct Cache: Codable {
    var channels: [LiveChannel]
    var programs: [LiveProgram]
    var saved: Date
  }

  private static var cacheURL: URL {
    let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    return base.appendingPathComponent("astra-livetv.json")
  }

  private func writeCache() {
    let cache = Cache(channels: channels, programs: guide.programs.values.flatMap { $0 }, saved: guideUpdated ?? Date())
    let url = Self.cacheURL
    Task.detached(priority: .background) {
      if let data = try? JSONEncoder().encode(cache) { try? data.write(to: url, options: .atomic) }
    }
  }

  private static func readCache() -> Cache? {
    guard let data = try? Data(contentsOf: cacheURL) else { return nil }
    return try? JSONDecoder().decode(Cache.self, from: data)
  }
}

/// Made-up channels for the CI screenshots (`-AstraDemo YES`).
enum LiveTVDemo {
  static let channels: [LiveChannel] = [
    channel("205", "Sports 1", 205, "Sports"), channel("101", "Newsline HD", 101, "News"),
    channel("310", "Cinema Classics", 310, "Movies"), channel("412", "Food & Home", 412, "Entertainment"),
    channel("520", "Kids Zone", 520, "Kids"), channel("102", "World News", 102, "News"),
    channel("206", "Sports 2", 206, "Sports"), channel("311", "Action Movies", 311, "Movies"),
  ]

  private static func channel(_ id: String, _ name: String, _ number: Int, _ group: String) -> LiveChannel {
    LiveChannel(
      id: id, name: name, number: number, group: group, stream: URL(string: "http://demo.astra/live/\(id).ts")!,
      guideID: id)
  }

  static func guide(now: Date) -> LiveGuide {
    let titles: [String: [String]] = [
      "205": ["Sunday Night Football", "Post-game Show", "Highlights", "Sports Tonight"],
      "101": ["Evening News", "Game Night", "Late Edition", "Overnight"],
      "310": ["The Getaway", "Midnight Run", "Night Train", "The Long Road"],
      "412": ["Kitchen Rescue", "Home Flip", "Garden Rooms", "Bake Off"],
      "520": ["Cartoon Hour", "Ocean Pals", "Space Cadets", "Bedtime Stories"],
      "102": ["World Report", "Business Today", "World Report", "Overnight"],
      "206": ["College Basketball", "Fight Night", "Replay", "Golf Classics"],
      "311": ["Steel Rain", "Overdrive", "Last Stand", "Thunder Road"],
    ]
    let base = Calendar.current.dateInterval(of: .hour, for: now)?.start ?? now
    var programs: [LiveProgram] = []
    for (index, (id, list)) in titles.sorted(by: { $0.key < $1.key }).enumerated() {
      var start = base.addingTimeInterval(-Double((index % 3) * 20 + 10) * 60)
      for (n, title) in list.enumerated() {
        let length = Double(n == 0 ? 60 + (index % 4) * 30 : 30 + (n % 2) * 30) * 60
        programs.append(
          LiveProgram(
            channel: id, title: title, start: start, end: start.addingTimeInterval(length),
            summary: n == 0 ? "Live now on Astra's demo channel." : nil))
        start = start.addingTimeInterval(length)
      }
    }
    return LiveGuide(programs)
  }
}
