import AstraKit
import SwiftUI

@main
struct AstraiOSApp: App {
  @State private var app = AppModel()

  var body: some Scene {
    WindowGroup {
      RootView()
        .environment(app)
        .preferredColorScheme(.dark)
        .tint(.white)
        .task { await app.start() }
    }
  }
}
