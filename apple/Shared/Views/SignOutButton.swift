import SwiftUI

/// Settings → Sign Out, asking first (QA P1-3, 2026-11-14). Signing out
/// deletes the saved library index, Watchlist and artwork, and the index takes
/// a long time to rebuild, so one stray tap or remote click shouldn't do it.
///
/// Looks exactly like the plain button it replaces: style it with
/// `.buttonStyle(...)` as before; the question is the system's own dialog.
struct SignOutButton: View {
  var role: ButtonRole? = nil
  @Environment(AppModel.self) private var app
  @State private var confirming = false

  var body: some View {
    Button("Sign Out", role: role) { confirming = true }
      .confirmationDialog("Sign out of Plex?", isPresented: $confirming, titleVisibility: .visible) {
        Button("Sign Out", role: .destructive) { app.signOut() }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("Astra forgets this server and its saved library index, which takes a while to build again.")
      }
  }
}
