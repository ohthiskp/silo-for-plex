import Foundation

/// What is holding memory, for the crash report's activity list (KP,
/// 2026-11-15: iOS stopped Astra at 2.7 GB on Home, twice, about nine seconds
/// after it came on screen). Read from SessionWatch's background check, so
/// everything here sits behind a lock.
enum MemoryClues {
  private static let lock = NSLock()
  nonisolated(unsafe) private static var storesAlive = 0
  nonisolated(unsafe) private static var imageMB = 0
  nonisolated(unsafe) private static var imagesDecoded = 0
  nonisolated(unsafe) private static var indexTitles = 0

  static func storeOpened() { change { storesAlive += 1 } }
  static func storeFreed() { change { storesAlive -= 1 } }
  static func decodedImage(bytes: Int) { change { imagesDecoded += 1; imageMB += bytes >> 20 } }
  static func index(titles: Int) { change { indexTitles = titles } }

  /// "images 34 decoded (132 MB), index 9812 titles, 1 server store"
  static var summary: String {
    lock.lock()
    defer { lock.unlock() }
    return "images \(imagesDecoded) decoded (\(imageMB) MB so far), index \(indexTitles) titles, "
      + "\(storesAlive) server store\(storesAlive == 1 ? "" : "s")"
  }

  private static func change(_ body: () -> Void) {
    lock.lock()
    body()
    lock.unlock()
  }
}
