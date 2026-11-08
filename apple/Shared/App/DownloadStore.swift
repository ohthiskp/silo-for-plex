import AstraKit
import Foundation
import Observation

/// Saves original files for offline viewing and plays them back from disk.
///
/// Files are downloaded exactly as the server stores them (`?download=1` on
/// the part), never transcoded. They live in Application Support/Astra/Downloads
/// with an `index.json` listing them. Two downloads run at a time; the rest wait.
@MainActor
@Observable
final class DownloadStore {
  enum State: Equatable {
    case none
    case queued
    case downloading(Double)
    case done
    case failed(String)
  }

  struct Job: Identifiable, Equatable, Codable {
    var record: DownloadRecord
    var partKey: String
    /// The server it comes from, so a saved queue only resumes on that server.
    var serverID: String?
    var fraction: Double = 0
    /// Bytes received so far (shown even when the total is unknown).
    var received: Int64?
    /// Bytes per second, smoothed; nil until measured.
    var speed: Double?
    var running = false
    var id: String { record.ratingKey }
  }

  private(set) var index: DownloadIndex
  private(set) var jobs: [Job] = []
  /// Downloads that stopped, with why; shown on the Downloads page with Retry.
  private(set) var failed: [String: (job: Job, reason: String)] = [:]
  var lastError: String?
  /// The connected server's Plex id (see `attach`).
  @ObservationIgnored private var serverID: String?
  /// Partial data from a failed transfer, so Retry continues instead of starting over.
  @ObservationIgnored private var resumeData: [String: Data] = [:]
  @ObservationIgnored private let queueURL: URL

  let folder: URL
  @ObservationIgnored private let indexURL: URL
  @ObservationIgnored private let session: DownloadSession
  @ObservationIgnored weak var library: LibraryStore?
  /// The server each job was queued from, so a server switch can't send a
  /// queued job's request to a different server.
  @ObservationIgnored private var jobClients: [String: PlexServerClient] = [:]

  private static let maxConcurrent = 2

  init() {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    folder = base.appendingPathComponent("Astra/Downloads", isDirectory: true)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    #if os(iOS)
      // Large video files don't belong in iCloud backups.
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      var url = folder
      try? url.setResourceValues(values)
    #endif
    indexURL = folder.appendingPathComponent("index.json")
    queueURL = folder.appendingPathComponent("queue.json")
    index = DownloadIndex.load(from: indexURL)
    session = DownloadSession()
    // Forget records whose file was deleted outside Astra.
    for record in index.records where !FileManager.default.fileExists(atPath: fileURL(record).path) {
      index.remove(record.ratingKey)
    }
    save()
    // Downloads that were queued or running when Astra quit start again once
    // their server is connected (see attach).
    if let data = try? Data(contentsOf: queueURL), let saved = try? JSONDecoder().decode([Job].self, from: data) {
      jobs = saved.map { var job = $0; job.running = false; job.fraction = 0; return job }
    }
    // QA P2-4: transfers the system carried on while Astra was closed are
    // picked up again by the queued jobs; anything no job wants is stopped.
    session.keepLeftovers(for: Set(jobs.map(\.id)))
  }

  /// Connects the store to a server session; queued downloads from that server carry on.
  func attach(_ library: LibraryStore?, serverID: String?) {
    self.library = library
    self.serverID = serverID
    // Signed out or switching: queued jobs mustn't start with the old server's token.
    for job in jobs where !job.running { jobClients[job.id] = nil }
    guard let library else { return }
    for job in jobs where job.serverID == serverID && jobClients[job.id] == nil {
      jobClients[job.id] = library.client
    }
    pump()
  }

  private func saveQueue() {
    let pending = jobs.map { var job = $0; job.running = false; return job }
    try? JSONEncoder().encode(pending).write(to: queueURL, options: .atomic)
  }

  // MARK: - Queries

  func fileURL(_ record: DownloadRecord) -> URL { folder.appendingPathComponent(record.fileName) }

  func imageURL(_ record: DownloadRecord) -> URL? {
    record.imageName.map { folder.appendingPathComponent($0) }
  }

