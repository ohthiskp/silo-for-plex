import Foundation

/// Who Astra says it is on every Plex request. The client identifier is
/// created once per install and kept, so Plex sees one stable device.
public struct PlexClientInfo: Sendable, Equatable {
  public var product: String
  public var version: String
  public var platform: String
  public var platformVersion: String
  public var device: String
  public var deviceName: String
  public var clientIdentifier: String

  public init(
    product: String = "Astra",
    version: String,
    platform: String,
    platformVersion: String,
    device: String,
    deviceName: String,
    clientIdentifier: String
  ) {
    self.product = product
    self.version = version
    self.platform = platform
    self.platformVersion = platformVersion
    self.device = device
    self.deviceName = deviceName
    self.clientIdentifier = clientIdentifier
  }

  /// The identifier stored in `defaults`, created on first use.
  public static func persistentIdentifier(in defaults: UserDefaults = .standard) -> String {
    let key = "astra.plex.clientIdentifier"
    if let existing = defaults.string(forKey: key), !existing.isEmpty { return existing }
    let created = UUID().uuidString.lowercased()
    defaults.set(created, forKey: key)
    return created
  }

  /// The standard X-Plex-* headers, plus the token when there is one.
  public func headers(token: String? = nil) -> [String: String] {
    var headers = [
      "Accept": "application/json",
      "X-Plex-Product": product,
      "X-Plex-Version": version,
      "X-Plex-Platform": platform,
      "X-Plex-Platform-Version": platformVersion,
      "X-Plex-Device": device,
      "X-Plex-Device-Name": deviceName,
      "X-Plex-Client-Identifier": clientIdentifier,
      "X-Plex-Language": "en",
    ]
    if let token, !token.isEmpty { headers["X-Plex-Token"] = token }
    return headers
  }
}

extension URLRequest {
  mutating func apply(headers: [String: String]) {
    for (name, value) in headers { setValue(value, forHTTPHeaderField: name) }
  }
}

extension URL {
  /// Appends `path` (which may carry its own query) and extra query items.
  func appending(plexPath path: String, query: [URLQueryItem] = []) -> URL {
    var base = absoluteString
    if base.hasSuffix("/") { base.removeLast() }
    let joined = path.hasPrefix("/") ? base + path : base + "/" + path
    guard var components = URLComponents(string: joined) else { return self }
    if !query.isEmpty {
      components.queryItems = (components.queryItems ?? []) + query
    }
    return components.url ?? self
  }
}
