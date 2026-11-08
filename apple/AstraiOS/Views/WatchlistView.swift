import AstraKit
import SwiftUI

/// Astra: the Plex Watchlist, opened from the bookmark at the top right of
/// Home (KP, 2026-11-07). Titles on the server open as usual; the rest open
/// with Play greyed out.
struct WatchlistView: View {
  var library: LibraryStore

  @Environment(AppModel.self) private var app

  var body: some View {
    ScrollView(.vertical) {
      WatchlistContent(library: library)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 100)
    }
    .scrollIndicators(.never)
    .background(Astra.Color.bg.ignoresSafeArea())
    .navigationTitle("Watchlist")
    .navigationBarTitleDisplayMode(.large)
    .toolbar(.visible, for: .navigationBar)
    .refreshable { await app.refreshWatchlist(force: true) }
  }
}
