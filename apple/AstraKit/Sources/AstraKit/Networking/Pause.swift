import Foundation

extension Task where Success == Never, Failure == Never {
  /// Sleeps for `seconds`. Use this instead of `Task.sleep(for:)`: on iPhone
  /// (iOS 27, Release build) the Duration-based sleep aborted the app in
  /// swift_task_dealloc right after it returned. The nanosecond sleep has no
  /// clock or Duration involved.
  public static func pause(_ seconds: Double) async throws {
    try await sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
  }

  /// Same, for a `Duration`.
  public static func pause(_ duration: Duration) async throws {
    let (s, attos) = duration.components
    try await pause(Double(s) + Double(attos) / 1e18)
  }
}
