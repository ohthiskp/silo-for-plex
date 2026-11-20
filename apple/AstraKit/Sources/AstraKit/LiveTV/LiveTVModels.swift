import Foundation

/// Live TV (KP, 2026-11-16): channels from an IPTV provider, either an
/// Xtream Codes login or an M3U playlist link, with an optional XMLTV guide.
/// This is the one part of Astra that isn't Plex; it only appears once a
/// source is added in Settings → Live TV.
public enum LiveTVSource: Codable, Sendable, Equatable {
  case xtream(server: String, username: String, password: String)
  case m3u(playlist: String, guide: String?)

  /// "tv.example.com" for Settings.
  public var displayHost: String {
    switch self {
    case .xtream(let server, _, _): Self.host(server)
    case .m3u(let playlist, _): Self.host(playlist)
    }
  }

  public var kindTitle: String {
    switch self {
    case .xtream: "Xtream"
    case .m3u: "M3U playlist"
    }
  }

  static func host(_ text: String) -> String {
    URL(string: XtreamClient.normalizedServer(text))?.host() ?? text
  }
}

public struct LiveChannel: Codable, Sendable, Hashable, Identifiable {
  /// Stable for favourites: the Xtream stream id, or the M3U tvg-id / URL.
  public var id: String
  public var name: String
  public var number: Int?
  public var logo: URL?
  /// Category ("Sports", "News"…): Xtream category or M3U group-title.
  public var group: String?
  public var stream: URL
  /// The XMLTV channel id the guide uses.
  public var guideID: String?

  public init(
    id: String, name: String, number: Int? = nil, logo: URL? = nil, group: String? = nil, stream: URL,
    guideID: String? = nil
  ) {
    self.id = id
    self.name = name
    self.number = number
    self.logo = logo
    self.group = group
    self.stream = stream
    self.guideID = guideID
  }
}

public struct LiveProgram: Codable, Sendable, Hashable {
  public var channel: String
  public var title: String
  public var start: Date
  public var end: Date
  public var summary: String?
  public var image: URL?

  public init(channel: String, title: String, start: Date, end: Date, summary: String? = nil, image: URL? = nil) {
    self.channel = channel
    self.title = title
    self.start = start
    self.end = end
    self.summary = summary
    self.image = image
  }

  public func isOn(at date: Date) -> Bool { start <= date && date < end }

  /// 0…1 of the way through at `date`.
  public func progress(at date: Date) -> Double {
    let total = end.timeIntervalSince(start)
    guard total > 0 else { return 0 }
    return min(1, max(0, date.timeIntervalSince(start) / total))
  }

  /// "11 min left", "2h 10m left".
  public func remainingText(at date: Date) -> String {
    let minutes = max(1, Int((end.timeIntervalSince(date) / 60).rounded(.up)))
    if minutes < 60 { return "\(minutes) min left" }
    let hours = minutes / 60
    let rest = minutes % 60
    return rest == 0 ? "\(hours)h left" : "\(hours)h \(rest)m left"
  }
}

/// The guide by XMLTV channel id, each list sorted by start time.
public struct LiveGuide: Sendable, Equatable {
  public private(set) var programs: [String: [LiveProgram]]

  public init(_ programs: [LiveProgram] = []) {
    var byChannel: [String: [LiveProgram]] = [:]
    for program in programs { byChannel[program.channel.lowercased(), default: []].append(program) }
    for key in byChannel.keys { byChannel[key]?.sort { $0.start < $1.start } }
    self.programs = byChannel
  }

  public var isEmpty: Bool { programs.isEmpty }

  /// What's on `channel` now, then the next `count - 1` programmes.
  public func lineup(for channel: LiveChannel, at date: Date, count: Int = 4) -> [LiveProgram] {
    guard let key = (channel.guideID ?? channel.name).nilIfEmpty?.lowercased(), let list = programs[key] else {
      return []
    }
    guard let first = list.firstIndex(where: { $0.end > date }) else { return [] }
    return Array(list[first..<min(list.count, first + count)])
  }

  public func now(on channel: LiveChannel, at date: Date) -> LiveProgram? {
    lineup(for: channel, at: date, count: 1).first.flatMap { $0.isOn(at: date) ? $0 : nil }
  }

  /// Keeps only programmes that end after `from` and start before `to`, for
  /// channels in `ids` (a provider's full guide can be tens of MB).
  public static func trimmed(_ programs: [LiveProgram], from: Date, to: Date, channels ids: Set<String>?) -> [LiveProgram] {
    programs.filter { p in
      p.end > from && p.start < to && (ids?.contains(p.channel.lowercased()) ?? true)
    }
  }
}

/// Category chips: the provider's groups in their first-seen order.
public enum LiveCategories {
  public static func groups(in channels: [LiveChannel], hidden: Set<String> = []) -> [String] {
    var seen = Set<String>()
    var out: [String] = []
    for channel in channels {
      guard let group = channel.group?.nilIfEmpty, !hidden.contains(group), seen.insert(group).inserted else { continue }
      out.append(group)
    }
    return out
  }
}

extension String {
  var nilIfEmpty: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
