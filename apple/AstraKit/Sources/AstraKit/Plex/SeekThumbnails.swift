import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Plex's seek preview images for one file: a BIF ("base index frames")
/// file the server generates (`/library/parts/{id}/indexes/sd`), a header,
/// an index of timestamps and offsets, then one JPEG per frame (usually every
/// 2–10 s). Reading it is far cheaper than decoding frames with mpv.
public struct SeekThumbnails: Sendable {
  public struct Frame: Sendable, Equatable {
    public var milliseconds: Int
    public var range: Range<Int>
  }

  public let frames: [Frame]
  let data: Data

  static let magic: [UInt8] = [0x89, 0x42, 0x49, 0x46, 0x0D, 0x0A, 0x1A, 0x0A]

  /// Nil when `data` isn't a well-formed BIF file.
  public init?(bif data: Data) {
    let bytes = [UInt8](data)
    guard bytes.count >= 64, Array(bytes[0..<8]) == Self.magic else { return nil }
    func u32(_ at: Int) -> Int? {
      guard at + 4 <= bytes.count else { return nil }
      return Int(bytes[at]) | Int(bytes[at + 1]) << 8 | Int(bytes[at + 2]) << 16 | Int(bytes[at + 3]) << 24
    }
    guard let count = u32(12), let multiplierRaw = u32(16), count > 0, count < 1_000_000 else { return nil }
    let multiplier = multiplierRaw == 0 ? 1000 : multiplierRaw
    var frames: [Frame] = []
    frames.reserveCapacity(count)
    for i in 0..<count {
      guard let timestamp = u32(64 + i * 8), let offset = u32(64 + i * 8 + 4), let next = u32(64 + (i + 1) * 8 + 4),
        offset < next, next <= bytes.count
      else { return nil }
      frames.append(Frame(milliseconds: timestamp * multiplier, range: offset..<next))
    }
    self.frames = frames
    self.data = data
  }

  /// The index of the frame shown at `seconds`: the last one at or before it.
  public func frameIndex(at seconds: Double) -> Int? {
    guard !frames.isEmpty, seconds.isFinite else { return nil }
    let ms = Int(max(0, seconds) * 1000)
    var low = 0
    var high = frames.count - 1
    while low < high {
      let mid = (low + high + 1) / 2
      if frames[mid].milliseconds <= ms { low = mid } else { high = mid - 1 }
    }
    return low
  }

  /// The JPEG bytes of frame `index`.
  public func jpeg(_ index: Int) -> Data? {
    guard frames.indices.contains(index) else { return nil }
    let range = frames[index].range
    return data.subdata(in: (data.startIndex + range.lowerBound)..<(data.startIndex + range.upperBound))
  }
}

extension PlexServerClient {
  /// The seek previews Plex made for a file; nil when the server has none
  /// (thumbnail generation off, or not done yet).
  public func seekThumbnails(partID: Int) async throws -> SeekThumbnails? {
    do {
      let data = try await send("/library/parts/\(partID)/indexes/sd")
      return SeekThumbnails(bif: data)
    } catch PlexError.http(404) {
      return nil
    }
  }
}
