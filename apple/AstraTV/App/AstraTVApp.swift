import AstraKit
import SwiftUI

/// Apple TV (KP, 2026-11-08): the same AppModel, Plex client and mpv player as
/// Mac and iPhone. Navigation will be the Mac's sidebar, expanding when focus
/// moves onto it, with the streaming switcher (For You, Netflix…) along the top.
@main
struct AstraTVApp: App {
  @State private var app = AppModel()

  init() {
    // First, so a crash anywhere after this is caught; the next launch shows
    // the report, as on iPhone and Mac (QA P2-3, 2026-11-14).
    CrashReporter.shared.install()
  }

  var body: some Scene {
    WindowGroup {
      TVRootView()
        .environment(app)
        .crashReportSheet()
        .recordsActivity(app)
        // Colour scheme and tint follow the app theme (RootView).
        .task { await app.start() }
    }
  }
}
