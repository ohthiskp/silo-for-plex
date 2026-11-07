import Foundation

/// A home or related hub: a titled row of items.
public struct PlexHub: Codable, Sendable, Hashable, Identifiable {
  public var hubIdentifier: String
  public var title: String
  public var type: String?
  public var key: String?
  public var size: Int?
  public var more: Bool?
  public var items: [PlexMetadata]

  public var id: String { hubIdentifier }

  enum CodingKeys: String, CodingKey {
    case hubIdentifier, title, type, key, size, more
    case items = "Metadata"
  }

  public init(hubIdentifier: String, title: String, items: [PlexMetadata]) {
    self.hubIdentifier = hubIdentifier
    self.title = title
    self.items = items
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    hubIdentifier = try c.decodeLenientString(.hubIdentifier) ?? UUID().uuidString
    title = try c.decodeLenientString(.title) ?? ""
    type = try c.decodeIfPresent(String.self, forKey: .type)
    key = try c.decodeIfPresent(String.self, forKey: .key)
    size = try c.decodeLenientInt(.size)
    more = try c.decodeLenientBool(.more)
    items = try c.decodeIfPresent([PlexMetadata].self, forKey: .items) ?? []
  }

  /// Plex's Continue Watching and On Deck hubs.
  public var isContinueWatching: Bool {
    hubIdentifier.hasPrefix("home.continue") || hubIdentifier.hasPrefix("home.ondeck")
      || hubIdentifier == "continueWatching"
  }
}

/// A library section (Movies, TV Shows…).
public struct PlexLibrarySection: Codable, Sendable, Hashable, Identifiable {
  public var key: String
  public var title: String
  public var type: String

  public var id: String { key }

  enum CodingKeys: String, CodingKey { case key, title, type }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    key = try c.decodeLenientString(.key) ?? ""
    title = try c.decodeLenientString(.title) ?? ""
    type = try c.decodeIfPresent(String.self, forKey: .type) ?? ""
  }
}

/// The `MediaContainer` envelope every Plex Media Server JSON response uses.
struct MediaContainerEnvelope<Body: Decodable>: Decodable {
  var MediaContainer: Body
}

struct MetadataBody: Decodable {
  var Metadata: [PlexMetadata]?
}

struct HubBody: Decodable {
  var Hub: [PlexHub]?
}

struct DirectoryBody: Decodable {
  var Directory: [PlexLibrarySection]?
}
