import Foundation

/// The kind of a Plex library item. Unknown server types decode as `.other`
/// so a new Plex type never breaks a whole hub.
public enum PlexItemType: String, Codable, Sendable, Hashable {
  case movie, show, season, episode, collection, clip, other

  public init(from decoder: Decoder) throws {
    let raw = try decoder.singleValueContainer().decode(String.self)
    self = PlexItemType(rawValue: raw) ?? .other
  }
}

public struct PlexTag: Codable, Sendable, Hashable {
  public var tag: String
  public var role: String?
  public var thumb: String?

  public init(tag: String, role: String? = nil, thumb: String? = nil) {
    self.tag = tag
    self.role = role
    self.thumb = thumb
  }
}

public struct PlexImage: Codable, Sendable, Hashable {
  public var type: String
  public var url: String
}

public struct PlexStream: Codable, Sendable, Hashable, Identifiable {
  /// 1 video, 2 audio, 3 subtitle.
  public var id: Int
  public var streamType: Int
  public var codec: String?
  public var displayTitle: String?
  public var extendedDisplayTitle: String?
  public var language: String?
  public var languageCode: String?
  public var selected: Bool?
  public var `default`: Bool?
  public var forced: Bool?
  public var key: String?
  public var DOVIPresent: Bool?
  public var colorTrc: String?

  enum CodingKeys: String, CodingKey {
    case id, streamType, codec, displayTitle, extendedDisplayTitle, language, languageCode, selected, `default`,
      forced, key, DOVIPresent, colorTrc
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decodeLenientInt(.id) ?? 0
    streamType = try c.decodeLenientInt(.streamType) ?? 0
    codec = try c.decodeIfPresent(String.self, forKey: .codec)
    displayTitle = try c.decodeIfPresent(String.self, forKey: .displayTitle)
    extendedDisplayTitle = try c.decodeIfPresent(String.self, forKey: .extendedDisplayTitle)
    language = try c.decodeIfPresent(String.self, forKey: .language)
    languageCode = try c.decodeIfPresent(String.self, forKey: .languageCode)
    selected = try c.decodeLenientBool(.selected)
    `default` = try c.decodeLenientBool(.default)
    forced = try c.decodeLenientBool(.forced)
    key = try c.decodeIfPresent(String.self, forKey: .key)
    DOVIPresent = try c.decodeLenientBool(.DOVIPresent)
    colorTrc = try c.decodeIfPresent(String.self, forKey: .colorTrc)
  }
}

public struct PlexPart: Codable, Sendable, Hashable, Identifiable {
  public var id: Int
  public var key: String?
  public var duration: Int?
  public var file: String?
  public var size: Int64?
  public var container: String?
  public var streams: [PlexStream]

  enum CodingKeys: String, CodingKey {
    case id, key, duration, file, size, container
    case streams = "Stream"
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decodeLenientInt(.id) ?? 0
    key = try c.decodeIfPresent(String.self, forKey: .key)
    duration = try c.decodeLenientInt(.duration)
    file = try c.decodeIfPresent(String.self, forKey: .file)
    size = try c.decodeLenientInt(.size).map(Int64.init)
    container = try c.decodeIfPresent(String.self, forKey: .container)
    streams = try c.decodeIfPresent([PlexStream].self, forKey: .streams) ?? []
  }
}

public struct PlexMedia: Codable, Sendable, Hashable, Identifiable {
  public var id: Int
  public var duration: Int?
  public var bitrate: Int?
  public var width: Int?
  public var height: Int?
  public var videoResolution: String?
  public var videoCodec: String?
  public var videoProfile: String?
  public var audioCodec: String?
  public var audioChannels: Int?
  public var container: String?
  public var parts: [PlexPart]

