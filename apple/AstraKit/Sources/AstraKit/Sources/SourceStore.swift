import Foundation

/// The sources from Settings → Sources, saved as `Sources/sources.json` in
/// Application Support. Passwords and tokens are not in the file; they are
/// in the Keychain under each source's `secretAccount`.
public struct SourceStore: Sendable {
  public let directory: URL
  var fileURL: URL { directory.appendingPathComponent("sources.json") }

  public init(directory: URL = SourceStore.defaultDirectory) {
    self.directory = directory
  }

  public static var defaultDirectory: URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    return base.appendingPathComponent("Astra/Sources", isDirectory: true)
  }

  struct File: Codable {
    var version = 1
    var sources: [SourceConfig]
  }

  public func load() -> [SourceConfig] {
    guard let data = try? Data(contentsOf: fileURL), let file = try? JSONDecoder().decode(File.self, from: data) else {
      return []
    }
    return file.sources
  }

  public func save(_ sources: [SourceConfig]) {
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try? encoder.encode(File(sources: sources)).write(to: fileURL, options: .atomic)
  }

  /// Removes what a deleted source left behind (its index and watched state).
  public func removeFiles(of id: String) {
    for name in ["\(id)-index.json", "\(id)-watched.json"] {
      try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
    }
  }
}
