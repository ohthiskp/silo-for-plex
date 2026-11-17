import AMSMB2
import AstraKit
import Foundation

/// SMB shares through AMSMB2 (libsmb2): Windows, macOS and NAS file sharing.
/// One connection per share, opened on first use and opened again if it drops.
final class SMBShareProvider: FileShareProvider, @unchecked Sendable {
  let host: String
  let credential: URLCredential?
  private let lock = NSLock()
  private var shares: [String: SMBShare] = [:]

  /// `host` is "nas.local", "192.168.1.20" or "smb://nas.local"; an empty
  /// username signs in as a guest.
  init(host: String, username: String, password: String) {
    var text = host.trimmingCharacters(in: .whitespacesAndNewlines)
    for prefix in ["smb://", "SMB://", "\\\\"] where text.hasPrefix(prefix) { text.removeFirst(prefix.count) }
    while text.hasSuffix("/") || text.hasSuffix("\\") { text.removeLast() }
    self.host = text
    credential = username.isEmpty ? nil : URLCredential(user: username, password: password, persistence: .forSession)
  }

  var url: URL? { URL(string: "smb://\(host)") }

  func manager() throws -> SMB2Manager {
    guard let url, let manager = SMB2Manager(url: url, credential: credential) else {
      throw SourceError.badAddress
    }
    manager.timeout = 15
    return manager
  }

  func shareNames() async throws -> [String] {
    let manager = try manager()
    do {
      return try await manager.listShares().map(\.name).filter { !$0.hasSuffix("$") }.sorted {
        $0.localizedStandardCompare($1) == .orderedAscending
      }
    } catch {
      throw SMBShare.describe(error)
    }
  }

  func share(_ name: String) async throws -> any FileShare {
    if let share = lock.withLock({ shares[name] }) { return share }
    let share = SMBShare(provider: self, name: name)
    try await share.connect()
    lock.withLock { shares[name] = share }
    return share
  }

  func disconnectAll() {
    let all = lock.withLock { () -> [SMBShare] in
      defer { shares = [:] }
      return Array(shares.values)
    }
    for share in all { Task { await share.disconnect() } }
  }
}

/// One connected share.
final class SMBShare: FileShare, @unchecked Sendable {
  let provider: SMBShareProvider
  let name: String
  private let lock = NSLock()
  private var manager: SMB2Manager?

  init(provider: SMBShareProvider, name: String) {
    self.provider = provider
    self.name = name
  }

  func connect() async throws {
    let manager = try provider.manager()
    do {
      try await manager.connectShare(name: name)
    } catch {
      throw Self.describe(error)
    }
    lock.withLock { self.manager = manager }
  }

  func disconnect() async {
    let manager = lock.withLock { () -> SMB2Manager? in
      defer { self.manager = nil }
      return self.manager
    }
    try? await manager?.disconnectShare()
  }

  /// Runs `body` on the connection; if it fails because the connection
  /// dropped (sleep, Wi-Fi change), connects once more and tries again.
  private func run<T>(_ body: (SMB2Manager) async throws -> T) async throws -> T {
    if let manager = lock.withLock({ manager }) {
      do {
        return try await body(manager)
      } catch {
        if Self.isMissing(error) { throw SourceError.notFound }
      }
    }
    try await connect()
    guard let manager = lock.withLock({ manager }) else { throw SourceError.unreachable }
    do {
      return try await body(manager)
    } catch {
      throw Self.describe(error)
    }
  }

  func list(_ path: String) async throws -> [ShareEntry] {
    let folder = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    let items = try await run { try await $0.contentsOfDirectory(atPath: folder.isEmpty ? "/" : folder) }
    return items.compactMap { attributes in
      guard let name = attributes.name, name != ".", name != ".." else { return nil }
      return ShareEntry(
        name: name, path: folder.isEmpty ? name : folder + "/" + name, isDirectory: attributes.isDirectory,
        size: attributes.fileSize ?? 0, modified: attributes.contentModificationDate)
    }
  }

  func size(of path: String) async throws -> Int64 {
    let attributes = try await run { try await $0.attributesOfItem(atPath: path) }
    return (attributes[.fileSizeKey] as? NSNumber)?.int64Value ?? (attributes[.fileSizeKey] as? Int64) ?? 0
  }

  func read(_ path: String, offset: Int64, length: Int) async throws -> Data {
    guard length > 0 else { return Data() }
    let start = UInt64(max(0, offset))
    return try await run { try await $0.contents(atPath: path, range: start..<(start + UInt64(length))) }
  }

  static func isMissing(_ error: Error) -> Bool {
    let ns = error as NSError
    return ns.domain == NSPOSIXErrorDomain && ns.code == Int(ENOENT)
  }

  /// libsmb2's errors in words for Settings.
  static func describe(_ error: Error) -> SourceError {
    if let error = error as? SourceError { return error }
    let ns = error as NSError
    if ns.domain == NSPOSIXErrorDomain {
      switch Int32(ns.code) {
      case EACCES, EPERM: return .wrongLogin
      case ENOENT: return .share("That share or folder wasn't found.")
      case ETIMEDOUT, ECONNREFUSED, EHOSTUNREACH, ENETUNREACH, EHOSTDOWN: return .unreachable
      default: break
      }
    }
    let text = ns.localizedDescription.lowercased()
    if text.contains("logon") || text.contains("access denied") || text.contains("password") { return .wrongLogin }
    return .share("The share answered with an error: \(ns.localizedDescription)")
  }
}
