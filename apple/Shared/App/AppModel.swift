import AstraKit
import Foundation
import Observation
import SwiftUI

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

/// App-wide state: who is signed in, which server Astra talks to, and the player.
@MainActor
@Observable
final class AppModel {
  enum Phase: Equatable {
    case launching
    case signedOut
    case waitingForApproval(code: String, url: URL)
    case choosingServer([PlexServerResource])
    case connecting(String)
    case ready
    case failed(String)
  }

  private(set) var phase: Phase = .launching
  private(set) var server: PlexServerClient?
  private(set) var library: LibraryStore?
  /// The connected server's Plex id.
  private(set) var serverID: String?

  /// Server switching while connected (Settings → Change Server). The current
  /// server keeps working until the new one is validated; see `connect(to:)`.
  struct ServerSwitch: Equatable {
    var servers: [PlexServerResource] = []
    var loadingList = true
    /// The server (its Plex id) being validated right now.
    var connecting: String?
    var error: String?
  }
  var serverSwitch: ServerSwitch?
  let player = PlayerController()
  let downloads = DownloadStore()

  let info: PlexClientInfo
  private let account: PlexAccountClient
  private let connector: ServerConnector
  /// Each connection attempt's identity; a slower, older attempt never wins.
  private var connectGeneration = Generation()
  private let tokens: TokenStore
  /// The last server's own access token, for opening it at launch with no wait.
  private let serverTokens: TokenStore
  private var accountToken: String?
  private var signInTask: Task<Void, Never>?

  private static let serverKey = "astra.plex.serverIdentifier"

  init(
    tokens: TokenStore = KeychainTokenStore(),
    serverTokens: TokenStore = KeychainTokenStore(account: "server-token")
  ) {
    let bundle = Bundle.main
    let os = ProcessInfo.processInfo.operatingSystemVersion
    #if os(macOS)
      let platform = "macOS"
      let device = "Mac"
      let deviceName = Host.current().localizedName ?? "Mac"
    #else
      let platform = "iOS"
      let device = UIDevice.current.model
      let deviceName = UIDevice.current.name
    #endif
    info = PlexClientInfo(
      version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1",
      platform: platform,
      platformVersion: "\(os.majorVersion).\(os.minorVersion)",
      device: device,
      deviceName: deviceName,
      clientIdentifier: PlexClientInfo.persistentIdentifier()
    )
    account = PlexAccountClient(info: info)
    connector = ServerConnector(info: info)
    self.tokens = tokens
    self.serverTokens = serverTokens
    player.playNext = { [weak self] next in self?.playEpisode(next) }
  }

  /// Next Episode (tap only): plays `episode`, from its download when there is one.
  private func playEpisode(_ episode: PlexMetadata) {
    guard let library else { return }
    do {
      try player.play(episode, library: library, local: downloads.source(for: episode))
    } catch {
      player.lastError = error.localizedDescription
    }
  }

  // MARK: - Launch

  func start() async {
    guard phase == .launching else { return }
    // Astra: CI screenshots run against a fake server (Demo.swift).
    if Demo.isOn {
      commit(Demo.session(info: info))
      if let demo = Demo.playback() {
        // UI tests: straight into the player with a local file.
        try? await Task.pause(2)
        if let library { try? player.play(demo.0, library: library, local: demo.1) }
      }
      return
    }
    guard let token = tokens.load() else {
      phase = .signedOut
      return
    }
    accountToken = token
    // Astra (KP: "Plex and Infuse open immediately"): the last server that
    // worked opens at once, with Home from its saved copies; plex.tv and the
    // address are checked behind it, and only a failure reconnects.
    if let saved = SavedConnection.load(),
      saved.serverID == UserDefaults.standard.string(forKey: Self.serverKey),
      let serverToken = serverTokens.load()
    {
      let attempt = connectGeneration.next()
      commit(connector.resume(saved, token: serverToken, generation: attempt))
      Task { await verifyResumed(attempt, accountToken: token) }
      return
    }
    await loadServers(token: token, autoSelect: true)
  }

  /// Checks the session opened from the saved connection. If its address no
  /// longer answers (another network, a new IP), the server is looked up on
  /// plex.tv and connected again; if plex.tv says the sign-in ended, signs out.
  /// Offline, the saved session stays (downloads keep working).
  private func verifyResumed(_ attempt: Int, accountToken token: String) async {
    guard let session, connectGeneration.isCurrent(attempt) else { return }
    async let valid = try? account.validate(token: token)
    let reachable = await connector.check(session) != nil
    if await valid == false {
      guard connectGeneration.isCurrent(attempt) else { return }
      return signOut()
    }
    guard !reachable, connectGeneration.isCurrent(attempt) else { return }
    guard let servers = try? await account.servers(token: token),
      let match = servers.first(where: { $0.clientIdentifier == session.serverID }),
      connectGeneration.isCurrent(attempt)
    else { return }
    let retry = connectGeneration.next()
    guard let fresh = try? await connector.connect(to: match, accountToken: token, generation: retry),
      connectGeneration.isCurrent(retry), phase == .ready
    else { return }
    commit(fresh)
  }

