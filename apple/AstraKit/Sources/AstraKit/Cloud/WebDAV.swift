import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif
#if canImport(FoundationXML)
  import FoundationXML
#endif

/// A WebDAV folder (Nextcloud, ownCloud, a NAS's WebDAV server), with a
/// username and password. `address` is the folder's URL; paths are inside it.
public final class WebDAVShare: FileShareProvider, FileShare, @unchecked Sendable {
  public let base: URL
  let http: CloudHTTP

  /// `address` like "https://cloud.example.com/remote.php/dav/files/kp" or
  /// "nas.local:5005"; an empty username reads without signing in.
  public init(address: String, username: String, password: String, transport: HTTPTransport = URLSessionTransport()) throws {
    guard let base = Self.normalizedURL(address) else { throw SourceError.badAddress }
    self.base = base
    http = CloudHTTP(auth: username.isEmpty ? .none : .basic(user: username, password: password), transport: transport)
  }

  /// Adds "https://" when there's no scheme and a trailing "/".
  public static func normalizedURL(_ address: String) -> URL? {
    var text = address.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return nil }
    if text.lowercased().hasPrefix("webdav://") { text = "http://" + text.dropFirst(9) }
    if text.lowercased().hasPrefix("webdavs://") { text = "https://" + text.dropFirst(10) }
    if !text.lowercased().hasPrefix("http://"), !text.lowercased().hasPrefix("https://") { text = "https://" + text }
    if !text.hasSuffix("/") { text += "/" }
    guard let url = URL(string: text), url.host != nil else { return nil }
    return url
  }

  public var preferredChunkSize: Int { 4 << 20 }

  public func roots() async throws -> [ShareRoot] { [ShareRoot(id: "", title: base.host ?? "WebDAV")] }
  public func share(_ name: String) async throws -> any FileShare { self }

  func url(_ path: String, folder: Bool) -> URL {
    let trimmed = CloudPath.trim(path)
    let encoded = CloudPath.encode(trimmed)
    return URL(string: base.absoluteString + encoded + (folder && !trimmed.isEmpty ? "/" : ""))!
  }

  static let propfindBody = """
    <?xml version="1.0" encoding="utf-8"?>
    <d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/><d:getcontentlength/><d:getlastmodified/></d:prop></d:propfind>
    """

  func propfind(_ path: String, folder: Bool, depth: String) async throws -> [WebDAVResponse] {
    var request = URLRequest(url: url(path, folder: folder))
    request.httpMethod = "PROPFIND"
    request.setValue(depth, forHTTPHeaderField: "Depth")
    request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
    request.httpBody = Data(Self.propfindBody.utf8)
    let (data, response) = try await http.send(request)
    guard response.statusCode == 207 || response.statusCode == 200 else {
      try CloudHTTP.check(response.statusCode, data: data)
      throw SourceError.share("That address doesn't answer as a WebDAV folder.")
    }
    return WebDAVResponse.parse(data)
  }

  public func list(_ path: String) async throws -> [ShareEntry] {
    let folder = CloudPath.trim(path)
    let own = url(folder, folder: true).path
    return try await propfind(folder, folder: true, depth: "1").compactMap { response in
      // The folder itself comes back first (with or without its trailing slash).
      let href = response.path
      guard CloudPath.trim(href) != CloudPath.trim(own) else { return nil }
      let name = CloudPath.name(href)
      guard !name.isEmpty else { return nil }
      return ShareEntry(
        name: name, path: CloudPath.join(folder, name), isDirectory: response.isCollection, size: response.length ?? 0,
        modified: CloudPath.date(rfc1123: response.modified))
    }
  }

  public func size(of path: String) async throws -> Int64 {
    try await propfind(path, folder: false, depth: "0").first?.length ?? 0
  }

  public func read(_ path: String, offset: Int64, length: Int) async throws -> Data {
    try await http.range(URLRequest(url: url(path, folder: false)), offset: offset, length: length)
  }
}

/// One <d:response> of a PROPFIND answer.
struct WebDAVResponse: Equatable {
  /// The decoded path of the href ("/remote.php/dav/files/kp/Movies/").
  var path: String
  var isCollection: Bool
  var length: Int64?
  var modified: String?

  static func parse(_ data: Data) -> [WebDAVResponse] {
    let delegate = Parser()
    let parser = XMLParser(data: data)
    parser.shouldProcessNamespaces = true
    parser.delegate = delegate
    parser.parse()
    return delegate.responses
  }

  private final class Parser: NSObject, XMLParserDelegate {
    var responses: [WebDAVResponse] = []
    private var current: WebDAVResponse?
    private var text = ""

    func parser(
      _ parser: XMLParser, didStartElement element: String, namespaceURI: String?, qualifiedName: String?,
      attributes: [String: String] = [:]
    ) {
      text = ""
      switch Self.local(element) {
      case "response": current = WebDAVResponse(path: "", isCollection: false)
      case "collection": current?.isCollection = true
      default: break
      }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
      let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
      switch Self.local(element) {
      case "href":
        // An href is a path or a full URL, percent-encoded.
        current?.path = URL(string: value)?.path ?? value.removingPercentEncoding ?? value
      case "getcontentlength": current?.length = Int64(value)
      case "getlastmodified": current?.modified = value
      case "response":
        if let current { responses.append(current) }
        current = nil
      default: break
      }
      text = ""
    }

    /// "d:href" → "href" when namespaces aren't split.
    static func local(_ name: String) -> String {
      name.split(separator: ":").last.map { String($0).lowercased() } ?? name.lowercased()
    }
  }
}