  func record(for ratingKey: String) -> DownloadRecord? { index.record(ratingKey) }

  func state(for ratingKey: String) -> State {
    if index.record(ratingKey) != nil { return .done }
    if let job = jobs.first(where: { $0.id == ratingKey }) { return job.running ? .downloading(job.fraction) : .queued }
    if let failure = failed[ratingKey] { return .failed(failure.reason) }
    return .none
  }

  /// A show's or season's state across its episodes: done when every
  /// episode is saved, downloading while any is in progress.
  func state(forEpisodesOf parent: PlexMetadata) -> State {
    let belongs = { (record: DownloadRecord) in Self.belongs(record, to: parent) }
    let saved = index.records.filter(belongs)
    let active = jobs.filter { belongs($0.record) }
    if !active.isEmpty {
      let total = Double(active.count + saved.count)
      return .downloading((active.reduce(0) { $0 + $1.fraction } + Double(saved.count)) / max(total, 1))
    }
    if let leafCount = parent.leafCount, leafCount > 0, saved.count >= leafCount { return .done }
    return .none
  }

  /// Settings → Downloads → Storage Used.
  var storageUsed: Int64 { index.totalBytes }

  var hasAnything: Bool { !index.records.isEmpty || !jobs.isEmpty || !failed.isEmpty }

  /// Failed downloads, by title.
  var failedList: [(job: Job, reason: String)] {
    failed.values.sorted { $0.job.record.displayTitle < $1.job.record.displayTitle }
  }

  // MARK: - Actions

  /// Downloads a movie or episode, or every episode of a show or season.
  func download(_ item: PlexMetadata) {
    guard let library else { return }
    let client = library.client
    Task {
      do {
        let resolved = try await library.resolve(item)
        var targets: [PlexMetadata] = []
        switch resolved.type {
        case .movie, .episode:
          targets = [resolved]
        case .season:
          targets = try await library.children(of: resolved.ratingKey).filter { $0.type == .episode }
        case .show:
          for season in try await library.children(of: resolved.ratingKey) where season.type == .season {
            targets += try await library.children(of: season.ratingKey).filter { $0.type == .episode }
          }
        default:
          throw PlexError.nothingToPlay
        }
        for target in targets where state(for: target.ratingKey) == .none || isFailed(target.ratingKey) {
          var full = target
          if full.media.isEmpty { full = try await library.details(target.ratingKey, refresh: true) }
          guard let made = DownloadRecord.make(for: full, quality: .current()) else { continue }
          // A second tap may have queued it while details loaded.
          if index.record(made.record.ratingKey) != nil || jobs.contains(where: { $0.id == made.record.ratingKey }) {
            continue
          }
          failed[full.ratingKey] = nil
          jobs.append(Job(record: made.record, partKey: made.partKey, serverID: serverID))
          jobClients[made.record.ratingKey] = client
          Task { await saveImage(for: full, record: made.record) }
        }
        saveQueue()
        pump()
      } catch {
        lastError = "\(item.displayTitle) didn't download: \(PlexError.describe(error, server: client.serverName))"
      }
    }
  }

  /// Tries a failed download again, continuing from where it stopped when possible.
  func retry(_ ratingKey: String) {
    guard let entry = failed.removeValue(forKey: ratingKey) else { return }
    var job = entry.job
    job.running = false
    job.fraction = 0
    jobs.append(job)
    if jobClients[job.id] == nil, job.serverID == serverID { jobClients[job.id] = library?.client }
    saveQueue()
    pump()
  }

  /// Forgets a failed download.
  func dismissFailure(_ ratingKey: String) {
    failed[ratingKey] = nil
    resumeData[ratingKey] = nil
    jobClients[ratingKey] = nil
    try? FileManager.default.removeItem(at: folder.appendingPathComponent("\(DownloadRecord.safeName(ratingKey)).jpg"))
  }

