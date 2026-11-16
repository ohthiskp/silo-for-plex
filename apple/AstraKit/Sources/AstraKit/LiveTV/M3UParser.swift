import Foundation

/// Reads an IPTV M3U playlist: `#EXTINF:-1 tvg-id="…" tvg-name="…"
/// tvg-logo="…" tvg-chno="…" group-title="…",Name` followed by the stream URL.
public enum M3UParser {
  public struct Result: Sendable, Equatable {
    public var channels: [LiveChannel]
    /// The guide link from the header (`#EXTM3U url-tvg="…"` or `x-tvg-url`).
    public var guide: URL?
  }

  public static func parse(_ text: String) -> Result {
    var channels: [LiveChannel] = []
    var guide: URL?
    var pending: (attrs: [String: String], name: String)?
    var pendingGroup: String?
    var seen = Set<String>()

    for raw in text.split(whereSeparator: \.isNewline) {
      let line = raw.trimmingCharacters(in: .whitespaces)
      if line.isEmpty { continue }
      if line.hasPrefix("#EXTM3U") {
        let attrs = attributes(in: line)
        guide = (attrs["url-tvg"] ?? attrs["x-tvg-url"])
          .flatMap { $0.split(separator: ",").first.map(String.init) }
          .flatMap { URL(string: $0.trimmingCharacters(in: .whitespaces)) }
      } else if line.hasPrefix("#EXTINF") {
        let comma = commaOutsideQuotes(line)
        let head = comma.map { String(line[..<$0]) } ?? line
        let name = comma.map { String(line[line.index(after: $0)...]).trimmingCharacters(in: .whitespaces) } ?? ""
        pending = (attributes(in: head), name)
        pendingGroup = nil
      } else if line.hasPrefix("#EXTGRP:") {
        pendingGroup = String(line.dropFirst("#EXTGRP:".count)).trimmingCharacters(in: .whitespaces)
      } else if line.hasPrefix("#") {
        continue
      } else if let info = pending, let url = URL(string: line), url.scheme != nil {
        let attrs = info.attrs
        let name = info.name.nilIfEmpty ?? attrs["tvg-name"]?.nilIfEmpty ?? url.lastPathComponent
        var id = attrs["tvg-id"]?.nilIfEmpty ?? line
        // Two entries with one tvg-id (HD and SD feeds): keep both, apart.
        if seen.contains(id) { id = line }
        // The very same stream listed twice: once is enough.
        guard seen.insert(id).inserted else {
          pending = nil
          continue
        }
        channels.append(
          LiveChannel(
            id: id, name: name, number: (attrs["tvg-chno"] ?? attrs["channel-number"]).flatMap { Int($0) },
            logo: attrs["tvg-logo"]?.nilIfEmpty.flatMap(URL.init(string:)),
            group: attrs["group-title"]?.nilIfEmpty ?? pendingGroup, stream: url,
            guideID: attrs["tvg-id"]?.nilIfEmpty ?? attrs["tvg-name"]?.nilIfEmpty))
        pending = nil
        pendingGroup = nil
      }
    }
    return Result(channels: channels, guide: guide)
  }

  /// `key="value"` pairs (values may hold commas and spaces).
  static func attributes(in line: String) -> [String: String] {
    var out: [String: String] = [:]
    let scalars = Array(line)
    var i = 0
    while i < scalars.count {
      guard scalars[i] == "=" , i + 1 < scalars.count, scalars[i + 1] == "\"" else {
        i += 1
        continue
      }
      // Key: the run of non-space characters before "=".
      var k = i - 1
      while k >= 0, !scalars[k].isWhitespace, scalars[k] != "\"" { k -= 1 }
      let key = String(scalars[(k + 1)..<i]).lowercased()
      var j = i + 2
      while j < scalars.count, scalars[j] != "\"" { j += 1 }
      let value = String(scalars[min(i + 2, scalars.count)..<min(j, scalars.count)])
      if !key.isEmpty { out[key] = value }
      i = j + 1
    }
    return out
  }

  /// The comma that starts the display name (one inside quotes doesn't count).
  static func commaOutsideQuotes(_ line: String) -> String.Index? {
    var quoted = false
    var index = line.startIndex
    while index < line.endIndex {
      let c = line[index]
      if c == "\"" { quoted.toggle() } else if c == ",", !quoted { return index }
      index = line.index(after: index)
    }
    return nil
  }
}
