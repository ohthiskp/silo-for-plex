import AstraKit
import Foundation
import Observation

/// Home rows, libraries and a small metadata cache for the connected server.
@MainActor
@Observable
final class LibraryStore {
  let client: PlexServerClient

  private(set) var continueWatching: [PlexMetadata] = []
  private(set) var hubs: [PlexHub] = []
  private(set) var hero: [PlexMetadata] = []
  private(set) var sections: [PlexLibrarySection] = []
  private(set) var isLoadingHome = false
  private(set) var homeError: String?

  private var detailCache: [String: PlexMetadata] = [:]

  init(client: PlexServerClient) {
    self.client = client
  }

  func loadHome() async {
    isLoadingHome = hubs.isEmpty
    homeError = nil
    async let continueTask = client.continueWatching()
    async let hubsTask = client.homeHubs()
    async let sectionsTask = client.librarySections()

    let loadedContinue = (try? await continueTask) ?? []
    let loadedSections = (try? await sectionsTask) ?? []
    do {
      let loadedHubs = try await hubsTask
      let rows = await Self.deduplicatedRows(
        continueWatching: loadedContinue.isEmpty
          ? loadedHubs.first(where: \.isContinueWatching)?.items ?? [] : loadedContinue,
        hubs: loadedHubs.filter { !$0.isContinueWatching },
        more: { [client] key, start in (try? await client.hubItems(key: key, start: start)) ?? [] })
      continueWatching = rows.continueWatching
      hubs = rows.hubs
      sections = loadedSections
      hero = await pickHero(from: hubs)
    } catch {
      homeError = error.localizedDescription
    }
    isLoadingHome = false
  }

  /// Rows with every title shown once across the whole page, in Plex's row
  /// order. Continue Watching claims its titles first. A row left short by
  /// de-duplication loads more of its own items (up to three more pages)
  /// instead of repeating titles; a row left empty is dropped.
  static func deduplicatedRows(
    continueWatching: [PlexMetadata], hubs: [PlexHub], minimumPerRow: Int = 10,
    more: (String, Int) async -> [PlexMetadata]
  ) async -> (continueWatching: [PlexMetadata], hubs: [PlexHub]) {
    var dedup = HomeDeduplicator()
    let keptContinue = dedup.filter(continueWatching)
    var keptHubs: [PlexHub] = []
    for var hub in hubs {
      var items = dedup.filter(hub.items)
      var offset = hub.items.count
      var pages = 0
      while items.count < minimumPerRow, hub.more == true, let key = hub.key, pages < 3 {
        let page = await more(key, offset)
        if page.isEmpty { break }
        offset += page.count
        pages += 1
        items += dedup.filter(page)
      }
      hub.items = items
      if !items.isEmpty { keptHubs.append(hub) }
    }
    return (keptContinue, keptHubs)
  }

  /// Up to five recent movies or shows with backdrops, loaded in full so the
  /// hero can show clear logos.
  private func pickHero(from hubs: [PlexHub]) async -> [PlexMetadata] {
    let recent = hubs.filter { $0.hubIdentifier.contains("recentlyadded") || $0.hubIdentifier.contains("recentlyAdded") }
    let pool = (recent.isEmpty ? hubs : recent).flatMap(\.items)
    var seen = Set<String>()
    let candidates = pool.compactMap { item -> PlexMetadata? in
      // Show the show, not one of its episodes.
      if item.type == .episode || item.type == .season {
        guard let key = item.grandparentRatingKey ?? item.parentRatingKey else { return nil }
        return seen.insert(key).inserted ? PlexMetadata(ratingKey: key, type: .show, title: item.displayTitle) : nil
      }
      guard item.type == .movie || item.type == .show else { return nil }
      return seen.insert(item.ratingKey).inserted ? item : nil
    }
    .prefix(5)

    var full: [PlexMetadata] = []
    for item in candidates {
      if let loaded = try? await details(item.ratingKey), loaded.backdrop != nil { full.append(loaded) }
    }
    return full
  }

  func details(_ ratingKey: String, refresh: Bool = false) async throws -> PlexMetadata {
    if !refresh, let cached = detailCache[ratingKey] { return cached }
    let item = try await client.metadata(ratingKey: ratingKey)
    detailCache[ratingKey] = item
    return item
  }

  func children(of ratingKey: String) async throws -> [PlexMetadata] {
    try await client.children(ratingKey: ratingKey)
  }

  func related(_ ratingKey: String) async -> [PlexHub] {
    (try? await client.relatedHubs(ratingKey: ratingKey)) ?? []
  }

  /// The item Play should start: the movie or episode itself, or for a show
  /// or season the next unwatched episode (Plex's On Deck), else the first.
  func playable(for item: PlexMetadata) async throws -> PlexMetadata {
    switch item.type {
    case .movie, .episode:
      return item.media.isEmpty ? try await details(item.ratingKey, refresh: true) : item
    case .show, .season:
      var episodes: [PlexMetadata] = []
      if item.type == .show {
        let seasons = try await children(of: item.ratingKey).filter { $0.type == .season }
        for season in seasons where (season.index ?? 1) > 0 || seasons.count == 1 {
          episodes += try await children(of: season.ratingKey)
          if episodes.contains(where: { !$0.isWatched }) { break }
        }
      } else {
        episodes = try await children(of: item.ratingKey)
      }
      let next = episodes.first { ($0.viewOffset ?? 0) > 0 } ?? episodes.first { !$0.isWatched } ?? episodes.first
      guard let next else { throw PlexError.nothingToPlay }
      return try await details(next.ratingKey, refresh: true)
    default:
      throw PlexError.nothingToPlay
    }
  }

  func setWatched(_ item: PlexMetadata, watched: Bool) async {
    do {
      if watched {
        try await client.markWatched(ratingKey: item.ratingKey)
      } else {
        try await client.markUnwatched(ratingKey: item.ratingKey)
      }
      detailCache[item.ratingKey] = nil
      await loadHome()
    } catch {
      homeError = error.localizedDescription
    }
  }

  /// Called when the player closes, so Continue Watching shows the new position.
  func playbackEnded(ratingKey: String) {
    detailCache[ratingKey] = nil
    Task { await loadHome() }
  }

  /// Plex artwork sized for a frame, in steps (see `ImageSize.bucketed`) so a
  /// resizing window or an animating layout doesn't refetch on every frame.
  func imageURL(_ path: String?, width: CGFloat, height: CGFloat, scale: CGFloat = 2) -> URL? {
    guard let size = ImageSize.bucketed(width: Double(width * scale), height: Double(height * scale)) else {
      return nil
    }
    return client.imageURL(path, width: size.width, height: size.height)
  }
}
