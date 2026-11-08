import Foundation

/// Settings → Navigation (Astra 4.0, KP 2026-11-08): which tabs the iPhone's
/// bottom bar shows. Home is always there; up to four tabs in all; the
/// default is Home, Search and Library.
public enum PhoneTab: String, CaseIterable, Sendable, Identifiable {
  case home, search, watchlist, downloads, libraries, settings

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .home: "Home"
    case .search: "Search"
    case .watchlist: "Watchlist"
    case .downloads: "Downloads"
    case .libraries: "Library"
    case .settings: "Settings"
    }
  }

  public var symbol: String {
    switch self {
    case .home: "house.fill"
    case .search: "magnifyingglass"
    case .watchlist: "bookmark.fill"
    case .downloads: "arrow.down.circle.fill"
    case .libraries: "square.stack.fill"
    case .settings: "gearshape.fill"
    }
  }
}

public enum TabLayout {
  public static let storageKey = "astra.navigation.tabs"
  public static let defaultTabs: [PhoneTab] = [.home, .search, .libraries]
  /// Five fit the bar at a comfortable size.
  public static let maximum = 5

  /// The saved list ("home,search,libraries") cleaned up: known tabs only,
  /// each once, in the saved order (KP: drag to reorder), Home always in,
  /// at most `maximum`. An empty or unreadable value is the default.
  public static func tabs(from stored: String) -> [PhoneTab] {
    var seen = Set<PhoneTab>()
    var out = stored.split(separator: ",").compactMap { PhoneTab(rawValue: String($0)) }
      .filter { seen.insert($0).inserted }
    guard !out.isEmpty else { return defaultTabs }
    if !out.contains(.home) { out.insert(.home, at: 0) }
    if out.count > maximum {
      out = Array(out.filter { $0 != .home }.prefix(maximum - 1))
      out.insert(.home, at: 0)
    }
    return out
  }

  public static func stored(_ tabs: [PhoneTab]) -> String {
    tabs.map(\.rawValue).joined(separator: ",")
  }

  /// The list after switching `tab` on (added at the end) or off. Home can't
  /// be turned off, and nothing is added past `maximum`.
  public static func toggled(_ tabs: [PhoneTab], _ tab: PhoneTab, on: Bool) -> [PhoneTab] {
    guard tab != .home else { return tabs }
    if on {
      guard !tabs.contains(tab), tabs.count < maximum else { return tabs }
      return tabs + [tab]
    }
    return tabs.filter { $0 != tab }
  }

  /// The list after dragging the tabs at `offsets` to `destination` (List's onMove).
  public static func moved(_ tabs: [PhoneTab], from offsets: IndexSet, to destination: Int) -> [PhoneTab] {
    let moving = offsets.sorted().map { tabs[$0] }
    var rest = tabs
    for i in offsets.sorted(by: >) { rest.remove(at: i) }
    let before = offsets.filter { $0 < destination }.count
    let at = min(max(destination - before, 0), rest.count)
    rest.insert(contentsOf: moving, at: at)
    return rest
  }
}
