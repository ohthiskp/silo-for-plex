import AstraKit
import CryptoKit
import Foundation

/// Files every crash report as an issue in KP's private crash repository, so
/// Claude can read it without KP copying it over (KP, 2026-11-15: "make it so
/// it sends you info auto every time it crashes").
///
/// The token is a fine-grained GitHub token that can only write issues in that
/// one private repository. It comes from the `ASTRA_CRASH_TOKEN` GitHub secret
/// at build time (Info.plist `AstraCrashToken`); a build without it sends
/// nothing. A report that couldn't be sent (offline) is tried again on the
/// next launch, and the same report is never filed twice.
@MainActor
enum CrashUpload {
  static let repository = "ohthiskp/astra-crashes"

  private static let sentKey = "AstraCrashSentReports"
  private static let queuedKey = "AstraCrashQueuedReport"

  private static var token: String? {
    guard let raw = Bundle.main.object(forInfoDictionaryKey: "AstraCrashToken") as? String else { return nil }
    let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    // An unset build setting leaves "" or the literal "$(ASTRA_CRASH_TOKEN)".
    return token.isEmpty || token.hasPrefix("$(") ? nil : token
  }

  /// Sends `report` unless it was sent before. Safe to call again with a
  /// longer copy of the same crash (MetricKit's part added later): that one
  /// is filed too, so nothing Apple adds is lost.
  static func send(_ report: String) {
    guard !Demo.isOn, let token else { return }
    let id = fingerprint(report)
    guard !sent.contains(id) else { return }
    UserDefaults.standard.set(report, forKey: queuedKey)
    Task.detached(priority: .utility) {
      guard await post(report, token: token) else { return }
      await MainActor.run {
        markSent(id)
        if UserDefaults.standard.string(forKey: queuedKey) == report {
          UserDefaults.standard.removeObject(forKey: queuedKey)
        }
      }
    }
  }

  /// A report that couldn't be sent last time (offline, server error).
  static func retryQueued() {
    guard let queued = UserDefaults.standard.string(forKey: queuedKey) else { return }
    send(queued)
  }

  // MARK: - GitHub

  private static func post(_ report: String, token: String) async -> Bool {
    guard let url = URL(string: "https://api.github.com/repos/\(repository)/issues") else { return false }
    let summary = CrashReportText.summary(of: report)
    let version = summary.version ?? "?"
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 30
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    let title = "\(platform) \(version): \(summary.what)" + (summary.place.map { " in \($0)" } ?? "")
    // GitHub's body limit is 65,536 characters.
    let body = "```\n" + String(report.prefix(60_000)) + "\n```\n"
    request.httpBody = try? JSONSerialization.data(withJSONObject: ["title": String(title.prefix(250)), "body": body])
    guard let (_, response) = try? await URLSession.shared.data(for: request),
      let status = (response as? HTTPURLResponse)?.statusCode
    else { return false }
    // 201 = filed. A 4xx other than rate limiting won't get better by retrying.
    return status == 201 || (400..<500).contains(status) && status != 403 && status != 429
  }

  private static var platform: String {
    #if os(macOS)
      "Mac"
    #elseif os(tvOS)
      "Apple TV"
    #else
      "iPhone"
    #endif
  }

  // MARK: - Sent reports

  private static var sent: [String] {
    UserDefaults.standard.stringArray(forKey: sentKey) ?? []
  }

  private static func markSent(_ id: String) {
    UserDefaults.standard.set(Array((sent + [id]).suffix(50)), forKey: sentKey)
  }

  private static func fingerprint(_ report: String) -> String {
    SHA256.hash(data: Data(report.utf8)).map { String(format: "%02x", $0) }.joined()
  }
}
