#if os(iOS) || os(macOS)
  import Darwin
  import Foundation
  import MachO
  import MetricKit
  import Observation

  /// Astra (KP, 2026-11-12): "this app crashed, copy this report". When Astra
  /// crashes, a small report is written to disk on the way down; on the next
  /// launch `CrashReportSheet` shows it with Copy and Send. Nothing leaves the
  /// device unless the person sends it themselves (no crash service).
  ///
  /// Two sources:
  /// - a signal handler (Swift traps, aborts, bad memory access, also inside
  ///   mpv) and an uncaught Objective-C exception handler, written by Astra;
  /// - Apple's own crash diagnostics from MetricKit, which arrive on a later
  ///   launch and also cover kills a handler can't see (watchdog, memory).
  ///
  /// Offsets in the report ("Astra + 954076") go into astra-ios-symbolicate.yml.
  @MainActor @Observable
  final class CrashReporter {
    static let shared = CrashReporter()

    /// The report to show, until the person closes it.
    private(set) var pending: String?

    private let folder: URL
    private var report: URL { folder.appendingPathComponent("last-crash.txt") }
    private var signalLog: URL { folder.appendingPathComponent("signal.log") }
    private var exceptionLog: URL { folder.appendingPathComponent("exception.log") }
    private var installed = false
    private let metrics = MetricsSubscriber()

    private init() {
      let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        ?? URL(fileURLWithPath: NSTemporaryDirectory())
      folder = base.appendingPathComponent("CrashReports", isDirectory: true)
    }

    /// Call once, first thing at launch.
    func install() {
      guard !installed else { return }
      installed = true
      try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

      // Last launch's crash, if there was one.
      if let text = collectRawLogs() {
        try? text.write(to: report, atomically: true, encoding: .utf8)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.shownKey)
      }
      pending = try? String(contentsOf: report, encoding: .utf8)

      CrashSignals.install(path: signalLog.path, exceptionPath: exceptionLog.path, header: Self.header())
      metrics.onCrash = { [weak self] text, range in self?.receive(metricKit: text, range: range) }
      MXMetricManager.shared.add(metrics)

      // CI only: `-AstraDemo YES -AstraDemoCrash YES` crashes a few seconds in,
      // so the next launch's screenshot shows a real report.
      if Demo.isOn, UserDefaults.standard.bool(forKey: "AstraDemoCrash") {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { Self.demoCrash() }
      }
    }

    /// The person closed the report: it is gone for good.
    func dismiss() {
      pending = nil
      try? FileManager.default.removeItem(at: report)
    }

    // MARK: - Reading what the handlers wrote

    private func collectRawLogs() -> String? {
      let signal = try? String(contentsOf: signalLog, encoding: .utf8)
      let exception = try? String(contentsOf: exceptionLog, encoding: .utf8)
      try? FileManager.default.removeItem(at: signalLog)
      try? FileManager.default.removeItem(at: exceptionLog)
      guard signal != nil || exception != nil else { return nil }

      var parts: [String] = []
      // The handler wrote the time as Unix seconds; show it readably.
      if let signal {
        parts.append(signal.components(separatedBy: "\n").map(Self.readableTime).joined(separator: "\n"))
      }
      if let exception { parts.append(exception) }
      return "Astra crashed\n\n" + parts.joined(separator: "\n")
    }

    private static func readableTime(_ line: String) -> String {
      guard line.hasPrefix("Time: "), let seconds = TimeInterval(line.dropFirst(6)) else { return line }
      return "Time: " + stamp(Date(timeIntervalSince1970: seconds))
    }

    // MARK: - MetricKit

    private static let shownKey = "AstraCrashShownAt"

    private func receive(metricKit text: String, range: ClosedRange<Date>) {
      let section = "\n\n--- Apple's crash report (MetricKit)\n" + text
      if let pending {
        // The report on screen gets Apple's view of the same crash.
        self.pending = String((pending + section).prefix(200_000))
      } else {
        // Already shown from Astra's own handler: don't bring the same crash back.
        let shown = UserDefaults.standard.double(forKey: Self.shownKey)
        if shown > 0, shown >= range.lowerBound.timeIntervalSince1970 { return }
        self.pending = "Astra crashed" + section
      }
      try? self.pending?.write(to: report, atomically: true, encoding: .utf8)
    }

    // MARK: - Header (built at launch, written by the signal handler as is)

    private static func header() -> String {
      let info = Bundle.main.infoDictionary ?? [:]
      let version = info["CFBundleShortVersionString"] as? String ?? "?"
      let build = info["CFBundleVersion"] as? String ?? "?"
      let image = CrashSignals.mainImage()
      return """
        Version: \(version) (\(build))
        OS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        Device: \(deviceModel())
        Launched: \(stamp(Date()))
        Binary: Astra \(image.base) UUID \(image.uuid)

        """
    }

    private static func deviceModel() -> String {
      #if os(iOS)
        let key = "hw.machine"
      #else
        let key = "hw.model"
      #endif
      var size = 0
      sysctlbyname(key, nil, &size, nil, 0)
      guard size > 0 else { return "?" }
      var chars = [CChar](repeating: 0, count: size)
      sysctlbyname(key, &chars, &size, nil, 0)
      return String(cString: chars)
    }

    nonisolated static func stamp(_ date: Date) -> String {
      let f = DateFormatter()
      f.locale = Locale(identifier: "en_US_POSIX")
      f.dateFormat = "yyyy-MM-dd HH:mm:ss ZZZ"
      return f.string(from: date)
    }

    nonisolated private static func demoCrash() {
      let empty: [Int] = []
      _ = empty[Int(Date().timeIntervalSince1970) % 2 + 1]
    }
  }

  // MARK: - MetricKit subscriber

  private final class MetricsSubscriber: NSObject, MXMetricManagerSubscriber {
    var onCrash: (@MainActor (String, ClosedRange<Date>) -> Void)?

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
      for payload in payloads {
        guard let crashes = payload.crashDiagnostics, !crashes.isEmpty else { continue }
        let text = crashes.map(Self.describe).joined(separator: "\n\n")
        let begin = payload.timeStampBegin
        let range = begin...max(begin, payload.timeStampEnd)
        DispatchQueue.main.async { [onCrash] in
          MainActor.assumeIsolated { onCrash?(text, range) }
        }
      }
    }

    private static func describe(_ crash: MXCrashDiagnostic) -> String {
      var lines: [String] = []
      lines.append("Version: \(crash.applicationVersion) (\(crash.metaData.applicationBuildVersion))")
      lines.append("OS: \(crash.metaData.osVersion) · \(crash.metaData.deviceType)")
      if let type = crash.exceptionType { lines.append("Exception type: \(type)") }
      if let code = crash.exceptionCode { lines.append("Exception code: \(code)") }
      if let signal = crash.signal { lines.append("Signal: \(signal)") }
      if let reason = crash.terminationReason { lines.append("Termination: \(reason)") }
      if let region = crash.virtualMemoryRegionInfo { lines.append("Memory: \(region)") }
      if #available(iOS 17.0, macOS 14.0, *), let ex = crash.exceptionReason {
        lines.append("Reason: \(ex.exceptionName) \(ex.composedMessage)")
      }
      lines.append("Crashed thread:")
      lines.append(contentsOf: crashedFrames(crash.callStackTree.jsonRepresentation()))
      return lines.joined(separator: "\n")
    }

    /// The crashed thread's frames as "Astra + 954076" lines.
    private static func crashedFrames(_ json: Data) -> [String] {
      guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
        let stacks = root["callStacks"] as? [[String: Any]]
      else { return ["(no call stack)"] }
      let stack = stacks.first { ($0["threadAttributed"] as? Bool) == true } ?? stacks.first
      var frames: [String] = []
      var level = stack?["callStackRootFrames"] as? [[String: Any]]
      while let frame = level?.first, frames.count < 80 {
        let name = frame["binaryName"] as? String ?? "?"
        let offset = frame["offsetIntoBinaryTextSegment"] as? Int ?? 0
        let uuid = frame["binaryUUID"] as? String ?? ""
        frames.append("\(frames.count)  \(name) + \(offset)" + (name == "Astra" ? "  \(uuid)" : ""))
        level = frame["subFrames"] as? [[String: Any]]
      }
      return frames.isEmpty ? ["(no frames)"] : frames
    }
  }

  // MARK: - Signal and exception handlers

  /// Written for the moment of a crash: no allocation, no locks, only
  /// async-signal-safe calls (open, write, close, backtrace_symbols_fd) on
  /// buffers made at launch.
  enum CrashSignals {
    nonisolated(unsafe) fileprivate static var path: UnsafeMutablePointer<CChar>?
    nonisolated(unsafe) fileprivate static var exceptionPath = ""
    nonisolated(unsafe) fileprivate static var header: UnsafeMutablePointer<CChar>?
    nonisolated(unsafe) fileprivate static var headerLength = 0
    nonisolated(unsafe) fileprivate static var frames: UnsafeMutablePointer<UnsafeMutableRawPointer?>?
    nonisolated(unsafe) fileprivate static var number: UnsafeMutablePointer<CChar>?
    nonisolated(unsafe) fileprivate static var previous: UnsafeMutablePointer<sigaction>?

    static let watched: [Int32] = [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGTRAP, SIGFPE, SIGSYS]
    static let frameCapacity: Int32 = 128

    static func install(path logPath: String, exceptionPath exPath: String, header text: String) {
      path = strdup(logPath)
      exceptionPath = exPath
      header = strdup(text)
      headerLength = strlen(header!)
      frames = .allocate(capacity: Int(frameCapacity))
      number = .allocate(capacity: 32)
      previous = .allocate(capacity: 32)
      previous!.initialize(repeating: sigaction(), count: 32)

      // Room to run even when the crash is a stack overflow.
      let stackSize = 256 * 1024
      if let stack = malloc(stackSize) {
        var alt = stack_t(ss_sp: stack, ss_size: stackSize, ss_flags: 0)
        sigaltstack(&alt, nil)
      }

      for sig in watched {
        var action = sigaction()
        action.__sigaction_u = __sigaction_u(__sa_sigaction: astraCrashSignal)
        action.sa_flags = SA_SIGINFO | SA_ONSTACK
        sigemptyset(&action.sa_mask)
        sigaction(sig, &action, previous! + Int(sig))
      }

      NSSetUncaughtExceptionHandler { exception in
        let text = """
          Exception: \(exception.name.rawValue)
          Reason: \(exception.reason ?? "")
          \(exception.callStackSymbols.joined(separator: "\n"))

          """
        try? text.write(toFile: CrashSignals.exceptionPath, atomically: false, encoding: .utf8)
      }
    }

    /// Astra's load address and build UUID, so frame offsets can be matched to this build.
    static func mainImage() -> (base: String, uuid: String) {
      guard let header = _dyld_get_image_header(0) else { return ("?", "?") }
      let base = "0x" + String(UInt(bitPattern: header), radix: 16)
      var command = UnsafeRawPointer(header).advanced(by: MemoryLayout<mach_header_64>.size)
      for _ in 0..<header.pointee.ncmds {
        let load = command.assumingMemoryBound(to: load_command.self).pointee
        if load.cmd == LC_UUID {
          let uuid = command.assumingMemoryBound(to: uuid_command.self).pointee.uuid
          return (base, UUID(uuid: uuid).uuidString)
        }
        command = command.advanced(by: Int(load.cmdsize))
      }
      return (base, "?")
    }

    fileprivate static func name(_ sig: Int32) -> StaticString {
      switch sig {
      case SIGABRT: return "SIGABRT (abort)"
      case SIGSEGV: return "SIGSEGV (bad memory access)"
      case SIGBUS: return "SIGBUS (bad memory access)"
      case SIGILL: return "SIGILL (illegal instruction)"
      case SIGTRAP: return "SIGTRAP (Swift runtime error)"
      case SIGFPE: return "SIGFPE (arithmetic error)"
      case SIGSYS: return "SIGSYS (bad system call)"
      default: return "signal"
      }
    }
  }

  private func put(_ fd: Int32, _ text: StaticString) {
    _ = write(fd, text.utf8Start, text.utf8CodeUnitCount)
  }

  /// Writes a number without allocating (decimal, or hex with "0x").
  private func put(_ fd: Int32, number: UInt, hex: Bool = false) {
    guard let buffer = CrashSignals.number else { return }
    let radix: UInt = hex ? 16 : 10
    var value = number
    var i = 31
    repeat {
      let digit = Int(value % radix)
      buffer[i] = CChar(digit < 10 ? 48 + digit : 87 + digit)
      value /= radix
      i -= 1
    } while value > 0 && i > 2
    if hex {
      buffer[i] = CChar(120)  // x
      buffer[i - 1] = CChar(48)  // 0
      i -= 2
    }
    _ = write(fd, buffer + i + 1, 31 - i)
  }

  private func astraCrashSignal(
    _ sig: Int32, _ info: UnsafeMutablePointer<__siginfo>?, _ context: UnsafeMutableRawPointer?
  ) {
    if let path = CrashSignals.path {
      let fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
      if fd >= 0 {
        if let header = CrashSignals.header { _ = write(fd, header, CrashSignals.headerLength) }
        put(fd, "Signal: ")
        put(fd, CrashSignals.name(sig))
        put(fd, "\nTime: ")
        put(fd, number: UInt(max(0, time(nil))))
        if let address = info?.pointee.si_addr {
          put(fd, "\nAddress: ")
          put(fd, number: UInt(bitPattern: address), hex: true)
        }
        put(fd, "\nIs main thread: ")
        put(fd, pthread_main_np() == 1 ? "yes" : "no")
        put(fd, "\n\nCrashed thread:\n")
        if let frames = CrashSignals.frames {
          let count = backtrace(frames, CrashSignals.frameCapacity)
          backtrace_symbols_fd(frames, count, fd)
        }
        close(fd)
      }
    }
    // Hand the crash on (the system's crash report and TestFlight still get it).
    if let previous = CrashSignals.previous {
      sigaction(sig, previous + Int(sig), nil)
    } else {
      signal(sig, SIG_DFL)
    }
    raise(sig)
  }
#endif
