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
  let player = PlayerController()

  let info: PlexClientInfo
  private let account: PlexAccountClient
  private let picker: ConnectionPicker
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
    picker = ConnectionPicker(info: info)
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
    tokens.clear()
    UserDefaults.standard.removeObject(forKey: Self.serverKey)
    accountToken = nil
    server = nil
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

  func chooseServer() async {
    guard let accountToken else { return phase = .signedOut }
    await loadServers(token: accountToken, autoSelect: false)
  }

  func connect(to resource: PlexServerResource) async {
    guard let accountToken else { return phase = .signedOut }
    phase = .connecting(resource.name)
    do {
      let url = try await picker.pick(for: resource, accountToken: accountToken)
      let client = PlexServerClient(
        baseURL: url, token: resource.accessToken ?? accountToken, serverName: resource.name, info: info)
      UserDefaults.standard.set(resource.clientIdentifier, forKey: Self.serverKey)
      server = client
      let store = LibraryStore(client: client)
      library = store
      player.server = client
      phase = .ready
      await store.loadHome()
    } catch {
      phase = .failed(error.localizedDescription)
    }
  }

  /// Plays an item; a show or season plays its next episode.
  func play(_ item: PlexMetadata) {
    guard let library else { return }
    Task {
      do {
        let playable = try await library.playable(for: item)
        try player.play(playable, library: library)
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