  func cancel(_ ratingKey: String) {
    guard let job = jobs.first(where: { $0.id == ratingKey }) else { return }
    if job.running { session.cancel(ratingKey) }
    jobs.removeAll { $0.id == ratingKey }
    if !job.running { removeParts(job.record) }
    jobClients[ratingKey] = nil
    resumeData[ratingKey] = nil
    saveQueue()
    pump()
  }

  /// Cancels every active download of a show's episodes.
  func cancelEpisodes(of parent: PlexMetadata) {
    for job in jobs where Self.belongs(job.record, to: parent) { cancel(job.id) }
  }

  static func belongs(_ record: DownloadRecord, to parent: PlexMetadata) -> Bool {
    switch parent.type {
    case .show: record.showRatingKey == parent.ratingKey
    case .season: record.showRatingKey == parent.parentRatingKey && record.seasonNumber == parent.index
    default: false
    }
  }

  func delete(_ ratingKey: String) {
    guard let record = index.remove(ratingKey) else { return cancel(ratingKey) }
    try? FileManager.default.removeItem(at: fileURL(record))
    if let image = imageURL(record) { try? FileManager.default.removeItem(at: image) }
    save()
  }

  func deleteEpisodes(of parent: PlexMetadata) {
    for record in index.records where Self.belongs(record, to: parent) { delete(record.ratingKey) }
  }

  /// Plays from disk; the saved position is the server's when online, else the start.
  func source(for item: PlexMetadata) -> PlaybackSource? {
    guard let record = index.record(item.ratingKey) else { return nil }
    let file = fileURL(record)
    guard FileManager.default.fileExists(atPath: file.path) else { return nil }
    return PlaybackResolver.local(record, fileURL: file, resumeMs: item.viewOffset)
  }

  // MARK: - Queue

  private func isFailed(_ key: String) -> Bool {
    if case .failed = state(for: key) { return true }
    return false
  }

  private func pump() {
    // Only jobs whose server is connected can run.
    while jobs.filter(\.running).count < Self.maxConcurrent,
      let i = jobs.firstIndex(where: { !$0.running && jobClients[$0.id] != nil })
    {
      guard let client = jobClients[jobs[i].id] else { return }
      jobs[i].running = true
      let job = jobs[i]
      var request = PlaybackResolver.downloadRequest(partKey: job.partKey, client: client)
      // Settings → Downloads → Wi-Fi Only: the transfer waits off cellular.
      request.allowsCellularAccess = !UserDefaults.standard.bool(forKey: Preferences.wifiOnlyKey)
      let destination = fileURL(job.record)
      let resume = resumeData.removeValue(forKey: job.id)
      let segmented = resume == nil && (job.record.bytes ?? 0) >= DownloadSegments.minimumBytes
      // Astra: say so up front when the file can't fit, instead of failing late.
      // Segmented: the parts, plus one part while they are joined (QA P1-3).
      if let needed = spaceNeeded(job.record, destination: destination, segmented: segmented),
        let free = freeSpace(), needed > free
      {
        let reason =
          "Not enough space: it needs \(ByteCountFormatter.string(fromByteCount: needed, countStyle: .file)), "
          + "\(ByteCountFormatter.string(fromByteCount: free, countStyle: .file)) is free."
        jobs.remove(at: i)
        if let resume { resumeData[job.id] = resume }  // Retry after freeing space continues.
        failed[job.id] = (job, reason)
        lastError = "\(job.record.displayTitle) didn't download: \(reason)"
        saveQueue()
        continue
      }
      // Astra: big files over several connections at once (faster on most servers).
      if segmented, let total = job.record.bytes {
        Task {
          do {
            try await downloadInSegments(job, request: request, total: total, to: destination)
            finish(job, error: nil)
          } catch {
            session.cancel(job.id)
            finish(job, error: error)
          }
        }
        continue
      }
      Task {
        do {
          try await session.download(
            request, id: job.id, to: destination, expectedBytes: job.record.bytes, resumeData: resume,
            progress: { [weak self] fraction, written in
              Task { @MainActor in self?.setProgress(fraction, written: written, for: job.id) }
            })
          finish(job, error: nil)
        } catch {
          finish(job, error: error)
        }
      }
    }
  }

