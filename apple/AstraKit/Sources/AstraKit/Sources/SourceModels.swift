import Foundation

/// Every kind of source Astra can read, as Infuse does (KP, 2026-11-17:
/// "add support for all that infuse has"; media servers are Plex, Jellyfin
/// and Emby).
public enum SourceKind: String, Codable, Sendable, CaseIterable, Identifiable {
  /// The signed-in Plex account's server. Listed with the media servers; its
  /// sign-in is the app's own, so it's never saved as a `SourceConfig`.
  case plex
  case jellyfin, emby
  case smb, webdav
  case googleDrive, dropbox, oneDrive, box, pCloud, yandexDisk

  public var id: String { rawValue }

  public enum Category: String, Sendable, CaseIterable {
    /// Keeps its own metadata and watched state.
    case mediaServer
    /// Plain files on the local network, matched to TMDB by Astra.
    case networkShare
    /// Plain files in a cloud account, matched to TMDB by Astra.
    case cloud
  }

  public var category: Category {
    switch self {
    case .plex, .jellyfin, .emby: .mediaServer
    case .smb, .webdav: .networkShare
    case .googleDrive, .dropbox, .oneDrive, .box, .pCloud, .yandexDisk: .cloud
    }
  }

  /// The kinds in each category, in the order a list shows them.
  public static func kinds(in category: Category) -> [SourceKind] { allCases.filter { $0.category == category } }

  /// The name shown for the kind.
  public var title: String {
    switch self {
    case .plex: "Plex"
    case .jellyfin: "Jellyfin"
    case .emby: "Emby"
    case .smb: "Network Share (SMB)"
    case .webdav: "WebDAV"
    case .googleDrive: "Google Drive"
    case .dropbox: "Dropbox"
    case .oneDrive: "OneDrive"
    case .box: "Box"
    case .pCloud: "pCloud"
    case .yandexDisk: "Yandex Disk"
    }
  }

  /// A short line under the title in an Add Source list.
  public var blurb: String {
    switch self {
    case .plex: "Your Plex server's libraries, watched state and progress."
    case .jellyfin: "Your Jellyfin server's libraries, watched state and progress."
    case .emby: "Your Emby server's libraries, watched state and progress."
    case .smb: "Folders on a NAS, Mac or PC. Astra finds the titles and artwork."
    case .webdav: "Nextcloud, ownCloud or a NAS's WebDAV folders."
    case .googleDrive, .dropbox, .oneDrive, .box, .pCloud, .yandexDisk:
      "Movies and shows in your \(title). Astra finds the titles and artwork."
    }
  }

  /// Media servers keep their own metadata and watched state; shares and
  /// cloud drives are plain files that Astra matches to TMDB and tracks on the device.
  public var isMediaServer: Bool { category == .mediaServer }

  /// Folders of files: listed, scanned and served through the file server.
  public var isFileSource: Bool { !isMediaServer }

  /// Signs in through the service's web page (OAuth) rather than a password.
  public var usesWebSignIn: Bool { category == .cloud }
}

/// What a share folder holds, so its files are matched as movies or episodes.
public enum FolderContent: String, Codable, Sendable, CaseIterable, Identifiable {
  case movies, shows

  public var id: String { rawValue }
  public var title: String { self == .movies ? "Movies" : "TV Shows" }
  /// The Plex section type the folder appears as.
  public var sectionType: String { self == .movies ? "movie" : "show" }
}

/// One folder of a share that Astra lists as a library.
public struct SourceFolder: Codable, Sendable, Hashable, Identifiable {
  /// Stable for the folder's life, so its section key and saved index survive edits.
  public var id: String
  /// The share's name on the server ("Media"). Cloud drives: "" for the
  /// account's own drive, or a shared drive's id (`ShareRoot.id`).
  public var share: String
  /// The folder inside the share, "" for the share's top ("Movies/4K").
  public var path: String
  public var content: FolderContent
  /// The library's name in Astra ("Movies on NAS").
  public var title: String

  public init(id: String = SourceConfig.newID(), share: String, path: String, content: FolderContent, title: String) {
    self.id = id
    self.share = share
    self.path = path
    self.content = content
    self.title = title
  }
}

/// A library a media server lists, remembered so the source's libraries show
/// at launch before the server has answered.
public struct SourceLibrary: Codable, Sendable, Hashable, Identifiable {
  public var id: String
  public var title: String
  /// "movie" or "show".
  public var type: String

  public init(id: String, title: String, type: String) {
    self.id = id
    self.title = title
    self.type = type
  }
}

