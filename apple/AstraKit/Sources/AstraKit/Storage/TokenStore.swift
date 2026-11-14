import Foundation

#if canImport(Security)
  import Security
#endif
#if canImport(os)
  import os
#endif

/// Where the Plex account token lives between launches.
public protocol TokenStore: Sendable {
  func load() -> String?
  /// Saves the token; false when it couldn't be stored (the reason is logged).
  @discardableResult func save(_ token: String) -> Bool
  func clear()
}

#if canImport(Security)
  /// The token in the Keychain, readable only by Astra.
  ///
  /// On Mac (2026-11-08 audit) the old login-Keychain item was tied to the
  /// exact build that wrote it. Astra's Mac builds are signed ad hoc, so every
  /// Sparkle update is a "different app" to that item: macOS asked for the
  /// password, or Astra opened signed out. Now the Mac uses the data-protection
  /// Keychain (as iPhone always has), which needs no per-build approval. Builds
  /// that macOS doesn't give a data-protection Keychain (ad hoc, no team ID)
  /// keep the token in a file only this user can read, in Application
  /// Support. A token in the old item moves over once, the first time it's read.
  public struct KeychainTokenStore: TokenStore {
    let service: String
    let account: String
    #if os(macOS)
      let fallback: FileTokenStore
    #endif

    public init(service: String = "app.astra.plex", account: String = "account-token") {
      self.service = service
      self.account = account
      #if os(macOS)
        fallback = FileTokenStore(
          url: FileTokenStore.defaultDirectory.appendingPathComponent("\(service).\(account).token"))
      #endif
    }

    private var baseQuery: [String: Any] {
      [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account,
      ]
    }

    /// The data-protection Keychain (iPhone's only one; on Mac, asked for by name).
    private var query: [String: Any] {
      var query = baseQuery
      #if os(macOS)
        query[kSecUseDataProtectionKeychain as String] = true
      #endif
      return query
    }

    public func load() -> String? {
      if let token = Self.read(query) { return token }
      #if os(macOS)
        if let token = fallback.load() { return token }
        // The old login-Keychain item: read it once (macOS may ask one last
        // time), move it to the new place, and delete it.
        guard let legacy = Self.read(baseQuery) else { return nil }
        if save(legacy) { SecItemDelete(baseQuery as CFDictionary) }
        return legacy
      #else
        return nil
      #endif
    }

    @discardableResult public func save(_ token: String) -> Bool {
      let data = Data(token.utf8)
      var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
      if status == errSecItemNotFound {
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        status = SecItemAdd(add as CFDictionary, nil)
      }
      if status == errSecSuccess {
        #if os(macOS)
          fallback.clear()
        #endif
        return true
      }
      if status != errSecMissingEntitlement { TokenStoreLog.failure("Keychain save", status: status) }
      #if os(macOS)
        // Usually errSecMissingEntitlement (an ad-hoc build has no data-protection
        // Keychain). Whatever the reason, keep the token rather than lose it.
        return fallback.save(token)
      #else
        return false
      #endif
    }

    public func clear() {
      SecItemDelete(query as CFDictionary)
      #if os(macOS)
        fallback.clear()
        SecItemDelete(baseQuery as CFDictionary)
      #endif
    }

    private static func read(_ base: [String: Any]) -> String? {
      var query = base
      query[kSecReturnData as String] = true
      query[kSecMatchLimit as String] = kSecMatchLimitOne
      var result: AnyObject?
      guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data
      else { return nil }
      return String(data: data, encoding: .utf8)
    }
  }
#endif

/// A token in a file only this user can read (0600, in a 0700 folder). Used on
/// Mac builds that have no data-protection Keychain.
public struct FileTokenStore: TokenStore {
  public let url: URL

  public init(url: URL) { self.url = url }

  public static var defaultDirectory: URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    return base.appendingPathComponent("Astra/Credentials", isDirectory: true)
  }

  public func load() -> String? {
    guard let data = try? Data(contentsOf: url), let token = String(data: data, encoding: .utf8),
      !token.isEmpty
    else { return nil }
    return token
  }

  @discardableResult public func save(_ token: String) -> Bool {
    let manager = FileManager.default
    let folder = url.deletingLastPathComponent()
    do {
      try manager.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
      try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
      // Written beside the file with 0600 first, then moved over it, so the
      // token is never readable by others, even for a moment.
      let temp = folder.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString)")
      guard manager.createFile(atPath: temp.path, contents: Data(token.utf8), attributes: [.posixPermissions: 0o600])
      else { throw CocoaError(.fileWriteUnknown) }
      // rename(2) replaces the old file in one step.
      guard rename(temp.path, url.path) == 0 else {
        try? manager.removeItem(at: temp)
        throw CocoaError(.fileWriteUnknown)
      }
      return true
    } catch {
      TokenStoreLog.failure("Token file save (\(error.localizedDescription))", status: nil)
      return false
    }
  }

  public func clear() {
    try? FileManager.default.removeItem(at: url)
  }
}

enum TokenStoreLog {
  static func failure(_ what: String, status: Int32?) {
    #if canImport(os)
      let logger = Logger(subsystem: "app.astra", category: "TokenStore")
      if let status {
        logger.error("\(what, privacy: .public) failed: OSStatus \(status, privacy: .public)")
      } else {
        logger.error("\(what, privacy: .public) failed")
      }
    #endif
  }
}

/// A token store for tests and previews.
public final class MemoryTokenStore: TokenStore, @unchecked Sendable {
  private let lock = NSLock()
  private var token: String?
  /// Tests: make `save` fail.
  public var failsSaving = false

  public init(_ token: String? = nil) { self.token = token }

  public func load() -> String? { lock.withLock { token } }
  @discardableResult public func save(_ token: String) -> Bool {
    lock.withLock {
      guard !failsSaving else { return false }
      self.token = token
      return true
    }
  }
  public func clear() { lock.withLock { token = nil } }
}