  enum CodingKeys: String, CodingKey {
    case id, duration, bitrate, width, height, videoResolution, videoCodec, videoProfile, audioCodec, audioChannels,
      container
    case parts = "Part"
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decodeLenientInt(.id) ?? 0
    duration = try c.decodeLenientInt(.duration)
    bitrate = try c.decodeLenientInt(.bitrate)
    width = try c.decodeLenientInt(.width)
    height = try c.decodeLenientInt(.height)
    videoResolution = try c.decodeLenientString(.videoResolution)
    videoCodec = try c.decodeIfPresent(String.self, forKey: .videoCodec)
    videoProfile = try c.decodeIfPresent(String.self, forKey: .videoProfile)
    audioCodec = try c.decodeIfPresent(String.self, forKey: .audioCodec)
    audioChannels = try c.decodeLenientInt(.audioChannels)
    container = try c.decodeIfPresent(String.self, forKey: .container)
    parts = try c.decodeIfPresent([PlexPart].self, forKey: .parts) ?? []
  }
}

/// One Plex library item: a movie, show, season, episode or collection.
public struct PlexMetadata: Codable, Sendable, Hashable, Identifiable {
  public var ratingKey: String
  public var key: String?
  public var guid: String?
  public var type: PlexItemType
  public var title: String
  public var titleSort: String?
  public var tagline: String?
  public var summary: String?
  public var year: Int?
  public var originallyAvailableAt: String?
  public var contentRating: String?
  public var studio: String?
  public var audienceRating: Double?
  public var rating: Double?
  public var duration: Int?
  public var viewOffset: Int?
  public var viewCount: Int?
  public var lastViewedAt: Int?
  public var index: Int?
  public var parentIndex: Int?
  public var leafCount: Int?
  public var viewedLeafCount: Int?
  public var childCount: Int?
  public var thumb: String?
  public var art: String?
  public var parentTitle: String?
  public var parentThumb: String?
  public var parentRatingKey: String?
  public var grandparentTitle: String?
  public var grandparentThumb: String?
  public var grandparentArt: String?
  public var grandparentRatingKey: String?
  public var librarySectionID: Int?
  public var genres: [PlexTag]
  public var directors: [PlexTag]
  public var roles: [PlexTag]
  public var images: [PlexImage]
  public var media: [PlexMedia]

  public var id: String { ratingKey }

  enum CodingKeys: String, CodingKey {
    case ratingKey, key, guid, type, title, titleSort, tagline, summary, year, originallyAvailableAt, contentRating,
      studio, audienceRating, rating, duration, viewOffset, viewCount, lastViewedAt, index, parentIndex, leafCount,
      viewedLeafCount, childCount, thumb, art, parentTitle, parentThumb, parentRatingKey, grandparentTitle,
      grandparentThumb, grandparentArt, grandparentRatingKey, librarySectionID
    case genres = "Genre"
    case directors = "Director"
    case roles = "Role"
    case images = "Image"
    case media = "Media"
  }

