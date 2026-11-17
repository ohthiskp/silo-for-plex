import AstraKit
import Foundation
import Observation

/// Settings → Sources: the Jellyfin, Emby and SMB sources next to Plex
/// (KP, 2026-11-17: "add support for all that infuse has"). Owns their saved
/// configs, sign-ins, share indexes and the local file server, and hands
/// `AppModel` a `SourceRouter` whenever they change.
@MainActor
@Observable
final class SourcesModel {
  enum Status: Equatable {
    case ready
    case working(String)
    case failed(String)
  }

  private(set) var configs: [SourceConfig] = []
  /// Per source: a scan in progress, or why it couldn't be read.
  private(set) var status: [String: Status] = [:]
  /// Set by `AppModel`: the sources changed, so the library is rebuilt with them.
  @ObservationIgnored var onChange: (() -> Void)?

  @ObservationIgnored private let store: SourceStore
  @ObservationIgnored private let info: PlexClientInfo
  @ObservationIgnored private var providers: [String: SMBShareProvider] = [:]
  @ObservationIgnored private var shareStates: [String: ShareLibraryState] = [:]
  @ObservationIgnored private var scans: [String: Task<Void, Never>] = [:]
  #if canImport(Network)
    /// Serves share files to mpv over 127.0.0.1 (set up at the end of `init`).
    @ObservationIgnored private var fileServer: LoopbackFileServer!
  #endif
  @ObservationIgnored private var router = SourceRouter.none
  @ObservationIgnored private var tmdb: TMDBClient? {
    guard let token = Bundle.main.object(forInfoDictionaryKey: "AstraTMDBToken") as? String, !token.isEmpty,
      !token.hasPrefix("$(")
    else { return nil }
    return TMDBClient(token: token)
  }

  init(info: PlexClientInfo, store: SourceStore = SourceStore()) {
    self.info = info
    self.store = store
    configs = Demo.isOn ? Demo.sources : store.load()
    #if canImport(Network)
      fileServer = LoopbackFileServer { [weak self] source, path in
        guard let self else { throw SourceError.unreachable }
        return try await self.share(for: source, path: path)
      }
    #endif
    // Ready before the first library opens; share URLs work once the file server runs.
    router = makeRouter()
  }

  /// The sources as clients, for the library. Built again after each change.
  var currentRouter: SourceRouter { router }

  // MARK: - Launch

  /// Opens every source: starts the file server for shares, then refreshes
  /// media servers' library lists and re-reads shares not read in 6 hours.
  func start() async {
    guard !Demo.isOn else { return }
    #if canImport(Network)
      if configs.contains(where: { $0.kind == .smb && $0.enabled }) { try? await fileServer.start() }
    #endif
    for config in configs where config.enabled {
      switch config.kind {
      case .jellyfin, .emby: Task { await refreshLibraries(config.id) }
      case .smb:
        let state = shareState(config.id)
        let stale = config.folders.contains { folder in
          (state.index.scannedAt[folder.id].map { Date().timeIntervalSince($0) > 6 * 3600 }) ?? true
        }
        if stale { scan(config.id) }
      }
    }
  }

  /// Builds the clients again and tells the library.
  private func rebuild() async {
    #if canImport(Network)
      if configs.contains(where: { $0.kind == .smb && $0.enabled }) { try? await fileServer.start() }
    #endif
    router = makeRouter()
    onChange?()
  }

  /// The clients for every enabled source, with the file server's address for shares.
  private func makeRouter() -> SourceRouter {
    // Screenshots list the demo sources in Settings but never contact them.
    guard !Demo.isOn else { return .none }
    var clients: [any MediaSourceClient] = []
    for config in configs where config.enabled {
      switch config.kind {
      case .jellyfin, .emby:
        let token = secret(config.id) ?? ""
        if let client = try? JellyfinClient(config: config, token: token, info: info) { clients.append(client) }
      case .smb:
        let id = config.id
        #if canImport(Network)
          let server = fileServer!
          let base: @Sendable () -> URL? = { server.base(for: id) }
        #else
          let base: @Sendable () -> URL? = { nil }
        #endif
        clients.append(ShareClient(config: config, state: shareState(id), streamBase: base))
      }
    }
    return SourceRouter(clients)
  }

