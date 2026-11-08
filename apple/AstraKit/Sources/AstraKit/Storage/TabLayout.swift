import Foundation

/// Settings → Navigation (Astra 4.0, KP 2026-11-08): which tabs the iPhone's
/// bottom bar shows. Home is always there; up to four tabs in all; the
/// default is Home, Search and Library.
public enum PhoneTab: String, CaseIterable, Sendable, Identifiable {
  case home, search, watchlist, downloads, libraries

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .home: "Home"
    case .search: "Search"
    case .watchlist: "Watchlist"
    case .downloads: "Downloads"
    case .libraries: "Library"
    }
  }

  public var symbol: String {
    switch self {
    case .home: "house.fill"
    case .search: "magnifyingglass"
    case .watchlist: "bookmark.fill"
    case .downloads: "arrow.down.circle.fill"
    case .libraries: "square.stack.fill"
    }
  }
}

public enum TabLayout {
  public static let storageKey = "astra.navigation.tabs"
  public static let defaultTabs: [PhoneTab] = [.home, .search, .libraries]
  public static let maximum = 4

  /// The saved list ("home,search,libraries") cleaned up: known tabs only,
  /// each once, in the bar's fixed order, Home always in, at most `maximum`.
  /// An empty or unreadable value is the default.
  public static func tabs(from stored: String) -> [PhoneTab] {
    let picked = Set(stored.split(separator: ",").compactMap { PhoneTab(rawValue: String($0)) })
    guard !picked.isEmpty else { return defaultTabs }
    let ordered = PhoneTab.allCases.filter { $0 == .home || picked.contains($0) }
    return Array(ordered.prefix(maximum))
  }

  public static func stored(_ tabs: [PhoneTab]) -> String {
    tabs.map(\.rawValue).joined(separator: ",")
  }

  /// The list after switching `tab` on or off. Home can't be turned off, and
  /// nothing is added past `maximum`.
  public static func toggled(_ tabs: [PhoneTab], _ tab: PhoneTab, on: Bool) -> [PhoneTab] {
    guard tab != .home else { return tabs }
    var set = Set(tabs)
    if on {
      guard tabs.count < maximum else { return tabs }
      set.insert(tab)
    } else {
      set.remove(tab)
    }
    return PhoneTab.allCases.filter { $0 == .home || set.contains($0) }
  }
}
