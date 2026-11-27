import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Fetches channels and the guide for a Live TV source.
public enum LiveTVLoader {
  public struct Channels: Sendable {
    public var channels: [LiveChannel]
    /// Where the guide comes from: the source's own link, the playlist
    /// header's, or the Xtream provider's xmltv.php.
    public var guide: URL?
  }

  public static func channels(
    for source: LiveTVSource, transport: HTTPTransport = URLSessionTransport(log: nil)
  ) async throws -> Channels {
    switch source {
    case .xtream(let server, let username, let password):
      let client = try XtreamClient(server: server, username: username, password: password, transport: transport)
      let format = try await client.login()
      return Channels(channels: try await client.channels(format: format), guide: client.guideURL)
    case .m3u(let playlist, let guide):
      guard let url = URL(string: playlist.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme != nil else {
        throw XtreamClient.Failure.badServer
      }
      let data = try await fetch(url, transport: transport)
      let parsed = M3UParser.parse(String(decoding: data, as: UTF8.self))
      guard !parsed.channels.isEmpty else { throw EmptyPlaylist() }
      let own = guide?.nilIfEmpty.flatMap(URL.init(string:))
      return Channels(channels: parsed.channels, guide: own ?? parsed.guide)
    }
  }

  public struct EmptyPlaylist: LocalizedError {
    public var errorDescription: String? { "That link didn't have any channels in it." }
  }

  /// The guide from `now - 1h` to `now + hours`, for these channels only.
  public static func guide(
    from url: URL, channels: [LiveChannel], now: Date = Date(), hours: Double = 12,
    transport: HTTPTransport = URLSessionTransport(log: nil)
  ) async throws -> LiveGuide {
    let data = gunzipped(try await fetch(url, transport: transport, timeout: 120))
    let ids = Set(channels.compactMap { ($0.guideID ?? $0.name).nilIfEmpty?.lowercased() })
    let programs = XMLTVParser.parse(
      data, from: now.addingTimeInterval(-3600), to: now.addingTimeInterval(hours * 3600), channels: ids)
    return LiveGuide(programs)
  }

  static func fetch(_ url: URL, transport: HTTPTransport, timeout: TimeInterval = 60) async throws -> Data {
    var request = URLRequest(url: url)
    request.timeoutInterval = timeout
    let (data, response) = try await transport.send(request)
    if response.statusCode == 401 || response.statusCode == 403 { throw XtreamClient.Failure.rejected }
    guard (200..<300).contains(response.statusCode) else { throw PlexError.http(response.statusCode) }
    return data
  }

  /// Guides are often served as .xml.gz; anything else comes back unchanged.
  static func gunzipped(_ data: Data) -> Data {
    guard data.count > 18, data[data.startIndex] == 0x1f, data[data.startIndex + 1] == 0x8b,
      data[data.startIndex + 2] == 8
    else { return data }
    #if canImport(Darwin)
      let bytes = [UInt8](data)
      let flags = bytes[3]
      var offset = 10
      if flags & 0x04 != 0, offset + 2 <= bytes.count {  // FEXTRA
        offset += 2 + (Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8))
      }
      if flags & 0x08 != 0 { while offset < bytes.count, bytes[offset] != 0 { offset += 1 }; offset += 1 }  // FNAME
      if flags & 0x10 != 0 { while offset < bytes.count, bytes[offset] != 0 { offset += 1 }; offset += 1 }  // FCOMMENT
      if flags & 0x02 != 0 { offset += 2 }  // FHCRC
      guard offset < bytes.count - 8 else { return data }
      let body = Data(bytes[offset..<(bytes.count - 8)]) as NSData
      // NSData's .zlib is raw DEFLATE, which is what a gzip member holds.
      guard let out = try? body.decompressed(using: .zlib) else { return data }
      return out as Data
    #else
      return data
    #endif
  }
}