  // MARK: - Sign-in

  func signIn() {
    signInTask?.cancel()
    signInTask = Task { [weak self] in
      guard let self else { return }
      do {
        let pin = try await account.createPin()
        let url = account.authURL(for: pin)
        phase = .waitingForApproval(code: pin.code, url: url)
        Self.open(url)
        let token = try await account.waitForToken(pin)
        // A failed save (logged by the store) only means signing in again next launch.
        tokens.save(token)
        accountToken = token
        await loadServers(token: token, autoSelect: true)
      } catch {
        // Cancel already set .signedOut. A request in flight ends with
        // URLError(.cancelled), not CancellationError, so check the task itself.
        if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
          if !Task.isCancelled { phase = .signedOut }
          return
        }
        phase = .failed(error.localizedDescription)
      }
    }
  }

  static func open(_ url: URL) {
    #if os(macOS)
      NSWorkspace.shared.open(url)
    #else
      UIApplication.shared.open(url)
    #endif
  }

  func cancelSignIn() {
    signInTask?.cancel()
    signInTask = nil
    phase = .signedOut
  }

  func signOut() {
    player.close()
    serverSwitch = nil
    _ = connectGeneration.next()
    library?.close()
    downloads.attach(nil, serverID: nil)
    tokens.clear()
    serverTokens.clear()
    SavedConnection.clear()
    UserDefaults.standard.removeObject(forKey: Self.serverKey)
    accountToken = nil
    server = nil
    serverID = nil
    library = nil
    health?.stop()
    health = nil
    watchlistItems = nil
    watchlistKeys = []
    watchlistRefreshedAt = nil
    // A Watchlist read still in flight must not save the old account's list.
    watchlistRefresh?.cancel()
    watchlistRefresh = nil
    watchlistGeneration += 1
    let watchlistURL = Self.watchlistURL
    onWatchlistDisk { try? FileManager.default.removeItem(at: watchlistURL) }
    // The saved library lists go too, so nothing of the account stays on disk
    // (off the main thread: a big library's lists take a moment to delete).
    let indexFolder = LibraryStore.indexFolder
    Task.detached(priority: .utility) { try? FileManager.default.removeItem(at: indexFolder) }
    // Cached artwork and the per-server image tokens go too (security review).
    ImagePipeline.shared.clearCache()
    phase = .signedOut
  }

  // MARK: - Servers

  private func loadServers(token: String, autoSelect: Bool) async {
    phase = .connecting("Plex")
    do {
      guard try await account.validate(token: token) else {
        // plex.tv ended the sign-in: forget the server's token and address too.
        tokens.clear()
        serverTokens.clear()
        SavedConnection.clear()
        UserDefaults.standard.removeObject(forKey: Self.serverKey)
        phase = .signedOut
        return
      }
      let servers = try await account.servers(token: token)
      let saved = UserDefaults.standard.string(forKey: Self.serverKey)
      if autoSelect, let match = servers.first(where: { $0.clientIdentifier == saved }) ?? (servers.count == 1 ? servers.first : nil) {
        await connect(to: match)
      } else if servers.isEmpty {
        phase = .failed("This Plex account has no servers.")
      } else {
        phase = .choosingServer(servers)
      }
    } catch {
      phase = .failed(error.localizedDescription)
    }
  }

  /// Settings → Change Server. While connected, the list opens over the app
  /// and the current server stays in use until another one is validated.
  func chooseServer() async {
    guard let accountToken else { return phase = .signedOut }
    guard phase == .ready, library != nil else {
      return await loadServers(token: accountToken, autoSelect: false)
    }
    // Already open (maybe mid-connect): keep its state, only refresh the list.
    if serverSwitch == nil { serverSwitch = ServerSwitch() }
    do {
      let servers = try await account.servers(token: accountToken)
      guard serverSwitch != nil else { return }
      serverSwitch?.servers = servers
      serverSwitch?.loadingList = false
      if servers.isEmpty { serverSwitch?.error = "This Plex account has no servers." }
    } catch {
      guard serverSwitch != nil else { return }
      serverSwitch?.loadingList = false
      if serverSwitch?.servers.isEmpty ?? true {
        serverSwitch?.error = PlexError.describe(error, server: "Plex")
      }
    }
  }

  func cancelServerSwitch() {
    _ = connectGeneration.next()
    serverSwitch = nil
  }

  /// Connects to a server. The address is probed and the token checked
  /// (by listing libraries) before anything changes; only then is the old
  /// session closed and replaced. If it fails while another server is in
  /// use, that server keeps working and the error shows in the switcher.
  func connect(to resource: PlexServerResource) async {
    guard let accountToken else { return phase = .signedOut }
    let attempt = connectGeneration.next()
    let switching = phase == .ready && library != nil
    if switching {
      if serverSwitch == nil { serverSwitch = ServerSwitch(loadingList: false) }
      serverSwitch?.connecting = resource.clientIdentifier
      serverSwitch?.error = nil
    } else {
      phase = .connecting(resource.name)
    }
    do {
      let session = try await connector.connect(to: resource, accountToken: accountToken, generation: attempt)
      // Another attempt (or Cancel, or Sign Out) came after this one: drop it.
      guard connectGeneration.isCurrent(attempt) else { return }
      commit(session)
    } catch {
      guard connectGeneration.isCurrent(attempt) else { return }
      let message = PlexError.describe(error, server: resource.name)
      if switching {
        serverSwitch?.connecting = nil
        serverSwitch?.error = message
      } else {
        phase = .failed(message)
      }
    }
  }

  /// The connected server's session, kept so the library can be rebuilt.
  @ObservationIgnored private var session: ServerSession?
  /// Astra 4.0: the connected server's health (nil before a server is chosen).
  private(set) var health: ServerHealthMonitor?

  /// Whether `item` can play now: its download is here, or the server isn't
  /// confirmed unreachable (KP: don't keep trying to play while it's offline).
  func canPlay(_ item: PlexMetadata) -> Bool {
    if downloads.source(for: item) != nil { return true }
    return health?.state.allowsStreaming ?? true
  }

  /// Settings → Content → Library Quality changed: Home, the tabs and search
  /// are rebuilt with the new choice (each choice keeps its own saved index).
  func libraryQualityChanged() {
    guard let session, let library, library.libraryQuality != LibraryQuality.stored() else { return }
    commit(session)
  }

  private func commit(_ session: ServerSession) {
    self.session = session
    let old = library
    let store = LibraryStore(session: session)
    UserDefaults.standard.set(session.serverID, forKey: Self.serverKey)
    if !Demo.isOn {
      SavedConnection(session).save()
      serverTokens.save(session.client.token)
    }
    server = session.client
    serverID = session.serverID
    library = store
    health?.stop()
    let monitor = ServerHealthMonitor(client: session.client)
    health = monitor
    // Details skips the Plex search while the server is down (shows "Couldn't check your server").
    store.serverReachable = { [weak monitor] in monitor?.state.allowsStreaming ?? true }
    if !Demo.isOn { monitor.start() }
    downloads.attach(store, serverID: session.serverID)
    player.server = session.client
    serverSwitch = nil
    phase = .ready
    // The old server's requests stop; anything still in flight is ignored.
    old?.close()
    Task { await store.loadHome() }
  }

  /// Plays an item; a show or season plays its next episode.
  func play(_ item: PlexMetadata) {
    guard let library else { return }
    Task {
      do {
        let resolved = try await library.resolve(item)
        // A downloaded movie or episode plays from disk.
        if let local = downloads.source(for: resolved) {
          return try player.play(resolved, library: library, local: local)
        }
        // Astra 4.0: no streaming attempt while the server is confirmed down.
        if let health, !health.state.allowsStreaming {
          player.lastError = Self.unavailableMessage
          return
        }
        let playable = try await library.playable(for: resolved)
        try player.play(playable, library: library, local: downloads.source(for: playable))
      } catch {
        player.lastError = error.localizedDescription
        health?.requestFailed(error)
      }
    }
  }

  static let unavailableMessage =
    "Your media server is unavailable. You can still browse, but streaming is temporarily unavailable."

  /// Plays a downloaded file from disk, resuming where Plex says when the server answers.
  func playDownload(_ record: DownloadRecord) {
    Task {
      var item = PlexMetadata(ratingKey: record.ratingKey, type: record.type, title: record.title)
      if let library, let fresh = try? await library.details(record.ratingKey, refresh: true) { item = fresh }
      guard let local = downloads.source(for: item) else {
        player.lastError = "The downloaded file is missing."
        return
      }
      do {
        guard let library else { throw PlexError.notSignedIn }
        try player.play(item, library: library, local: local)
      } catch {
        player.lastError = error.localizedDescription
      }
    }
  }

  /// Runs `action` with the Plex item for `item`; a TMDB title is looked up on the server first.
  func resolve(_ item: PlexMetadata, then action: @escaping (PlexMetadata) -> Void) {
    guard item.isCatalogOnly, let library else { return action(item) }
    Task {
      do {
        action(try await library.resolve(item))
      } catch {
        player.lastError = error.localizedDescription
      }
    }
  }

  // MARK: - Watchlist (Astra 4.0)

  /// The Plex Watchlist, newest first: the saved copy at once (nil until
  /// there is one), then plex.tv's answer. Shown even when the server is down.
  private(set) var watchlistItems: [PlexMetadata]? = AppModel.savedWatchlist
  /// Why the last refresh failed; the saved list stays on screen.
  private(set) var watchlistError: String?
  /// TMDB keys of the titles on the Plex Watchlist, for the + / ✓ buttons.
  private(set) var watchlistKeys: Set<String> = Set((AppModel.savedWatchlist ?? []).compactMap(\.tmdbKey))
  /// The saved Watchlist, read from disk once at launch (it was decoded twice).
  nonisolated private static let savedWatchlist = WatchlistSnapshot.load(from: AppModel.watchlistURL)?.items
  @ObservationIgnored private var watchlistRefresh: Task<Void, Never>?
  @ObservationIgnored private var watchlistRefreshedAt: Date?
  /// Bumped on sign-out, so a Watchlist read that started before it is dropped.
  @ObservationIgnored private var watchlistGeneration = 0

  nonisolated static var watchlistURL: URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    return base.appendingPathComponent("Astra/Watchlist.json")
  }

  func isOnWatchlist(_ item: PlexMetadata) -> Bool {
    item.tmdbKey.map(watchlistKeys.contains) ?? false
  }

  /// Reads the Watchlist from plex.tv. Callers share one request; within
  /// 30 s of the last one nothing is sent unless `force`.
  func refreshWatchlist(force: Bool = false) async {
    if let running = watchlistRefresh { return await running.value }
    if !force, let at = watchlistRefreshedAt, Date().timeIntervalSince(at) < 30 { return }
    guard let accountToken else {
      watchlistError = PlexError.describe(PlexError.notSignedIn)
      return
    }
    let account = account
    let generation = watchlistGeneration
    let task = Task { @MainActor [weak self] in
      do {
        let list = try await account.watchlist(token: accountToken)
        guard let self, !Task.isCancelled, generation == self.watchlistGeneration else { return }
        self.setWatchlist(list)
        self.watchlistError = nil
        self.watchlistRefreshedAt = Date()
      } catch {
        self?.watchlistError = PlexError.describe(error)
      }
    }
    watchlistRefresh = task
    await task.value
    watchlistRefresh = nil
  }

  /// Reads the Watchlist once so the + buttons know what's already on it.
  func loadWatchlistIfNeeded() async {
    guard watchlistRefreshedAt == nil else { return }
    await refreshWatchlist()
  }

  private func setWatchlist(_ list: [PlexMetadata]) {
    watchlistItems = list
    watchlistKeys = Set(list.compactMap(\.tmdbKey))
    let snapshot = WatchlistSnapshot(savedAt: Date(), items: list)
    let url = Self.watchlistURL
    onWatchlistDisk { try? snapshot.save(to: url) }
  }

  /// Every Watchlist.json write on one chain, in the order made, so a delete
  /// on sign-out always wins over an earlier save.
  @ObservationIgnored private var watchlistDisk: Task<Void, Never>?

  private func onWatchlistDisk(_ work: @escaping @Sendable () -> Void) {
    let previous = watchlistDisk
    watchlistDisk = Task.detached(priority: .utility) {
      await previous?.value
      work()
    }
  }

  /// Astra (KP, 2026-11-07): the + adds to the Plex Watchlist, ✓ takes it
  /// off. The button flips at once; on failure it flips back.
  func toggleWatchlist(_ item: PlexMetadata) async {
    guard let accountToken, let key = item.tmdbKey else { return }
    let adding = !watchlistKeys.contains(key)
    if adding { watchlistKeys.insert(key) } else { watchlistKeys.remove(key) }
    // The Watchlist page changes at once too, with no refetch.
    watchlistItems = WatchlistMatch.toggled(watchlistItems ?? [], item, adding: adding)
    do {
      guard let catalog = try await account.catalogKey(for: item, token: accountToken) else {
        throw PlexError.invalidResponse
      }
      if adding {
        try await account.addToWatchlist(catalogKey: catalog, token: accountToken)
      } else {
        try await account.removeFromWatchlist(catalogKey: catalog, token: accountToken)
      }
      if let list = watchlistItems { setWatchlist(list) }
    } catch {
      if adding { watchlistKeys.remove(key) } else { watchlistKeys.insert(key) }
      // Undo only this change, so a refresh that landed meanwhile is kept.
      if let list = watchlistItems { watchlistItems = WatchlistMatch.toggled(list, item, adding: !adding) }
      player.lastError = "Couldn't update your Watchlist: \(PlexError.describe(error))"
    }
  }

  func retry() async {
    if let accountToken {
      await loadServers(token: accountToken, autoSelect: true)
    } else {
      phase = .signedOut
    }
  }
}