  /// Connections per large download.
  /// Eight: a remote server over the internet sends each connection at its
  /// own pace, so more connections fill a fast line (KP: "way faster").
  private static let segmentCount = 8
  @ObservationIgnored private var segmentWritten: [String: [Int: Int64]] = [:]

  private func partURL(_ destination: URL, _ i: Int) -> URL {
    destination.deletingLastPathComponent().appendingPathComponent(destination.lastPathComponent + ".part\(i)")
  }

  /// Fetches the file as `segmentCount` byte ranges in parallel, then joins
  /// them. Parts already complete from an earlier try are kept, so Retry
  /// continues. A server that ignores ranges falls back to one connection.
  private func downloadInSegments(_ job: Job, request: URLRequest, total: Int64, to destination: URL) async throws {
    guard await Self.supportsRanges(request) else {
      return try await session.download(
        request, id: job.id, to: destination, expectedBytes: total, resumeData: nil,
        progress: { [weak self] fraction, written in
          Task { @MainActor in self?.setProgress(fraction, written: written, for: job.id) }
        })
    }
    let ranges = DownloadSegments.ranges(total: total, count: Self.segmentCount)
    segmentWritten[job.id] = [:]
    defer { segmentWritten[job.id] = nil }
    try await withThrowingTaskGroup(of: Void.self) { group in
      for (i, range) in ranges.enumerated() {
        let part = partURL(destination, i)
        let length = range.upperBound - range.lowerBound + 1
        if Self.size(of: part) == length {
          segmentWritten[job.id]?[i] = length
          continue
        }
        var ranged = request
        ranged.setValue(DownloadSegments.header(range), forHTTPHeaderField: "Range")
        let segmentRequest = ranged
        group.addTask { [session] in
          try await session.download(
            segmentRequest, id: "\(job.id)#\(i)", to: part, expectedBytes: length, resumeData: nil,
            progress: { [weak self] _, written in
              Task { @MainActor in self?.segmentProgress(job.id, part: i, written: written, total: total) }
            })
          guard Self.size(of: part) == length else {
            throw DownloadCheck.Failure.incomplete(got: Self.size(of: part) ?? 0, expected: length)
          }
        }
      }
      do {
        while try await group.next() != nil {}
      } catch {
        // The other connections stop too (the group waits for them otherwise).
        session.cancel(job.id)
        throw error
      }
    }
    let parts = ranges.indices.map { partURL(destination, $0) }
    try await Task.detached(priority: .utility) {
      try Self.join(parts, into: destination)
    }.value
  }

  private func segmentProgress(_ id: String, part: Int, written: Int64, total: Int64) {
    segmentWritten[id]?[part] = written
    let sum = segmentWritten[id]?.values.reduce(0, +) ?? written
    setProgress(Double(sum) / Double(total), written: sum, for: id)
  }

  /// Asks for the first byte: a 206 means the server sends ranges.
  private nonisolated static func supportsRanges(_ request: URLRequest) async -> Bool {
    var probe = request
    probe.setValue("bytes=0-0", forHTTPHeaderField: "Range")
    probe.timeoutInterval = 15
    // QA P2-5: read only the answer's headers. A server that ignores Range
    // answers 200 with the whole file, which `data(for:)` would have read
    // into memory; the transfer is cancelled as soon as the status is known.
    guard let (bytes, response) = try? await URLSession.shared.bytes(for: probe) else { return false }
    bytes.task.cancel()
    return (response as? HTTPURLResponse)?.statusCode == 206
  }

