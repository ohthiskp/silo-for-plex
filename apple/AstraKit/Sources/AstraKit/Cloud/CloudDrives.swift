import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Who a cloud account belongs to, for the source's name.
public struct CloudAccount: Sendable, Hashable {
  public var name: String
  public var email: String?

  public init(name: String, email: String? = nil) {
    self.name = name
    self.email = email
  }
}

/// A cloud account's files as shares (KP, 2026-11-17: "build Google Drive,
/// Dropbox, Box, any popular cloud services"). Read-only: Astra never
/// changes, moves or deletes anything in the cloud.
public protocol CloudDrive: FileShareProvider {
  var kind: SourceKind { get }
  func account() async throws -> CloudAccount
}

public enum CloudDrives {
  /// The drive for a signed-in account of `kind`. `token` is the saved
  /// sign-in, for values a drive needs up front (pCloud's API host).
  public static func drive(
    _ kind: SourceKind, session: OAuthSession, token: OAuthToken, transport: HTTPTransport = URLSessionTransport()
  ) -> (any CloudDrive)? {
    switch kind {
    case .googleDrive: return GoogleDrive(session: session, transport: transport)
    case .dropbox: return Dropbox(session: session, transport: transport)
    case .oneDrive: return OneDrive(session: session, transport: transport)
    case .box: return BoxDrive(session: session, transport: transport)
    case .pCloud: return PCloud(session: session, host: token.extra["hostname"] ?? "api.pcloud.com", transport: transport)
    case .yandexDisk: return YandexDisk(session: session, transport: transport)
    default: return nil
    }
  }
}

/// Bigger reads for the cloud: every chunk is a round trip to the internet.
let cloudChunk = 8 << 20

// MARK: - Google Drive

/// Google Drive (Drive API v3): My Drive and shared drives. Files are found by id;
/// `PathIDs` maps Astra's paths to them.
public final class GoogleDrive: CloudDrive, @unchecked Sendable {
  public let kind = SourceKind.googleDrive
  let http: CloudHTTP
  static let api = "https://www.googleapis.com/drive/v3"
  private let lock = NSLock()
  private var shares: [String: GoogleDriveShare] = [:]

  public init(session: OAuthSession, transport: HTTPTransport = URLSessionTransport()) {
    http = CloudHTTP(auth: .oauth(session, scheme: "Bearer"), transport: transport)
  }

  public func account() async throws -> CloudAccount {
    struct Body: Decodable {
      struct User: Decodable {
        var displayName: String?
        var emailAddress: String?
      }
      var user: User?
    }
    let body: Body = try await http.json(URLRequest(url: URL(string: Self.api + "/about?fields=user(displayName,emailAddress)")!))
    return CloudAccount(name: body.user?.displayName ?? body.user?.emailAddress ?? "Google Drive", email: body.user?.emailAddress)
  }

  /// My Drive ("" id), then each shared drive.
  public func roots() async throws -> [ShareRoot] {
    struct Body: Decodable {
      struct Drive: Decodable {
        var id: String
        var name: String
      }
      var drives: [Drive]?
      var nextPageToken: String?
    }
    var roots = [ShareRoot(id: "", title: "My Drive")]
    var page: String?
    repeat {
      var components = URLComponents(string: Self.api + "/drives")!
      components.queryItems = [URLQueryItem(name: "pageSize", value: "100")] + (page.map { [URLQueryItem(name: "pageToken", value: $0)] } ?? [])
      let body: Body = try await http.json(URLRequest(url: components.url!))
      roots += (body.drives ?? []).map { ShareRoot(id: $0.id, title: $0.name) }
      page = body.nextPageToken
    } while page != nil
    return roots
  }

  public func share(_ name: String) async throws -> any FileShare {
    lock.withLock {
      if let share = shares[name] { return share }
      let share = GoogleDriveShare(http: http, driveID: name.isEmpty ? nil : name)
      shares[name] = share
      return share
    }
  }
}

struct GoogleDriveShare: FileShare {
  let http: CloudHTTP
  /// nil: My Drive.
  let driveID: String?
  let ids: PathIDs

  init(http: CloudHTTP, driveID: String?) {
    self.http = http
    self.driveID = driveID
    ids = PathIDs(root: driveID ?? "root")
  }

