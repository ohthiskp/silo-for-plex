import Foundation

/// The "Trending on Cineby" list from cineby.tech's home page, as TMDB ids
/// in the site's order (KP chose this source for the For You hero and Top 10,
/// 2026-11-07). Only the public page's links are read; nothing is played
/// from the site. If the page can't be read or its layout changes, callers
/// fall back to TMDB's trending list.
public enum CinebyTrending {
  public static let pageURL = URL(string: "https://cineby.tech/")!

  public struct Entry: Sendable, Hashable {
    public var kind: TMDBItem.Kind
    public var tmdbID: Int
    public var id: String { "\(kind.rawValue):\(tmdbID)" }
  }

  /// `/movie/123` and `/tv/456` links in page order, each title once.
  public static func parse(_ html: String) -> [Entry] {
    let pattern = try! NSRegularExpression(pattern: #"/(movie|tv)/([0-9]{1,9})(?=[/"'?#])"#)
    let range = NSRange(html.startIndex..., in: html)
    var seen = Set<String>()
    var out: [Entry] = []
    for match in pattern.matches(in: html, range: range) {
      guard let kindRange = Range(match.range(at: 1), in: html), let idRange = Range(match.range(at: 2), in: html),
        let kind = TMDBItem.Kind(rawValue: String(html[kindRange])), let id = Int(html[idRange])
      else { continue }
      let entry = Entry(kind: kind, tmdbID: id)
      if seen.insert(entry.id).inserted { out.append(entry) }
    }
    return out
  }

  /// Reads the page. Throws on a network error or a non-200 answer.
  public static func fetch(transport: HTTPTransport = URLSessionTransport()) async throws -> [Entry] {
    var request = URLRequest(url: pageURL)
    request.timeoutInterval = 8
    // The page is served to browsers; a plain client gets a challenge page.
    request.setValue(
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
      forHTTPHeaderField: "User-Agent")
    request.setValue("text/html", forHTTPHeaderField: "Accept")
    let (data, response) = try await transport.send(request)
    guard response.statusCode == 200 else { throw PlexError.http(response.statusCode) }
    return parse(String(decoding: data, as: UTF8.self))
  }

  /// Cineby's titles first, then `fill` (TMDB trending) for anything it
  /// doesn't list, each title once.
  public static func merge(_ cineby: [TMDBItem], fill: [TMDBItem]) -> [TMDBItem] {
    var seen = Set<String>()
    return (cineby + fill).filter { seen.insert($0.id).inserted }
  }
}
