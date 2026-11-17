import Sparkle
import SwiftUI

/// In-app updates through Sparkle 2. The feed is the `appcast-swiftui` branch
/// (Info.plist `SUFeedURL`), written by the "Astra SwiftUI release" workflow;
/// updates are EdDSA-signed (secret SPARKLE_SWIFTUI_ED_SEED, public key in Info.plist).
@MainActor
final class AppUpdater {
  static let shared = AppUpdater()

  private let controller = SPUStandardUpdaterController(
    startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

  var canCheck: Bool { controller.updater.canCheckForUpdates }

  func checkForUpdates() {
    controller.checkForUpdates(nil)
  }
}
