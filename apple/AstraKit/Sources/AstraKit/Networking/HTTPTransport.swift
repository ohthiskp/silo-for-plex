import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// The one seam between AstraKit and the network, so tests can answer requests
/// without a server.
public protocol HTTPTransport: Sendable {
  func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
  let session: URLSession

  public init(session: URLSession = .astraDefault) {
    self.session = session
  }

  public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw PlexError.invalidResponse }
    return (data, http)
  }
}

extension URLSession {
  /// Short timeouts: a Plex server that has not answered in 15 s is not going to.
  public static let astraDefault: URLSession = {
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 15
    config.timeoutIntervalForResource = 60
    config.waitsForConnectivity = false
    config.httpMaximumConnectionsPerHost = 6
    return URLSession(configuration: config)
  }()
}

public enum PlexError: LocalizedError, Equatable, Sendable {
  case invalidResponse
  case unauthorized
  case http(Int)
  case noReachableConnection(String)
  case pinExpired
  case notSignedIn
  case nothingToPlay

  public var errorDescription: String? {
    switch self {
    case .invalidResponse: "The server sent a response Astra couldn't read."
    case .unauthorized: "Plex rejected the sign-in. Please sign in again."
    case .http(let code): "The server answered with an error (\(code))."
    case .noReachableConnection(let name): "Astra couldn't reach \(name) on any of its addresses."
    case .pinExpired: "The sign-in code expired. Start again to get a new one."
    case .notSignedIn: "Sign in to Plex first."
    case .nothingToPlay: "This item has no playable file."
    }
  }
}
