import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Astra 4.0 (KP, 2026-11-08): one picture of whether the Plex server can
/// stream, shared by Home, Search, Details, Watchlist and the player.
public enum ServerHealthState: String, Sendable, Equatable {
  case connected, checking, offline, authRequired, networkUnavailable, degraded

  public var title: String {
    switch self {
    case .connected: "Connected"
    case .checking: "Checking…"
    case .offline: "Offline"
    case .authRequired: "Sign-in required"
    case .networkUnavailable: "No network"
    case .degraded: "Not responding"
    }
  }

  /// Streaming is only refused once the server is confirmed unreachable or
  /// the sign-in is rejected; a single failure (degraded) still lets it try.
  public var allowsStreaming: Bool {
    switch self {
    case .offline, .authRequired, .networkUnavailable: false
    case .connected, .checking, .degraded: true
    }
  }
}

/// Why a health check failed.
public enum ProbeFailure: Sendable, Equatable {
  /// The server (or plex.tv) rejected the token: sign in again, not "offline".
  case unauthorized
  /// This device has no network at all.
  case network
  /// The server didn't answer (timeout, refused, DNS).
  case unreachable
  /// It answered, but with an error.
  case server

  public static func classify(_ error: Error) -> ProbeFailure {
    if let plex = error as? PlexError {
      switch plex {
      case .unauthorized, .notSignedIn: return .unauthorized
      case .noReachableConnection: return .unreachable
      default: return .server
      }
    }
    if let url = error as? URLError {
      switch url.code {
      case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
        return .network
      case .userAuthenticationRequired: return .unauthorized
      default: return .unreachable
      }
    }
    return .unreachable
  }
}

/// The health state machine, without timers or I/O so it can be tested.
/// Offline is only declared after `failuresForOffline` checks in a row fail;
/// before that the server is "degraded". Retries back off exponentially.
public struct ServerHealthTracker: Sendable, Equatable {
  public private(set) var state: ServerHealthState = .checking
  public private(set) var failures = 0
  public private(set) var lastChecked: Date?
  public private(set) var lastError: String?

  public static let failuresForOffline = 2
  /// While connected, a light check this often (no aggressive polling).
  public static let connectedInterval: TimeInterval = 300
  public static let firstRetry: TimeInterval = 10
  public static let maxRetry: TimeInterval = 300

  public init() {}

  public mutating func checking() {
    if state != .connected { state = .checking }
  }

  public mutating func recordSuccess(at date: Date) {
    state = .connected
    failures = 0
    lastChecked = date
    lastError = nil
  }

  public mutating func recordFailure(_ failure: ProbeFailure, message: String? = nil, at date: Date) {
    lastChecked = date
    lastError = message
    switch failure {
    case .unauthorized:
      state = .authRequired
    case .network:
      state = .networkUnavailable
    case .unreachable, .server:
      failures += 1
      state = failures >= Self.failuresForOffline ? .offline : .degraded
    }
  }

  /// The network went away (from the system's path monitor).
  public mutating func networkLost(at date: Date) {
    state = .networkUnavailable
    lastChecked = date
  }

  /// Seconds until the next automatic check; nil when only a person can fix it.
  public var nextCheck: TimeInterval? {
    switch state {
    case .connected: Self.connectedInterval
    case .authRequired: nil
    case .networkUnavailable: nil  // the path monitor re-checks when it's back
    case .checking: Self.firstRetry
    case .degraded, .offline:
      min(Self.maxRetry, Self.firstRetry * pow(2, Double(max(0, failures - 1))))
    }
  }
}
