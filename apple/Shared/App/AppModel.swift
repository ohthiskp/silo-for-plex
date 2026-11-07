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
  private var accountToken: String?
  private var signInTask: Task<Void, Never>?

  private static let serverKey = "astra.plex.serverIdentifier"

  init(tokens: TokenStore = KeychainTokenStore()) {
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
  }

  // MARK: - Launch

  func start() async {
    guard phase == .launching else { return }
    guard let token = tokens.load() else {
      phase = .signedOut
      return
    }
    accountToken = token
    await loadServers(token: token, autoSelect: true)
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
        tokens.save(token)
        accountToken = token
        await loadServers(token: token, autoSelect: true)
      } catch is CancellationError {
        phase = .signedOut
      } catch {
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
    UserDefaults.standard.removeObject(forKey: Self.serverKey)
    accountToken = nil
    server = nil
    serverID = nil
    library = nil
    phase = .signedOut
  }

  // MARK: - Servers

  private func loadServers(token: String, autoSelect: Bool) async {
    phase = .connecting("Plex")
    do {
      guard try await account.validate(token: token) else {
        tokens.clear()
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
    server = session.client
    serverID = session.serverID
    library = store
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
        let playable = try await library.playable(for: resolved)
        try player.play(playable, library: library, local: downloads.source(for: playable))
      } catch {
        player.lastError = error.localizedDescription
      }
    }
  }

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

  func retry() async {
    if let accountToken {
      await loadServers(token: accountToken, autoSelect: true)
    } else {
      phase = .signedOut
    }
  }
}
