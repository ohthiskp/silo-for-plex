import Foundation

/// What Astra knows about the run in progress, kept on disk so the next launch
/// can tell when iOS stopped the app (KP, 2026-11-14: "crashed twice and no
/// crash report").
///
/// Astra's signal handler sees Swift errors, aborts and bad memory access, but
/// not a kill by the system: running out of memory (jetsam) or a frozen main
/// thread (watchdog) end the app with SIGKILL, which no handler can catch. So
/// the app writes this record while it runs. If the next launch finds that the
/// last run was on screen and never went to the background or quit, and no
/// handler wrote a report, the system stopped it, and the record says what
/// Astra was doing and how much memory it used.
public struct AppSessionRecord: Codable, Equatable, Sendable {
  /// "3.1.0 (202611141644)"
  public var version: String
  public var osVersion: String
  /// When the device last started (seconds since 1970), to tell a restart from a kill.
  public var bootTime: TimeInterval
  public var launched: Date
  /// The last time the record was written (every few seconds while on screen).
  public var lastSeen: Date
  public var inForeground: Bool
  /// The app quit normally (Mac, or iOS terminating it in the background).
  public var endedCleanly: Bool
  /// Memory Astra used at `lastSeen`, and how much more iOS would have let it use.
  public var memoryUsedMB: Int?
  public var memoryLeftMB: Int?
  public var peakMemoryUsedMB: Int?
  public var memoryWarnings: Int
  /// Set when the main thread stopped answering for a few seconds (a freeze).
  public var frozenSince: Date?
  /// The last few things that happened: "17:02:11  Playing Dune: Part Two (4K)".
  public var activity: [String]

  public init(
    version: String, osVersion: String, bootTime: TimeInterval, launched: Date = Date(),
    inForeground: Bool = true
  ) {
    self.version = version
    self.osVersion = osVersion
    self.bootTime = bootTime
    self.launched = launched
    self.lastSeen = launched
    self.inForeground = inForeground
    self.endedCleanly = false
    self.memoryWarnings = 0
    self.activity = []
  }

  public static let activityLimit = 20

  public mutating func note(_ text: String, at date: Date = Date()) {
    activity.append(AppSession.clock(date) + "  " + text)
    if activity.count > Self.activityLimit { activity.removeFirst(activity.count - Self.activityLimit) }
  }

  public mutating func recordMemory(usedMB: Int?, leftMB: Int?) {
    memoryUsedMB = usedMB
    memoryLeftMB = leftMB
    if let usedMB { peakMemoryUsedMB = max(peakMemoryUsedMB ?? 0, usedMB) }
  }
}

public enum AppSession {
  /// Whether the last run was stopped by the system while it was on screen.
  /// Not when the app or the OS was updated or the device restarted in
  /// between (those stop the app too), and not when it was in the background
  /// (iOS ends background apps all the time; that is normal).
  public static func endedUnexpectedly(
    _ previous: AppSessionRecord?, version: String, osVersion: String, bootTime: TimeInterval
  ) -> Bool {
    guard let previous, previous.inForeground, !previous.endedCleanly else { return false }
    guard previous.version == version, previous.osVersion == osVersion else { return false }
    // Boot time is read in whole seconds; allow a little slack.
    guard bootTime == 0 || previous.bootTime == 0 || abs(previous.bootTime - bootTime) < 5 else { return false }
    return true
  }

  /// "Memory" when Astra was close to its limit or iOS had warned it; "freeze" when the main thread had stopped.
  public enum Cause: Equatable, Sendable { case memory, freeze, unknown }

  public static func likelyCause(of record: AppSessionRecord) -> Cause {
    if record.frozenSince != nil { return .freeze }
    if record.memoryWarnings > 0 { return .memory }
    if let left = record.memoryLeftMB, left < 400 { return .memory }
    return .unknown
  }

  /// The report shown on the crash screen. `CrashReportText.summary` reads
  /// its Signal, Reason, Time and Version lines.
  public static func report(for record: AppSessionRecord) -> String {
    let reason: String
    switch likelyCause(of: record) {
    case .memory: reason = "Astra ran out of memory and iOS closed it."
    case .freeze: reason = "Astra stopped responding and iOS closed it."
    case .unknown: reason = "iOS closed Astra while it was on screen (out of memory or not responding)."
    }
    var lines = [
      "Astra crashed",
      "",
      "Version: \(record.version)",
      "OS: \(record.osVersion)",
      "Launched: \(stamp(record.launched))",
      "Signal: SIGKILL (stopped by the system)",
      "Reason: \(reason)",
      "Time: \(stamp(record.lastSeen))",
    ]
    if let frozen = record.frozenSince {
      lines.append("Not responding since: \(stamp(frozen))")
    }
    var memory: [String] = []
    if let used = record.memoryUsedMB { memory.append("\(used) MB in use") }
    if let left = record.memoryLeftMB { memory.append("\(left) MB left") }
    if let peak = record.peakMemoryUsedMB { memory.append("peak \(peak) MB") }
    if record.memoryWarnings > 0 { memory.append("\(record.memoryWarnings) low-memory warning(s)") }
    if !memory.isEmpty { lines.append("Memory: " + memory.joined(separator: ", ")) }
    lines.append("")
    lines.append("Last thing Astra did (it was last seen \(stamp(record.lastSeen))):")
    lines.append(contentsOf: record.activity.isEmpty ? ["(nothing recorded)"] : record.activity)
    return lines.joined(separator: "\n") + "\n"
  }

  /// The recent activity, added below a crash the signal handler did catch.
  public static func activitySection(for record: AppSessionRecord) -> String {
    guard !record.activity.isEmpty else { return "" }
    var lines = ["", "--- What Astra was doing"]
    lines.append(contentsOf: record.activity)
    if let used = record.memoryUsedMB {
      lines.append("Memory: \(used) MB in use" + (record.memoryLeftMB.map { ", \($0) MB left" } ?? ""))
    }
    return lines.joined(separator: "\n") + "\n"
  }

  public static func stamp(_ date: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd HH:mm:ss ZZZ"
    return f.string(from: date)
  }

  static func clock(_ date: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "HH:mm:ss"
    return f.string(from: date)
  }
}