  private nonisolated static func size(of url: URL) -> Int64? {
    (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
  }

  /// Joins the parts into `destination`: the first part becomes the file
  /// and each later one is appended, then deleted. Copying every part into
  /// a new file needed twice the file's size free, so a big 4K original
  /// that fit the space check could still fail at the very end.
  private nonisolated static func join(_ parts: [URL], into destination: URL) throws {
    guard let first = parts.first else { return }
    try? FileManager.default.removeItem(at: destination)
    try FileManager.default.moveItem(at: first, to: destination)
    let out = try FileHandle(forWritingTo: destination)
    defer { try? out.close() }
    try out.seekToEnd()
    for part in parts.dropFirst() {
      let input = try FileHandle(forReadingFrom: part)
      while let chunk = try input.read(upToCount: 8 << 20), !chunk.isEmpty {
        try out.write(contentsOf: chunk)
      }
      try? input.close()
      try? FileManager.default.removeItem(at: part)
    }
  }

  /// Bytes of free space `record` needs before it starts; nil when its size is unknown.
  private func spaceNeeded(_ record: DownloadRecord, destination: URL, segmented: Bool) -> Int64? {
    guard let total = record.bytes else { return nil }
    guard segmented else { return total }
    let onDisk = (0..<Self.segmentCount).compactMap { Self.size(of: partURL(destination, $0)) }.reduce(0, +)
    return DownloadSegments.spaceNeeded(total: total, count: Self.segmentCount, alreadyOnDisk: onDisk)
  }

  /// Removes a download's leftover parts (cancel or delete).
  private func removeParts(_ record: DownloadRecord) {
    let destination = fileURL(record)
    for i in 0..<Self.segmentCount { try? FileManager.default.removeItem(at: partURL(destination, i)) }
  }

  /// Free space on the downloads volume, as the system counts it for files the person asked for.
  private func freeSpace() -> Int64? {
    #if os(iOS)
      let values = try? folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
      return values?.volumeAvailableCapacityForImportantUsage
    #else
      let values = try? folder.resourceValues(forKeys: [.volumeAvailableCapacityKey])
      return values?.volumeAvailableCapacity.map(Int64.init)
    #endif
  }

  @ObservationIgnored private var speedSamples: [String: (time: Date, bytes: Int64)] = [:]

  private func setProgress(_ fraction: Double?, written: Int64, for id: String) {
    guard let i = jobs.firstIndex(where: { $0.id == id }) else { return }
    // The speed, once a second, smoothed (shown as "4.2 MB/s").
    let now = Date()
    if let last = speedSamples[id] {
      let elapsed = now.timeIntervalSince(last.time)
      if elapsed >= 1, written >= last.bytes {
        let rate = Double(written - last.bytes) / elapsed
        jobs[i].speed = jobs[i].speed.map { $0 * 0.6 + rate * 0.4 } ?? rate
        speedSamples[id] = (now, written)
      }
    } else {
      speedSamples[id] = (now, written)
    }
    // Publish whole percents and whole megabytes only, so a fast download doesn't redraw every frame.
    if let fraction, Int(fraction * 100) != Int(jobs[i].fraction * 100) { jobs[i].fraction = fraction }
    if written / 1_000_000 != (jobs[i].received ?? -1) / 1_000_000 { jobs[i].received = written }
  }

  private func finish(_ job: Job, error: Error?) {
    let wasCancelled = !jobs.contains { $0.id == job.id }
    // A retry measures its speed afresh (the old sample's byte count is higher
    // than a restarted download's, so no speed showed until it caught up).
    speedSamples[job.id] = nil
    jobs.removeAll { $0.id == job.id }
    defer { saveQueue() }
    if let error {
      if !wasCancelled, (error as? URLError)?.code != .cancelled {
        let reason =
          (error as? DownloadCheck.Failure)?.errorDescription
          ?? PlexError.describe(error, server: jobClients[job.id]?.serverName)
        if let data = (error as? URLError)?.downloadTaskResumeData { resumeData[job.id] = data }
        failed[job.id] = (job, reason)
        lastError = "\(job.record.displayTitle) didn't download: \(reason)"
      } else {
        jobClients[job.id] = nil
      }
    } else if !wasCancelled {
      jobClients[job.id] = nil
      var record = job.record
      let image = folder.appendingPathComponent("\(DownloadRecord.safeName(record.ratingKey)).jpg")
      if FileManager.default.fileExists(atPath: image.path) { record.imageName = image.lastPathComponent }
      if let size = try? FileManager.default.attributesOfItem(atPath: fileURL(record).path)[.size] as? NSNumber {
        record.bytes = size.int64Value
      }
      index.upsert(record)
      save()
    } else {
      try? FileManager.default.removeItem(at: fileURL(job.record))
      removeParts(job.record)
    }
    pump()
  }

  /// The poster (movies) or still (episodes) for the Downloads page, saved next to the file.
  private func saveImage(for item: PlexMetadata, record: DownloadRecord) async {
    guard let library else { return }
    let url =
      item.type == .episode
      ? library.imageURL(item.thumb, width: 400, height: 225)
      : await library.artworkURL(for: item, .poster, width: 300, height: 450)
    guard let url, let (data, _) = try? await URLSession.shared.data(from: url) else { return }
    let image = folder.appendingPathComponent("\(DownloadRecord.safeName(record.ratingKey)).jpg")
    try? data.write(to: image, options: .atomic)
    if var saved = index.record(record.ratingKey), saved.imageName == nil {
      saved.imageName = image.lastPathComponent
      index.upsert(saved)
      save()
    }
  }

  private func save() {
    try? index.save(to: indexURL)
  }
}

/// A URLSession download with progress, moved into place when complete.
final class DownloadSession: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
  private struct Pending {
    var request: URLRequest
    var started: Date
    var destination: URL
    var expectedBytes: Int64?
    var progress: @Sendable (Double?, Int64) -> Void
    var continuation: CheckedContinuation<Void, Error>
    var moveError: Error?
  }

