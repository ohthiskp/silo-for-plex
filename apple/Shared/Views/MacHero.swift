#if os(macOS)
  import AppKit
  import AstraKit
  import SwiftUI

  /// The Mac's Home hero, laid out like Apple TV's (KP, 2026-11-16: "the hero
  /// stuff is not updated on the Mac… it's still in the middle"): the logo,
  /// "2024 [PG-13] 2h 46m 4K UHD…", the genres and Play / Details at the left,
  /// the art sharp on the right with its faces clear of the text, the rest
  /// of it softly blurred. One title at a time with a crossfade, so resizing
  /// the window never shows half of one title and half of the next (the old
  /// paging hero did). A sideways trackpad swipe or a click on a dot moves
  /// to the next title.
  struct MacHero: View {
    var library: LibraryStore
    var items: [PlexMetadata]
    var height: CGFloat
    /// The title now showing (for the page's frosted background).
    var onCurrent: (PlexMetadata) -> Void = { _ in }

    @State private var index = 0
    @State private var hovering = false
    @State private var swipe = HeroSwipe()
    @Environment(\.contentLeading) private var leading
    @Environment(\.openItem) private var openItem
    @Environment(\.isPageActive) private var isActive

    private var current: PlexMetadata? { items.indices.contains(index) ? items[index] : items.first }

    var body: some View {
      ZStack(alignment: .bottomLeading) {
        if let current {
          MacHeroArt(library: library, item: current, clearX: leading + HeroInfo.blockWidth + 70)
            .overlay { HeroBlend() }
            .id(current.id)
            .transition(.opacity)

          VStack(alignment: .leading, spacing: 22) {
            HeroInfo(library: library, item: current)
              .id(current.id)
              .transition(.opacity)
            if items.count > 1 {
              StretchDots(count: items.count, progress: CGFloat(index)) { go(to: $0) }
                .padding(.leading, 2)
                .astraOnArt()
            }
          }
          .padding(.leading, leading)
          .padding(.bottom, 34)
        }
      }
      .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .bottomLeading)
      // The bottom dissolves into the frosted page background.
      .mask {
        LinearGradient(
          stops: [.init(color: .black, location: 0.8), .init(color: .clear, location: 1)],
          startPoint: .top, endPoint: .bottom)
      }
      .clipped()
      // A click anywhere opens Details; Play and Details keep their own action.
      .contentShape(Rectangle())
      .onTapGesture { if let current { openItem(current) } }
      .onHover { hovering = $0 }
      .onAppear {
        if let current { onCurrent(current) }
        swipe.start { step($0) }
      }
      .onDisappear { swipe.stop() }
      .onChange(of: hovering) { swipe.enabled = $0 && isActive }
      .onChange(of: isActive) { swipe.enabled = hovering && isActive }
      .onChange(of: items.map(\.id)) { index = 0 }
      .onChange(of: current?.id) { if let current { onCurrent(current) } }
      .sensoryFeedback(.selection, trigger: index)
    }

    private func go(to target: Int) {
      guard items.indices.contains(target), target != index else { return }
      astraWithAnimation(Astra.Motion.hero) { index = target }
    }

    private func step(_ by: Int) {
      guard items.count > 1 else { return }
      go(to: (index + by + items.count) % items.count)
    }
  }

  /// Two-finger sideways swipes over the hero, one title per swipe. Reads
  /// the scroll events directly, since nothing in the hero scrolls sideways.
  @MainActor private final class HeroSwipe {
    var enabled = false
    private var monitor: Any?
    private var travelled: CGFloat = 0
    private var fired = false

    func start(_ step: @escaping (Int) -> Void) {
      guard monitor == nil else { return }
      monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
        // Local monitors run on the main thread.
        MainActor.assumeIsolated { self?.handle(event, step: step) ?? event }
      }
    }

    private func handle(_ event: NSEvent, step: (Int) -> Void) -> NSEvent? {
      guard enabled else { return event }
      if event.phase == .began || event.phase == .mayBegin {
        travelled = 0
        fired = false
      }
      // Only clearly sideways swipes; up and down still scroll the page.
      guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else { return event }
      if !event.momentumPhase.isEmpty { return nil }
      travelled += event.scrollingDeltaX
      if !fired, abs(travelled) > 70 {
        fired = true
        step(travelled < 0 ? 1 : -1)
      }
      if event.phase == .ended || event.phase == .cancelled {
        travelled = 0
        fired = false
      }
      return nil
    }

    func stop() {
      if let monitor { NSEvent.removeMonitor(monitor) }
      monitor = nil
    }
  }

  /// The hero's picture, as on Apple TV (KP, 2026-11-16): the art sharp on the
  /// right with its faces (found once by Vision) clear of the text block on
  /// the left, fading into the same art softly blurred across the whole hero.
  /// The blur is made at a small fixed size and scaled up, so resizing the
  /// window only stretches it.
  struct MacHeroArt: View {
    var library: LibraryStore
    var item: PlexMetadata
    /// Where the text block ends; faces stay right of this line.
    var clearX: CGFloat
    var kind: LibraryStore.ArtKind = .heroBackdrop
    /// 0 puts the faces just past `clearX`; 1 as far right as they fit.
    var push: Double = 0.6

    @State private var url: URL?
    @State private var focus: ArtFocus?
    /// The art shows once it's framed, so it never slides to a new place
    /// after it appears (that jump read as a glitch on every Details open).
    @State private var ready = false

    var body: some View {
      GeometryReader { geo in
        let size = geo.size
        let rect = ArtFraming.side(
          boxWidth: size.width, boxHeight: size.height, aspect: focus?.aspect ?? 16.0 / 9.0,
          clearX: clearX, rightMargin: 40, minX: size.width * 0.12, maxX: size.width * 0.62,
          defaultX: size.width * 0.24, focus: focus?.focus, push: push)
        ZStack(alignment: .topLeading) {
          // A colour wash only: blurred so far that no shape survives.
          let small = CGSize(width: 192, height: 108)
          let scale = max(size.width / small.width, size.height / small.height)
          RemoteImage(url: url, contentMode: .fill, placeholder: Color.clear)
            .frame(width: small.width, height: small.height)
            .clipped()
            .blur(radius: 10, opaque: true)
            .drawingGroup()
            .scaleEffect(scale)
            .frame(width: size.width, height: size.height)
            .opacity(0.6)
          RemoteImage(url: url, contentMode: .fill, placeholder: Color.clear)
            .frame(width: rect.width, height: rect.height)
            .clipped()
            .mask {
              // A long, soft fade so the sharp art's left edge melts into the blur.
              LinearGradient(
                stops: [
                  .init(color: .clear, location: 0), .init(color: .black.opacity(0.3), location: 0.18),
                  .init(color: .black.opacity(0.75), location: 0.35), .init(color: .black, location: 0.5),
                ],
                startPoint: .leading, endPoint: .trailing)
            }
            .offset(x: rect.minX)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .opacity(ready ? 1 : 0)
      }
      .clipped()
      .allowsHitTesting(false)
      .accessibilityHidden(true)
      .task(id: "\(item.id)|\(kind)") {
        ready = false
        focus = nil
        let found = await library.artworkURL(for: item, kind, width: 1920, height: 1080)
        guard !Task.isCancelled else { return }
        url = found
        guard let found else { return }
        if let hit = await ArtFocusStore.shared.cached(found) {
          focus = hit
          show()
          return
        }
        // Faces not looked for yet: wait a moment for Vision, then show the
        // art where it is. A late answer is remembered for next time but
        // doesn't move the art on screen.
        let fallback = Task { @MainActor in
          try? await Task.pause(0.6)
          if !Task.isCancelled { show() }
        }
        let result = await ArtFocusStore.shared.focus(for: found)
        fallback.cancel()
        guard !Task.isCancelled, !ready else { return }
        focus = result
        show()
      }
    }

    private func show() {
      guard !ready else { return }
      astraWithAnimation(.easeOut(duration: 0.3)) { ready = true }
    }
  }

#endif