  // MARK: - Adding and removing

  /// Signs in to a Jellyfin or Emby server, reads its libraries and adds it.
  func addMediaServer(kind: SourceKind, address: String, username: String, password: String) async throws {
    let signIn = try await JellyfinClient.signIn(
      kind: kind, address: address, username: username, password: password, info: info)
    var config = SourceConfig(
      kind: kind, name: signIn.serverName ?? kind.title,
      address: JellyfinClient.normalizedURL(address)?.absoluteString ?? address, username: username,
      userID: signIn.userID)
    let client = try JellyfinClient(config: config, token: signIn.token, info: info)
    config.libraries = try await client.libraries()
    saveSecret(signIn.token, for: config.id)
    configs.append(config)
    store.save(configs)
    await rebuild()
  }

  /// A provider for the Add Share pages: the login typed, or an existing source's saved one.
  private func provider(_ login: ShareLogin) -> SMBShareProvider {
    if let id = login.existingID, let config = configs.first(where: { $0.id == id }) {
      return SMBShareProvider(host: config.address, username: config.username, password: secret(id) ?? "")
    }
    return SMBShareProvider(host: login.host, username: login.username, password: login.password)
  }

  /// Connects to an SMB server and lists its shares, for the Add Share page.
  func shareNames(_ login: ShareLogin) async throws -> [String] {
    try await provider(login).shareNames()
  }

  /// The folders inside `path` on a share, for picking the library folder.
  func folders(_ login: ShareLogin, share: String, path: String) async throws -> [String] {
    let provider = provider(login)
    defer { provider.disconnectAll() }
    let entries = try await provider.share(share).list(path)
    return entries.filter { $0.isDirectory && !MediaFiles.skips(folder: $0.name) }.map(\.path).sorted {
      $0.localizedStandardCompare($1) == .orderedAscending
    }
  }

  /// Adds an SMB share folder as a library, then reads it.
  func addShare(login: ShareLogin, share: String, path: String, content: FolderContent) async {
    let title = path.split(separator: "/").last.map(String.init) ?? share
    let folder = SourceFolder(share: share, path: path, content: content, title: title)
    // One source per server and sign-in; another folder on it joins that source.
    let host = SMBShareProvider(host: login.host, username: "", password: "").host
    if let index = configs.firstIndex(where: {
      $0.id == login.existingID
        || ($0.kind == .smb && $0.address.caseInsensitiveCompare(host) == .orderedSame && $0.username == login.username)
    }) {
      configs[index].folders.append(folder)
      if login.existingID == nil { saveSecret(login.password, for: configs[index].id) }
      providers[configs[index].id] = nil
    } else {
      let config = SourceConfig(
        kind: .smb, name: login.name.isEmpty ? host : login.name, address: host, username: login.username,
        folders: [folder])
      saveSecret(login.password, for: config.id)
      configs.append(config)
    }
    store.save(configs)
    await rebuild()
    if let config = configs.first(where: { $0.folders.contains(folder) }) { scan(config.id, only: folder.id) }
  }

  func remove(_ id: String) {
    scans[id]?.cancel()
    scans[id] = nil
    providers[id]?.disconnectAll()
    providers[id] = nil
    shareStates[id] = nil
    status[id] = nil
    configs.removeAll { $0.id == id }
    keychain(id).clear()
    store.removeFiles(of: id)
    store.save(configs)
    Task { await rebuild() }
  }

  func removeFolder(_ folderID: String, from id: String) {
    guard let index = configs.firstIndex(where: { $0.id == id }) else { return }
    configs[index].folders.removeAll { $0.id == folderID }
    if configs[index].folders.isEmpty { return remove(id) }
    let state = shareState(id)
    var shareIndex = state.index
    shareIndex.files.removeAll { $0.folder == folderID }
    state.setIndex(shareIndex)
    store.save(configs)
    Task { await rebuild() }
  }