  var preferredChunkSize: Int { cloudChunk }

  struct File: Decodable {
    struct Shortcut: Decodable {
      var targetId: String?
      var targetMimeType: String?
    }
    var id: String
    var name: String
    var mimeType: String
    var size: String?
    var modifiedTime: String?
    var shortcutDetails: Shortcut?
  }

  static let folderType = "application/vnd.google-apps.folder"

  func list(_ path: String) async throws -> [ShareEntry] {
    let folder = CloudPath.trim(path)
    let parent = try await ids.resolve(folder) { try await self.list($0) }
    guard parent.isDirectory else { throw SourceError.notFound }
    struct Body: Decodable {
      var files: [File]?
      var nextPageToken: String?
    }
    var entries: [ShareEntry] = []
    var page: String?
    repeat {
      var components = URLComponents(string: GoogleDrive.api + "/files")!
      var query = [
        URLQueryItem(name: "q", value: "'\(parent.id)' in parents and trashed = false"),
        URLQueryItem(
          name: "fields", value: "nextPageToken,files(id,name,mimeType,size,modifiedTime,shortcutDetails(targetId,targetMimeType))"),
        URLQueryItem(name: "pageSize", value: "1000"),
        URLQueryItem(name: "supportsAllDrives", value: "true"),
        URLQueryItem(name: "includeItemsFromAllDrives", value: "true"),
      ]
      if let driveID {
        query += [URLQueryItem(name: "corpora", value: "drive"), URLQueryItem(name: "driveId", value: driveID)]
      }
      if let page { query.append(URLQueryItem(name: "pageToken", value: page)) }
      components.queryItems = query
      let body: Body = try await http.json(URLRequest(url: components.url!))
      for file in body.files ?? [] {
        // A shortcut stands for its target.
        let id = file.shortcutDetails?.targetId ?? file.id
        let type = file.shortcutDetails?.targetMimeType ?? file.mimeType
        let isFolder = type == Self.folderType
        // Google Docs, Sheets and the like aren't files.
        guard isFolder || !type.hasPrefix("application/vnd.google-apps.") else { continue }
        let childPath = CloudPath.join(folder, file.name)
        let size = Int64(file.size ?? "") ?? 0
        if ids[childPath] == nil { ids[childPath] = PathIDs.Item(id: id, isDirectory: isFolder, size: size) }
        entries.append(
          ShareEntry(name: file.name, path: childPath, isDirectory: isFolder, size: size, modified: CloudPath.date(iso: file.modifiedTime)))
      }
      page = body.nextPageToken
    } while page != nil
    return entries
  }

  func size(of path: String) async throws -> Int64 {
    try await ids.resolve(path) { try await self.list($0) }.size
  }

  func read(_ path: String, offset: Int64, length: Int) async throws -> Data {
    let item = try await ids.resolve(path) { try await self.list($0) }
    let url = URL(string: GoogleDrive.api + "/files/\(item.id)?alt=media&supportsAllDrives=true")!
    return try await http.range(URLRequest(url: url), offset: offset, length: length)
  }
}

// MARK: - Dropbox

/// Dropbox (API v2): paths, no ids needed.
public final class Dropbox: CloudDrive, FileShare, @unchecked Sendable {
  public let kind = SourceKind.dropbox
  let http: CloudHTTP

  public init(session: OAuthSession, transport: HTTPTransport = URLSessionTransport()) {
    http = CloudHTTP(auth: .oauth(session, scheme: "Bearer"), transport: transport)
  }

  public var preferredChunkSize: Int { cloudChunk }

  func rpc(_ endpoint: String, _ body: Any?) -> URLRequest {
    var request = URLRequest(url: URL(string: "https://api.dropboxapi.com/2/" + endpoint)!)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = body.flatMap { try? JSONSerialization.data(withJSONObject: $0) } ?? Data("null".utf8)
    return request
  }

  /// Dropbox's paths: "" for the top, otherwise "/a/b".
  static func path(_ path: String) -> String {
    let trimmed = CloudPath.trim(path)
    return trimmed.isEmpty ? "" : "/" + trimmed
  }

