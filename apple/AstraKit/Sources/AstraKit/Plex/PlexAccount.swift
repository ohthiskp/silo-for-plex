import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// A sign-in PIN: the user enters `code` at plex.tv/link (or approves the auth
/// page), then polling the PIN yields the account token.
public struct PlexPin: Decodable, Sendable, Equatable {
  public var id: Int
  public var code: String
  public var authToken: String?
  public var expiresIn: Int?
}

/// A server the account can use, with every address Plex knows for it.
public struct PlexServerResource: Decodable, Sendable, Hashable, Identifiable {
  public struct Connection: Decodable, Sendable, Hashable {
    public var uri: String
    public var local: Bool
    public var relay: Bool
    public var `protocol`: String?
    public var IPv6: Bool?

    public init(uri: String, local: Bool, relay: Bool, `protocol`: String? = nil, IPv6: Bool? = nil) {
      self.uri = uri
      self.local = local
      self.relay = relay
      self.protocol = `protocol`
      self.IPv6 = IPv6
    }
  }

  public var name: String
  public var clientIdentifier: String
  public var accessToken: String?
  public var owned: Bool?
  public var presence: Bool?
  public var provides: String?
  public var productVersion: String?
  public var connections: [Connection]

  public var id: String { clientIdentifier }

  public init(name: String, clientIdentifier: String, accessToken: String?, connections: [Connection]) {
    self.name = name
    self.clientIdentifier = clientIdentifier
    self.accessToken = accessToken
    self.connections = connections
    provides = "server"
  }

  public var isServer: Bool { provides?.split(separator: ",").contains("server") ?? false }
}

/// plex.tv: sign-in and the list of servers.
public struct PlexAccountClient: Sendable {
  public static let apiBase = URL(string: "https://plex.tv/api/v2")!
  public static let clientsBase = URL(string: "https://clients.plex.tv/api/v2")!

  let info: PlexClientInfo
  let transport: HTTPTransport

  public init(info: PlexClientInfo, transport: HTTPTransport = URLSessionTransport()) {
    self.info = info
    self.transport = transport
  }

  /// How the PIN is approved.
  public enum PinStyle: Sendable, Equatable {
    /// A long code, approved on the auth page that opens in the browser (Mac, iPhone).
    case strong
    /// A short 4-character code typed at plex.tv/link on another device
    /// (Apple TV: no browser, and a long code can't be typed with a remote).
    case link

    /// Link on tvOS, strong everywhere else.
    public static var platformDefault: PinStyle {
      #if os(tvOS)
        .link
      #else
        .strong
      #endif
    }
  }

  /// Where a short `link` PIN is typed in.
  public static let linkURL = URL(string: "https://plex.tv/link")!

  /// Starts a sign-in: a strong PIN for the auth page, or a short one for
  /// plex.tv/link (Apple TV). Both are checked with `checkPin` / `waitForToken`.
  public func createPin(style: PinStyle = .platformDefault) async throws -> PlexPin {
    let strong = style == .strong ? "true" : "false"
    var request = URLRequest(url: Self.apiBase.appending(plexPath: "/pins", query: [.init(name: "strong", value: strong)]))
    request.httpMethod = "POST"
    request.apply(headers: info.headers())
    return try await decode(PlexPin.self, request)
  }

  /// The page that signs the user in and approves the PIN; works for both
  /// styles, so on Apple TV it is what a QR code points at (a phone opens
  /// it, signs in, and the TV's `waitForToken` picks up the token).
  public func authURL(for pin: PlexPin) -> URL {
    // app.plex.tv reads its parameters from the fragment.
    var fragment = URLComponents()
    fragment.queryItems = [
      .init(name: "clientID", value: info.clientIdentifier),
      .init(name: "code", value: pin.code),
      .init(name: "context[device][product]", value: info.product),
    ]
    let query = fragment.percentEncodedQuery ?? ""
    return URL(string: "https://app.plex.tv/auth#?\(query)")!
  }

  /// Checks the PIN once. Returns the token after the user approved it, nil while waiting.
  public func checkPin(_ pin: PlexPin) async throws -> String? {
    var request = URLRequest(url: Self.apiBase.appending(plexPath: "/pins/\(pin.id)"))
    request.apply(headers: info.headers())
    do {
      let checked = try await decode(PlexPin.self, request)
      if let token = checked.authToken, !token.isEmpty { return token }
      return nil
    } catch PlexError.http(404) {
      throw PlexError.pinExpired
    }
  }

  /// Polls the PIN until the user approves it, the PIN expires, or the task is cancelled.
  public func waitForToken(_ pin: PlexPin, every interval: Duration = .seconds(2)) async throws -> String {
    let deadline = ContinuousClock.now + .seconds(max(60, pin.expiresIn ?? 900))
    while ContinuousClock.now < deadline {
      try Task.checkCancellation()
      if let token = try await checkPin(pin) { return token }
      try await Task.pause(interval)
    }
    throw PlexError.pinExpired
  }

