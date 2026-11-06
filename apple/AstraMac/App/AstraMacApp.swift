import AstraKit
import SwiftUI

@main
struct AstraMacApp: App {
  @State private var app = AppModel()

  var body: some Scene {
    WindowGroup("Astra") {
      RootView()
        .environment(app)
        .frame(minWidth: 960, minHeight: 600)
        .preferredColorScheme(.dark)
        .task { await app.start() }
    }
    .windowStyle(.hiddenTitleBar)
    .windowToolbarStyle(.unified(showsTitle: false))
    .defaultSize(width: 1440, height: 900)
    .commands {
      CommandGroup(replacing: .newItem) {}
      CommandMenu("Playback") {
        Button("Play/Pause") { app.player.togglePause() }
          .keyboardShortcut(.space, modifiers: [])
          .disabled(!app.player.isActive)
        Button("Back 10 Seconds") { app.player.seek(by: -10) }
          .keyboardShortcut(.leftArrow, modifiers: [])
          .disabled(!app.player.isActive)
        Button("Forward 10 Seconds") { app.player.seek(by: 10) }
          .keyboardShortcut(.rightArrow, modifiers: [])
          .disabled(!app.player.isActive)
        Divider()
        Button("Close Player") { app.player.close() }
          .keyboardShortcut(.escape, modifiers: [])
          .disabled(!app.player.isActive)
      }
    }

    Settings {
      SettingsView()
        .frame(width: 480, height: 420)
        .environment(app)
        .preferredColorScheme(.dark)
    }
  }
}