  /// The Dropbox-API-Arg header must be ASCII: other characters as \uXXXX.
  static func apiArg(_ object: [String: String]) -> String {
    let json = String(decoding: (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data(), as: UTF8.self)
    var out = ""
    for unit in json.utf16 {
      if unit < 0x80 {
        out.append(Character(Unicode.Scalar(UInt8(unit))))
      } else {
        out += String(format: "\\u%04x", unit)
      }
    }
    return out
  }

  public func account() async throws -> CloudAccount {
    struct Body: Decodable {
      struct Name: Decodable { var display_name: String? }
      var name: Name?
      var email: String?
    }
    let body: Body = try await http.json(rpc("users/get_current_account", nil))
    return CloudAccount(name: body.name?.display_name ?? body.email ?? "Dropbox", email: body.email)
  }

  public func roots() async throws -> [ShareRoot] { [ShareRoot(id: "", title: "Dropbox")] }
  public func share(_ name: String) async throws -> any FileShare { self }

  struct Entry: Decodable {
    var tag: String
    var name: String
    var size: Int64?
    var server_modified: String?

    enum CodingKeys: String, CodingKey {
      case tag = ".tag"
      case name, size, server_modified
    }
  }

  public func list(_ path: String) async throws -> [ShareEntry] {
    let folder = CloudPath.trim(path)
    struct Body: Decodable {
      var entries: [Entry]
      var cursor: String?
      var has_more: Bool?
    }
    var entries: [ShareEntry] = []
    var body: Body = try await http.json(rpc("files/list_folder", ["path": Self.path(folder), "limit": 2000]))
    while true {
      for entry in body.entries where entry.tag == "folder" || entry.tag == "file" {
        entries.append(
          ShareEntry(
            name: entry.name, path: CloudPath.join(folder, entry.name), isDirectory: entry.tag == "folder",
            size: entry.size ?? 0, modified: CloudPath.date(iso: entry.server_modified)))
      }
      guard body.has_more == true, let cursor = body.cursor else { break }
      body = try await http.json(rpc("files/list_folder/continue", ["cursor": cursor]))
    }
    return entries
  }

  public func size(of path: String) async throws -> Int64 {
    let entry: Entry = try await http.json(rpc("files/get_metadata", ["path": Self.path(path)]))
    return entry.size ?? 0
  }

  public func read(_ path: String, offset: Int64, length: Int) async throws -> Data {
    var request = URLRequest(url: URL(string: "https://content.dropboxapi.com/2/files/download")!)
    request.httpMethod = "POST"
    request.setValue(Self.apiArg(["path": Self.path(path)]), forHTTPHeaderField: "Dropbox-API-Arg")
    return try await http.range(request, offset: offset, length: length)
  }
}

// MARK: - OneDrive

/// OneDrive (Microsoft Graph): personal and work accounts, by path.
public final class OneDrive: CloudDrive, FileShare, @unchecked Sendable {
  public let kind = SourceKind.oneDrive
  let http: CloudHTTP
  let links = LinkCache(lifetime: 45 * 60)
  static let api = "https://graph.microsoft.com/v1.0"

  public init(session: OAuthSession, transport: HTTPTransport = URLSessionTransport()) {
    http = CloudHTTP(auth: .oauth(session, scheme: "Bearer"), transport: transport)
  }

  public var preferredChunkSize: Int { cloudChunk }

  public func account() async throws -> CloudAccount {
    struct Body: Decodable {
      var displayName: String?
      var userPrincipalName: String?
      var mail: String?
    }
    let body: Body = try await http.json(URLRequest(url: URL(string: Self.api + "/me")!))
    let email = body.mail ?? body.userPrincipalName
    return CloudAccount(name: body.displayName ?? email ?? "OneDrive", email: email)
  }

  public func roots() async throws -> [ShareRoot] { [ShareRoot(id: "", title: "OneDrive")] }
  public func share(_ name: String) async throws -> any FileShare { self }

  /// "/me/drive/root" or "/me/drive/root:/Movies/Dune:".
  static func item(_ path: String) -> String {
    let trimmed = CloudPath.trim(path)
    return trimmed.isEmpty ? api + "/me/drive/root" : api + "/me/drive/root:/" + CloudPath.encode(trimmed) + ":"
  }

