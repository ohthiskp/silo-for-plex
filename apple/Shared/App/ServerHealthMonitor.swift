import AstraKit
import Foundation
import Network

/// Astra 4.0 (KP, 2026-11-08): watches the connected Plex server. One small
/// authenticated request (the library list) with a short time limit checks
/// both "does it answer" and "does it still accept the sign-in". Offline is
/// only declared after two checks in a row fail; retries back off; a network
/// change (Wi-Fi back, new network) checks at once; Retry checks now.
@MainActor @Observable
final class ServerHealthMonitor {
  let serverName: String
  private(set) var tracker = ServerHealthTracker()
  var state: ServerHealthState { tracker.state }
  var lastChecked: Date? { tracker.lastChecked }

  @ObservationIgnored private let client: PlexServerClient
  @ObservationIgnored private var loop: Task<Void, Never>?
  @ObservationIgnored private var running: Task<Void, Never>?
  @ObservationIgnored private var path: NWPathMonitor?
  @ObservationIgnored private var hadNetwork = true
  @ObservationIgnored private var stopped = false

  /// A check gives up after this long (a sleeping server never answers).
  static let probeTimeout: TimeInterval = 8

  init(client: PlexServerClient) {
    self.client = client
    serverName = client.serverName
  }

  func start() {
    let monitor = NWPathMonitor()
    monitor.pathUpdateHandler = { [weak self] path in
      let online = path.status == .satisfied
      Task { @MainActor [weak self] in self?.networkChanged(online: online) }
    }
    monitor.start(queue: DispatchQueue(label: "astra.health.path", qos: .utility))
    path = monitor
    checkNow()
  }

  func stop() {
    stopped = true
    path?.cancel()
    path = nil
    loop?.cancel()
    running?.cancel()
  }

  /// Retry: checks now, replacing any check or wait in progress.
  func checkNow() {
    guard !stopped else { return }
    loop?.cancel()
    running?.cancel()
    tracker.checking()
    let client = client
    running = Task { [weak self] in
      let outcome = await Self.probe(client)
      guard let self, !Task.isCancelled, !self.stopped else { return }
      switch outcome {
      case .success: self.tracker.recordSuccess(at: Date())
      case .failure(let failure, let message): self.tracker.recordFailure(failure, message: message, at: Date())
      }
      self.scheduleNext()
    }
  }

  /// A request elsewhere failed: check (it never marks the server offline by itself).
  func requestFailed(_ error: Error) {
    guard state == .connected, ProbeFailure.classify(error) != .server else { return }
    checkNow()
  }

  private func scheduleNext() {
    loop?.cancel()
    guard let delay = tracker.nextCheck else { return }
    loop = Task { [weak self] in
      try? await Task.pause(delay)
      guard !Task.isCancelled else { return }
      self?.checkNow()
    }
  }

  private func networkChanged(online: Bool) {
    defer { hadNetwork = online }
    guard !stopped else { return }
    if !online {
      loop?.cancel()
      running?.cancel()
      tracker.networkLost(at: Date())
    } else if !hadNetwork || state != .connected {
      checkNow()
    }
  }

  private enum Outcome: Sendable { case success, failure(ProbeFailure, String) }

  /// The library list, or nothing within `probeTimeout`.
  private nonisolated static func probe(_ client: PlexServerClient) async -> Outcome {
    await withTaskGroup(of: Outcome?.self) { group in
      group.addTask {
        do {
          _ = try await client.librarySections()
          return .success
        } catch {
          return .failure(ProbeFailure.classify(error), PlexError.describe(error))
        }
      }
      group.addTask {
        try? await Task.pause(probeTimeout)
        return Task.isCancelled ? nil : .failure(.unreachable, "The server didn't answer in time.")
      }
      let first = await group.next() ?? nil
      group.cancelAll()
      return first ?? .failure(.unreachable, "The server didn't answer in time.")
    }
  }
}
