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

/// An external id from `includeGuids=1`, such as `tmdb://603` or `imdb://tt0133093`.
public struct PlexGuid: Codable, Sendable, Hashable {
  public var id: String
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
  /// The stream's position in the file (FFmpeg's index; mpv's `ff-index`).
  /// Nil for a sidecar subtitle, which has a `key` instead.
  public var index: Int?

  enum CodingKeys: String, CodingKey {
    case id, streamType, codec, displayTitle, extendedDisplayTitle, language, languageCode, selected, `default`,
      forced, key, DOVIPresent, colorTrc, index
  }

  public init(
    id: Int, streamType: Int, codec: String? = nil, displayTitle: String? = nil, language: String? = nil,
    languageCode: String? = nil, selected: Bool? = nil, forced: Bool? = nil, key: String? = nil, index: Int? = nil
  ) {
    self.id = id
    self.streamType = streamType
    self.codec = codec
    self.displayTitle = displayTitle
    self.language = language
    self.languageCode = languageCode
    self.selected = selected
    self.forced = forced
    self.key = key
    self.index = index
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
    index = try c.decodeLenientInt(.index)
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

  public init(
    id: Int, key: String? = nil, duration: Int? = nil, file: String? = nil, size: Int64? = nil,
    container: String? = nil, streams: [PlexStream] = []
  ) {
    self.id = id
    self.key = key
    self.duration = duration
    self.file = file
    self.size = size
    self.container = container
    self.streams = streams
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

/// The video's dynamic range as the file is encoded (KP, 2026-11-07: "can it
/// show Dolby Vision and HDR"). A label for the file, read from Plex's video
/// stream: Dolby Vision when Plex sees a DV layer, HDR10 for PQ, HLG.
public enum DynamicRange: String, Sendable, Hashable {
  case dolbyVision = "Dolby Vision"
  case hdr10Plus = "HDR10+"
  case hdr10 = "HDR10"
  case hlg = "HLG"

  /// The short badge: "DV", "HDR", "HLG".
  public var badge: String {
    switch self {
    case .dolbyVision: "DV"
    case .hdr10Plus: "HDR10+"
    case .hdr10: "HDR"
    case .hlg: "HLG"
    }
  }

  public init?(stream: PlexStream) {
    let names = [stream.displayTitle, stream.extendedDisplayTitle].compactMap { $0?.lowercased() }
    if stream.DOVIPresent == true || names.contains(where: { $0.contains("dovi") || $0.contains("dolby vision") }) {
      self = .dolbyVision
    } else if names.contains(where: { $0.contains("hdr10+") }) {
      self = .hdr10Plus
    } else {
      switch stream.colorTrc?.lowercased() {
      case "smpte2084": self = .hdr10
      case "arib-std-b67": self = .hlg
      default: return nil
      }
    }
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

  public init(
    id: Int, duration: Int? = nil, bitrate: Int? = nil, width: Int? = nil, height: Int? = nil,
    container: String? = nil, parts: [PlexPart] = []
  ) {
    self.id = id
    self.duration = duration
    self.bitrate = bitrate
    self.width = width
    self.height = height
    self.container = container
    self.parts = parts
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
  public var parentGuid: String?
  public var grandparentGuid: String?
  /// External ids (TMDB, IMDb, TVDB) when the request asked for `includeGuids`.
  public var guids: [PlexGuid]
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
    case ratingKey, key, guid, parentGuid, grandparentGuid, type, title, titleSort, tagline, summary, year, originallyAvailableAt, contentRating,
      studio, audienceRating, rating, duration, viewOffset, viewCount, lastViewedAt, index, parentIndex, leafCount,
      viewedLeafCount, childCount, thumb, art, parentTitle, parentThumb, parentRatingKey, grandparentTitle,
      grandparentThumb, grandparentArt, grandparentRatingKey, librarySectionID
    case genres = "Genre"
    case directors = "Director"
    case roles = "Role"
    case images = "Image"
    case media = "Media"
    case guids = "Guid"
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
    guids = []
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
    parentGuid = try c.decodeIfPresent(String.self, forKey: .parentGuid)
    grandparentGuid = try c.decodeIfPresent(String.self, forKey: .grandparentGuid)
    guids = (try? c.decodeIfPresent([PlexGuid].self, forKey: .guids)) ?? []
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
  /// The badge for the version this device would play at `quality`: "4K UHD" or "HD".
  public func resolutionBadge(for quality: PlaybackQuality = .auto) -> String? {
    PlaybackResolver.preferredMedia(media, quality: quality).flatMap { VideoTier.badge(for: $0.tier) }
  }

  /// Dolby Vision / HDR10 / HLG of the version this device would play, when
  /// Plex sent its streams (full details do; lists don't). Nil for SDR.
  public func dynamicRange(for quality: PlaybackQuality = .auto) -> DynamicRange? {
    PlaybackResolver.preferredMedia(media, quality: quality)?.dynamicRange
  }

  /// Whether the version this device would play has a Dolby Atmos track.
  public func hasAtmos(for quality: PlaybackQuality = .auto) -> Bool {
    PlaybackResolver.preferredMedia(media, quality: quality)?.hasAtmos ?? false
  }

  /// Plex's age rating as shown on the rating badge: "PG-13", "R", "TV-MA".
  /// Plex can prefix a country ("gb/15"), which is dropped; "Not Rated" and
  /// empty values give nil.
  public var officialRating: String? {
    guard var rating = contentRating?.trimmingCharacters(in: .whitespaces), !rating.isEmpty else { return nil }
    if let slash = rating.firstIndex(of: "/") { rating = String(rating[rating.index(after: slash)...]) }
    let unrated: Set<String> = ["not rated", "unrated", "nr", "none"]
    return rating.isEmpty || unrated.contains(rating.lowercased()) ? nil : rating
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

// MARK: - Identity across rows

extension PlexMetadata {
  /// Keys that identify the same movie or show wherever it appears, used to
  /// keep a title from showing up in two Home rows. The TMDB id comes first;
  /// Plex's own guid and the library rating key cover items without one.
  /// Episodes and seasons map to their show, so a show in Continue Watching
  /// is not repeated in another row.
  public var dedupKeys: [String] {
    switch type {
    case .movie:
      var keys = guids.compactMap { $0.id.hasPrefix("tmdb://") ? "movie:" + $0.id : nil }
      if let guid { keys.append("movie:" + guid) }
      keys.append("movie:rk:" + ratingKey)
      return keys
    case .show, .season, .episode:
      var keys: [String] = []
      let showGuid: String?
      let showKey: String?
      switch type {
      case .episode: (showGuid, showKey) = (grandparentGuid, grandparentRatingKey)
      case .season: (showGuid, showKey) = (parentGuid, parentRatingKey)
      default:
        (showGuid, showKey) = (guid, ratingKey)
        keys += guids.compactMap { $0.id.hasPrefix("tmdb://") ? "show:" + $0.id : nil }
      }
      if let showGuid { keys.append("show:" + showGuid) }
      if let showKey { keys.append("show:rk:" + showKey) }
      if keys.isEmpty { keys.append("item:rk:" + ratingKey) }
      return keys
    default:
      return ["item:rk:" + ratingKey]
    }
  }
}

/// Removes titles already seen, keeping order. `seen` carries over between rows.
public struct HomeDeduplicator: Sendable {
  public private(set) var seen = Set<String>()

  public init() {}

  /// Whether `item` is new; if it is, its keys are recorded.
  public mutating func admit(_ item: PlexMetadata) -> Bool {
    let keys = item.dedupKeys
    guard seen.isDisjoint(with: keys) else { return false }
    seen.formUnion(keys)
    return true
  }

  public mutating func filter(_ items: [PlexMetadata]) -> [PlexMetadata] {
    items.filter { admit($0) }
  }
}

extension PlexMedia {
  /// The dynamic range of this version's video stream, nil for SDR or unknown.
  public var dynamicRange: DynamicRange? {
    parts.lazy.flatMap(\.streams).first { $0.streamType == 1 }.flatMap(DynamicRange.init(stream:))
  }

  /// Whether any audio track is Dolby Atmos (Plex names it in the track's title).
  public var hasAtmos: Bool {
    parts.flatMap(\.streams).contains { stream in
      stream.streamType == 2
        && [stream.displayTitle, stream.extendedDisplayTitle].contains { $0?.localizedCaseInsensitiveContains("atmos") == true }
    }
  }
}