  struct Item: Decodable {
    struct Folder: Decodable { var childCount: Int? }
    var name: String
    var size: Int64?
    var folder: Folder?
    var lastModifiedDateTime: String?
    var downloadURL: String?

    enum CodingKeys: String, CodingKey {
      case name, size, folder, lastModifiedDateTime
      case downloadURL = "@microsoft.graph.downloadUrl"
    }
  }

  public func list(_ path: String) async throws -> [ShareEntry] {
    let folder = CloudPath.trim(path)
    struct Body: Decodable {
      var value: [Item]
      var nextLink: String?
      enum CodingKeys: String, CodingKey {
        case value
        case nextLink = "@odata.nextLink"
      }
    }
    var entries: [ShareEntry] = []
    var next: URL? = URL(
      string: Self.item(folder) + "/children?$top=1000&$select=name,size,folder,file,lastModifiedDateTime")
    while let url = next {
      let body: Body = try await http.json(URLRequest(url: url))
      for item in body.value {
        entries.append(
          ShareEntry(
            name: item.name, path: CloudPath.join(folder, item.name), isDirectory: item.folder != nil, size: item.size ?? 0,
            modified: CloudPath.date(iso: item.lastModifiedDateTime)))
      }
      next = body.nextLink.flatMap(URL.init(string:))
    }
    return entries
  }

  func link(_ path: String) async throws -> LinkCache.Link {
    let item: Item = try await http.json(URLRequest(url: URL(string: Self.item(path))!))
    guard let url = item.downloadURL.flatMap(URL.init(string:)) else { throw SourceError.notFound }
    return LinkCache.Link(url: url, size: item.size ?? 0, made: Date())
  }

  public func size(of path: String) async throws -> Int64 {
    if let link = links.get(path) { return link.size }
    let link = try await link(path)
    links.set(path, link)
    return link.size
  }

  /// Through the item's pre-signed download link (no token sent with it).
  public func read(_ path: String, offset: Int64, length: Int) async throws -> Data {
    try await links.read(path, offset: offset, length: length, http: http) { try await self.link(path) }
  }
}

// MARK: - Box

/// Box (API 2.0): files by id, so `PathIDs` maps paths. Folder "0" is the top.
public final class BoxDrive: CloudDrive, FileShare, @unchecked Sendable {
  public let kind = SourceKind.box
  let http: CloudHTTP
  let ids = PathIDs(root: "0")
  static let api = "https://api.box.com/2.0"

  public init(session: OAuthSession, transport: HTTPTransport = URLSessionTransport()) {
    http = CloudHTTP(auth: .oauth(session, scheme: "Bearer"), transport: transport)
  }

  public var preferredChunkSize: Int { cloudChunk }

  public func account() async throws -> CloudAccount {
    struct Body: Decodable {
      var name: String?
      var login: String?
    }
    let body: Body = try await http.json(URLRequest(url: URL(string: Self.api + "/users/me?fields=name,login")!))
    return CloudAccount(name: body.name ?? body.login ?? "Box", email: body.login)
  }

  public func roots() async throws -> [ShareRoot] { [ShareRoot(id: "", title: "Box")] }
  public func share(_ name: String) async throws -> any FileShare { self }

  public func list(_ path: String) async throws -> [ShareEntry] {
    let folder = CloudPath.trim(path)
    let parent = try await ids.resolve(folder) { try await self.list($0) }
    guard parent.isDirectory else { throw SourceError.notFound }
    struct Body: Decodable {
      struct Entry: Decodable {
        var id: String
        var type: String
        var name: String
        var size: Int64?
        var modified_at: String?
      }
      var entries: [Entry]
      var next_marker: String?
    }
    var entries: [ShareEntry] = []
    var marker: String?
    repeat {
      var components = URLComponents(string: Self.api + "/folders/\(parent.id)/items")!
      components.queryItems = [
        URLQueryItem(name: "fields", value: "id,type,name,size,modified_at"), URLQueryItem(name: "limit", value: "1000"),
        URLQueryItem(name: "usemarker", value: "true"),
      ] + (marker.map { [URLQueryItem(name: "marker", value: $0)] } ?? [])
      let body: Body = try await http.json(URLRequest(url: components.url!))
      for entry in body.entries where entry.type == "folder" || entry.type == "file" {
        let childPath = CloudPath.join(folder, entry.name)
        let isFolder = entry.type == "folder"
        ids[childPath] = PathIDs.Item(id: entry.id, isDirectory: isFolder, size: entry.size ?? 0)
        entries.append(
          ShareEntry(
            name: entry.name, path: childPath, isDirectory: isFolder, size: entry.size ?? 0,
            modified: CloudPath.date(iso: entry.modified_at)))
      }
      marker = body.next_marker.flatMap { $0.isEmpty ? nil : $0 }
    } while marker != nil
    return entries
  }

