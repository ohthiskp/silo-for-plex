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
        .preferredColorScheme(.dark)
        // White, never the system accent colour (which can be purple).
        .tint(.white)
        .task { await app.start() }
    }
  }
}
