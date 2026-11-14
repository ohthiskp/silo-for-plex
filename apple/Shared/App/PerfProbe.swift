import AstraKit
import Darwin
import Foundation

/// Astra: measurements for the performance report, CI only. Runs only with
/// `-AstraDemo YES -AstraPerf YES` (the demo server); a normal launch never
/// starts it, and `mark`/`count` return at once.
///
/// Every line it writes starts with `ASTRA-PERF` (read by
/// `.github/workflows/astra-swiftui-perf.yml`):
/// - `mark <name> <ms>`: ms since the process started when something first showed.
/// - `value <name> <number>`: a measured duration or count.
/// - `net`, `img`, `cpu`, `main`: totals at each summary.
@MainActor
enum PerfProbe {
  static let isOn = Demo.isOn && UserDefaults.standard.bool(forKey: "AstraPerf")
  /// `-AstraPerfSwitch YES`: also switches streaming tabs to time them.
  static let switches = isOn && UserDefaults.standard.bool(forKey: "AstraPerfSwitch")

  private static var seen: Set<String> = []
  private static var counters: [String: Int] = [:]
  private static var longestStall: Double = 0
  private static var longestStallAt = 0
  private static var stalls = 0

  /// When the process started (the kernel's own record), so cold launch includes dyld and app init.
  nonisolated static let processStart: Date = {
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
    guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return Date() }
    let start = info.kp_proc.p_starttime
    return Date(timeIntervalSince1970: Double(start.tv_sec) + Double(start.tv_usec) / 1_000_000)
  }()

  static func ms(since date: Date = processStart) -> Int { Int(Date().timeIntervalSince(date) * 1000) }

  static func log(_ line: String) {
    NSLog("ASTRA-PERF %@", line)
  }

  /// The first time `name` happens, with ms since the process started.
  static func mark(_ name: String) {
    guard isOn, seen.insert(name).inserted else { return }
    log("mark \(name) \(ms())")
  }

  static func value(_ name: String, _ number: Double) {
    guard isOn else { return }
    log("value \(name) \(Int(number.rounded()))")
  }

  /// Counts how often something runs (a view's body, a rebuild).
  static func count(_ name: String) {
    guard isOn else { return }
    counters[name, default: 0] += 1
  }

  static func start(app: AppModel) {
    guard isOn else { return }
    log("start pid \(getpid())")
    // Main-thread responsiveness: a 16 ms heartbeat; a late beat is a stall.
    Task { @MainActor in
      var last = Date()
      while true {
        try? await Task.pause(0.016)
        let now = Date()
        let gap = now.timeIntervalSince(last) * 1000 - 16
        if gap > longestStall {
          longestStall = gap
          longestStallAt = ms()
        }
        if gap > 100 { stalls += 1 }
        last = now
      }
    }
    // What shows, and when.
    Task { @MainActor in
      while true {
        watch(app)
        try? await Task.pause(0.02)
      }
    }
    // Totals now and then.
    Task { @MainActor in
      for at in [10.0, 20, 30, 40] {
        try? await Task.pause(max(0, at - Date().timeIntervalSince(processStart)))
        await summary(at: Int(at))
      }
    }
    if switches {
      Task { @MainActor in await timeSwitches(app) }
    }
  }

  private static func watch(_ app: AppModel) {
    if app.phase == .ready { mark("app.ready") }
    guard let library = app.library else { return }
    if !library.continueWatching.isEmpty { mark("home.continueWatching") }
    if !library.homeHero.isEmpty, library.selectedService == nil { mark("home.hero") }
    let split = library.homeTopTenSplit
    if !(split.movies.isEmpty && split.shows.isEmpty), library.selectedService == nil { mark("home.topTrending") }
    if !library.homeRecent.isEmpty, !library.homeGreats.isEmpty, library.selectedService == nil {
      mark("home.forYouShelves")
    }
    if library.indexReady { mark("index.inMemory") }
    if library.indexComplete && library.indexTrusted { mark("index.trusted") }
    if app.player.isActive { mark("player.open") }
    if app.player.hasFirstFrame { mark("player.firstFrame") }
  }

  /// A tab not built yet (Hulu is built last in the background), then one built in the background.
  private static func timeSwitches(_ app: AppModel) async {
    while app.library?.homeHero.isEmpty ?? true { try? await Task.pause(0.05) }
    guard let library = app.library else { return }
    func time(_ id: String, _ name: String) async {
      guard let service = StreamingService.byID(id) else { return }
      let started = Date()
      library.select(service)
      while !(library.homeHasSections && !library.homeHero.isEmpty), Date().timeIntervalSince(started) < 20 {
        try? await Task.pause(0.01)
      }
      value("switch.\(name).ms", Date().timeIntervalSince(started) * 1000)
    }
    await time("hulu", "firstVisit")
    library.select(nil)
    try? await Task.pause(max(0, 25 - Date().timeIntervalSince(processStart)))
    await time("netflix", "prebuilt")
    library.select(nil)
  }

  private static func summary(at second: Int) async {
    let events = NetworkLog.shared.recent
    var byHost: [String: Int] = [:]
    var byPath: [String: Int] = [:]
    for event in events {
      byHost[event.host, default: 0] += 1
      byPath["\(event.host)\(pathClass(event.path))", default: 0] += 1
    }
    log("net t=\(second) total=\(events.count) " + byHost.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))
    for (path, n) in byPath.sorted(by: { $0.value > $1.value }) {
      log("path t=\(second) \(n) \(path)")
    }
    let images = await ImagePipeline.shared.stats
    log(
      "img t=\(second) asked=\(images.asked) fetched=\(images.fetched) decoded=\(images.decoded) prefetchedNoDecode=\(images.prefetched) megapixels=\(Int(images.megapixels)) bytesMB=\(images.bytes >> 20)"
    )
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    let cpu = Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) * 1000
      + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1000
    log("cpu t=\(second) ms=\(Int(cpu))")
    log("main t=\(second) longestStallMs=\(Int(longestStall)) endedAtMs=\(longestStallAt) stallsOver100ms=\(stalls)")
    for (name, n) in counters.sorted(by: { $0.key < $1.key }) { log("count t=\(second) \(name)=\(n)") }
  }

  /// "/3/movie/603" → "/3/movie/#": requests grouped by kind, not by title.
  private static func pathClass(_ path: String) -> String {
    let bare = path.split(separator: "?").first.map(String.init) ?? path
    return bare.split(separator: "/").map { $0.allSatisfy(\.isNumber) ? "#" : String($0) }.reduce("") { $0 + "/" + $1 }
  }
}
