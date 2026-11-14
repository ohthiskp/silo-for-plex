import AstraKit
import ImageIO
import SwiftUI

/// Loads, decodes and caches artwork away from the main thread.
///
/// Plex already resizes images to the card's pixel size (`/photo/:/transcode`),
/// and the decode is forced here on a background task, so scrolling a row
/// never decodes a JPEG on the main thread. That is most of what makes the
/// Flutter app's rows stutter.
actor ImagePipeline {
  static let shared = ImagePipeline()

  private let cache: NSCache<NSURL, PlatformImage> = {
    let cache = NSCache<NSURL, PlatformImage>()
    cache.totalCostLimit = 256 * 1024 * 1024
    return cache
  }()
  private var inFlight: [URL: Task<PlatformImage?, Never>] = [:]

  /// Counts for the CI performance report (`PerfProbe`): images asked for
  /// that weren't in memory, fetched (network or disk cache), decoded.
  struct Stats: Sendable {
    var asked = 0
    var fetched = 0
    var decoded = 0
    var megapixels: Double = 0
    var bytes = 0
    var prefetched = 0
  }
  private(set) var stats = Stats()
  /// The artwork disk cache ("AstraImages" in Caches). Plex URLs in it carry
  /// no token (see `PlexImageAuth`); `clearCache()` empties it on sign-out.
  nonisolated static let urlCache: URLCache = {
    // Builds before this one cached Plex URLs with the token in them, in the
    // default location: emptied once.
    let migrated = "astra.imageCache.tokenFree"
    if !UserDefaults.standard.bool(forKey: migrated) {
      URLCache(memoryCapacity: 0, diskCapacity: 512 << 20).removeAllCachedResponses()
      UserDefaults.standard.set(true, forKey: migrated)
    }
    return URLCache(memoryCapacity: 32 << 20, diskCapacity: 512 << 20, directory: cacheDirectory)
  }()

  nonisolated static var cacheDirectory: URL {
    (FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory)
      .appendingPathComponent("AstraImages", isDirectory: true)
  }

  private let session: URLSession = {
    let config = URLSessionConfiguration.default
    config.urlCache = ImagePipeline.urlCache
    config.requestCachePolicy = .returnCacheDataElseLoad
    config.httpMaximumConnectionsPerHost = 8
    return URLSession(configuration: config)
  }()

  /// Sign-out: forgets every image, on disk and in memory, and the Plex tokens.
  nonisolated func clearCache() {
    Self.urlCache.removeAllCachedResponses()
    cache.removeAllObjects()
    PlexImageAuth.reset()
  }

  nonisolated func cached(_ url: URL) -> PlatformImage? {
    cache.object(forKey: url as NSURL)
  }

  func image(for url: URL) async -> PlatformImage? {
    if let hit = cache.object(forKey: url as NSURL) { return hit }
    if let running = inFlight[url] { return await running.value }
    stats.asked += 1
    let session = session
    let task = Task.detached(priority: .userInitiated) { () -> PlatformImage? in
      // Plex images get the server's token as a header, never in the URL.
      guard let (data, _) = try? await session.data(for: PlexImageAuth.request(url)) else { return nil }
      return Self.decode(data)
    }
    inFlight[url] = task
    let image = await task.value
    inFlight[url] = nil
    if let image {
      stats.fetched += 1
      stats.decoded += 1
      stats.megapixels += Double(image.pixelArea) / 1_000_000
      let cost = image.pixelArea * 4
      stats.bytes += cost
      cache.setObject(image, forKey: url as NSURL, cost: cost)
    }
    return image
  }

  /// Performance audit (2026-11-10): downloads an image into the disk
  /// cache without decoding it, for artwork that may be needed soon but
  /// isn't on screen (Top Trending's Details backdrops and logos). Decoding
  /// every one up front filled the 256 MB memory cache with 2560 px bitmaps
  /// that were pushed out again before they were used. Opening one now
  /// decodes it from disk, with no network.
  func prefetch(_ url: URL) async {
    if cache.object(forKey: url as NSURL) != nil || inFlight[url] != nil { return }
    let request = PlexImageAuth.request(url)
    if Self.urlCache.cachedResponse(for: request) != nil { return }
    stats.prefetched += 1
    let session = session
    _ = await Task.detached(priority: .utility) { try? await session.data(for: request) }.value
  }

  /// Decodes at most `maxPixels` on the long side. TMDB's "original" hero
  /// backdrops can be 4K or larger; a full-size bitmap is ~35 MB and stalls
  /// the frame it is first drawn in. 2560 px covers a Retina window.
  static let maxPixels = 2560

  private static func decode(_ data: Data) -> PlatformImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceShouldCacheImmediately: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixels,
    ]
    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
    return PlatformImage.decoded(cgImage)
  }
}

/// Artwork that fades in once decoded, over a quiet placeholder. An image
/// already in memory shows on the first frame, with no fade.
struct RemoteImage<Placeholder: View>: View {
  var url: URL?
  var contentMode: ContentMode
  var placeholder: Placeholder

  @State private var image: PlatformImage?
  @State private var loadedURL: URL?

  init(url: URL?, contentMode: ContentMode = .fill, placeholder: Placeholder) {
    self.url = url
    self.contentMode = contentMode
    self.placeholder = placeholder
    let hit = url.flatMap { ImagePipeline.shared.cached($0) }
    _image = State(initialValue: hit)
    _loadedURL = State(initialValue: hit == nil ? nil : url)
  }

  var body: some View {
    ZStack {
      placeholder
      if let image {
        Image(platformImage: image)
          .resizable()
          .interpolation(.high)
          .aspectRatio(contentMode: contentMode)
          .transition(.opacity)
      }
    }
    .task(id: url) {
      guard let url else {
        image = nil
        loadedURL = nil
        return
      }
      guard url != loadedURL else { return }
      if let hit = ImagePipeline.shared.cached(url) {
        image = hit
        loadedURL = url
        return
      }
      let loaded = await ImagePipeline.shared.image(for: url)
      guard !Task.isCancelled else { return }
      loadedURL = url
      withAnimation(Astra.Motion.base) { image = loaded }
    }
  }
}

extension RemoteImage where Placeholder == SwiftUI.Color {
  init(url: URL?, contentMode: ContentMode = .fill) {
    self.init(url: url, contentMode: contentMode, placeholder: Astra.Color.surface2)
  }
}

/// A movie's or show's poster, backdrop or logo from TMDB, falling back to
/// Plex's own artwork. Episodes keep Plex's stills.
struct ArtworkImage<Placeholder: View>: View {
  var library: LibraryStore
  var item: PlexMetadata
  var kind: LibraryStore.ArtKind
  var width: CGFloat
  var height: CGFloat
  var contentMode: ContentMode = .fill
  var placeholder: Placeholder

  @State private var url: URL?
  @State private var resolved = false

  var body: some View {
    ZStack {
      if resolved {
        RemoteImage(url: url, contentMode: contentMode, placeholder: placeholder)
      } else {
        placeholder
      }
    }
    .task(id: "\(item.id)|\(kind)") {
      let found = await library.artworkURL(for: item, kind, width: width, height: height)
      guard !Task.isCancelled else { return }
      url = found
      resolved = true
    }
  }
}

extension ArtworkImage where Placeholder == SwiftUI.Color {
  init(
    library: LibraryStore, item: PlexMetadata, kind: LibraryStore.ArtKind, width: CGFloat, height: CGFloat,
    contentMode: ContentMode = .fill
  ) {
    self.init(
      library: library, item: item, kind: kind, width: width, height: height, contentMode: contentMode,
      placeholder: Astra.Color.surface2)
  }
}
