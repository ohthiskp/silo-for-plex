import AstraKit
import SwiftUI
import UIKit

@main
struct AstraiOSApp: App {
  @UIApplicationDelegateAdaptor(AstraAppDelegate.self) private var delegate
  @State private var app = AppModel()

  var body: some Scene {
    WindowGroup {
      RootView()
        .environment(app)
        // Colour scheme and tint follow the app theme (RootView).
        .task { await app.start() }
        // Astra: the player is landscape only on iPhone (KP, 2026-11-07).
        .onChange(of: app.player.isActive, initial: true) { _, active in
          OrientationLock.set(active ? .landscape : .all)
        }
    }
  }
}

/// Supplies the orientations the app allows right now.
final class AstraAppDelegate: NSObject, UIApplicationDelegate {
  func application(
    _ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?
  ) -> UIInterfaceOrientationMask {
    OrientationLock.mask
  }

  /// iOS woke Astra because background downloads finished; the download session
  /// calls this back once it has handled them.
  func application(
    _ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
    completionHandler: @escaping () -> Void
  ) {
    guard identifier == DownloadSession.backgroundIdentifier else { return completionHandler() }
    DownloadSession.backgroundCompletion = completionHandler
  }
}

/// Turns the iPhone sideways for the player and back afterwards. iPad keeps every orientation.
@MainActor
enum OrientationLock {
  static var mask: UIInterfaceOrientationMask = .all

  static func set(_ wanted: UIInterfaceOrientationMask) {
    guard UIDevice.current.userInterfaceIdiom == .phone else { return }
    mask = wanted
    for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
      scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
      scene.requestGeometryUpdate(.iOS(interfaceOrientations: wanted == .all ? .portrait : wanted)) { _ in }
    }
    if wanted == .all {
      // Back to portrait first, then let the phone rotate freely again.
      Task { @MainActor in
        try? await Task.pause(0.6)
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
          scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
      }
    }
  }
}