  func setEnabled(_ id: String, _ enabled: Bool) {
    guard let index = configs.firstIndex(where: { $0.id == id }) else { return }
    configs[index].enabled = enabled
    store.save(configs)
    Task { await rebuild() }
  }

  // MARK: - Refreshing

  /// Reads a Jellyfin/Emby server's library list again; saves and rebuilds when it changed.
  func refreshLibraries(_ id: String) async {
    guard let config = configs.first(where: { $0.id == id }), config.kind.isMediaServer,
      let client = router.client(id: id)
    else { return }
    do {
      let libraries = try await client.libraries()
      status[id] = .ready
      guard libraries != config.libraries, let index = configs.firstIndex(where: { $0.id == id }) else { return }
      configs[index].libraries = libraries
      store.save(configs)
      await rebuild()
    } catch SourceError.wrongLogin {
      status[id] = .failed("Sign in again: the server no longer accepts Astra's sign-in.")
    } catch {
      status[id] = .failed(PlexError.describe(error))
    }
  }

  /// Reads a share's folders again (or one folder) and matches new titles on TMDB.
  func scan(_ id: String, only folderID: String? = nil) {
    guard let config = configs.first(where: { $0.id == id }), config.kind == .smb, scans[id] == nil else { return }
    let folders = config.folders.filter { folderID == nil || $0.id == folderID }
    let state = shareState(id)
    let matcher = tmdb
    status[id] = .working("Looking for titles…")
    scans[id] = Task { [weak self] in
      var failure: String?
      for folder in folders {
        guard let self, !Task.isCancelled else { break }
        do {
          let share = try await self.share(for: id, name: folder.share)
          let index = try await ShareScanner.scan(folder, share: share, into: state.index, matcher: matcher) { progress in
            await MainActor.run { [weak self] in
              let found = progress.files == 1 ? "1 file" : "\(progress.files) files"
              self?.status[id] = .working(progress.matched > 0 ? "\(found), \(progress.matched) matched" : "Found \(found)")
            }
          }
          state.setIndex(index)
        } catch {
          failure = PlexError.describe(error)
        }
      }
      guard let self else { return }
      self.scans[id] = nil
      self.status[id] = failure.map(Status.failed) ?? .ready
      await self.rebuild()
    }
  }

  func isScanning(_ id: String) -> Bool { scans[id] != nil }

  // MARK: - Shares

  private func shareState(_ id: String) -> ShareLibraryState {
    if let state = shareStates[id] { return state }
    let state = ShareLibraryState.load(sourceID: id, directory: store.directory)
    shareStates[id] = state
    return state
  }

  /// The share a file server path belongs to ("<share>/<path>" isn't how
  /// paths look: a path is inside one of the source's folders, whose share it uses).
  private func share(for sourceID: String, path: String) async throws -> any FileShare {
    guard let config = configs.first(where: { $0.id == sourceID }) else { throw SourceError.notFound }
    let file = shareState(sourceID).index.files.first { $0.path == path }
    let folder = config.folders.first { $0.id == file?.folder } ?? config.folders.first {
      $0.path.isEmpty || path.hasPrefix($0.path + "/")
    }
    guard let folder else { throw SourceError.notFound }
    return try await share(for: sourceID, name: folder.share)
  }

  private func share(for sourceID: String, name: String) async throws -> any FileShare {
    guard let config = configs.first(where: { $0.id == sourceID }) else { throw SourceError.notFound }
    let provider: SMBShareProvider
    if let existing = providers[sourceID] {
      provider = existing
    } else {
      provider = SMBShareProvider(host: config.address, username: config.username, password: secret(sourceID) ?? "")
      providers[sourceID] = provider
    }
    return try await provider.share(name)
  }

  // MARK: - Keychain

  private func keychain(_ id: String) -> TokenStore {
    #if canImport(Security)
      KeychainTokenStore(service: "app.astra.sources", account: "source-\(id)")
    #else
      MemoryTokenStore()
    #endif
  }

  private func secret(_ id: String) -> String? { keychain(id).load() }

  private func saveSecret(_ value: String, for id: String) {
    if value.isEmpty { keychain(id).clear() } else { keychain(id).save(value) }
  }
}
