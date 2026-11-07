import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// A connection to one server that has been checked end to end: an address
/// answered, and the server accepted the token by listing its libraries.
///
/// `generation` is the session's identity. Every switch makes a new one, so
/// work started for an older session can tell it is stale and drop its result.
public struct ServerSession: Sendable {
  public let generation: Int
  public let serverID: String
  public let client: PlexServerClient
  public let sections: [PlexLibrarySection]
}

/// Opens and validates server sessions. Nothing is committed here: the caller
/// swaps to the new session only when `connect` returns, so a failed switch
/// leaves the current server working.
public struct ServerConnector: Sendable {
  let info: PlexClientInfo
  let transport: HTTPTransport
  let probeTimeout: TimeInterval

  public init(info: PlexClientInfo, transport: HTTPTransport = URLSessionTransport(), probeTimeout: TimeInterval = 4) {
    self.info = info
    self.transport = transport
    self.probeTimeout = probeTimeout
  }

  public func connect(
    to resource: PlexServerResource, accountToken: String, generation: Int
  ) async throws -> ServerSession {
    let picker = ConnectionPicker(info: info, transport: transport, probeTimeout: probeTimeout)
    let url = try await picker.pick(for: resource, accountToken: accountToken)
    try Task.checkCancellation()
    let client = PlexServerClient(
      baseURL: url, token: resource.accessToken ?? accountToken, serverName: resource.name, info: info,
      transport: transport)
    // /identity answers without a valid token; listing libraries proves the token works.
    let sections = try await client.librarySections()
    try Task.checkCancellation()
    return ServerSession(
      generation: generation, serverID: resource.clientIdentifier, client: client, sections: sections)
  }
}

/// Hands out increasing tokens and says whether one is still the latest.
/// Used to drop responses that arrive after a newer request replaced them.
public struct Generation: Sendable, Equatable {
  public private(set) var current = 0

  public init() {}

  /// Starts a new request; every earlier token is stale from now on.
  public mutating func next() -> Int {
    current += 1
    return current
  }

  public func isCurrent(_ token: Int) -> Bool { token == current }
}

/// Every movie and show on a server by TMDB key ("movie:603"), for matching
/// TMDB's streaming lists to the library.
public enum LibraryIndexer {
  /// Reads each section in pages (a single 20,000-item request times out on
  /// slow servers). Throws when any page fails, so a partial or empty index
  /// is never mistaken for the real one and cached.
  public static func build(
    client: PlexServerClient, sections: [PlexLibrarySection], pageSize: Int = 1000
  ) async throws -> [String: PlexMetadata] {
    var index: [String: PlexMetadata] = [:]
    for section in sections where section.type == "movie" || section.type == "show" {
      var start = 0
      while true {
        try Task.checkCancellation()
        let page = try await client.libraryItems(
          sectionKey: section.key, sort: "titleSort", start: start, size: pageSize)
        for item in page {
          if let key = item.tmdbKey, index[key] == nil { index[key] = item }
        }
        if page.count < pageSize { break }
        start += page.count
      }
    }
    return index
  }
}
