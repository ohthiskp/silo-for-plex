import Foundation

/// Parses an HTTP Range header against a file size. Kept apart from the
/// server so it is tested on every platform.
public enum ByteRange {
  /// "bytes=100-", "bytes=100-199", "bytes=-500" → the closed range to send;
  /// nil for no header (the whole file). Throws for a range past the end.
  public static func parse(_ header: String?, size: Int64) throws -> ClosedRange<Int64>? {
    guard let header, let spec = header.lowercased().split(separator: "=").last, header.lowercased().hasPrefix("bytes=") else {
      return nil
    }
    // Only the first range of a multi-range request is sent.
    let first = spec.split(separator: ",").first.map(String.init) ?? ""
    let ends = first.split(separator: "-", omittingEmptySubsequences: false).map {
      $0.trimmingCharacters(in: .whitespaces)
    }
    guard ends.count == 2, size > 0 else { throw RangeError.unsatisfiable }
    if ends[0].isEmpty {
      guard let suffix = Int64(ends[1]), suffix > 0 else { throw RangeError.unsatisfiable }
      return max(0, size - suffix)...(size - 1)
    }
    guard let start = Int64(ends[0]), start < size else { throw RangeError.unsatisfiable }
    let end = ends[1].isEmpty ? size - 1 : min(size - 1, Int64(ends[1]) ?? (size - 1))
    guard end >= start else { throw RangeError.unsatisfiable }
    return start...end
  }

  public enum RangeError: Error { case unsatisfiable }
}

