import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Requests to a cloud API with the account's sign-in: adds the token, and
/// after a 401 renews it once and tries again.
struct CloudHTTP: Sendable {
  enum Auth: Sendable {
    /// "Authorization: Bearer <token>" (or another scheme, as Yandex's "OAuth").
    case oauth(OAuthSession, scheme: String)
    /// WebDAV: a username and password.
    case basic(user: String, password: String)
    case none
  }

  let auth: Auth
  let transport: HTTPTransport

  init(auth: Auth, transport: HTTPTransport) {
    self.auth = auth
    self.transport = transport
  }

  /// Sends `request` signed in; nothing is thrown for an HTTP error status.
  func send(_ request: URLRequest, signed: Bool = true) async throws -> (Data, HTTPURLResponse) {
    guard signed else { return try await transport.send(request) }
    switch auth {
    case .none:
      return try await transport.send(request)
    case .basic(let user, let password):
      var request = request
      request.setValue("Basic " + Data("\(user):\(password)".utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
      return try await transport.send(request)
    case .oauth(let session, let scheme):
      let token = try await session.accessToken()
      var signedRequest = request
      signedRequest.setValue("\(scheme) \(token)", forHTTPHeaderField: "Authorization")
      let (data, response) = try await transport.send(signedRequest)
      guard response.statusCode == 401 else { return (data, response) }
      // Revoked or expired early: one refresh, one more try.
      let fresh = try await session.renew(after: token)
      signedRequest.setValue("\(scheme) \(fresh)", forHTTPHeaderField: "Authorization")
      return try await transport.send(signedRequest)
    }
  }

  /// A JSON answer, or the HTTP error as a `SourceError`.
  func json<Body: Decodable>(_ request: URLRequest, as type: Body.Type = Body.self, signed: Bool = true) async throws -> Body {
    let (data, response) = try await send(request, signed: signed)
    try Self.check(response.statusCode, data: data)
    do {
      return try JSONDecoder.cloud.decode(Body.self, from: data)
    } catch {
      throw PlexError.invalidResponse
    }
  }

  /// `length` bytes of a file from `offset` (fewer at its end, none past it).
  func range(_ request: URLRequest, offset: Int64, length: Int, signed: Bool = true) async throws -> Data {
    guard length > 0 else { return Data() }
    var request = request
    request.setValue("bytes=\(offset)-\(offset + Int64(length) - 1)", forHTTPHeaderField: "Range")
    let (data, response) = try await send(request, signed: signed)
    switch response.statusCode {
    case 206: return data.count > length ? data.prefix(length) : data
    case 200:
      // The server ignored the range and sent the whole file: take the part asked for.
      guard offset < Int64(data.count) else { return Data() }
      let start = data.index(data.startIndex, offsetBy: Int(offset))
      return data[start..<data.index(start, offsetBy: min(length, data.count - Int(offset)))]
    case 416: return Data()
    default:
      try Self.check(response.statusCode, data: data)
      return data
    }
  }

  static func check(_ status: Int, data: Data) throws {
    switch status {
    case 200..<300: return
    case 401: throw SourceError.wrongLogin
    case 403: throw SourceError.share("The service refused access to that file or folder.")
    case 404, 409, 410: throw SourceError.notFound
    case 429, 503: throw SourceError.share("The service is busy. Try again in a minute.")
    default: throw SourceError.http(status)
    }
  }
}

extension JSONDecoder {
  /// Cloud APIs: ISO 8601 dates are read by hand (some have fractions), so plain decoding.
  static let cloud = JSONDecoder()
}

/// Shared helpers for the cloud and WebDAV shares.
enum CloudPath {
  /// "Movies/Dune (2021)" → "Movies/Dune%20%282021%29", each part encoded.
  static func encode(_ path: String) -> String {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~")
    return path.split(separator: "/").map { $0.addingPercentEncoding(withAllowedCharacters: allowed) ?? String($0) }
      .joined(separator: "/")
  }

  /// "a/b/c" → "a/b"; "c" → "".
  static func parent(_ path: String) -> String {
    guard let slash = path.lastIndex(of: "/") else { return "" }
    return String(path[..<slash])
  }

  static func name(_ path: String) -> String {
    path.split(separator: "/").last.map(String.init) ?? path
  }

  static func join(_ folder: String, _ name: String) -> String { folder.isEmpty ? name : folder + "/" + name }

  static func trim(_ path: String) -> String { path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }

  /// "2026-11-17T20:21:23Z" or with fractions.
  static func date(iso text: String?) -> Date? {
    guard let text else { return nil }
    let plain = ISO8601DateFormatter()
    if let date = plain.date(from: text) { return date }
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return fractional.date(from: text)
  }

  /// "Thu, 21 Mar 2013 18:31:16 +0000" (pCloud, WebDAV).
  static func date(rfc1123 text: String?) -> Date? {
    guard let text else { return nil }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    for format in ["EEE, dd MMM yyyy HH:mm:ss Z", "EEE, dd MMM yyyy HH:mm:ss zzz"] {
      formatter.dateFormat = format
      if let date = formatter.date(from: text) { return date }
    }
    return nil
  }
}

/// Paths to ids, for drives that address files by id (Google Drive, Box).
/// Filled as folders are listed; a path not seen yet is found by listing
/// down from the top.
final class PathIDs: @unchecked Sendable {
  struct Item: Sendable {
    var id: String
    var isDirectory: Bool
    var size: Int64
  }

  private let lock = NSLock()
  private var items: [String: Item]

  init(root: String) { items = ["": Item(id: root, isDirectory: true, size: 0)] }

  subscript(path: String) -> Item? {
    get { lock.withLock { items[path] } }
    set { lock.withLock { items[path] = newValue } }
  }

  /// The item at `path`, listing its parents as needed with `list` (which
  /// fills this cache).
  func resolve(_ path: String, list: (String) async throws -> Void) async throws -> Item {
    let path = CloudPath.trim(path)
    if let item = self[path] { return item }
    var walked = ""
    for part in path.split(separator: "/") {
      let next = CloudPath.join(walked, String(part))
      if self[next] == nil { try await list(walked) }
      guard self[next] != nil else { throw SourceError.notFound }
      walked = next
    }
    guard let item = self[path] else { throw SourceError.notFound }
    return item
  }
}

/// Direct download links that expire (OneDrive, pCloud, Yandex): kept for
/// `lifetime` so a film's chunks don't each ask for a new one.
final class LinkCache: @unchecked Sendable {
  struct Link: Sendable {
    var url: URL
    var size: Int64
    var made: Date
  }

  private let lock = NSLock()
  private var links: [String: Link] = [:]
  let lifetime: TimeInterval

  init(lifetime: TimeInterval) { self.lifetime = lifetime }

  func get(_ path: String, now: Date = Date()) -> Link? {
    lock.withLock {
      guard let link = links[path], now.timeIntervalSince(link.made) < lifetime else { return nil }
      return link
    }
  }

  func set(_ path: String, _ link: Link) { lock.withLock { links[path] = link } }
  func drop(_ path: String) { lock.withLock { links[path] = nil } }

  /// Reads through a cached link, fetching a new one when there's none or the old one stopped working.
  func read(
    _ path: String, offset: Int64, length: Int, http: CloudHTTP, fetch: () async throws -> Link
  ) async throws -> Data {
    var fresh = false
    var link: Link
    if let cached = get(path) {
      link = cached
    } else {
      link = try await fetch()
      set(path, link)
      fresh = true
    }
    do {
      return try await http.range(URLRequest(url: link.url), offset: offset, length: length, signed: false)
    } catch {
      guard !fresh else { throw error }
      // The link expired early: one new link, one more try.
      drop(path)
      link = try await fetch()
      set(path, link)
      return try await http.range(URLRequest(url: link.url), offset: offset, length: length, signed: false)
    }
  }
}
