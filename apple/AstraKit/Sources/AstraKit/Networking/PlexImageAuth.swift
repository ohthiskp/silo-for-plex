import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Astra (security audit, 2026-11-08): Plex image URLs carry no token. The
/// URLs are cache keys written to disk, so a token in them would sit in the
/// image cache. Instead each server's token is kept here in memory, by
/// origin, and added as the `X-Plex-Token` header when the image is fetched.
public enum PlexImageAuth {
  private final class Store: @unchecked Sendable {
    let lock = NSLock()
    var tokens: [String: String] = [:]
  }
  private static let store = Store()

  /// "https://host:32400": scheme, host and port, lowercased.
  static func origin(_ url: URL) -> String? {
    guard let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased() else { return nil }
    let port = url.port.map { ":\($0)" } ?? ""
    return "\(scheme)://\(host)\(port)"
  }

  /// Remembers `token` for images from `baseURL`'s server.
  public static func register(_ baseURL: URL, token: String) {
    guard let origin = origin(baseURL), !token.isEmpty else { return }
    store.lock.withLock { store.tokens[origin] = token }
  }

  /// The token for a URL on a registered server, else nil (TMDB images).
  public static func token(for url: URL) -> String? {
    guard let origin = origin(url) else { return nil }
    return store.lock.withLock { store.tokens[origin] }
  }

  /// A request for `url`, with the server's token as a header when it has one.
  public static func request(_ url: URL) -> URLRequest {
    var request = URLRequest(url: url)
    if let token = token(for: url) { request.setValue(token, forHTTPHeaderField: "X-Plex-Token") }
    return request
  }

  /// Forgets every token (sign-out).
  public static func reset() {
    store.lock.withLock { store.tokens.removeAll() }
  }
}