  public init(
    ratingKey: String, type: PlexItemType, title: String, summary: String? = nil, year: Int? = nil,
    duration: Int? = nil, viewOffset: Int? = nil, thumb: String? = nil, art: String? = nil
  ) {
    self.ratingKey = ratingKey
    self.type = type
    self.title = title
    self.summary = summary
    self.year = year
    self.duration = duration
    self.viewOffset = viewOffset
    self.thumb = thumb
    self.art = art
    genres = []
    directors = []
    roles = []
    images = []
    media = []
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    ratingKey = try c.decodeLenientString(.ratingKey) ?? ""
    key = try c.decodeIfPresent(String.self, forKey: .key)
    guid = try c.decodeIfPresent(String.self, forKey: .guid)
    type = try c.decodeIfPresent(PlexItemType.self, forKey: .type) ?? .other
    title = try c.decodeLenientString(.title) ?? ""
    titleSort = try c.decodeIfPresent(String.self, forKey: .titleSort)
    tagline = try c.decodeIfPresent(String.self, forKey: .tagline)
    summary = try c.decodeIfPresent(String.self, forKey: .summary)
    year = try c.decodeLenientInt(.year)
    originallyAvailableAt = try c.decodeIfPresent(String.self, forKey: .originallyAvailableAt)
    contentRating = try c.decodeIfPresent(String.self, forKey: .contentRating)
    studio = try c.decodeIfPresent(String.self, forKey: .studio)
    audienceRating = try c.decodeLenientDouble(.audienceRating)
    rating = try c.decodeLenientDouble(.rating)
    duration = try c.decodeLenientInt(.duration)
    viewOffset = try c.decodeLenientInt(.viewOffset)
    viewCount = try c.decodeLenientInt(.viewCount)
    lastViewedAt = try c.decodeLenientInt(.lastViewedAt)
    index = try c.decodeLenientInt(.index)
    parentIndex = try c.decodeLenientInt(.parentIndex)
    leafCount = try c.decodeLenientInt(.leafCount)
    viewedLeafCount = try c.decodeLenientInt(.viewedLeafCount)
    childCount = try c.decodeLenientInt(.childCount)
    thumb = try c.decodeIfPresent(String.self, forKey: .thumb)
    art = try c.decodeIfPresent(String.self, forKey: .art)
    parentTitle = try c.decodeIfPresent(String.self, forKey: .parentTitle)
    parentThumb = try c.decodeIfPresent(String.self, forKey: .parentThumb)
    parentRatingKey = try c.decodeLenientString(.parentRatingKey)
    grandparentTitle = try c.decodeIfPresent(String.self, forKey: .grandparentTitle)
    grandparentThumb = try c.decodeIfPresent(String.self, forKey: .grandparentThumb)
    grandparentArt = try c.decodeIfPresent(String.self, forKey: .grandparentArt)
    grandparentRatingKey = try c.decodeLenientString(.grandparentRatingKey)
    librarySectionID = try c.decodeLenientInt(.librarySectionID)
    genres = try c.decodeIfPresent([PlexTag].self, forKey: .genres) ?? []
    directors = try c.decodeIfPresent([PlexTag].self, forKey: .directors) ?? []
    roles = try c.decodeIfPresent([PlexTag].self, forKey: .roles) ?? []
    images = try c.decodeIfPresent([PlexImage].self, forKey: .images) ?? []
    media = try c.decodeIfPresent([PlexMedia].self, forKey: .media) ?? []
  }
}

// MARK: - Display helpers

extension PlexMetadata {
  /// The clear logo Plex advertises for the title, when it has one.
  public var clearLogo: String? { images.first { $0.type == "clearLogo" }?.url }

  /// The backdrop: an episode falls back to its show's art.
  public var backdrop: String? { art ?? grandparentArt }

  /// The poster: an episode shows its show's poster in poster rows.
  public var poster: String? {
    type == .episode ? (grandparentThumb ?? parentThumb ?? thumb) : thumb
  }

  /// The headline title: an episode is shown under its show's name.
  public var displayTitle: String {
    type == .episode ? (grandparentTitle ?? title) : title
  }

  /// "S2 · E5" for an episode, nil otherwise.
  public var episodeLabel: String? {
    guard type == .episode, let index else { return nil }
    if let parentIndex { return "S\(parentIndex) · E\(index)" }
    return "E\(index)"
  }

  /// Fraction watched, 0...1, from the resume offset; nil when not started.
  public var progress: Double? {
    guard let viewOffset, let duration, duration > 0, viewOffset > 0 else { return nil }
    return min(1, Double(viewOffset) / Double(duration))
  }

  public var isWatched: Bool {
    if type == .show || type == .season, let leafCount, let viewedLeafCount {
      return leafCount > 0 && viewedLeafCount >= leafCount
    }
    return (viewCount ?? 0) > 0 && viewOffset == nil
  }

  /// The resolution badge for the first media version ("4K", "HD"), nil for SD or unknown.
  public var resolutionBadge: String? {
    guard let media = media.first else { return nil }
    let res = media.videoResolution?.lowercased()
    if res == "4k" || (media.width ?? 0) >= 3200 { return "4K" }
    if res == "1080" || res == "720" || (media.width ?? 0) >= 1280 { return "HD" }
    return nil
  }

  /// "2h 14m" or "48m".
  public var durationLabel: String? {
    guard let duration, duration > 0 else { return nil }
    let minutes = duration / 60_000
    let hours = minutes / 60
    let rest = minutes % 60
    if hours > 0 { return rest > 0 ? "\(hours)h \(rest)m" : "\(hours)h" }
    return "\(max(1, minutes))m"
  }
}