  public func size(of path: String) async throws -> Int64 {
    try await ids.resolve(path) { try await self.list($0) }.size
  }

  /// Box answers with a redirect to its download host, which the session follows.
  public func read(_ path: String, offset: Int64, length: Int) async throws -> Data {
    let item = try await ids.resolve(path) { try await self.list($0) }
    return try await http.range(URLRequest(url: URL(string: Self.api + "/files/\(item.id)/content")!), offset: offset, length: length)
  }
}

// MARK: - pCloud

/// pCloud: paths, on the account's own API host (US or EU). Its tokens don't expire.
public final class PCloud: CloudDrive, FileShare, @unchecked Sendable {
  public let kind = SourceKind.pCloud
  let http: CloudHTTP
  let host: String
  let links = LinkCache(lifetime: 30 * 60)

  public init(session: OAuthSession, host: String = "api.pcloud.com", transport: HTTPTransport = URLSessionTransport()) {
    http = CloudHTTP(auth: .oauth(session, scheme: "Bearer"), transport: transport)
    self.host = ["api.pcloud.com", "eapi.pcloud.com"].contains(host) ? host : "api.pcloud.com"
  }

  public var preferredChunkSize: Int { cloudChunk }

  func request(_ method: String, _ query: [String: String]) -> URLRequest {
    var components = URLComponents(string: "https://\(host)/\(method)")!
    components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
    return URLRequest(url: components.url!)
  }

  /// pCloud answers 200 with a "result" code: 0 is success.
  func call<Body: Decodable>(_ method: String, _ query: [String: String] = [:]) async throws -> Body {
    let (data, response) = try await http.send(request(method, query))
    try CloudHTTP.check(response.statusCode, data: data)
    guard let result = try? JSONDecoder().decode(PCloudResult.self, from: data) else { throw PlexError.invalidResponse }
    switch result.result {
    case 0: break
    case 1000, 2000, 2094, 2095: throw SourceError.wrongLogin
    case 2002, 2005, 2009: throw SourceError.notFound
    default: throw SourceError.share("pCloud answered: \(result.error ?? "error \(result.result)").")
    }
    guard let body = try? JSONDecoder().decode(Body.self, from: data) else { throw PlexError.invalidResponse }
    return body
  }

  static func path(_ path: String) -> String { "/" + CloudPath.trim(path) }

  struct PCloudResult: Decodable {
    var result: Int
    var error: String?
  }

  public func account() async throws -> CloudAccount {
    struct Body: Decodable { var email: String? }
    let body: Body = try await call("userinfo")
    return CloudAccount(name: body.email ?? "pCloud", email: body.email)
  }

  public func roots() async throws -> [ShareRoot] { [ShareRoot(id: "", title: "pCloud")] }
  public func share(_ name: String) async throws -> any FileShare { self }

  struct Metadata: Decodable {
    var name: String
    var isfolder: Bool?
    var size: Int64?
    var modified: String?
    var contents: [Metadata]?
  }

  public func list(_ path: String) async throws -> [ShareEntry] {
    let folder = CloudPath.trim(path)
    struct Body: Decodable { var metadata: Metadata }
    let body: Body = try await call("listfolder", ["path": Self.path(folder)])
    return (body.metadata.contents ?? []).map {
      ShareEntry(
        name: $0.name, path: CloudPath.join(folder, $0.name), isDirectory: $0.isfolder ?? false, size: $0.size ?? 0,
        modified: CloudPath.date(rfc1123: $0.modified))
    }
  }

