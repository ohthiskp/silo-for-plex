import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// One request Astra made, for Settings → Network Diagnostics. Tokens never
/// reach it: the URL is stored without its query's secrets.
public struct NetworkEvent: Identifiable, Sendable, Equatable {
  public let id: Int
  public let date: Date
  public let method: String
  public let host: String
  public let path: String
  /// Nil when no response arrived.
  public let status: Int?
  public let milliseconds: Int
  /// A readable reason when the request failed or was refused.
  public let failure: String?

  public var succeeded: Bool { failure == nil && (status.map { (200..<300).contains($0) } ?? false) }
}

/// The last few hundred requests, newest last. Shared by every client, safe from any thread.
public final class NetworkLog: @unchecked Sendable {
  public static let shared = NetworkLog()

  private let lock = NSLock()
  private var events: [NetworkEvent] = []
  private var nextID = 0
  let capacity: Int

  public init(capacity: Int = 300) {
    self.capacity = capacity
  }

  public var recent: [NetworkEvent] { lock.withLock { events } }

  public func clear() { lock.withLock { events.removeAll() } }

  public func record(
    _ request: URLRequest, status: Int?, started: Date, error: Error?, now: Date = Date()
  ) {
    // A request Astra cancelled itself (a newer one replaced it) isn't a failure.
    if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
    let url = request.url
    lock.withLock {
      nextID += 1
      events.append(
        NetworkEvent(
          id: nextID, date: started, method: request.httpMethod ?? "GET",
          host: url?.host() ?? "", path: url.map(Self.redactedPath) ?? "",
          status: status, milliseconds: max(0, Int(now.timeIntervalSince(started) * 1000)),
          failure: error.map { PlexError.describe($0) }
            ?? status.flatMap { (200..<300).contains($0) ? nil : PlexError.describe(PlexError.status($0)) }))
      if events.count > capacity { events.removeFirst(events.count - capacity) }
    }
  }

  /// The path and query with every secret removed (Plex and TMDB tokens).
  public static func redactedPath(_ url: URL) -> String {
    guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url.path }
    let secret: Set<String> = ["x-plex-token", "api_key", "token", "access_token"]
    parts.queryItems = parts.queryItems?.map {
      secret.contains($0.name.lowercased()) ? URLQueryItem(name: $0.name, value: "•••") : $0
    }
    let query = parts.percentEncodedQuery.map { "?\($0)" } ?? ""
    return redactNested(parts.percentEncodedPath + query)
  }

  /// Secrets inside other values, such as a photo transcode's
  /// `url=/library/…/thumb%3FX-Plex-Token%3Dabc` (encoded once or twice).
  private static let nestedSecret = try! NSRegularExpression(
    pattern: #"(?i)(?:(?<=[?&/])|(?<=%3F)|(?<=%26)|(?<=%253F)|(?<=%2526))(x-plex-token|access_token|api_key|token)(=|%3D|%253D)(.*?)(?=&|%26|%2526|#|$)"#)

  static func redactNested(_ text: String) -> String {
    nestedSecret.stringByReplacingMatches(
      in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "$1$2•••")
  }
}

extension PlexError {
  /// The error for an HTTP status that isn't success.
  static func status(_ code: Int) -> PlexError {
    code == 401 || code == 403 ? .unauthorized : .http(code)
  }

  /// A sentence for people, for any error Astra's network code can throw.
  /// `server` names who didn't answer ("Plex server Ohana").
  public static func describe(_ error: Error, server: String? = nil) -> String {
    let who = server ?? "The server"
    if let plex = error as? PlexError { return plex.errorDescription ?? "Something went wrong." }
    if let url = error as? URLError {
      switch url.code {
      case .timedOut:
        return "\(who) took too long to answer. It may be busy, asleep or unreachable from this network."
      case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
        return "Astra couldn't reach \(server ?? "the server"). Check that it's on and connected."
      case .networkConnectionLost:
        return "The connection to \(server ?? "the server") dropped. Try again."
      case .notConnectedToInternet:
        return "This device is offline."
      case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
        .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot:
        return "The secure connection to \(server ?? "the server") failed."
      case .cancelled:
        return "Cancelled."
      default:
        return url.localizedDescription
      }
    }
    if error is CancellationError { return "Cancelled." }
    if error is DecodingError { return PlexError.invalidResponse.errorDescription ?? "" }
    return error.localizedDescription
  }
}