#if canImport(Network)
  import Network

  /// A tiny HTTP server on 127.0.0.1 that hands mpv (and downloads) the bytes
  /// of files on a share, with Range support so seeking works. mpv only
  /// plays URLs, and its FFmpeg has no SMB client; this keeps playback the
  /// original file, read straight from the share, never copied or converted.
  ///
  /// URLs are "http://127.0.0.1:<port>/<secret>/<source id>/<path in share>".
  /// The secret is new each launch, so another app on the device can't read
  /// the shares by guessing the port.
  public final class LoopbackFileServer: @unchecked Sendable {
    public typealias Resolver = @Sendable (_ sourceID: String, _ path: String) async throws -> any FileShare

    private let queue = DispatchQueue(label: "astra.loopback-files")
    private let resolver: Resolver
    private let secret: String
    private var listener: NWListener?
    private let lock = NSLock()
    private var _port: UInt16?
    /// Bytes read from the share per request; mpv reads ahead on its own.
    let chunk = 2 << 20

    public init(resolver: @escaping Resolver) {
      self.resolver = resolver
      secret = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    public var port: UInt16? { lock.withLock { _port } }

    /// The URL prefix for one source's files, nil until the server is listening.
    public func base(for sourceID: String) -> URL? {
      guard let port else { return nil }
      return URL(string: "http://127.0.0.1:\(port)/\(secret)/\(sourceID)/")
    }

    /// Starts listening on a free port, and waits (up to 2 s) until it is ready.
    public func start() async throws {
      if port != nil { return }
      let parameters = NWParameters.tcp
      parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: .any)
      parameters.allowLocalEndpointReuse = true
      let listener = try NWListener(using: parameters)
      listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
      self.listener = listener
      let ready: Bool = await withCheckedContinuation { continuation in
        let once = Once()
        listener.stateUpdateHandler = { [weak self] state in
          switch state {
          case .ready:
            if let port = listener.port?.rawValue { self?.lock.withLock { self?._port = port } }
            once.run { continuation.resume(returning: true) }
          case .failed, .cancelled:
            self?.lock.withLock { self?._port = nil }
            once.run { continuation.resume(returning: false) }
          default: break
          }
        }
        listener.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 2) { once.run { continuation.resume(returning: false) } }
      }
      if !ready { throw SourceError.share("Astra couldn't start playback for network shares.") }
    }

    public func stop() {
      listener?.cancel()
      listener = nil
      lock.withLock { _port = nil }
    }

    // MARK: - Connections

    private func accept(_ connection: NWConnection) {
      connection.start(queue: queue)
      readRequest(connection, buffer: Data())
    }

    private func readRequest(_ connection: NWConnection, buffer: Data) {
      connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, done, error in
        guard let self else { return }
        var buffer = buffer
        if let data { buffer.append(data) }
        if let end = buffer.range(of: Data("\r\n\r\n".utf8)) {
          let head = String(decoding: buffer[..<end.lowerBound], as: UTF8.self)
          Task { await self.respond(to: head, on: connection) }
        } else if error != nil || done || buffer.count > 64 * 1024 {
          connection.cancel()
        } else {
          self.readRequest(connection, buffer: buffer)
        }
      }
    }

    private func respond(to head: String, on connection: NWConnection) async {
      let lines = head.components(separatedBy: "\r\n")
      let request = lines.first?.split(separator: " ").map(String.init) ?? []
      guard request.count >= 2, ["GET", "HEAD"].contains(request[0]) else {
        return await finish(connection, status: "405 Method Not Allowed")
      }
      var headers: [String: String] = [:]
      for line in lines.dropFirst() {
        guard let colon = line.firstIndex(of: ":") else { continue }
        headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
      }
      // "/<secret>/<source>/<path…>"
      let target = request[1].split(separator: "?").first.map(String.init) ?? ""
      let pieces = target.split(separator: "/", maxSplits: 2, omittingEmptySubsequences: true).map(String.init)
      guard pieces.count == 3, pieces[0] == secret, let path = pieces[2].removingPercentEncoding else {
        return await finish(connection, status: "404 Not Found")
      }
      do {
        let share = try await resolver(pieces[1], path)
        let size = try await share.size(of: path)
        let range: ClosedRange<Int64>?
        do {
          range = try ByteRange.parse(headers["range"], size: size)
        } catch {
          return await finish(connection, status: "416 Range Not Satisfiable", extra: ["Content-Range": "bytes */\(size)"])
        }
        let span = range ?? 0...max(0, size - 1)
        let length = size == 0 ? 0 : span.upperBound - span.lowerBound + 1
        var reply = [
          range == nil ? "HTTP/1.1 200 OK" : "HTTP/1.1 206 Partial Content",
          "Content-Type: \(Self.mimeType(path))",
          "Accept-Ranges: bytes",
          "Content-Length: \(length)",
          "Connection: close",
        ]
        if range != nil { reply.append("Content-Range: bytes \(span.lowerBound)-\(span.upperBound)/\(size)") }
        guard await send(Data((reply.joined(separator: "\r\n") + "\r\n\r\n").utf8), on: connection) else { return }
        if request[0] == "HEAD" || length == 0 { return await close(connection) }
        // Read one chunk ahead while the last one is sent, so the share and
        // the socket both stay busy.
        var offset = span.lowerBound
        let end = span.upperBound + 1
        var next: Task<Data, Error>? = Task { try await share.read(path, offset: offset, length: Int(min(Int64(chunk), end - offset))) }
        while let pending = next {
          let data = try await pending.value
          if data.isEmpty { break }
          offset += Int64(data.count)
          next = offset < end
            ? Task { [chunk, offset] in try await share.read(path, offset: offset, length: Int(min(Int64(chunk), end - offset))) }
            : nil
          guard await send(data, on: connection) else {
            next?.cancel()
            return
          }
        }
        await close(connection)
      } catch {
        await finish(connection, status: "502 Bad Gateway")
      }
    }

    private func finish(_ connection: NWConnection, status: String, extra: [String: String] = [:]) async {
      var lines = ["HTTP/1.1 \(status)", "Content-Length: 0", "Connection: close"]
      for (name, value) in extra { lines.append("\(name): \(value)") }
      _ = await send(Data((lines.joined(separator: "\r\n") + "\r\n\r\n").utf8), on: connection)
      await close(connection)
    }

    /// Sends and waits until the bytes are handed to the socket; false when
    /// the player closed the connection (it does on every seek).
    private func send(_ data: Data, on connection: NWConnection) async -> Bool {
      await withCheckedContinuation { continuation in
        connection.send(content: data, completion: .contentProcessed { error in continuation.resume(returning: error == nil) })
      }
    }

    private func close(_ connection: NWConnection) async {
      await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        connection.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
          continuation.resume()
        })
      }
      connection.cancel()
    }

    static func mimeType(_ path: String) -> String {
      switch MediaFiles.fileExtension(path) {
      case "mp4", "m4v": "video/mp4"
      case "mov": "video/quicktime"
      case "mkv": "video/x-matroska"
      case "webm": "video/webm"
      case "avi": "video/x-msvideo"
      case "ts", "m2ts", "mts": "video/mp2t"
      case "srt": "application/x-subrip"
      case "vtt": "text/vtt"
      case "ass", "ssa": "text/x-ssa"
      default: "application/octet-stream"
      }
    }
  }

  /// Runs a closure once, from whichever callback gets there first.
  private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func run(_ body: () -> Void) {
      let first = lock.withLock { () -> Bool in
        if done { return false }
        done = true
        return true
      }
      if first { body() }
    }
  }
#endif
