import Foundation

/// The crash report screen's reading of a report (KP, 2026-11-12/13): a short
/// plain-English summary on top, and crash lines tidied so they can be read.
///
/// The report itself is written by the app's crash handler (`CrashReporter`)
/// with `backtrace_symbols` lines such as
/// `2   Astra   0x0000000104b6fd58 $s5Astra13CrashReporterC... + 96`.
public struct CrashSummary: Equatable, Sendable {
  /// "Swift runtime error", "Bad memory access", "Uncaught exception"...
  public var what: String
  /// The exception's reason or the system's termination reason, when there is one.
  public var detail: String?
  /// Astra's own code nearest the crash ("CrashReporter.demoCrash()" or "Astra + 954076").
  public var place: String?
  public var onMainThread: Bool?
  public var time: Date?
  public var version: String?

  public init(
    what: String, detail: String? = nil, place: String? = nil, onMainThread: Bool? = nil,
    time: Date? = nil, version: String? = nil
  ) {
    self.what = what
    self.detail = detail
    self.place = place
    self.onMainThread = onMainThread
    self.time = time
    self.version = version
  }
}

public enum CrashReportText {
  /// One `backtrace_symbols` line, split up.
  struct Frame: Equatable {
    var index: String
    var image: String
    var address: UInt
    var symbol: String
    var offset: String
  }

  // MARK: - Tidy

  /// Rewrites the crash lines readably: Swift names demangled and shortened,
  /// and Astra's frames given their offset into the app ("Astra + 241240"),
  /// which is what the symbolication workflow needs. Other lines stay as they are.
  public static func tidy(_ report: String, demangle: (String) -> String? = swiftDemangle) -> String {
    let base = imageBase(in: report)
    return report.components(separatedBy: "\n").map { line in
      guard let frame = frame(line) else { return line }
      return tidyLine(frame, base: base, demangle: demangle)
    }.joined(separator: "\n")
  }

  static func tidyLine(_ frame: Frame, base: UInt?, demangle: (String) -> String?) -> String {
    let index = frame.index.padding(toLength: max(3, frame.index.count + 1), withPad: " ", startingAt: 0)
    let image = frame.image.padding(toLength: max(14, frame.image.count + 1), withPad: " ", startingAt: 0)
    let appOffset: String? = {
      guard frame.image == "Astra", let base, frame.address >= base else { return nil }
      return "Astra + \(frame.address - base)"
    }()
    if !hasRealSymbol(frame.symbol) {
      return index + image + (appOffset ?? "0x" + String(frame.address, radix: 16))
    }
    let name = demangle(frame.symbol).map(shorten) ?? frame.symbol
    return index + image + name + " + " + frame.offset + (appOffset.map { "  (\($0))" } ?? "")
  }

  /// Stripped builds have no names: the nearest symbol is the image header, `main`, or nothing.
  static func hasRealSymbol(_ symbol: String) -> Bool {
    !["_mh_execute_header", "<redacted>", "???", "0x0", "main"].contains(symbol)
  }

  static func frame(_ line: String) -> Frame? {
    let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
    // index, image, 0xaddress, symbol..., "+", offset
    guard parts.count >= 6, Int(parts[0]) != nil, parts[2].hasPrefix("0x"),
      let address = UInt(parts[2].dropFirst(2), radix: 16),
      parts[parts.count - 2] == "+", Int(parts[parts.count - 1]) != nil
    else { return nil }
    let symbol = parts[3..<(parts.count - 2)].joined(separator: " ")
    return Frame(index: parts[0], image: parts[1], address: address, symbol: symbol, offset: parts[parts.count - 1])
  }

  /// The app's load address, from the report's "Binary: Astra 0x104b34000 UUID ..." line.
  static func imageBase(in report: String) -> UInt? {
    for line in report.components(separatedBy: "\n") where line.hasPrefix("Binary: Astra 0x") {
      let hex = line.dropFirst("Binary: Astra 0x".count).prefix { $0.isHexDigit }
      return UInt(hex, radix: 16)
    }
    return nil
  }

