import AstraKit
import SwiftUI

enum Route: Hashable {
  case details(PlexMetadata)
}

// MARK: - Actions passed down the tree

private struct OpenItemKey: EnvironmentKey {
  static let defaultValue: (PlexMetadata) -> Void = { _ in }
}

private struct CheckForUpdatesKey: EnvironmentKey {
  static let defaultValue: (() -> Void)? = nil
}

private struct PlayItemKey: EnvironmentKey {
  static let defaultValue: (PlexMetadata) -> Void = { _ in }
}

extension EnvironmentValues {
  /// Opens the details page for an item.
  var openItem: (PlexMetadata) -> Void {
    get { self[OpenItemKey.self] }
    set { self[OpenItemKey.self] = newValue }
  }

  /// Checks for an app update (Sparkle, Mac only); nil where updates come from elsewhere.
  var checkForUpdates: (() -> Void)? {
    get { self[CheckForUpdatesKey.self] }
    set { self[CheckForUpdatesKey.self] = newValue }
  }

  /// Plays an item (a show or season plays its next episode).
  var playItem: (PlexMetadata) -> Void {
    get { self[PlayItemKey.self] }
    set { self[PlayItemKey.self] = newValue }
  }
}
