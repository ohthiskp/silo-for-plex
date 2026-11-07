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
      let request = PlaybackResolver.downloadRequest(partKey: job.partKey, client: client)
      let destination = fileURL(job.record)
      // Astra: say so up front when the file can't fit, instead of failing late.
      if let needed = job.record.bytes, let free = freeSpace(), needed > free {
        let reason =
          "Not enough space: it needs \(ByteCountFormatter.string(fromByteCount: needed, countStyle: .file)), "
          + "\(ByteCountFormatter.string(fromByteCount: free, countStyle: .file)) is free."
        jobs.remove(at: i)
        failed[job.id] = (job, reason)
        lastError = "\(job.record.displayTitle) didn't download: \(reason)"
        saveQueue()
        continue
      }
      let resume = resumeData.removeValue(forKey: job.id)
      // Astra: big files over several connections at once (faster on most servers).
      if resume == nil, let total = job.record.bytes, total >= DownloadSegments.minimumBytes {
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
  private static let segmentCount = 4
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
    guard let (_, response) = try? await URLSession.shared.data(for: probe) else { return false }
    return (response as? HTTPURLResponse)?.statusCode == 206
  }

  private nonisolated static func size(of url: URL) -> Int64? {
    (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
  }

  /// Writes the parts one after another into `destination`, then deletes them.
  private nonisolated static func join(_ parts: [URL], into destination: URL) throws {
    try? FileManager.default.removeItem(at: destination)
    FileManager.default.createFile(atPath: destination.path, contents: nil)
    let out = try FileHandle(forWritingTo: destination)
    defer { try? out.close() }
    for part in parts {
      let input = try FileHandle(forReadingFrom: part)
      defer { try? input.close() }
      while let chunk = try input.read(upToCount: 8 << 20), !chunk.isEmpty {
        try out.write(contentsOf: chunk)
      }
    }
    for part in parts { try? FileManager.default.removeItem(at: part) }
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

  private func setProgress(_ fraction: Double?, written: Int64, for id: String) {
    guard let i = jobs.firstIndex(where: { $0.id == id }) else { return }
    // Publish whole percents and whole megabytes only, so a fast download doesn't redraw every frame.
    if let fraction, Int(fraction * 100) != Int(jobs[i].fraction * 100) { jobs[i].fraction = fraction }
    if written / 1_000_000 != (jobs[i].received ?? -1) / 1_000_000 { jobs[i].received = written }
  }

  private func finish(_ job: Job, error: Error?) {
    let wasCancelled = !jobs.contains { $0.id == job.id }
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
    // Two downloads at a time, four connections each.
    config.httpMaximumConnectionsPerHost = 8
    let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    // Transfers left from an earlier launch have nobody waiting for them; the
    // saved queue starts them again, so stop the leftovers.
    session.getAllTasks { [weak self] tasks in
      guard let self else { return }
      for task in tasks where self.lock.withLock({ self.pending[task.taskIdentifier] == nil }) { task.cancel() }
    }
    return session
  }()

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
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      // Continue a transfer that broke off, when the server allows it.
      let task = resumeData.map { session.downloadTask(withResumeData: $0) } ?? session.downloadTask(with: request)
      lock.withLock {
        pending[task.taskIdentifier] = Pending(
          request: request, started: Date(), destination: destination, expectedBytes: expectedBytes, progress: progress, continuation: continuation)
        taskIDs[id] = task.taskIdentifier
        tasks[task.taskIdentifier] = task
      }
      task.resume()
    }
  }

  /// Cancels a download and any of its segments (`id#0`, `id#1`…).
  func cancel(_ id: String) {
    let found = lock.withLock {
      taskIDs.filter { $0.key == id || $0.key.hasPrefix(id + "#") }.compactMap { tasks[$0.value] }
    }
    for task in found { task.cancel() }
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
    guard let entry = lock.withLock({ pending[downloadTask.taskIdentifier] }) else { return }
    let response = downloadTask.response as? HTTPURLResponse
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

