import Foundation

/// One entry of a share folder.
public struct ShareEntry: Sendable, Hashable {
  public var name: String
  /// The path inside the share, "/"-separated, no leading slash ("Movies/Dune (2021)/Dune.mkv").
  public var path: String
  public var isDirectory: Bool
  public var size: Int64
  public var modified: Date?

  public init(name: String, path: String, isDirectory: Bool, size: Int64 = 0, modified: Date? = nil) {
    self.name = name
    self.path = path
    self.isDirectory = isDirectory
    self.size = size
    self.modified = modified
  }
}

/// A network share Astra reads files from (SMB today; NFS, WebDAV and FTP
/// later). The app supplies the real one; tests use a folder in memory.
public protocol FileShare: Sendable {
  /// The entries of a folder inside the share ("" is the top).
  func list(_ path: String) async throws -> [ShareEntry]
  /// The size of a file, in bytes.
  func size(of path: String) async throws -> Int64
  /// Up to `length` bytes from `offset`; fewer only at the end of the file.
  func read(_ path: String, offset: Int64, length: Int) async throws -> Data
}

/// Opens shares by name for one source (one server, one sign-in).
public protocol FileShareProvider: Sendable {
  /// The shares the server offers, for the Add Folder picker.
  func shareNames() async throws -> [String]
  func share(_ name: String) async throws -> any FileShare
}

public enum MediaFiles {
  /// Video files mpv plays. Disc images are left out: mpv can't open them
  /// over a stream.
  public static let videoExtensions: Set<String> = [
    "mkv", "mp4", "m4v", "mov", "avi", "wmv", "ts", "m2ts", "mts", "webm", "mpg", "mpeg", "vob", "flv", "ogv",
    "divx", "rmvb", "3gp", "asf",
  ]

  /// Sidecar subtitle files next to a video.
  public static let subtitleExtensions: Set<String> = ["srt", "ass", "ssa", "vtt", "sub", "sup"]

  /// Folders that hold extras or system files, never titles.
  static let skippedFolders: Set<String> = [
    "extras", "featurettes", "behind the scenes", "deleted scenes", "interviews", "trailers", "samples", "sample",
    "shorts", "scenes", "@eadir", "#recycle", "$recycle.bin", "system volume information", "#snapshot", ".snapshot",
    "lost+found",
  ]

  public static func isVideo(_ name: String) -> Bool {
    guard !name.hasPrefix("."), let dot = name.lastIndex(of: ".") else { return false }
    return videoExtensions.contains(name[name.index(after: dot)...].lowercased())
  }

  public static func skips(folder name: String) -> Bool {
    name.hasPrefix(".") || skippedFolders.contains(name.lowercased())
  }

  /// "Dune.2021.mkv" → "mkv".
  public static func fileExtension(_ name: String) -> String? {
    guard let dot = name.lastIndex(of: ".") else { return nil }
    return name[name.index(after: dot)...].lowercased()
  }

  /// Every video file under `root`, walking at most `depth` folders down,
  /// skipping extras, samples and system folders.
  public static func videos(in share: any FileShare, root: String, depth: Int = 8) async throws -> [ShareEntry] {
    var found: [ShareEntry] = []
    var queue: [(String, Int)] = [(root, 0)]
    while !queue.isEmpty {
      try Task.checkCancellation()
      let (folder, level) = queue.removeFirst()
      let entries: [ShareEntry]
      do {
        entries = try await share.list(folder)
      } catch {
        // The top folder must open; a subfolder that can't is skipped.
        if level == 0 { throw error }
        continue
      }
      for entry in entries {
        if entry.isDirectory {
          if level < depth, !skips(folder: entry.name) { queue.append((entry.path, level + 1)) }
        } else if isVideo(entry.name), !isSample(entry) {
          found.append(entry)
        }
      }
    }
    return found.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
  }

  /// "movie-sample.mkv" under 300 MB.
  static func isSample(_ entry: ShareEntry) -> Bool {
    let name = entry.name.lowercased()
    return (name.contains("sample") || name.hasPrefix("trailer")) && entry.size > 0 && entry.size < 300_000_000
  }
}