  private let lock = NSLock()
  private var pending: [Int: Pending] = [:]
  private var taskIDs: [String: Int] = [:]
  private var tasks: [Int: URLSessionDownloadTask] = [:]
  /// iPhone: the system finishes background-session downloads after the app is closed.
  static let backgroundIdentifier = "com.ohthiskp.astra.downloads"
  /// Handed over by the app delegate when iOS wakes Astra for finished downloads.
  nonisolated(unsafe) static var backgroundCompletion: (() -> Void)?

  private lazy var session: URLSession = {
    #if os(iOS)
      // Astra: a background session, so a download keeps going when the phone
      // locks or Astra is in the background (a normal session stops then).
      let config = URLSessionConfiguration.background(withIdentifier: Self.backgroundIdentifier)
      config.sessionSendsLaunchEvents = true
      config.isDiscretionary = false
    #else
      let config = URLSessionConfiguration.default
    #endif
    config.timeoutIntervalForRequest = 60
    config.timeoutIntervalForResource = 60 * 60 * 24
    config.allowsCellularAccess = true
    // Two downloads at a time, eight connections each (DownloadStore.segmentCount):
    // with only 8 here the second download's connections queued behind the first.
    config.httpMaximumConnectionsPerHost = 16
    let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    // QA P2-4: transfers left from an earlier launch (iPhone: the system kept
    // them going while Astra was closed) are kept, by the id in their task
    // description, for the queued job to pick up instead of starting at 0.
    session.getAllTasks { [weak self] tasks in
      guard let self else { return }
      let waiters = self.lock.withLock { () -> [CheckedContinuation<Void, Never>] in
        for case let task as URLSessionDownloadTask in tasks where self.pending[task.taskIdentifier] == nil {
          if let id = task.taskDescription, !id.isEmpty, task.state == .running || task.state == .suspended {
            self.leftoverTasks[id] = task
          } else {
            task.cancel()
          }
        }
        for task in tasks where !(task is URLSessionDownloadTask) { task.cancel() }
        self.leftoversReady = true
        defer { self.readyWaiters = [] }
        return self.readyWaiters
      }
      for waiter in waiters { waiter.resume() }
    }
    return session
  }()

  private enum Leftover { case file(URL), task(URLSessionDownloadTask), none }

  /// Transfers from an earlier launch, by download id ("ratingKey" or "ratingKey#part").
  private var leftoverTasks: [String: URLSessionDownloadTask] = [:]
  /// Files the system finished while nothing in Astra was waiting for them.
  private var leftoverFiles: [String: URL] = [:]
  private var leftoversReady = false
  private var readyWaiters: [CheckedContinuation<Void, Never>] = []

