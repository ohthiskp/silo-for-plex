import CoreGraphics
import Foundation
import Libmpv

/// Astra: seek previews made by Astra itself, from the file being played
/// (KP, 2026-11-07: "like Infuse, not through Plex").
///
/// A second, silent mpv opens its own connection to the same original file
/// (or the downloaded file): no audio, no picture on screen, software
/// decoding, scaled down to a small frame. For each request it jumps to the
/// keyframe at or before that time and takes that frame (`screenshot-raw`).
/// Only the newest request is worked on, so dragging fast never queues up
/// stale frames. Nothing is transcoded or saved.
final class SeekPreviewGenerator: @unchecked Sendable {
  /// Previews are this many pixels wide.
  static let width = 384

  private let url: String
  private let headers: [String: String]
  private let queue = DispatchQueue(label: "astra.seek-preview", qos: .userInitiated)
  private let lock = NSLock()
  /// The newest request waiting to be decoded.
  private var pending: (seconds: Double, done: @Sendable (CGImage?) -> Void)?
  private var working = false
  private var closed = false

  // Touched only on `queue`.
  private var handle: OpaquePointer?
  private var openFailed = false

  init(url: URL, headers: [String: String]) {
    self.url = url.isFileURL ? url.path : url.absoluteString
    self.headers = headers
  }

  deinit {
    if let handle { mpv_terminate_destroy(handle) }
  }

  /// Asks for the frame at `seconds`; `done` runs on the main queue. A newer
  /// request replaces one that hasn't started.
  func request(at seconds: Double, done: @escaping @Sendable (CGImage?) -> Void) {
    let start: Bool = lock.withLock {
      guard !closed else { return false }
      pending = (seconds, done)
      if working { return false }
      working = true
      return true
    }
    if start { queue.async { [self] in drain() } }
  }

  /// Stops the preview player (on its queue, after any frame in progress).
  func close() {
    lock.withLock {
      closed = true
      pending = nil
    }
    queue.async { [self] in
      if let handle { mpv_terminate_destroy(handle) }
      handle = nil
    }
  }

  private func drain() {
    while true {
      let next: (seconds: Double, done: @Sendable (CGImage?) -> Void)? = lock.withLock {
        let next = closed ? nil : pending
        pending = nil
        if next == nil { working = false }
        return next
      }
      guard let next else { return }
      let image = frame(at: next.seconds)
      DispatchQueue.main.async { next.done(image) }
    }
  }

  // MARK: - mpv

  private func openIfNeeded() -> OpaquePointer? {
    if let handle { return handle }
    if openFailed { return nil }
    openFailed = true
    guard let mpv = mpv_create() else { return nil }
    let options: [(String, String)] = [
      ("config", "no"), ("terminal", "no"), ("msg-level", "all=no"), ("load-scripts", "no"), ("ytdl", "no"),
      ("input-default-bindings", "no"), ("osc", "no"),
      // Nothing on screen, nothing heard: frames are only taken as pictures.
      ("vo", "null"), ("ao", "null"), ("aid", "no"), ("sid", "no"),
      ("hwdec", "no"), ("pause", "yes"), ("keep-open", "always"), ("idle", "yes"),
      // Jump to keyframes only (one frame to decode, like Infuse) and read little ahead.
      ("hr-seek", "no"), ("cache", "no"), ("demuxer-readahead-secs", "0"), ("demuxer-max-bytes", "4MiB"),
      ("vf", "scale=w=\(Self.width):h=-2"), ("screenshot-sw", "yes"),
    ]
    for (name, value) in options { mpv_set_option_string(mpv, name, value) }
    if !headers.isEmpty {
      let fields = headers.map { "\($0.key): \($0.value)" }.joined(separator: ",")
      mpv_set_option_string(mpv, "http-header-fields", fields)
    }
    guard mpv_initialize(mpv) >= 0 else {
      mpv_terminate_destroy(mpv)
      return nil
    }
    guard command(mpv, ["loadfile", url]) >= 0, wait(mpv, for: MPV_EVENT_PLAYBACK_RESTART, seconds: 20) else {
      mpv_terminate_destroy(mpv)
      return nil
    }
    handle = mpv
    openFailed = false
    return mpv
  }

  private func frame(at seconds: Double) -> CGImage? {
    guard let mpv = openIfNeeded() else { return nil }
    guard command(mpv, ["seek", String(format: "%.3f", max(0, seconds)), "absolute+keyframes"]) >= 0,
      wait(mpv, for: MPV_EVENT_PLAYBACK_RESTART, seconds: 10)
    else { return nil }
    var result = mpv_node()
    guard command(mpv, ["screenshot-raw", "video"], result: &result) >= 0 else { return nil }
    defer { mpv_free_node_contents(&result) }
    return Self.image(from: result)
  }

  /// Waits for `event` (true) or the file ending / the time running out (false).
  private func wait(_ mpv: OpaquePointer, for event: mpv_event_id, seconds: Double) -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
      if lock.withLock({ closed }) { return false }
      guard let next = mpv_wait_event(mpv, 0.25) else { continue }
      let id = next.pointee.event_id
      if id == event { return true }
      if id == MPV_EVENT_END_FILE || id == MPV_EVENT_SHUTDOWN { return false }
    }
    return false
  }

  @discardableResult
  private func command(_ mpv: OpaquePointer, _ args: [String], result: UnsafeMutablePointer<mpv_node>? = nil)
    -> Int32
  {
    let strings = args.map { strdup($0) }
    defer { strings.forEach { free($0) } }
    var pointers: [UnsafePointer<CChar>?] = strings.map { $0.map { UnsafePointer($0) } } + [nil]
    if let result { return mpv_command_ret(mpv, &pointers, result) }
    return mpv_command(mpv, &pointers)
  }

  /// `screenshot-raw` answers a map: w, h, stride, format ("bgr0") and data.
  private static func image(from node: mpv_node) -> CGImage? {
    guard node.format == MPV_FORMAT_NODE_MAP, let list = node.u.list?.pointee, let keys = list.keys,
      let values = list.values
    else { return nil }
    var width = 0
    var height = 0
    var stride = 0
    var data: Data?
    for i in 0..<Int(list.num) {
      guard let key = keys[i] else { continue }
      let value = values[i]
      switch String(cString: key) {
      case "w": width = Int(value.u.int64)
      case "h": height = Int(value.u.int64)
      case "stride": stride = Int(value.u.int64)
      case "data":
        if value.format == MPV_FORMAT_BYTE_ARRAY, let bytes = value.u.ba?.pointee, let base = bytes.data {
          data = Data(bytes: base, count: Int(bytes.size))
        }
      default: break
      }
    }
    guard width > 0, height > 0, stride >= width * 4, let data, data.count >= stride * height,
      let provider = CGDataProvider(data: data as CFData)
    else { return nil }
    // bgr0: blue, green, red, unused, byte by byte.
    return CGImage(
      width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: stride,
      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGBitmapInfo(
        rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
      provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
  }
}
