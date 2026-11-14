import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Astra (performance audit, 2026-11-10): one read of cineby's home page for
/// everyone who asks within `maxAge`. The hero/Top Trending list and the
/// Recently Released / All-Time Greats rows both come from that page; each
/// used to download it on its own, so a launch with stale saved copies read
/// the page twice. Callers asking at the same time share one request; a
/// failed read isn't kept, so the next caller tries again.
public actor CinebyPage {
  public static let shared = CinebyPage()

  private let transport: HTTPTransport
  private let maxAge: TimeInterval
  private let now: @Sendable () -> Date
  private var current: (task: Task<String, Error>, started: Date)?

  public init(
    transport: HTTPTransport = URLSessionTransport(), maxAge: TimeInterval = 5 * 60,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.transport = transport
    self.maxAge = maxAge
    self.now = now
  }

  public func html() async throws -> String {
    if let current, now().timeIntervalSince(current.started) < maxAge {
      return try await current.task.value
    }
    let transport = transport
    let task = Task { try await CinebyTrending.fetchHTML(transport: transport) }
    let started = now()
    current = (task, started)
    do {
      return try await task.value
    } catch {
      // Only forget this read; a newer one may have replaced it meanwhile.
      if current?.started == started { current = nil }
      throw error
    }
  }
}
