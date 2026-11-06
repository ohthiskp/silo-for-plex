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
  private let session: URLSession = {
    let config = URLSessionConfiguration.default
    config.urlCache = URLCache(memoryCapacity: 32 << 20, diskCapacity: 512 << 20)
    config.requestCachePolicy = .returnCacheDataElseLoad
    config.httpMaximumConnectionsPerHost = 8
    return URLSession(configuration: config)
  }()

  nonisolated func cached(_ url: URL) -> PlatformImage? {
    cache.object(forKey: url as NSURL)
  }

  func image(for url: URL) async -> PlatformImage? {
    if let hit = cache.object(forKey: url as NSURL) { return hit }
    if let running = inFlight[url] { return await running.value }
    let session = session
    let task = Task.detached(priority: .userInitiated) { () -> PlatformImage? in
      guard let (data, _) = try? await session.data(from: url) else { return nil }
      return Self.decode(data)
    }
    inFlight[url] = task
    let image = await task.value
    inFlight[url] = nil
    if let image {
      let cost = image.pixelArea * 4
      cache.setObject(image, forKey: url as NSURL, cost: cost)
    }
    return image
  }

  private static func decode(_ data: Data) -> PlatformImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    let options: [CFString: Any] = [kCGImageSourceShouldCacheImmediately: true]
    guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary) else { return nil }
    return PlatformImage.decoded(cgImage)
  }
}

/// Artwork that fades in once decoded, over a quiet placeholder.
struct RemoteImage: View {
  var url: URL?
  var contentMode: ContentMode = .fill

  @State private var image: PlatformImage?

  var body: some View {
    ZStack {
      Astra.Color.surface
      if let image {
        Image(platformImage: image)
          .resizable()
          .interpolation(.high)
          .aspectRatio(contentMode: contentMode)
          .transition(.opacity)
      }
    }
    .task(id: url) {
      guard let url else { return image = nil }
      if let hit = ImagePipeline.shared.cached(url) {
        image = hit
        return
      }
      let loaded = await ImagePipeline.shared.image(for: url)
      guard !Task.isCancelled else { return }
      withAnimation(Astra.Motion.base) { image = loaded }
    }
  }
}
