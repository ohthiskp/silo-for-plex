import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// What mpv (or a download) opens for one file: its URL and the headers that
/// carry the sign-in, so no token ends up in a URL.
public struct StreamRequest: Sendable, Hashable {
  public var url: URL
  public var headers: [String: String]

  public init(url: URL, headers: [String: String] = [:]) {
    self.url = url
    self.headers = headers
  }

  public var urlRequest: URLRequest {
    var request = URLRequest(url: url)
    for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
    return request
  }
}

/// One source besides Plex (Jellyfin, Emby, a network share). It answers in
/// Plex's models, with every key made by `SourceKey.make`, so Home, Library,
/// Details, the player and downloads treat its titles like Plex's.
///
/// Ids passed in are the source's own ("native") ids, with the
/// "src~<source>~" prefix already taken off.
public protocol MediaSourceClient: Sendable {
  var config: SourceConfig { get }

  /// The libraries as the source lists them now (a media server is asked; a
  /// share's are its folders).
  func libraries() async throws -> [SourceLibrary]
  /// A page of a library. `sort` and `filters` use Plex's names
  /// ("titleSort", "addedAt:desc", `unwatched=1`, `genre=<key>`); ones a
  /// source can't do are ignored.
  func items(library: String, sort: String, start: Int, size: Int, filters: [URLQueryItem]) async throws -> [PlexMetadata]
  func count(library: String, filters: [URLQueryItem]) async throws -> Int?
  func genres(library: String) async throws -> [PlexFilterValue]
  /// Full details of one item, with its files and streams.
  func metadata(_ id: String) async throws -> PlexMetadata
  /// A show's seasons, or a season's episodes.
  func children(_ id: String) async throws -> [PlexMetadata]
  func search(_ text: String, limit: Int) async throws -> [PlexMetadata]
  /// Titles started and not finished, most recent first.
  func continueWatching(count: Int) async throws -> [PlexMetadata]
  func setWatched(_ id: String, watched: Bool) async throws
  func removeFromContinueWatching(_ id: String) async throws
  /// Playback progress for `id` (the item's native id).
  func report(_ report: TimelineReport, id: String) async throws
  /// The original file behind a part key (or a sidecar subtitle's key).
  func stream(_ key: String) -> StreamRequest?
  /// An image the source serves, sized for the frame.
  func imageURL(_ path: String, width: Int, height: Int) -> URL?
}

extension MediaSourceClient {
  public var id: String { config.id }

  /// `native` as a key the rest of Astra uses.
  public func key(_ native: String) -> String { SourceKey.make(config.id, native) }
  public func optionalKey(_ native: String?) -> String? { native.map { SourceKey.make(config.id, $0) } }
}

/// The sources added in Settings, keyed by id. `PlexServerClient` asks it
/// first for any key that starts with "src~" and merges its libraries,
/// search and Continue Watching with Plex's.
public final class SourceRouter: Sendable {
  public let clients: [any MediaSourceClient]
  private let byID: [String: any MediaSourceClient]

  public static let none = SourceRouter([])

  public init(_ clients: [any MediaSourceClient]) {
    let enabled = clients.filter(\.config.enabled)
    self.clients = enabled
    var byID: [String: any MediaSourceClient] = [:]
    for client in enabled { byID[client.config.id] = client }
    self.byID = byID
  }

  public var isEmpty: Bool { clients.isEmpty }

  public func client(id: String) -> (any MediaSourceClient)? { byID[id] }

  /// The source and its own id for a source key; nil for a Plex key.
  public func route(_ key: String?) -> (client: any MediaSourceClient, native: String)? {
    guard let key, let (source, native) = SourceKey.split(key), let client = byID[source] else { return nil }
    return (client, native)
  }

  /// Every source's libraries as last saved (no network), for opening the
  /// library at once at launch.
  public var sections: [PlexLibrarySection] { clients.flatMap(\.config.sections) }

  /// Calls `body` on every source at once and keeps what each returned; a
  /// source that fails or is offline adds nothing (Plex's results still show).
  public func gather<T: Sendable>(
    _ body: @escaping @Sendable (any MediaSourceClient) async throws -> [T]
  ) async -> [T] {
    guard !clients.isEmpty else { return [] }
    return await withTaskGroup(of: (Int, [T]).self) { group in
      for (index, client) in clients.enumerated() {
        group.addTask { (index, (try? await body(client)) ?? []) }
      }
      var results: [(Int, [T])] = []
      for await result in group { results.append(result) }
      return results.sorted { $0.0 < $1.0 }.flatMap(\.1)
    }
  }
}

extension PlexFilterValue {
  public init(key: String, title: String) {
    self.key = key
    self.title = title
  }
}