  func link(_ path: String) async throws -> LinkCache.Link {
    struct Body: Decodable {
      var hosts: [String]
      var path: String
      var size: Int64?
    }
    let body: Body = try await call("getfilelink", ["path": Self.path(path), "forcedownload": "1"])
    guard let host = body.hosts.first, let url = URL(string: "https://\(host)\(body.path)") else { throw SourceError.notFound }
    return LinkCache.Link(url: url, size: body.size ?? 0, made: Date())
  }

  public func size(of path: String) async throws -> Int64 {
    struct Body: Decodable { var metadata: Metadata }
    let body: Body = try await call("stat", ["path": Self.path(path)])
    return body.metadata.size ?? 0
  }

  public func read(_ path: String, offset: Int64, length: Int) async throws -> Data {
    try await links.read(path, offset: offset, length: length, http: http) { try await self.link(path) }
  }
}

// MARK: - Yandex Disk

/// Yandex Disk (REST API v1): paths under "disk:/".
public final class YandexDisk: CloudDrive, FileShare, @unchecked Sendable {
  public let kind = SourceKind.yandexDisk
  let http: CloudHTTP
  let links = LinkCache(lifetime: 30 * 60)
  static let api = "https://cloud-api.yandex.net/v1/disk"

  public init(session: OAuthSession, transport: HTTPTransport = URLSessionTransport()) {
    http = CloudHTTP(auth: .oauth(session, scheme: "OAuth"), transport: transport)
  }

  public var preferredChunkSize: Int { cloudChunk }

  func url(_ endpoint: String, _ query: [String: String]) -> URL {
    var components = URLComponents(string: Self.api + endpoint)!
    components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
    return components.url!
  }

  static func path(_ path: String) -> String { "disk:/" + CloudPath.trim(path) }

  public func account() async throws -> CloudAccount {
    struct Body: Decodable {
      struct User: Decodable {
        var display_name: String?
        var login: String?
      }
      var user: User?
    }
    let body: Body = try await http.json(URLRequest(url: url("/", ["fields": "user"])))
    return CloudAccount(name: body.user?.display_name ?? body.user?.login ?? "Yandex Disk", email: body.user?.login)
  }

  public func roots() async throws -> [ShareRoot] { [ShareRoot(id: "", title: "Yandex Disk")] }
  public func share(_ name: String) async throws -> any FileShare { self }

  struct Resource: Decodable {
    struct Embedded: Decodable {
      var items: [Resource]
      var total: Int?
    }
    var name: String?
    var type: String?
    var size: Int64?
    var modified: String?
    var _embedded: Embedded?
  }

  public func list(_ path: String) async throws -> [ShareEntry] {
    let folder = CloudPath.trim(path)
    var entries: [ShareEntry] = []
    var offset = 0
    while true {
      let body: Resource = try await http.json(
        URLRequest(url: url("/resources", ["path": Self.path(folder), "limit": "1000", "offset": String(offset)])))
      let items = body._embedded?.items ?? []
      for item in items {
        guard let name = item.name else { continue }
        entries.append(
          ShareEntry(
            name: name, path: CloudPath.join(folder, name), isDirectory: item.type == "dir", size: item.size ?? 0,
            modified: CloudPath.date(iso: item.modified)))
      }
      offset += items.count
      guard !items.isEmpty, offset < (body._embedded?.total ?? 0) else { break }
    }
    return entries
  }

  public func size(of path: String) async throws -> Int64 {
    let body: Resource = try await http.json(URLRequest(url: url("/resources", ["path": Self.path(path), "fields": "size"])))
    return body.size ?? 0
  }

  func link(_ path: String) async throws -> LinkCache.Link {
    struct Body: Decodable { var href: String }
    let body: Body = try await http.json(URLRequest(url: url("/resources/download", ["path": Self.path(path)])))
    guard let url = URL(string: body.href) else { throw SourceError.notFound }
    return LinkCache.Link(url: url, size: 0, made: Date())
  }

  public func read(_ path: String, offset: Int64, length: Int) async throws -> Data {
    try await links.read(path, offset: offset, length: length, http: http) { try await self.link(path) }
  }
}
