import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// An Xtream Codes provider (KP, 2026-11-16): `player_api.php` for the
/// login, categories and live channels, `xmltv.php` for the guide, and
/// `/live/<user>/<password>/<id>.<ext>` for each stream. The stream is
/// played as the provider sends it; nothing is transcoded.
public struct XtreamClient: Sendable {
  public enum Failure: LocalizedError, Equatable {
    case badServer
    case rejected
    case expired(String)

    public var errorDescription: String? {
      switch self {
      case .badServer: "That server address doesn't look right. It should be like http://tv.example.com:8080."
      case .rejected: "Your provider didn't accept that username and password."
      case .expired(let status): "Your provider says this account is \(status.lowercased())."
      }
    }
  }

  public let server: URL
  public let username: String
  public let password: String
  let transport: HTTPTransport

  public init(server: String, username: String, password: String, transport: HTTPTransport = URLSessionTransport(log: nil)) throws {
    guard let url = URL(string: Self.normalizedServer(server)), url.host() != nil else { throw Failure.badServer }
    self.server = url
    self.username = username
    self.password = password
    self.transport = transport
  }

  /// "tv.example.com:8080/" → "http://tv.example.com:8080" (a pasted
  /// "…/player_api.php" or "…/get.php?…" link works too).
  public static func normalizedServer(_ text: String) -> String {
    var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if !value.contains("://") { value = "http://" + value }
    guard var parts = URLComponents(string: value) else { return value }
    parts.query = nil
    parts.fragment = nil
    for suffix in ["/player_api.php", "/get.php", "/xmltv.php"] where parts.path.hasSuffix(suffix) {
      parts.path = String(parts.path.dropLast(suffix.count))
    }
    while parts.path.hasSuffix("/") { parts.path.removeLast() }
    return parts.string ?? value
  }

  /// The player_api URL for `action` (nil = the login check).
  func apiURL(_ action: String? = nil) -> URL {
    var parts = URLComponents(url: server.appendingPathComponent("player_api.php"), resolvingAgainstBaseURL: false)!
    parts.queryItems = [URLQueryItem(name: "username", value: username), URLQueryItem(name: "password", value: password)]
    if let action { parts.queryItems?.append(URLQueryItem(name: "action", value: action)) }
    return parts.url!
  }

  public var guideURL: URL {
    var parts = URLComponents(url: server.appendingPathComponent("xmltv.php"), resolvingAgainstBaseURL: false)!
    parts.queryItems = [URLQueryItem(name: "username", value: username), URLQueryItem(name: "password", value: password)]
    return parts.url!
  }

  public func streamURL(_ id: String, format: String) -> URL {
    server.appendingPathComponent("live").appendingPathComponent(username).appendingPathComponent(password)
      .appendingPathComponent("\(id).\(format)")
  }

  struct Login: Decodable {
    struct UserInfo: Decodable {
      var auth: Int?
      var status: String?
      var formats: [String]

      enum CodingKeys: String, CodingKey { case auth, status, allowed_output_formats }

      init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        auth = try c.decodeLenientInt(.auth)
        status = try c.decodeLenientString(.status)
        formats = (try? c.decode([String].self, forKey: .allowed_output_formats)) ?? []
      }
    }
    var user_info: UserInfo?
  }

  struct Category: Decodable {
    var id: String
    var name: String

    enum CodingKeys: String, CodingKey { case category_id, category_name }

    init(from decoder: Decoder) throws {
      let c = try decoder.container(keyedBy: CodingKeys.self)
      id = try c.decodeLenientString(.category_id) ?? ""
      name = try c.decodeLenientString(.category_name) ?? ""
    }
  }

  struct Stream: Decodable {
    var id: String
    var name: String
    var number: Int?
    var icon: String?
    var guideID: String?
    var category: String?

    enum CodingKeys: String, CodingKey { case stream_id, name, num, stream_icon, epg_channel_id, category_id }

    init(from decoder: Decoder) throws {
      let c = try decoder.container(keyedBy: CodingKeys.self)
      id = try c.decodeLenientString(.stream_id) ?? ""
      name = try c.decodeLenientString(.name) ?? ""
      number = try c.decodeLenientInt(.num)
      icon = try c.decodeLenientString(.stream_icon)
      guideID = try c.decodeLenientString(.epg_channel_id)
      category = try c.decodeLenientString(.category_id)
    }
  }

  private func get<T: Decodable>(_ url: URL, as type: T.Type) async throws -> T {
    var request = URLRequest(url: url)
    request.timeoutInterval = 30
    let (data, response) = try await transport.send(request)
    if response.statusCode == 401 || response.statusCode == 403 { throw Failure.rejected }
    guard (200..<300).contains(response.statusCode) else { throw PlexError.http(response.statusCode) }
    return try JSONDecoder().decode(T.self, from: data)
  }

  /// Checks the login; returns the stream format to use ("ts" when allowed,
  /// else the first the provider allows; "ts" when it says nothing).
  public func login() async throws -> String {
    let login = try await get(apiURL(), as: Login.self)
    guard let info = login.user_info, info.auth != 0 else { throw Failure.rejected }
    if let status = info.status, !status.isEmpty, status.lowercased() != "active" { throw Failure.expired(status) }
    return Self.format(from: info.formats)
  }

  static func format(from allowed: [String]) -> String {
    let lower = allowed.map { $0.lowercased() }
    if lower.isEmpty || lower.contains("ts") { return "ts" }
    if lower.contains("m3u8") { return "m3u8" }
    return lower.first ?? "ts"
  }

  /// Every live channel, in the provider's order, with its category name.
  public func channels(format: String) async throws -> [LiveChannel] {
    async let categories = get(apiURL("get_live_categories"), as: [Category].self)
    async let streams = get(apiURL("get_live_streams"), as: [Stream].self)
    let names = Dictionary(try await categories.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    return try await streams.compactMap { stream in
      guard !stream.id.isEmpty, !stream.name.isEmpty else { return nil }
      return LiveChannel(
        id: stream.id, name: stream.name, number: stream.number,
        logo: stream.icon?.nilIfEmpty.flatMap(URL.init(string:)),
        group: stream.category.flatMap { names[$0] }, stream: streamURL(stream.id, format: format),
        guideID: stream.guideID?.nilIfEmpty)
    }
  }
}
