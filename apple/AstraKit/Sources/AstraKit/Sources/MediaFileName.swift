import Foundation

/// What a video file's name and folders say it is, the way Infuse reads a
/// share: "Dune Part Two (2024) 2160p.mkv" is a 2024 movie in 4K;
/// "Breaking Bad/Season 2/Breaking.Bad.S02E05.mkv" is an episode.
public struct MediaFileName: Sendable, Hashable, Codable {
  public enum Kind: String, Sendable, Codable { case movie, episode }

  public var kind: Kind
  /// The movie's or show's title, cleaned up ("Dune Part Two", "Breaking Bad").
  public var title: String
  public var year: Int?
  public var season: Int?
  public var episode: Int?
  /// The last episode of a double episode ("S01E01-E02" → 2).
  public var episodeEnd: Int?
  /// The picture height the name claims ("2160p", "4K" → 2160), nil when it doesn't say.
  public var height: Int?
  /// "Dolby Vision", "HDR10+", "HDR" when the name says so.
  public var dynamicRange: String?

  /// "movie:dune part two:2024" / "tv:breaking bad:" — files with the same
  /// key are the same title (two versions of a movie, episodes of a show).
  public var matchKey: String {
    let folded = title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en"))
      .lowercased()
    let base = folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == " " }
    let words = String(String.UnicodeScalarView(base)).split(separator: " ").joined(separator: " ")
    return (kind == .movie ? "movie:" : "tv:") + words + ":" + (year.map(String.init) ?? "")
  }

  /// Parses the path inside a library folder ("Breaking Bad/Season 2/x.mkv").
  /// The library's own folder is not part of it.
  public static func parse(_ relativePath: String, content: FolderContent) -> MediaFileName {
    let components = relativePath.split(separator: "/").map(String.init)
    let file = components.last ?? relativePath
    let stem = file.lastIndex(of: ".").map { String(file[..<$0]) } ?? file
    let folders = Array(components.dropLast())
    let height = Self.height(in: stem) ?? folders.reversed().lazy.compactMap(Self.height(in:)).first
    let range = Self.dynamicRange(in: stem)

    if let episode = Self.episodeNumbers(in: stem, folders: folders) ?? (content == .shows ? Self.looseEpisode(stem, folders: folders) : nil) {
      // The show: the first folder under the library (most reliable), else the name before "S01E02".
      var showTitle: String?
      var showYear: Int?
      if let top = folders.first, !Self.isSeasonFolder(top) {
        (showTitle, showYear) = Self.titleAndYear(top)
      }
      if showTitle?.isEmpty ?? true {
        (showTitle, showYear) = Self.titleAndYear(String(stem[..<episode.start]))
      }
      if showTitle?.isEmpty ?? true, folders.count >= 2 {
        (showTitle, showYear) = Self.titleAndYear(folders[folders.count - 2])
      }
      return MediaFileName(
        kind: .episode, title: showTitle?.isEmpty == false ? showTitle! : Self.clean(stem), year: showYear,
        season: episode.season, episode: episode.episode, episodeEnd: episode.end, height: height, dynamicRange: range)
    }

    // A movie: its own name, or its folder's when the file has a generic name
    // ("movie.mkv", "VTS_01_1") or no year and the folder has one.
    var (title, year) = Self.titleAndYear(stem)
    if let folder = folders.last {
      let (folderTitle, folderYear) = Self.titleAndYear(folder)
      if !folderTitle.isEmpty, (title.count < 3 || (year == nil && folderYear != nil)) {
        (title, year) = (folderTitle, folderYear)
      }
    }
    if title.isEmpty { title = Self.clean(stem) }
    return MediaFileName(
      kind: .movie, title: title, year: year, season: nil, episode: nil, episodeEnd: nil, height: height,
      dynamicRange: range)
  }

  // MARK: - Pieces

  struct EpisodeMatch {
    var season: Int
    var episode: Int
    var end: Int?
    /// Where the "S01E02" starts in the name, for the show title before it.
    var start: String.Index
  }

  /// "S01E02", "s1e2", "S01E01-E02", "1x02".
  static func episodeNumbers(in stem: String, folders: [String]) -> EpisodeMatch? {
    let patterns = [
      #"(?i)(?<![a-z0-9])s(\d{1,2})[ ._-]*e(\d{1,3})(?:[ ._-]*-?[ ._-]*e(\d{1,3}))?"#,
      #"(?i)(?<![a-z0-9])(\d{1,2})x(\d{2,3})(?![0-9p])"#,
    ]
    for pattern in patterns {
      guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
      let ns = stem as NSString
      guard let m = regex.firstMatch(in: stem, range: NSRange(location: 0, length: ns.length)) else { continue }
      func group(_ i: Int) -> Int? {
        guard i < m.numberOfRanges, m.range(at: i).location != NSNotFound else { return nil }
        return Int(ns.substring(with: m.range(at: i)))
      }
      guard let season = group(1), let episode = group(2), let start = Range(m.range, in: stem)?.lowerBound else { continue }
      let end = group(3).flatMap { $0 > episode ? $0 : nil }
      return EpisodeMatch(season: season, episode: episode, end: end, start: start)
    }
    return nil
  }

  /// In a TV folder: "Season 2/05 - Title.mkv" or "Season 2/Episode 5.mkv".
  static func looseEpisode(_ stem: String, folders: [String]) -> EpisodeMatch? {
    guard let seasonFolder = folders.last, let season = seasonNumber(seasonFolder) else { return nil }
    let patterns = [#"(?i)^(?:e|ep|episode)[ ._-]*(\d{1,3})"#, #"^(\d{1,3})(?![0-9])"#]
    for pattern in patterns {
      guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
      let ns = stem as NSString
      if let m = regex.firstMatch(in: stem, range: NSRange(location: 0, length: ns.length)),
        let episode = Int(ns.substring(with: m.range(at: 1)))
      {
        return EpisodeMatch(season: season, episode: episode, end: nil, start: stem.startIndex)
      }
    }
    return nil
  }

  static func isSeasonFolder(_ name: String) -> Bool { seasonNumber(name) != nil }

  /// "Season 2", "S02", "Series 2", "Specials" (season 0).
  static func seasonNumber(_ name: String) -> Int? {
    let lower = name.lowercased().trimmingCharacters(in: .whitespaces)
    if lower == "specials" { return 0 }
    guard let regex = try? NSRegularExpression(pattern: #"^(?:season|series|s)[ ._-]*(\d{1,2})$"#) else { return nil }
    let ns = lower as NSString
    guard let m = regex.firstMatch(in: lower, range: NSRange(location: 0, length: ns.length)) else { return nil }
    return Int(ns.substring(with: m.range(at: 1)))
  }

  /// Words that start the release details in a name: the title ends before them.
  static let stopWords: Set<String> = [
    "2160p", "1080p", "1080i", "720p", "576p", "480p", "4k", "uhd", "bluray", "blu", "bdrip", "brrip", "bdremux",
    "remux", "web", "webrip", "webdl", "web-dl", "hdtv", "dvdrip", "dvd", "hdrip", "x264", "x265", "h264", "h265",
    "hevc", "avc", "av1", "hdr", "hdr10", "hdr10+", "dv", "dovi", "proper", "repack", "extended", "unrated",
    "imax", "atmos", "truehd", "dts", "ddp", "dd5", "aac", "10bit", "complete", "multi", "internal", "limited",
  ]

  /// "The.Matrix.1999.1080p.BluRay" → ("The Matrix", 1999); "Alien (1979) [Director's Cut]" → ("Alien", 1979).
  static func titleAndYear(_ raw: String) -> (String, Int?) {
    // Brackets go first: "[Group]" and "{tmdb-603}" never belong to the title,
    // but "(1999)" does carry the year.
    var text = raw
    for (open, close) in [("[", "]"), ("{", "}")] {
      while let a = text.range(of: open), let b = text.range(of: close, range: a.upperBound..<text.endIndex) {
        text.replaceSubrange(a.lowerBound..<b.upperBound, with: " ")
      }
    }
    let words = text.replacingOccurrences(of: "_", with: " ")
      .replacingOccurrences(of: ".", with: " ")
      .replacingOccurrences(of: "(", with: " ( ")
      .replacingOccurrences(of: ")", with: " ) ")
      .split(separator: " ").map(String.init)
    var title: [String] = []
    var year: Int?
    let thisYear = Calendar(identifier: .gregorian).component(.year, from: Date()) + 1
    for (i, word) in words.enumerated() {
      let bare = word.trimmingCharacters(in: CharacterSet(charactersIn: "()-,"))
      if let value = Int(bare), bare.count == 4, (1900...thisYear).contains(value), !title.isEmpty {
        // "2001 A Space Odyssey": a year as the first word is the title's.
        year = value
        break
      }
      if stopWords.contains(bare.lowercased()) && i > 0 { break }
      if word == "(" || word == ")" { continue }
      title.append(word)
    }
    var joined = title.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: " -–,"))
    while joined.hasSuffix(" -") { joined.removeLast(2) }
    return (joined, year)
  }

  static func clean(_ text: String) -> String {
    text.replacingOccurrences(of: ".", with: " ").replacingOccurrences(of: "_", with: " ")
      .trimmingCharacters(in: .whitespaces)
  }

  static func height(in text: String) -> Int? {
    let lower = text.lowercased()
    for (token, height) in [("2160p", 2160), ("4k", 2160), ("uhd", 2160), ("1080p", 1080), ("1080i", 1080), ("720p", 720), ("576p", 576), ("480p", 480)] {
      if let range = lower.range(of: token) {
        // A token, not part of a word ("4k" in "4kids" doesn't count).
        let before = range.lowerBound == lower.startIndex ? nil : lower[lower.index(before: range.lowerBound)]
        let after = range.upperBound == lower.endIndex ? nil : lower[range.upperBound]
        if !(before?.isLetter ?? false), !(after?.isLetter ?? false) { return height }
      }
    }
    return nil
  }

  static func dynamicRange(in text: String) -> String? {
    let words = Set(
      text.lowercased().split(whereSeparator: { " ._-[]()".contains($0) }).map(String.init))
    if words.contains("dv") || words.contains("dovi") || text.lowercased().contains("dolby vision") { return "Dolby Vision" }
    if words.contains("hdr10+") || words.contains("hdr10plus") { return "HDR10+" }
    if words.contains("hdr") || words.contains("hdr10") { return "HDR" }
    return nil
  }
}
