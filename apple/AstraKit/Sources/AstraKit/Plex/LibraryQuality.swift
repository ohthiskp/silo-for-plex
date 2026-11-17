import Foundation

/// Settings → Content → Library Quality. Saved per device: iPhone defaults to
/// HD, Apple TV (and the Mac) to 4K (KP, 2026-11-07).
///
/// Many Plex servers keep 4K copies in their own libraries ("Movies 4K"),
/// so the same title shows up twice. This picks one copy of each title:
/// - HD: the 4K libraries are left out everywhere (tabs, Home rows, search,
///   the streaming tabs' matching), and a title with several versions plays its HD one.
/// - 4K: every library is used, but a movie that also has a 4K copy shows
///   only that copy; titles with no 4K copy show their HD one. A show in
///   both kinds of library shows once, as the copy listed first (4K show
///   libraries are often missing seasons, so shows are never swapped).
///
/// Like Preferred Quality, it never transcodes: it only chooses between files.
public enum LibraryQuality: String, CaseIterable, Sendable, Identifiable {
  case hd
  case uhd

  public static let storageKey = "astra.content.libraryQuality"

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .hd: "HD"
    case .uhd: "4K"
    }
  }

  /// This device's default.
  public static var deviceDefault: LibraryQuality {
    #if os(iOS)
      .hd
    #else
      .uhd
    #endif
  }

  public static func stored(in defaults: UserDefaults = .standard) -> LibraryQuality {
    defaults.string(forKey: storageKey).flatMap(LibraryQuality.init(rawValue:)) ?? deviceDefault
  }

  /// Whether a library holds 4K copies, from its name: "4K", "UHD", "Ultra HD" or "2160p".
  public static func isUHD(_ section: PlexLibrarySection) -> Bool {
    let title = section.title.lowercased()
    if title.contains("ultra hd") { return true }
    let words = title.split { !$0.isLetter && !$0.isNumber }
    return words.contains { ["4k", "uhd", "2160", "2160p"].contains(String($0)) }
  }
}

extension PlaybackQuality {
  /// The version choice actually used: Auto follows Library Quality, so an HD
  /// device plays the HD version of a title that has both.
  public static func current(in defaults: UserDefaults = .standard) -> PlaybackQuality {
    let stored = stored(in: defaults)
    guard stored == .auto else { return stored }
    return LibraryQuality.stored(in: defaults) == .hd ? .hd : .auto
  }
}

/// Applies Library Quality to sections and item lists. Cheap: set lookups only.
public struct LibraryFilter: Sendable {
  public let quality: LibraryQuality
  /// The keys of the libraries named as 4K.
  public let uhdSectionKeys: Set<String>

  public init(quality: LibraryQuality, sections: [PlexLibrarySection]) {
    self.quality = quality
    uhdSectionKeys = Set(sections.filter(LibraryQuality.isUHD).map(\.key))
  }

  public func isUHD(_ item: PlexMetadata) -> Bool {
    guard let id = item.librarySectionID else { return false }
    return uhdSectionKeys.contains(String(id))
  }

  /// The libraries to index: HD leaves the 4K ones out; 4K reads them first,
  /// so the index (first copy wins) holds the 4K copy of a title.
  public func indexSections(_ sections: [PlexLibrarySection]) -> [PlexLibrarySection] {
    let uhd = sections.filter { uhdSectionKeys.contains($0.key) }
    let main = sections.filter { !uhdSectionKeys.contains($0.key) }
    return quality == .hd ? main : uhd + main
  }

  /// The libraries the Movies and Shows tabs browse. A 4K library is only
  /// offered when there is no other library of that kind.
  public func browseSections(_ sections: [PlexLibrarySection]) -> [PlexLibrarySection] {
    let main = sections.filter { !uhdSectionKeys.contains($0.key) }
    if quality == .hd { return main }
    let kinds = Set(main.map(\.type))
    return sections.filter { !uhdSectionKeys.contains($0.key) || !kinds.contains($0.type) }
  }

  /// One copy of each title, in the list's order. HD drops 4K-library items;
  /// 4K swaps a movie for its 4K copy (from `twins`, or later in the list)
  /// and drops the other copy. `swap: false` keeps each item as it is (for
  /// Continue Watching, whose progress belongs to the copy being watched).
  public func apply(
    _ items: [PlexMetadata], twins: [String: PlexMetadata] = [:], swap: Bool = true
  ) -> [PlexMetadata] {
    guard !uhdSectionKeys.isEmpty else { return items }
    if quality == .hd { return items.filter { !isUHD($0) } }
    // 4K copies of movies in this list or the index, by TMDB key.
    var uhdCopies: [String: PlexMetadata] = [:]
    if swap {
      for item in items where item.type == .movie && isUHD(item) {
        if let key = item.tmdbKey, uhdCopies[key] == nil { uhdCopies[key] = item }
      }
    }
    var seen = Set<String>()
    var kept: [PlexMetadata] = []
    for item in items {
      var shown = item
      if swap, item.type == .movie, !isUHD(item), let key = item.tmdbKey,
        let copy = uhdCopies[key] ?? twins[key].flatMap({ isUHD($0) ? $0 : nil })
      {
        shown = copy
      }
      let keys = shown.dedupKeys + item.dedupKeys
      guard seen.isDisjoint(with: keys) else { continue }
      seen.formUnion(keys)
      kept.append(shown)
    }
    return kept
  }
}
