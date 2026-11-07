import CoreGraphics
import Foundation
import Libavcodec
import Libavformat
import Libavutil
import Libswscale

/// Astra: seek previews made by Astra itself, from the file being played
/// (KP, 2026-11-07: "like Infuse, not through Plex").
///
/// It opens its own connection to the same original file (or the downloaded
/// file), jumps to the keyframe at or before the time asked for, decodes that
/// one frame and scales it down. Only the newest request is worked on, so
/// dragging fast never queues up stale frames. Nothing is transcoded or saved:
/// the frame only exists as a small picture while scrubbing.
final class SeekPreviewGenerator: @unchecked Sendable {
  /// Previews are this wide (points × 2 for Retina).
  static let width = 384

  private let url: String
  private let headers: String
  private let queue = DispatchQueue(label: "astra.seek-preview", qos: .userInitiated)
  private let lock = NSLock()
  /// The newest request waiting to be decoded.
  private var pending: (seconds: Double, done: @Sendable (CGImage?) -> Void)?
  private var working = false
  private var closed = false

  // Touched only on `queue`.
  private var format: UnsafeMutablePointer<AVFormatContext>?
  private var decoder: UnsafeMutablePointer<AVCodecContext>?
  private var streamIndex: Int32 = -1
  private var timeBase = AVRational(num: 1, den: 1000)
  private var startTime: Int64 = 0
  private var openFailed = false

  init(url: URL, headers: [String: String]) {
    self.url = url.isFileURL ? url.path : url.absoluteString
    self.headers = headers.map { "\($0.key): \($0.value)\r\n" }.joined()
  }

  deinit {
    // `close()` normally runs first; this only frees what is left.
    freeContexts()
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

  /// Stops and frees the connection (on its queue, after any frame in progress).
  func close() {
    lock.withLock {
      closed = true
      pending = nil
    }
    queue.async { [self] in freeContexts() }
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

  // MARK: - FFmpeg

  private func openIfNeeded() -> Bool {
    if decoder != nil { return true }
    if openFailed { return false }
    openFailed = true

    var context = avformat_alloc_context()
    guard context != nil else { return false }
    // Read as little as possible before the first frame.
    context?.pointee.probesize = 2 << 20
    var options: OpaquePointer?
    if !headers.isEmpty { av_dict_set(&options, "headers", headers, 0) }
    av_dict_set(&options, "rw_timeout", "15000000", 0)
    av_dict_set(&options, "reconnect", "1", 0)
    let opened = avformat_open_input(&context, url, nil, &options)
    av_dict_free(&options)
    guard opened == 0, let context else { return false }
    format = context

    // The main video stream, not cover art.
    var index: Int32 = -1
    for i in 0..<Int(context.pointee.nb_streams) {
      guard let stream = context.pointee.streams[i], let parameters = stream.pointee.codecpar else { continue }
      let isCoverArt = stream.pointee.disposition & (1 << 10) != 0
      if parameters.pointee.codec_type == AVMEDIA_TYPE_VIDEO, !isCoverArt {
        index = Int32(i)
        break
      }
    }
    guard index >= 0, let stream = context.pointee.streams[Int(index)], let parameters = stream.pointee.codecpar,
      let codec = avcodec_find_decoder(parameters.pointee.codec_id)
    else { return false }

    var codecContext = avcodec_alloc_context3(codec)
    guard let decoding = codecContext, avcodec_parameters_to_context(decoding, parameters) >= 0 else {
      avcodec_free_context(&codecContext)
      return false
    }
    // Slice threads only: frame threads would hold frames back.
    decoding.pointee.thread_count = 0
    decoding.pointee.thread_type = 2  // FF_THREAD_SLICE
    // A preview doesn't need the deblocking pass.
    decoding.pointee.skip_loop_filter = AVDISCARD_ALL
    guard avcodec_open2(decoding, codec, nil) >= 0 else {
      avcodec_free_context(&codecContext)
      return false
    }
    decoder = decoding
    streamIndex = index
    timeBase = stream.pointee.time_base
    startTime = stream.pointee.start_time == Int64.min ? 0 : stream.pointee.start_time
    openFailed = false
    return true
  }

  private func frame(at seconds: Double) -> CGImage? {
    guard openIfNeeded(), let format, let decoder, timeBase.num > 0, timeBase.den > 0 else { return nil }
    let target = startTime + Int64(max(0, seconds) * Double(timeBase.den) / Double(timeBase.num))
    // The keyframe at or before the time: one frame to decode, like Infuse.
    guard avformat_seek_file(format, streamIndex, Int64.min, target, target, 0) >= 0 else { return nil }
    avcodec_flush_buffers(decoder)

    var packetStorage = av_packet_alloc()
    var frameStorage = av_frame_alloc()
    defer {
      av_packet_free(&packetStorage)
      av_frame_free(&frameStorage)
    }
    guard let packet = packetStorage, let frame = frameStorage else { return nil }
    var videoPackets = 0
    while videoPackets < 400, av_read_frame(format, packet) >= 0 {
      defer { av_packet_unref(packet) }
      guard packet.pointee.stream_index == streamIndex else { continue }
      videoPackets += 1
      guard avcodec_send_packet(decoder, packet) >= 0 else { continue }
      if avcodec_receive_frame(decoder, frame) >= 0 {
        defer { av_frame_unref(frame) }
        return image(from: frame)
      }
    }
    return nil
  }

  /// The frame scaled to `width` (keeping its display shape), as BGRA.
  private func image(from frame: UnsafeMutablePointer<AVFrame>) -> CGImage? {
    let sourceWidth = frame.pointee.width
    let sourceHeight = frame.pointee.height
    guard sourceWidth > 0, sourceHeight > 0 else { return nil }
    let aspect = frame.pointee.sample_aspect_ratio
    let pixelAspect = aspect.num > 0 && aspect.den > 0 ? Double(aspect.num) / Double(aspect.den) : 1
    let width = Self.width
    let height = max(2, Int((Double(width) * Double(sourceHeight) / (Double(sourceWidth) * pixelAspect)).rounded()) & ~1)

    let scaler = sws_getContext(
      sourceWidth, sourceHeight, AVPixelFormat(rawValue: frame.pointee.format), Int32(width), Int32(height),
      AV_PIX_FMT_BGRA, 2 /* SWS_BILINEAR */, nil, nil, nil)
    guard let scaler else { return nil }
    defer { sws_freeContext(scaler) }

    let bytesPerRow = width * 4
    var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
    let scaled: Int32 = pixels.withUnsafeMutableBufferPointer { buffer in
      var destination: [UnsafeMutablePointer<UInt8>?] = [buffer.baseAddress, nil, nil, nil]
      var destinationStride: [Int32] = [Int32(bytesPerRow), 0, 0, 0]
      return withUnsafePointer(to: &frame.pointee.data) { data in
        data.withMemoryRebound(to: UnsafePointer<UInt8>?.self, capacity: 8) { planes in
          withUnsafePointer(to: &frame.pointee.linesize) { lines in
            lines.withMemoryRebound(to: Int32.self, capacity: 8) { strides in
              sws_scale(scaler, planes, strides, 0, sourceHeight, &destination, &destinationStride)
            }
          }
        }
      }
    }
    guard scaled > 0, let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
    return CGImage(
      width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGBitmapInfo(
        rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
      provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
  }

  private func freeContexts() {
    if decoder != nil { avcodec_free_context(&decoder) }
    if format != nil { avformat_close_input(&format) }
  }
}
