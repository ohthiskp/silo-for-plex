import Foundation

#if canImport(FoundationXML)
  import FoundationXML
#endif

/// Reads an XMLTV guide: `<programme start="20261116180000 +0000"
/// stop="…" channel="id"><title>…</title><desc>…</desc><icon src="…"/>`.
public final class XMLTVParser: NSObject, XMLParserDelegate {
  private var programs: [LiveProgram] = []
  private var current: (channel: String, start: Date, end: Date)?
  private var title = ""
  private var summary = ""
  private var image: URL?
  private var text = ""
  private var inTitle = false
  private var inDesc = false
  private let window: (from: Date, to: Date)?
  private let channels: Set<String>?

  /// `window` and `channels` drop programmes nobody will see while parsing,
  /// so a big guide doesn't fill memory.
  public static func parse(_ data: Data, from: Date? = nil, to: Date? = nil, channels: Set<String>? = nil) -> [LiveProgram] {
    let delegate = XMLTVParser(window: from.flatMap { f in to.map { (f, $0) } }, channels: channels)
    let parser = XMLParser(data: data)
    parser.delegate = delegate
    parser.shouldResolveExternalEntities = false
    parser.parse()
    return delegate.programs
  }

  private init(window: (Date, Date)?, channels: Set<String>?) {
    self.window = window
    self.channels = channels
  }

  public func parser(
    _ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
    attributes: [String: String] = [:]
  ) {
    switch name {
    case "programme":
      guard let channel = attributes["channel"], let start = attributes["start"].flatMap(Self.date),
        let end = attributes["stop"].flatMap(Self.date) ?? attributes["start"].flatMap(Self.date)?.addingTimeInterval(1800)
      else {
        current = nil
        return
      }
      if let window, end <= window.from || start >= window.to {
        current = nil
        return
      }
      if let channels, !channels.contains(channel.lowercased()) {
        current = nil
        return
      }
      current = (channel, start, end)
      title = ""
      summary = ""
      image = nil
    case "title" where current != nil:
      inTitle = true
      text = ""
    case "desc" where current != nil:
      inDesc = true
      text = ""
    case "icon" where current != nil:
      image = attributes["src"].flatMap(URL.init(string:))
    default:
      break
    }
  }

  public func parser(_ parser: XMLParser, foundCharacters string: String) {
    if inTitle || inDesc { text += string }
  }

  public func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
    switch name {
    case "title" where inTitle:
      if title.isEmpty { title = text.trimmingCharacters(in: .whitespacesAndNewlines) }
      inTitle = false
    case "desc" where inDesc:
      if summary.isEmpty { summary = text.trimmingCharacters(in: .whitespacesAndNewlines) }
      inDesc = false
    case "programme":
      if let current, !title.isEmpty {
        programs.append(
          LiveProgram(
            channel: current.channel, title: title, start: current.start, end: current.end,
            summary: summary.isEmpty ? nil : summary, image: image))
      }
      current = nil
    default:
      break
    }
  }

  /// "20261116180000 +0000", "20261116180000 -0600" or "20261116180000" (UTC).
  static func date(_ text: String) -> Date? {
    let parts = text.trimmingCharacters(in: .whitespaces).split(separator: " ")
    guard let stamp = parts.first, stamp.count >= 12 else { return nil }
    let digits = Array(stamp.prefix(14))
    guard digits.allSatisfy(\.isNumber) else { return nil }
    func number(_ from: Int, _ length: Int) -> Int? {
      guard from + length <= digits.count else { return nil }
      return Int(String(digits[from..<(from + length)]))
    }
    guard let year = number(0, 4), let month = number(4, 2), let day = number(6, 2), let hour = number(8, 2),
      let minute = number(10, 2)
    else { return nil }
    let second = number(12, 2) ?? 0
    var offset = 0
    if parts.count > 1 {
      let zone = Array(parts[1])
      if zone.count == 5, let h = Int(String(zone[1...2])), let m = Int(String(zone[3...4])) {
        offset = (h * 3600 + m * 60) * (zone[0] == "-" ? -1 : 1)
      }
    }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
    return calendar.date(from: components).map { $0.addingTimeInterval(TimeInterval(-offset)) }
  }
}
