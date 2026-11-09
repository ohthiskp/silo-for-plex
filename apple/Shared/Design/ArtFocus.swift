import AstraKit
import ImageIO
import SwiftUI
import Vision

/// Where the faces are in a backdrop (else its most eye-catching subject),
/// found once with Apple's Vision and remembered, so a title's art is framed
/// the same way, instantly, every time after (KP, 2026-11-09).
struct ArtFocus: Codable, Equatable, Sendable {
  /// Image width / height.
  var aspect: Double
  /// Normalized, top-left origin; nil when nothing stood out.
  var focus: CGRect?
}

actor ArtFocusStore {
  static let shared = ArtFocusStore()

  private static let defaultsKey = "astra.artFocus.v1"
  private static let maxEntries = 400

  private var cache: [String: ArtFocus]
  private var order: [String]
  private var running: [String: Task<ArtFocus?, Never>] = [:]

  init() {
    let saved =
      (UserDefaults.standard.data(forKey: Self.defaultsKey))
      .flatMap { try? JSONDecoder().decode([String: ArtFocus].self, from: $0) } ?? [:]
    cache = saved
    order = Array(saved.keys)
  }

  /// Cached result, if this picture was looked at before.
  func cached(_ url: URL) -> ArtFocus? { cache[Self.key(url)] }

  func focus(for url: URL) async -> ArtFocus? {
    let key = Self.key(url)
    if let hit = cache[key] { return hit }
    if let task = running[key] { return await task.value }
    let small = Self.analysisURL(url)
    let task = Task.detached(priority: .utility) { () -> ArtFocus? in
      guard let loaded = try? await URLSession.shared.data(from: small) else { return nil }
      return ArtFocusStore.analyze(loaded.0)
    }
    running[key] = task
    let result = await task.value
    running[key] = nil
    if let result { remember(result, key) }
    return result
  }

  private func remember(_ value: ArtFocus, _ key: String) {
    cache[key] = value
    order.append(key)
    if order.count > Self.maxEntries {
      for old in order.prefix(order.count - Self.maxEntries) { cache[old] = nil }
      order.removeFirst(order.count - Self.maxEntries)
    }
    if let data = try? JSONEncoder().encode(cache) {
      UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
  }

  /// TMDB pictures by file name; Plex ones by path (their URLs carry tokens and sizes).
  static func key(_ url: URL) -> String {
    if url.host?.contains("tmdb") == true { return "tmdb:" + url.lastPathComponent }
    return url.path
  }

  /// A 780 px copy is plenty to find faces in.
  static func analysisURL(_ url: URL) -> URL {
    guard url.host?.contains("tmdb") == true else { return url }
    let parts = url.pathComponents
    guard let i = parts.firstIndex(of: "p"), i + 1 < parts.count else { return url }
    var copy = url.deletingLastPathComponent().deletingLastPathComponent()
    copy.appendPathComponent("w780")
    copy.appendPathComponent(url.lastPathComponent)
    return copy
  }

  static func analyze(_ data: Data) -> ArtFocus? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil), image.height > 0
    else { return nil }
    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    let faces = VNDetectFaceRectanglesRequest()
    let saliency = VNGenerateAttentionBasedSaliencyImageRequest()
    try? handler.perform([faces, saliency])
    // Vision's origin is bottom-left.
    func flip(_ r: CGRect) -> CGRect { CGRect(x: r.minX, y: 1 - r.maxY, width: r.width, height: r.height) }
    let faceRects = (faces.results ?? []).filter { $0.confidence > 0.6 }.map { flip($0.boundingBox) }
    let salient = (saliency.results?.first?.salientObjects ?? []).map { flip($0.boundingBox) }
    let rects = faceRects.isEmpty ? salient : faceRects
    let focus = rects.dropFirst().reduce(rects.first) { $0?.union($1) }
    return ArtFocus(aspect: Double(image.width) / Double(image.height), focus: focus)
  }
}

/// A backdrop framed so the faces end above the title logo, at `limitY`.
/// Fills the art area edge to edge; moves into place once the faces are found.
struct FramedArtwork: View {
  var library: LibraryStore
  var item: PlexMetadata
  var kind: LibraryStore.ArtKind = .heroBackdrop
  var zoneHeight: CGFloat
  var limitY: CGFloat
  var topOffset: CGFloat = 0
  var minTop: CGFloat = 0

  @State private var url: URL?
  @State private var focus: ArtFocus?

  var body: some View {
    GeometryReader { geo in
      let rect = ArtFraming.frame(
        boxWidth: geo.size.width, zoneHeight: zoneHeight, aspect: focus?.aspect ?? 16.0 / 9.0,
        limitY: limitY, topOffset: topOffset, minTop: minTop, focus: focus?.focus)
      RemoteImage(url: url, contentMode: .fill, placeholder: Color.clear)
        .frame(width: rect.width, height: rect.height)
        // KP (2026-11-09): wherever the framing puts the picture, its top and
        // bottom edges melt into the frosted page (no hard line across the
        // hero, and the art blurs up under the Dynamic Island).
        .mask {
          LinearGradient(
            stops: [
              .init(color: .clear, location: 0), .init(color: .black, location: 0.14),
              .init(color: .black, location: 0.72), .init(color: .clear, location: 1),
            ],
            startPoint: .top, endPoint: .bottom)
        }
        .offset(x: rect.minX, y: rect.minY)
        .astraAnimation(Astra.Motion.base, value: focus)
    }
    .frame(height: zoneHeight)
    .clipped()
    .task(id: "\(item.id)|\(kind)") {
      focus = nil
      let found = await library.artworkURL(for: item, kind, width: 1920, height: 1080)
      guard !Task.isCancelled else { return }
      url = found
      guard let found else { return }
      if let hit = await ArtFocusStore.shared.cached(found) {
        focus = hit
        return
      }
      let result = await ArtFocusStore.shared.focus(for: found)
      guard !Task.isCancelled else { return }
      focus = result
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}

#if os(iOS)
  /// A blur along the bottom of the screen, behind the floating tab bar, so
  /// rows soften as they slide under it instead of fading to black.
  struct BottomEdgeBlur: View {
    var height: CGFloat = 130

    var body: some View {
      ZStack {
        Rectangle().fill(.ultraThinMaterial)
        LinearGradient(
          colors: [Astra.Color.bg.opacity(0.2), Astra.Color.bg.opacity(0.6)],
          startPoint: .top, endPoint: .bottom)
      }
      .mask {
        LinearGradient(
          stops: [
            .init(color: .clear, location: 0), .init(color: .black.opacity(0.7), location: 0.4),
            .init(color: .black, location: 1),
          ],
          startPoint: .top, endPoint: .bottom)
      }
      .frame(height: height)
      .ignoresSafeArea(edges: .bottom)
      .allowsHitTesting(false)
      .accessibilityHidden(true)
    }
  }
#endif
