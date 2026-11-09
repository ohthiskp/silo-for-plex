import AppKit
import AstraKit
import SwiftUI

@main
struct AstraMacApp: App {
  @State private var app = AppModel()
  private let updater = AppUpdater.shared

  var body: some Scene {
    WindowGroup("Astra") {
      RootView()
        .environment(app)
        .frame(minWidth: 960, minHeight: 600)
        // Colour scheme and tint follow the app theme (RootView).
        .environment(\.checkForUpdates) { [updater] in updater.checkForUpdates() }
        .task { await app.start() }
    }
    .windowStyle(.hiddenTitleBar)
    .windowToolbarStyle(.unified(showsTitle: false))
    .defaultSize(width: 1440, height: 900)
    .commands {
      CommandGroup(replacing: .newItem) {}
      CommandGroup(after: .appInfo) {
        Button("Check for Updates…") { updater.checkForUpdates() }
      }
      CommandMenu("Playback") {
        Button("Play/Pause") { if !TextKey.space.sendToTextField() { app.player.togglePause() } }
          .keyboardShortcut(.space, modifiers: [])
          .disabled(!app.player.isActive)
        Button("Back 10 Seconds") { if !TextKey.left.sendToTextField() { app.player.seek(by: -10) } }
          .keyboardShortcut(.leftArrow, modifiers: [])
          .disabled(!app.player.isActive)
        Button("Forward 10 Seconds") { if !TextKey.right.sendToTextField() { app.player.seek(by: 10) } }
          .keyboardShortcut(.rightArrow, modifiers: [])
          .disabled(!app.player.isActive)
        Divider()
        Button("Close Player") { if !TextKey.escape.sendToTextField() { app.player.close() } }
          .keyboardShortcut(.escape, modifiers: [])
          .disabled(!app.player.isActive)
      }
    }

    Settings {
      SettingsView()
        .tint(.white)
        .frame(width: 480, height: 420)
        .environment(app)
        .environment(\.checkForUpdates) { [updater] in updater.checkForUpdates() }
        .preferredColorScheme(.dark)
    }
  }
}

/// Space, ← → and Esc are the player's menu shortcuts (no modifier), and menu
/// shortcuts win over a text field. While someone is typing (Search with the
/// mini player open), the key goes to the text field instead.
private enum TextKey {
  case space, left, right, escape

  @MainActor func sendToTextField() -> Bool {
    guard let editor = NSApp.keyWindow?.firstResponder as? NSTextView, editor.isEditable else { return false }
    switch self {
    case .space: editor.insertText(" ", replacementRange: editor.selectedRange())
    case .left: editor.doCommand(by: #selector(NSResponder.moveLeft(_:)))
    case .right: editor.doCommand(by: #selector(NSResponder.moveRight(_:)))
    case .escape: editor.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
    }
    return true
  }
}