/// One source the person added in Settings → Sources. The password or access
/// token is not in here: it lives in the Keychain under `secretAccount`.
public struct SourceConfig: Codable, Sendable, Hashable, Identifiable {
  public var id: String
  public var kind: SourceKind
  /// "Living Room NAS", or the server's own name.
  public var name: String
  /// Jellyfin/Emby: "http://192.168.1.20:8096". SMB: the host ("nas.local" or
  /// "192.168.1.20"). WebDAV: "https://cloud.example.com/remote.php/dav/files/kp".
  /// Cloud: the account's email or name.
  public var address: String
  public var username: String
  /// Jellyfin/Emby: the signed-in user's id.
  public var userID: String?
  /// Jellyfin/Emby: the server's libraries as last seen.
  public var libraries: [SourceLibrary]
  /// Shares and cloud drives: the folders listed as libraries.
  public var folders: [SourceFolder]
  /// Off hides the source everywhere without forgetting it.
  public var enabled: Bool

  public init(
    id: String = SourceConfig.newID(), kind: SourceKind, name: String, address: String, username: String = "",
    userID: String? = nil, libraries: [SourceLibrary] = [], folders: [SourceFolder] = [], enabled: Bool = true
  ) {
    self.id = id
    self.kind = kind
    self.name = name
    self.address = address
    self.username = username
    self.userID = userID
    self.libraries = libraries
    self.folders = folders
    self.enabled = enabled
  }

  /// The Keychain account that holds this source's password or token.
  public var secretAccount: String { "source-\(id)" }

  /// Eight lowercase letters and digits: short, and never contains the key separator.
  public static func newID() -> String {
    let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")
    return String((0..<8).map { _ in alphabet.randomElement()! })
  }

  /// The libraries this source adds to Astra, as Plex sections with
  /// source keys ("src~<id>~<library>").
  public var sections: [PlexLibrarySection] {
    guard enabled else { return [] }
    switch kind {
    case .plex:
      return []
    case .jellyfin, .emby:
      return libraries.map { PlexLibrarySection(key: SourceKey.make(id, $0.id), title: $0.title, type: $0.type) }
    default:
      return folders.map { PlexLibrarySection(key: SourceKey.make(id, $0.id), title: $0.title, type: $0.content.sectionType) }
    }
  }
}

/// Keys for items, sections, images and files that come from a source rather
/// than from Plex: "src~<source id>~<the source's own id>". Plex keys are
/// numbers or paths, so they never start with "src~".
public enum SourceKey {
  public static let prefix = "src~"

  public static func make(_ sourceID: String, _ native: String) -> String {
    prefix + sourceID + "~" + native
  }

  /// The source id and the source's own key, or nil for a Plex key.
  public static func split(_ key: String) -> (source: String, native: String)? {
    guard key.hasPrefix(prefix) else { return nil }
    let rest = key.dropFirst(prefix.count)
    guard let tilde = rest.firstIndex(of: "~") else { return nil }
    let source = String(rest[..<tilde])
    guard !source.isEmpty else { return nil }
    return (source, String(rest[rest.index(after: tilde)...]))
  }

  public static func isSource(_ key: String?) -> Bool { key.map { split($0) != nil } ?? false }

  /// A short stable id for any text ("movie:dune:2021" → "9f2c41d07a3b"), safe in keys and URLs.
  public static func slug(_ text: String) -> String {
    String(UInt64(-(number(text) + 1)) & 0xFFFF_FFFF_FFFF, radix: 16)
  }

  /// A stable number for a source key, for the numeric ids Plex models use
  /// (`librarySectionID`, media and part ids). Negative, so it can never be
  /// taken for a Plex id (Plex's are positive): a negative part id has no
  /// Plex seek previews or saved stream choice. FNV-1a over the UTF-8 bytes.
  public static func number(_ key: String) -> Int {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in key.utf8 {
      hash ^= UInt64(byte)
      hash = hash &* 0x100_0000_01b3
    }
    // 52 bits: exact in a Double, so JSON round trips keep it.
    return -Int(hash & 0x000F_FFFF_FFFF_FFFF) - 1
  }
}

extension PlexLibrarySection {
  public init(key: String, title: String, type: String) {
    self.key = key
    self.title = title
    self.type = type
  }

  /// The section's number as items carry it in `librarySectionID`.
  public var numericID: Int? { Int(key) ?? (SourceKey.isSource(key) ? SourceKey.number(key) : nil) }

  /// The source this section comes from, nil for Plex.
  public var sourceID: String? { SourceKey.split(key)?.source }
}

extension PlexMetadata {
  /// The source this item comes from, nil for Plex.
  public var sourceID: String? { SourceKey.split(ratingKey)?.source }
}
