import AstraKit
import SwiftUI

/// Apple TV (KP, 2026-11-08): the same AppModel, Plex client and mpv player as
/// Mac and iPhone. Navigation will be the Mac's sidebar, expanding when focus
/// moves onto it, with the streaming switcher (For You, Netflix…) along the top.
@main
struct AstraTVApp: App {
  @State private var app = AppModel()

  var body: some Scene {
    WindowGroup {
      TVRootView()
        .environment(app)
        // Colour scheme and tint follow the app theme (RootView).
        .task { await app.start() }
    }
  }
}
