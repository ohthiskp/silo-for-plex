import AstraKit
import Foundation
import Observation

/// Every source next to Plex (KP, 2026-11-17: "add support for all that
/// infuse has"): Jellyfin and Emby servers, SMB and WebDAV shares, and cloud
/// drives (Google Drive, Dropbox, OneDrive, Box, pCloud, Yandex Disk). Owns
/// their saved configs, sign-ins (Keychain), share indexes and the local file
/// server, and hands `AppModel` a `SourceRouter` whenever they change.
///
/// This is the engine only: KP designs the screens (2026-11-17: "Just build
/// the back end … The UI and stuff I'll give you"). A screen calls these
/// methods; nothing here presents anything.
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
  @ObservationIgnored private var providers: [String: any FileShareProvider] = [:]
  @ObservationIgnored private var shareStates: [String: ShareLibraryState] = [:]
  @ObservationIgnored private var scans: [String: Task<Void, Never>] = [:]
  #if canImport(Network)
    /// Serves share and cloud files to mpv over 127.0.0.1 (set up at the end of `init`).
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
    configs = Demo.isOn ? [] : store.load()
    #if canImport(Network)
      fileServer = LoopbackFileServer { [weak self] source, path in
        guard let self else { throw SourceError.unreachable }
        return try await self.share(for: source, path: path)
      }
    #endif
    // Ready before the first library opens; file URLs work once the file server runs.
    router = makeRouter()
  }

  /// The sources as clients, for the library. Built again after each change.
  var currentRouter: SourceRouter { router }

  // MARK: - What can be added

  /// Kinds this build can add: media servers and shares always, a cloud
  /// drive only when its app registration is in Info.plist. Plex is the
  /// app's own sign-in, listed so a screen can show the three media servers together.
  func isAvailable(_ kind: SourceKind) -> Bool {
    kind.category != .cloud || cloudApp(kind) != nil
  }

  func kinds(in category: SourceKind.Category) -> [SourceKind] {
    SourceKind.kinds(in: category).filter(isAvailable)
  }

  // MARK: - Launch

  /// Opens every source: starts the file server, refreshes media servers'
  /// library lists and re-reads folders not read in 6 hours.
  func start() async {
    guard !Demo.isOn else { return }
    await startFileServerIfNeeded()
    for config in configs where config.enabled {
      if config.kind.isMediaServer {
        Task { await refreshLibraries(config.id) }
      } else {
        let state = shareState(config.id)
        let stale = config.folders.contains { folder in
          (state.index.scannedAt[folder.id].map { Date().timeIntervalSince($0) > 6 * 3600 }) ?? true
        }
        if stale { scan(config.id) }
      }
    }
  }

  private func startFileServerIfNeeded() async {
    #if canImport(Network)
      if configs.contains(where: { $0.kind.isFileSource && $0.enabled }) { try? await fileServer.start() }
    #endif
  }

  /// Builds the clients again and tells the library.
  private func rebuild() async {
    await startFileServerIfNeeded()
    router = makeRouter()
    onChange?()
  }

  /// The clients for every enabled source, with the file server's address for file sources.
  private func makeRouter() -> SourceRouter {
    guard !Demo.isOn else { return .none }
    var clients: [any MediaSourceClient] = []
    for config in configs where config.enabled {
      switch config.kind {
      case .plex:
        continue
      case .jellyfin, .emby:
        let token = secret(config.id) ?? ""
        if let client = try? JellyfinClient(config: config, token: token, info: info) { clients.append(client) }
      default:
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

  private func add(_ config: SourceConfig, secret: String) async {
    saveSecret(secret, for: config.id)
    configs.append(config)
    store.save(configs)
    await rebuild()
  }

  // MARK: - Jellyfin and Emby

  /// Signs in to a Jellyfin or Emby server, reads its libraries and adds it.
  @discardableResult
  func addMediaServer(kind: SourceKind, address: String, username: String, password: String) async throws -> String {
    let signIn = try await JellyfinClient.signIn(
      kind: kind, address: address, username: username, password: password, info: info)
    var config = SourceConfig(
      kind: kind, name: signIn.serverName ?? kind.title,
      address: JellyfinClient.normalizedURL(address)?.absoluteString ?? address, username: username,
      userID: signIn.userID)
    let client = try JellyfinClient(config: config, token: signIn.token, info: info)
    config.libraries = try await client.libraries()
    await add(config, secret: signIn.token)
    return config.id
  }

  // MARK: - SMB

  /// A provider for an SMB server being set up: the login typed, or an existing source's saved one.
  private func smbProvider(_ login: ShareLogin) -> SMBShareProvider {
    if let id = login.existingID, let config = configs.first(where: { $0.id == id }) {
      return SMBShareProvider(host: config.address, username: config.username, password: secret(id) ?? "")
    }
    return SMBShareProvider(host: login.host, username: login.username, password: login.password)
  }

  /// Connects to an SMB server and lists its shares, before it's added.
  func shareNames(_ login: ShareLogin) async throws -> [String] {
    try await smbProvider(login).shareNames()
  }

  /// The folders inside `path` on an SMB share, before it's added.
  func folders(_ login: ShareLogin, share: String, path: String) async throws -> [String] {
    let provider = smbProvider(login)
    defer { provider.disconnectAll() }
    return try await Self.folderPaths(in: provider.share(share), path: path)
  }

  /// Adds an SMB share folder as a library, then reads it. One source per
  /// server and sign-in; another folder on it joins that source.
  func addShare(login: ShareLogin, share: String, path: String, content: FolderContent) async {
    let host = SMBShareProvider(host: login.host, username: "", password: "").host
    if let existing = configs.first(where: {
      $0.id == login.existingID
        || ($0.kind == .smb && $0.address.caseInsensitiveCompare(host) == .orderedSame && $0.username == login.username)
    }) {
      if login.existingID == nil { saveSecret(login.password, for: existing.id) }
      providers[existing.id] = nil
      await addFolder(to: existing.id, share: share, path: path, content: content)
      return
    }
    let config = SourceConfig(kind: .smb, name: login.name.isEmpty ? host : login.name, address: host, username: login.username)
    await add(config, secret: login.password)
    await addFolder(to: config.id, share: share, path: path, content: content)
  }

  // MARK: - WebDAV

  /// Checks the WebDAV folder answers with this sign-in, then adds it (no
  /// folders yet: add them with `addFolder`).
  @discardableResult
  func addWebDAV(address: String, username: String, password: String, name: String = "") async throws -> String {
    let share = try WebDAVShare(address: address, username: username, password: password)
    _ = try await share.list("")
    let config = SourceConfig(
      kind: .webdav, name: name.isEmpty ? (share.base.host ?? "WebDAV") : name, address: share.base.absoluteString,
      username: username)
    await add(config, secret: password)
    return config.id
  }

  // MARK: - Cloud drives

  /// The service's registration in this build, nil when it isn't set up.
  func cloudApp(_ kind: SourceKind) -> OAuthApp? {
    CloudApps.app(kind, info: Bundle.main.infoDictionary ?? [:])
  }

  private func oauthClient(_ kind: SourceKind) throws -> OAuthClient {
    guard let service = OAuthService.of(kind), let app = cloudApp(kind) else {
      throw SourceError.share("\(kind.title) isn't set up in this build of Astra yet.")
    }
    return OAuthClient(service: service, app: app)
  }

  /// Step 1 of a cloud sign-in: the page to open in a web authentication
  /// session, waiting for `app.callbackScheme`.
  func signInRequest(_ kind: SourceKind) throws -> OAuthRequest {
    try oauthClient(kind).authorization()
  }

  /// Step 2: the redirect the session came back with. Adds the account and
  /// returns its source id (add folders with `addFolder`).
  @discardableResult
  func completeSignIn(_ request: OAuthRequest, callback: URL) async throws -> String {
    let token = try await oauthClient(request.kind).exchange(callback: callback, for: request)
    return try await addCloudAccount(request.kind, token: token)
  }

  /// Apple TV: a code to enter on a phone. Only OneDrive and Yandex Disk
  /// offer this; the others sign in on iPhone or Mac.
  func startDeviceSignIn(_ kind: SourceKind) async throws -> DeviceCode {
    try await oauthClient(kind).startDeviceCode()
  }

  /// Waits until the code is approved (or expires, or the task is cancelled),
  /// then adds the account and returns its source id.
  @discardableResult
  func finishDeviceSignIn(_ kind: SourceKind, code: DeviceCode) async throws -> String {
    let client = try oauthClient(kind)
    var interval = Double(code.interval)
    while true {
      try await Task.pause(interval)
      switch try await client.poll(code) {
      case .waiting: continue
      case .slowDown: interval += 5
      case .done(let token): return try await addCloudAccount(kind, token: token)
      }
    }
  }

  private func addCloudAccount(_ kind: SourceKind, token: OAuthToken) async throws -> String {
    let session = OAuthSession(token: token, client: try? oauthClient(kind))
    guard let drive = CloudDrives.drive(kind, session: session, token: token) else { throw SourceError.notFound }
    let account = try await drive.account()
    let address = account.email ?? account.name
    // Signing in to the same account again only renews its sign-in.
    if let existing = configs.first(where: { $0.kind == kind && $0.address == address }) {
      saveSecret(token.json, for: existing.id)
      providers[existing.id] = nil
      await rebuild()
      return existing.id
    }
    let config = SourceConfig(kind: kind, name: "\(kind.title) (\(account.name))", address: address, username: account.email ?? "")
    await add(config, secret: token.json)
    return config.id
  }

  // MARK: - Folders of a share or cloud drive

  /// An added file source's shares: SMB shares, My Drive and shared drives, or the one drive.
  func roots(_ id: String) async throws -> [ShareRoot] {
    try await provider(id).roots()
  }

  /// The folders inside `path` of an added file source, for picking a library folder.
  func folders(in id: String, share: String, path: String) async throws -> [String] {
    try await Self.folderPaths(in: provider(id).share(share), path: path)
  }

  private static func folderPaths(in share: any FileShare, path: String) async throws -> [String] {
    try await share.list(path).filter { $0.isDirectory && !MediaFiles.skips(folder: $0.name) }.map(\.path).sorted {
      $0.localizedStandardCompare($1) == .orderedAscending
    }
  }

  /// Lists a folder of a file source as a library, then reads it.
  func addFolder(to id: String, share: String, path: String, content: FolderContent, title: String? = nil) async {
    guard let index = configs.firstIndex(where: { $0.id == id }), configs[index].kind.isFileSource else { return }
    let name = title ?? path.split(separator: "/").last.map(String.init) ?? configs[index].name
    let folder = SourceFolder(share: share, path: path, content: content, title: name)
    configs[index].folders.append(folder)
    store.save(configs)
    await rebuild()
    scan(id, only: folder.id)
  }

  // MARK: - Removing and switching off

  func remove(_ id: String) {
    scans[id]?.cancel()
    scans[id] = nil
    (providers[id] as? SMBShareProvider)?.disconnectAll()
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
    let state = shareState(id)
    var shareIndex = state.index
    shareIndex.files.removeAll { $0.folder == folderID }
    shareIndex.scannedAt[folderID] = nil
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

  func rename(_ id: String, to name: String) {
    guard let index = configs.firstIndex(where: { $0.id == id }), !name.isEmpty else { return }
    configs[index].name = name
    store.save(configs)
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

  /// Reads a file source's folders again (or one folder) and matches new titles on TMDB.
  func scan(_ id: String, only folderID: String? = nil) {
    guard let config = configs.first(where: { $0.id == id }), config.kind.isFileSource, scans[id] == nil else { return }
    let folders = config.folders.filter { folderID == nil || $0.id == folderID }
    guard !folders.isEmpty else { return }
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
        } catch SourceError.wrongLogin {
          failure = "Sign in again: \(config.kind.title) no longer accepts Astra's sign-in."
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

  // MARK: - File access

  private func shareState(_ id: String) -> ShareLibraryState {
    if let state = shareStates[id] { return state }
    let state = ShareLibraryState.load(sourceID: id, directory: store.directory)
    shareStates[id] = state
    return state
  }

  /// The share a file server path belongs to: the folder whose files include it.
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
    try await provider(sourceID).share(name)
  }

  /// The added source's files: one provider per source, kept while it's in use.
  private func provider(_ id: String) throws -> any FileShareProvider {
    if let existing = providers[id] { return existing }
    guard let config = configs.first(where: { $0.id == id }), config.kind.isFileSource else { throw SourceError.notFound }
    let provider: any FileShareProvider
    switch config.kind {
    case .smb:
      provider = SMBShareProvider(host: config.address, username: config.username, password: secret(id) ?? "")
    case .webdav:
      provider = try WebDAVShare(address: config.address, username: config.username, password: secret(id) ?? "")
    default:
      guard let token = secret(id).flatMap(OAuthToken.init(json:)) else { throw SourceError.wrongLogin }
      let store = keychain(id)
      // A refreshed sign-in is saved straight away (Box hands out a new refresh token each time).
      let session = OAuthSession(token: token, client: try? oauthClient(config.kind)) { fresh in store.save(fresh.json) }
      guard let drive = CloudDrives.drive(config.kind, session: session, token: token) else { throw SourceError.notFound }
      provider = drive
    }
    providers[id] = provider
    return provider
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

/// An SMB server and sign-in being set up, before it's saved as a source.
struct ShareLogin: Hashable {
  var name: String
  var host: String
  var username: String
  var password: String
  /// The share source this joins (its saved password is used).
  var existingID: String?
}
