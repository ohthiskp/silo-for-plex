import AstraKit
import Darwin
import Foundation
import os

#if os(iOS) || os(tvOS)
  import UIKit
#elseif os(macOS)
  import AppKit
#endif

/// Keeps `AppSessionRecord` on disk while Astra runs (KP, 2026-11-14: "crashed
/// twice and no crash report"). When iOS stops the app for memory or a freeze
/// no crash handler runs, so the next launch reads this record instead:
/// whether Astra was on screen, how much memory it used, whether the main
/// thread had stopped answering, and the last things it did.
///
/// All state sits behind one lock; the file is small and written atomically.
final class SessionWatch: @unchecked Sendable {
  private let url: URL
  private let lock = NSLock()
  private var record: AppSessionRecord?
  private var observers: [NSObjectProtocol] = []
  private let queue = DispatchQueue(label: "astra.session-watch", qos: .utility)
  private var checker: DispatchSourceTimer?
  private var heartbeat: Timer?
  /// The main thread's last heartbeat (seconds, monotonic).
  private var mainBeat = SessionWatch.now()
  private var lastWrite: TimeInterval = 0

  /// How long the main thread may stay silent before it counts as frozen.
  /// iOS's watchdog allows a little more than this before it stops the app.
  static let freezeAfter: TimeInterval = 4

  init(url: URL) {
    self.url = url
  }

  /// The record the previous run left, if any.
  func loadPrevious() -> AppSessionRecord? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(AppSessionRecord.self, from: data)
  }

  /// Starts this run's record. Call on the main thread, at launch.
  func start(_ initial: AppSessionRecord, watchMainThread: Bool) {
    var first = initial
    first.note("Astra launched")
    first.recordMemory(usedMB: Self.memoryUsedMB(), leftMB: Self.memoryLeftMB())
    update { $0 = first }
    observeLifecycle()
    guard watchMainThread else { return }

    // The main thread ticks once a second; a background check notices when it stops.
    let beat = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.mainThreadBeat() }
    beat.tolerance = 0.3
    RunLoop.main.add(beat, forMode: .common)
    heartbeat = beat

    let timer = DispatchSource.makeTimerSource(queue: queue)
    timer.schedule(deadline: .now() + 2, repeating: 2, leeway: .milliseconds(500))
    timer.setEventHandler { [weak self] in self?.check() }
    timer.resume()
    checker = timer
  }

  func note(_ text: String) {
    update(write: true) { $0.note(text) }
  }

  // MARK: - Lifecycle

  private func observeLifecycle() {
    let center = NotificationCenter.default
    func on(_ name: Notification.Name, _ body: @escaping (SessionWatch) -> Void) {
      observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
        if let self { body(self) }
      })
    }
    #if os(iOS) || os(tvOS)
      on(UIApplication.didFinishLaunchingNotification) { watch in
        // Woken in the background (finished downloads): not on screen yet.
        let background = UIApplication.shared.applicationState == .background
        watch.update { $0.inForeground = !background }
      }
      on(UIApplication.willEnterForegroundNotification) { watch in
        watch.resetBeat()
        watch.update {
          $0.inForeground = true
          $0.note("Back on screen")
        }
      }
      on(UIApplication.didEnterBackgroundNotification) { watch in
        watch.update {
          $0.inForeground = false
          $0.frozenSince = nil
          $0.note("Went to the background")
        }
      }
      on(UIApplication.willTerminateNotification) { watch in
        watch.update { $0.endedCleanly = true }
      }
      on(UIApplication.didReceiveMemoryWarningNotification) { watch in
        let used = Self.memoryUsedMB()
        let left = Self.memoryLeftMB()
        watch.update {
          $0.memoryWarnings += 1
          $0.recordMemory(usedMB: used, leftMB: left)
          $0.note("Low-memory warning from iOS" + (used.map { " (\($0) MB in use)" } ?? ""))
        }
      }
    #elseif os(macOS)
      on(NSApplication.willTerminateNotification) { watch in
        watch.update { $0.endedCleanly = true }
      }
    #endif
  }

  // MARK: - Freeze and memory checks

  private func mainThreadBeat() {
    lock.lock()
    mainBeat = Self.now()
    lock.unlock()
  }

  private func resetBeat() {
    mainThreadBeat()
  }

  /// Runs on the background queue every 2 s.
  private func check() {
    lock.lock()
    let silent = Self.now() - mainBeat
    let onScreen = record?.inForeground ?? false
    let frozen = record?.frozenSince
    lock.unlock()
    guard onScreen else { return }

    if silent > Self.freezeAfter, frozen == nil {
      let since = Date().addingTimeInterval(-silent)
      update(write: true) {
        $0.frozenSince = since
        $0.note("Not responding (main thread busy)")
      }
    } else if silent <= Self.freezeAfter, let frozen {
      let seconds = Int(Date().timeIntervalSince(frozen))
      update(write: true) {
        $0.frozenSince = nil
        $0.note("Responding again after \(seconds) s")
      }
    }
    // Memory and "last seen" every 10 s.
    let used = Self.memoryUsedMB()
    let left = Self.memoryLeftMB()
    update(write: Self.now() - lastWrite >= 10) { $0.recordMemory(usedMB: used, leftMB: left) }
  }

  // MARK: - Record

  /// Changes the record and, by default, writes it at once.
  private func update(write: Bool = true, _ change: (inout AppSessionRecord) -> Void) {
    lock.lock()
    defer { lock.unlock() }
    var current = record ?? AppSessionRecord(version: "?", osVersion: "?", bootTime: 0)
    change(&current)
    guard write else {
      record = current
      return
    }
    current.lastSeen = Date()
    record = current
    lastWrite = Self.now()
    if let data = try? JSONEncoder().encode(current) {
      try? data.write(to: url, options: .atomic)
    }
  }

  // MARK: - Measurements

  private static func now() -> TimeInterval {
    ProcessInfo.processInfo.systemUptime
  }

  /// Astra's memory footprint, the number iOS compares with its limit.
  static func memoryUsedMB() -> Int? {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
      }
    }
    guard result == KERN_SUCCESS else { return nil }
    return Int(info.phys_footprint / 1_048_576)
  }

  /// How much more memory iOS would let Astra use.
  static func memoryLeftMB() -> Int? {
    #if os(iOS) || os(tvOS)
      return Int(os_proc_available_memory() / 1_048_576)
    #else
      return nil
    #endif
  }
}
