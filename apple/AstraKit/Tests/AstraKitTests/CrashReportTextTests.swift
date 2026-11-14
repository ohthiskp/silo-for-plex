import XCTest

@testable import AstraKit

final class CrashReportTextTests: XCTestCase {
  /// The report CI's demo crash wrote (run 43294070219), shortened.
  private let report = """
    Astra crashed

    Version: 3.1.0 (1)
    OS: Version 26.4.1 (Build 23E254a)
    Device: arm64
    Launched: 2026-11-12 20:05:10 +0000
    Binary: Astra 0x104b34000 UUID 1B723F3F-01B3-35DB-BC60-1DFBF025C7AA
    Signal: SIGTRAP (Swift runtime error)
    Time: 2026-11-12 20:05:13 +0000
    Address: 0x104b6fd8c
    Is main thread: yes

    Crashed thread:
    0   Astra                               0x0000000104b7111c $s5Astra16astraCrashSignal33_3CEEC496A1D58980F3AE3FE48DF3222FLLyys5Int32V_SpySo9__siginfoVGSgSvSgtFTf4nnd_n + 344
    1   libsystem_platform.dylib            0x0000000109933540 _sigtramp + 52
    2   Astra                               0x0000000104b6fd58 $s5Astra13CrashReporterC04demoB033_3CEEC496A1D58980F3AE3FE48DF3222FLLyyFZTf4d_n + 96
    4   libdispatch.dylib                   0x000000018019fe98 _dispatch_client_callout + 12
    18  Astra                               0x0000000104b4fe5c main + 64
    """

  func testFrameLinesAreSplit() {
    let f = CrashReportText.frame("4   libdispatch.dylib                   0x000000018019fe98 _dispatch_client_callout + 12")
    XCTAssertEqual(f?.image, "libdispatch.dylib")
    XCTAssertEqual(f?.symbol, "_dispatch_client_callout")
    XCTAssertEqual(f?.offset, "12")
    XCTAssertNil(CrashReportText.frame("Version: 3.1.0 (1)"))
  }

  func testSwiftNamesAreShortened() {
    XCTAssertEqual(
      CrashReportText.shorten(
        "function signature specialization <Arg[0] = Dead> of static Astra.CrashReporter.(demoCrash in _3CEEC496A1D58980F3AE3FE48DF3222F)() -> ()"),
      "CrashReporter.demoCrash()")
  }

  func testAstraFramesGetTheirOffsetIntoTheApp() {
    let fake: (String) -> String? = { $0.hasPrefix("$s5Astra13CrashReporter") ? "static Astra.CrashReporter.demoCrash() -> ()" : nil }
    let tidy = CrashReportText.tidy(report, demangle: fake)
    // 0x104b6fd58 - 0x104b34000 = 245080
    XCTAssertTrue(tidy.contains("CrashReporter.demoCrash() + 96  (Astra + 245080)"), tidy)
    // Stripped: "main + 64" is no real name, so only the offset is shown.
    XCTAssertTrue(tidy.contains("Astra + 114268"), tidy)
    XCTAssertTrue(tidy.contains("_dispatch_client_callout + 12"))
    XCTAssertTrue(tidy.contains("Version: 3.1.0 (1)"))
  }

  func testSummaryInPlainWords() {
    let fake: (String) -> String? = { $0.hasPrefix("$s5Astra13CrashReporter") ? "static Astra.CrashReporter.demoCrash() -> ()" : nil }
    let s = CrashReportText.summary(of: CrashReportText.tidy(report, demangle: fake))
    XCTAssertEqual(s.what, "Swift runtime error")
    XCTAssertEqual(s.place, "CrashReporter.demoCrash()")
    XCTAssertEqual(s.onMainThread, true)
    XCTAssertEqual(s.version, "3.1.0 (1)")
    XCTAssertEqual(s.time, Date(timeIntervalSince1970: 1_794_513_913))
  }

  func testExceptionSummary() {
    let s = CrashReportText.summary(of: "Exception: NSInvalidArgumentException\nReason: bad thing\n")
    XCTAssertEqual(s.what, "Uncaught exception (NSInvalidArgumentException)")
    XCTAssertEqual(s.detail, "bad thing")
  }

  func testMetricKitOnlyReport() {
    let s = CrashReportText.summary(
      of: "Astra crashed\n\n--- Apple's crash report (MetricKit)\nSignal: 9\nCrashed thread:\n0  libsystem_kernel.dylib + 12\n1  Astra + 954076  22CEC676\n")
    XCTAssertEqual(s.what, "Stopped by iOS (watchdog or memory)")
    XCTAssertEqual(s.place, "Astra + 954076")
  }

  func testSwiftDemanglerIsReachable() {
    XCTAssertEqual(CrashReportText.swiftDemangle("$sSi"), "Swift.Int")
  }
}
