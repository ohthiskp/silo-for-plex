import Foundation

#if canImport(Security)
  import Security
#endif

/// Where the Plex account token lives between launches.
public protocol TokenStore: Sendable {
  func load() -> String?
  func save(_ token: String)
  func clear()
}

#if canImport(Security)
  /// The token in the login Keychain, readable only by Astra.
  public struct KeychainTokenStore: TokenStore {
    let service: String
    let account: String

    public init(service: String = "app.astra.plex", account: String = "account-token") {
      self.service = service
      self.account = account
    }

    private var query: [String: Any] {
      [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account,
      ]
    }

    public func load() -> String? {
      var query = query
      query[kSecReturnData as String] = true
      query[kSecMatchLimit as String] = kSecMatchLimitOne
      var result: AnyObject?
      guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
        let data = result as? Data
      else { return nil }
      return String(data: data, encoding: .utf8)
    }

    public func save(_ token: String) {
      let data = Data(token.utf8)
      let update: [String: Any] = [kSecValueData as String: data]
      let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
      if status == errSecItemNotFound {
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
      }
    }

    public func clear() {
      SecItemDelete(query as CFDictionary)
    }
  }
#endif

/// A token store for tests and previews.
public final class MemoryTokenStore: TokenStore, @unchecked Sendable {
  private let lock = NSLock()
  private var token: String?

  public init(_ token: String? = nil) { self.token = token }

  public func load() -> String? { lock.withLock { token } }
  public func save(_ token: String) { lock.withLock { self.token = token } }
  public func clear() { lock.withLock { token = nil } }
}
