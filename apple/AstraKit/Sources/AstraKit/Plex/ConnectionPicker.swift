import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Picks the address Astra talks to a server on.
///
/// All addresses are probed at once. The preferred order is local direct,
/// remote direct, then Plex relay (relay is bandwidth-capped, so it is the
/// last resort). A lower-ranked address that answers first is only used once
/// every better one has failed, so a fast relay never beats a LAN address
/// that is a few milliseconds slower.
public struct ConnectionPicker: Sendable {
  let info: PlexClientInfo
  let transport: HTTPTransport
  let probeTimeout: TimeInterval

  public init(info: PlexClientInfo, transport: HTTPTransport = URLSessionTransport(), probeTimeout: TimeInterval = 4) {
    self.info = info
    self.transport = transport
    self.probeTimeout = probeTimeout
  }

  /// Lower is better.
  public static func rank(_ connection: PlexServerResource.Connection) -> Int {
    if connection.relay { return 3 }
    let https = connection.uri.hasPrefix("https")
    if connection.local { return https ? 0 : 1 }
    return 2
  }

  public static func ordered(_ connections: [PlexServerResource.Connection]) -> [PlexServerResource.Connection] {
    connections.enumerated()
      .sorted { lhs, rhs in
        let (l, r) = (rank(lhs.element), rank(rhs.element))
        return l != r ? l < r : lhs.offset < rhs.offset
      }
      .map(\.element)
  }

  public func pick(for server: PlexServerResource, accountToken: String) async throws -> URL {
    let token = server.accessToken ?? accountToken
    let candidates = Self.ordered(server.connections).compactMap { URL(string: $0.uri) }
    guard !candidates.isEmpty else { throw PlexError.noReachableConnection(server.name) }

    return try await withThrowingTaskGroup(of: (Int, Bool).self) { group in
      for (index, url) in candidates.enumerated() {
        group.addTask { (index, await probe(url, token: token)) }
      }
      var outcome = [Bool?](repeating: nil, count: candidates.count)
      for try await (index, ok) in group {
        outcome[index] = ok
        // The best address that answered, once nothing better is still pending.
        for i in outcome.indices {
          guard let result = outcome[i] else { break }
          if result {
            group.cancelAll()
            return candidates[i]
          }
        }
      }
      throw PlexError.noReachableConnection(server.name)
    }
  }

  private func probe(_ url: URL, token: String) async -> Bool {
    var request = URLRequest(url: url.appending(plexPath: "/identity"))
    request.timeoutInterval = probeTimeout
    request.apply(headers: info.headers(token: token))
    do {
      let (_, response) = try await transport.send(request)
      return (200..<300).contains(response.statusCode)
    } catch {
      return false
    }
  }
}