  /// Where finished leftover files wait for their job (Caches, so the system
  /// may reclaim them; the job then downloads again).
  private static let leftoverFolder: URL = {
    let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    let folder = base.appendingPathComponent("Astra/DownloadLeftovers", isDirectory: true)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
  }()

  private static func leftoverURL(_ id: String) -> URL {
    leftoverFolder.appendingPathComponent(id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? id)
  }

  override init() {
    super.init()
    // Files finished by an earlier launch that no job claimed yet.
    let names = (try? FileManager.default.contentsOfDirectory(atPath: Self.leftoverFolder.path)) ?? []
    for name in names {
      guard let id = name.removingPercentEncoding else { continue }
      leftoverFiles[id] = Self.leftoverFolder.appendingPathComponent(name)
    }
    // Create the session now: iOS hands over events for finished background
    // transfers only once a session with the same identifier exists.
    _ = session
  }

  private func waitForLeftovers() async {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      let ready = lock.withLock { () -> Bool in
        if leftoversReady { return true }
        readyWaiters.append(continuation)
        return false
      }
      if ready { continuation.resume() }
    }
  }

  /// Stops leftover transfers and drops leftover files that no queued job
  /// (`ids`, ratingKeys) wants.
  func keepLeftovers(for ids: Set<String>) {
    Task {
      await waitForLeftovers()
      let (tasks, files) = lock.withLock { () -> ([URLSessionDownloadTask], [URL]) in
        func unwanted(_ id: String) -> Bool { !ids.contains(String(id.split(separator: "#").first ?? "")) }
        let tasks = leftoverTasks.filter { unwanted($0.key) }
        let files = leftoverFiles.filter { unwanted($0.key) }
        for key in tasks.keys { leftoverTasks[key] = nil }
        for key in files.keys { leftoverFiles[key] = nil }
        return (Array(tasks.values), Array(files.values))
      }
      for task in tasks { task.cancel() }
      for file in files { try? FileManager.default.removeItem(at: file) }
    }
  }

  func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    DispatchQueue.main.async {
      Self.backgroundCompletion?()
      Self.backgroundCompletion = nil
    }
  }

  func download(
    _ request: URLRequest, id: String, to destination: URL, expectedBytes: Int64?, resumeData: Data?,
    progress: @escaping @Sendable (Double?, Int64) -> Void
  ) async throws {
    await waitForLeftovers()
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      let entry = Pending(
        request: request, started: Date(), destination: destination, expectedBytes: expectedBytes, progress: progress,
        continuation: continuation)
      // QA P2-4: an earlier launch's transfer for this id, finished or still
      // going, is used instead of starting again from 0. Decided under the
      // lock, so it can't race the delegate filing a finished transfer.
      let leftover = lock.withLock { () -> Leftover in
        if let file = leftoverFiles.removeValue(forKey: id) {
          leftoverTasks[id] = nil
          return .file(file)
        }
        if let task = leftoverTasks.removeValue(forKey: id) {
          if resumeData == nil {
            pending[task.taskIdentifier] = entry
            taskIDs[id] = task.taskIdentifier
            tasks[task.taskIdentifier] = task
            return .task(task)
          }
          task.cancel()
        }
        return .none
      }
      switch leftover {
      case .task(let task):
        task.resume()
        return
      case .file(let file):
        let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.int64Value ?? 0
        if DownloadCheck.validate(status: 200, mimeType: nil, fileSize: size, expected: expectedBytes) == nil {
          do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: file, to: destination)
            progress(1, size)
            continuation.resume()
            return
          } catch {}
        }
        try? FileManager.default.removeItem(at: file)
      case .none:
        break
      }
      // Continue a transfer that broke off, when the server allows it.
      let task = resumeData.map { session.downloadTask(withResumeData: $0) } ?? session.downloadTask(with: request)
      // Read back after a relaunch (see the session's getAllTasks).
      task.taskDescription = id
      lock.withLock {
        pending[task.taskIdentifier] = entry
        taskIDs[id] = task.taskIdentifier
        tasks[task.taskIdentifier] = task
      }
      task.resume()
    }
  }

  /// Cancels a download and any of its segments (`id#0`, `id#1`…).
  func cancel(_ id: String) {
    func matches(_ key: String) -> Bool { key == id || key.hasPrefix(id + "#") }
    let (found, files) = lock.withLock { () -> ([URLSessionDownloadTask], [URL]) in
      var found = taskIDs.filter { matches($0.key) }.compactMap { tasks[$0.value] }
      let leftovers = leftoverTasks.filter { matches($0.key) }
      let files = leftoverFiles.filter { matches($0.key) }
      for key in leftovers.keys { leftoverTasks[key] = nil }
      for key in files.keys { leftoverFiles[key] = nil }
      found += leftovers.values
      return (found, Array(files.values))
    }
    for task in found { task.cancel() }
    for file in files { try? FileManager.default.removeItem(at: file) }
  }

  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
  ) {
    guard let entry = lock.withLock({ pending[downloadTask.taskIdentifier] }) else { return }
    let fraction = DownloadCheck.fraction(
      written: totalBytesWritten, reportedTotal: totalBytesExpectedToWrite, expected: entry.expectedBytes)
    entry.progress(fraction, totalBytesWritten)
  }

  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
    // The temporary file is deleted when this returns, so move it now.
    let response = downloadTask.response as? HTTPURLResponse
    // QA P2-4: finished while nothing waited for it (Astra was closed, or the
    // job hasn't picked it up yet): kept for the job, if it looks right.
    let orphan = lock.withLock { () -> String? in
      guard pending[downloadTask.taskIdentifier] == nil, let id = downloadTask.taskDescription, !id.isEmpty else {
        return nil
      }
      leftoverTasks[id] = nil
      let size = (try? FileManager.default.attributesOfItem(atPath: location.path)[.size] as? NSNumber)?.int64Value ?? 0
      guard
        DownloadCheck.validate(
          status: response?.statusCode ?? 0, mimeType: response?.mimeType, fileSize: size, expected: nil) == nil
      else { return nil }
      let kept = Self.leftoverURL(id)
      try? FileManager.default.removeItem(at: kept)
      guard (try? FileManager.default.moveItem(at: location, to: kept)) != nil else { return nil }
      leftoverFiles[id] = kept
      return id
    }
    if orphan != nil { return }
    guard let entry = lock.withLock({ pending[downloadTask.taskIdentifier] }) else { return }
    // Settings → Network shows the download's answer too.
    NetworkLog.shared.record(entry.request, status: response?.statusCode, started: entry.started, error: nil)
    let size = (try? FileManager.default.attributesOfItem(atPath: location.path)[.size] as? NSNumber)?.int64Value ?? 0
    do {
      // The right status, a video rather than an error page, and every byte.
      if let failure = DownloadCheck.validate(
        status: response?.statusCode ?? 0, mimeType: response?.mimeType, fileSize: size,
        expected: entry.expectedBytes)
      {
        throw failure
      }
      try? FileManager.default.removeItem(at: entry.destination)
      try FileManager.default.moveItem(at: location, to: entry.destination)
    } catch {
      lock.withLock { pending[downloadTask.taskIdentifier]?.moveError = error }
    }
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    let entry = lock.withLock { () -> Pending? in
      let entry = pending.removeValue(forKey: task.taskIdentifier)
      tasks[task.taskIdentifier] = nil
      taskIDs = taskIDs.filter { $0.value != task.taskIdentifier }
      // A leftover that ended (failed) before its job came for it.
      if entry == nil, let id = task.taskDescription, leftoverTasks[id]?.taskIdentifier == task.taskIdentifier {
        leftoverTasks[id] = nil
      }
      return entry
    }
    guard let entry else { return }
    if let error {
      NetworkLog.shared.record(
        entry.request, status: (task.response as? HTTPURLResponse)?.statusCode, started: entry.started, error: error)
    }
    if let error = error ?? entry.moveError {
      entry.continuation.resume(throwing: error)
    } else {
      entry.continuation.resume()
    }
  }
}