  /// "function signature specialization <Arg[0] = Dead> of static Astra.CrashReporter.(demoCrash in _3CEE…)() -> ()"
  /// becomes "CrashReporter.demoCrash()".
  public static func shorten(_ name: String) -> String {
    var s = name
    // Specialization prefixes, possibly nested.
    while let r = s.range(of: #"^(\w+ )*specialization <[^>]*> of "#, options: .regularExpression) {
      s.removeSubrange(r)
    }
    for prefix in ["merged ", "static ", "@objc ", "closure #1 in ", "implicit closure #1 in "] where s.hasPrefix(prefix) {
      s.removeFirst(prefix.count)
    }
    s = s.replacingOccurrences(of: #"\((\w+) in _[0-9A-F]+\)"#, with: "$1", options: .regularExpression)
    s = s.replacingOccurrences(of: #" -> .*$"#, with: "", options: .regularExpression)
    if s.hasPrefix("Astra.") { s.removeFirst("Astra.".count) }
    // Long parameter lists say little here.
    s = s.replacingOccurrences(of: #"\(([^()]{40,})\)"#, with: "(…)", options: .regularExpression)
    return s
  }

  // MARK: - Summary

  public static func summary(of report: String) -> CrashSummary {
    let lines = report.components(separatedBy: "\n")
    func value(_ key: String) -> String? {
      lines.first { $0.hasPrefix(key + ": ") }.map { String($0.dropFirst(key.count + 2)) }
    }

    var summary = CrashSummary(what: "Astra quit unexpectedly")
    if let exception = value("Exception") {
      summary.what = "Uncaught exception (\(exception))"
      summary.detail = value("Reason").flatMap { $0.isEmpty ? nil : $0 }
    } else if let signal = value("Signal") {
      summary.what = describe(signal: signal)
    } else if let type = value("Exception type") {
      summary.what = type
    }
    if summary.detail == nil { summary.detail = value("Reason") ?? value("Termination") }
    if let main = value("Is main thread") { summary.onMainThread = main == "yes" }
    summary.version = value("Version")
    if let time = value("Time") ?? value("Launched") { summary.time = date(time) }
    summary.place = place(in: lines)
    return summary
  }

  static func describe(signal: String) -> String {
    let name = signal.split(separator: " ").first.map(String.init) ?? signal
    switch name {
    case "SIGTRAP", "5": return "Swift runtime error"
    case "SIGSEGV", "SIGBUS", "11", "10": return "Bad memory access"
    case "SIGABRT", "6": return "The app stopped itself (abort)"
    case "SIGILL", "4": return "Illegal instruction"
    case "SIGFPE", "8": return "Arithmetic error"
    case "SIGKILL", "9": return "Stopped by iOS (watchdog or memory)"
    default: return "Crash (\(signal))"
    }
  }

  /// Astra's frame nearest the crash, below the crash handler's own frames.
  static func place(in lines: [String]) -> String? {
    // Tidied MetricKit lines: "3  Astra + 954076  UUID".
    var afterHandler = false
    for line in lines {
      if line.contains("_sigtramp") { afterHandler = true; continue }
      if let f = frame(line) ?? tidiedFrame(line) {
        guard afterHandler || !lines.contains(where: { $0.contains("_sigtramp") }) else { continue }
        guard f.image == "Astra" else { continue }
        return placeName(f.symbol)
      }
    }
    return nil
  }

  /// A line `tidy` already rewrote: "2   Astra         CrashReporter.demoCrash() + 96  (Astra + 241240)".
  static func tidiedFrame(_ line: String) -> Frame? {
    let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true).map(String.init)
    guard parts.count == 3, Int(parts[0]) != nil else { return nil }
    var rest = parts[2].trimmingCharacters(in: .whitespaces)
    // MetricKit's "Astra + 954076  <uuid>" lines split the image off.
    if rest.hasPrefix("+ ") { rest = parts[1] + " " + rest }
    // Anything after two spaces is a note: "(Astra + 241240)" or the UUID.
    if let gap = rest.range(of: "  ") { rest = String(rest[..<gap.lowerBound]) }
    return Frame(index: parts[0], image: parts[1], address: 0, symbol: rest, offset: "")
  }

  static func placeName(_ symbol: String) -> String {
    if symbol.hasPrefix("$s") || symbol.hasPrefix("_$s") { return shorten(swiftDemangle(symbol) ?? symbol) }
    // "CrashReporter.demoCrash() + 96" → "CrashReporter.demoCrash()"
    if let r = symbol.range(of: #" \+ \d+$"#, options: .regularExpression), !symbol.hasPrefix("Astra +") {
      return String(symbol[..<r.lowerBound])
    }
    return symbol
  }

  static func date(_ text: String) -> Date? {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd HH:mm:ss ZZZ"
    return f.date(from: text)
  }

  // MARK: - Demangling

  /// Swift's own demangler (in the Swift runtime on every Apple OS).
  public static func swiftDemangle(_ symbol: String) -> String? {
    let mangled = symbol.hasPrefix("_$s") ? String(symbol.dropFirst()) : symbol
    guard mangled.hasPrefix("$s") else { return nil }
    return mangled.withCString { pointer -> String? in
      guard let out = _astraSwiftDemangle(pointer, UInt(strlen(pointer)), nil, nil, 0) else { return nil }
      defer { free(out) }
      return String(cString: out)
    }
  }
}

@_silgen_name("swift_demangle")
private func _astraSwiftDemangle(
  _ mangledName: UnsafePointer<CChar>?, _ mangledNameLength: UInt,
  _ outputBuffer: UnsafeMutablePointer<CChar>?, _ outputBufferSize: UnsafeMutablePointer<UInt>?,
  _ flags: UInt32
) -> UnsafeMutablePointer<CChar>?