  /// Confirms a saved token still works.
  public func validate(token: String) async throws -> Bool {
    var request = URLRequest(url: Self.apiBase.appending(plexPath: "/user"))
    request.apply(headers: info.headers(token: token))
    do {
      _ = try await send(request)
      return true
    } catch PlexError.unauthorized {
      return false
    }
  }

  /// Every server this account can reach, owned ones first.
  public func servers(token: String) async throws -> [PlexServerResource] {
    let url = Self.clientsBase.appending(
      plexPath: "/resources",
      query: [
        .init(name: "includeHttps", value: "1"),
        .init(name: "includeRelay", value: "1"),
        .init(name: "includeIPv6", value: "1"),
      ])
    var request = URLRequest(url: url)
    request.apply(headers: info.headers(token: token))
    let resources = try await decode([PlexServerResource].self, request)
    return resources.filter(\.isServer).sorted { ($0.owned ?? false) && !($1.owned ?? false) }
  }

  public static let discoverBase = URL(string: "https://discover.provider.plex.tv")!

  /// The account's Plex Watchlist, newest first. Items come from Plex's own
  /// catalog (not the server): their guids (TMDB, IMDb) match them to the
  /// server, and `thumb` / `art` are full image URLs.
  public func watchlist(token: String, size: Int = 100) async throws -> [PlexMetadata] {
    let url = Self.discoverBase.appending(
      plexPath: "/library/sections/watchlist/all",
      query: [
        .init(name: "includeGuids", value: "1"),
        .init(name: "sort", value: "watchlistedAt:desc"),
        .init(name: "X-Plex-Container-Start", value: "0"),
        .init(name: "X-Plex-Container-Size", value: String(size)),
      ])
    var request = URLRequest(url: url)
    request.apply(headers: info.headers(token: token))
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    return try await decode(MediaContainerEnvelope<MetadataBody>.self, request).MediaContainer.Metadata ?? []
  }

  public static let metadataBase = URL(string: "https://metadata.provider.plex.tv")!

  /// Astra (KP, 2026-11-07: the + button adds to the Plex Watchlist): the
  /// title's id in Plex's own catalog. A server item carries it in its
  /// `plex://movie/<id>` guid; a TMDB-only title is looked up by its TMDB id.
  public func catalogKey(for item: PlexMetadata, token: String) async throws -> String? {
    if let guid = item.guid, guid.hasPrefix("plex://"), let id = guid.split(separator: "/").last {
      return String(id)
    }
    guard let tmdb = item.tmdbKey?.split(separator: ":"), tmdb.count == 2 else { return nil }
    let type = tmdb[0] == "tv" ? "2" : "1"
    let url = Self.metadataBase.appending(
      plexPath: "/library/metadata/matches",
      query: [.init(name: "type", value: type), .init(name: "guid", value: "tmdb://\(tmdb[1])")])
    var request = URLRequest(url: url)
    request.apply(headers: info.headers(token: token))
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    let found = try await decode(MediaContainerEnvelope<MetadataBody>.self, request).MediaContainer.Metadata ?? []
    return found.first.flatMap { $0.guid?.split(separator: "/").last.map(String.init) ?? $0.ratingKey }
  }

  /// Adds a title (by its catalog id) to the account's Plex Watchlist.
  public func addToWatchlist(catalogKey: String, token: String) async throws {
    try await watchlistAction("addToWatchlist", catalogKey: catalogKey, token: token)
  }

  /// Takes a title (by its catalog id) off the account's Plex Watchlist.
  public func removeFromWatchlist(catalogKey: String, token: String) async throws {
    try await watchlistAction("removeFromWatchlist", catalogKey: catalogKey, token: token)
  }

  private func watchlistAction(_ action: String, catalogKey: String, token: String) async throws {
    let url = Self.discoverBase.appending(
      plexPath: "/actions/\(action)", query: [.init(name: "ratingKey", value: catalogKey)])
    var request = URLRequest(url: url)
    request.httpMethod = "PUT"
    request.apply(headers: info.headers(token: token))
    _ = try await send(request)
  }

  private func send(_ request: URLRequest) async throws -> Data {
    let (data, response) = try await transport.send(request)
    switch response.statusCode {
    case 200..<300: return data
    case 401, 403: throw PlexError.unauthorized
    default: throw PlexError.http(response.statusCode)
    }
  }

  private func decode<T: Decodable>(_ type: T.Type, _ request: URLRequest) async throws -> T {
    let data = try await send(request)
    do {
      return try JSONDecoder().decode(T.self, from: data)
    } catch {
      throw PlexError.invalidResponse
    }
  }
}
