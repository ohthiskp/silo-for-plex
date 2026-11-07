import AstraKit
import SwiftUI

/// Astra: the Plex Watchlist, opened from the bookmark at the top right of
/// Home (KP, 2026-11-07). Titles on the server open as usual; the rest open
/// with Play greyed out.
struct WatchlistView: View {
  var library: LibraryStore

  @Environment(AppModel.self) private var app
  @State private var items: [PlexMetadata] = []
  @State private var loaded = false
  @State private var error: String?

  var body: some View {
    ScrollView(.vertical) {
      VStack(alignment: .leading, spacing: 16) {
        if !loaded {
          ProgressView().controlSize(.large).frame(maxWidth: .infinity).padding(.vertical, 80)
        } else if let error {
          EmptyState(
            symbol: "exclamationmark.triangle", title: "Couldn't load your Watchlist", message: error,
            action: ("Try Again", { Task { await load() } }))
        } else if items.isEmpty {
          EmptyState(
            symbol: "bookmark", title: "Your Watchlist is empty",
            message: "Add movies and shows to your Watchlist in Plex and they'll show up here.")
        } else {
          LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 14) {
            ForEach(items) { PosterCard(library: library, item: $0, width: 108) }
          }
        }
      }
      .padding(.horizontal, 16)
      .padding(.top, 8)
      .padding(.bottom, 100)
    }
    .scrollIndicators(.never)
    .background(Astra.Color.bg.ignoresSafeArea())
    .navigationTitle("Watchlist")
    .navigationBarTitleDisplayMode(.large)
    .toolbar(.visible, for: .navigationBar)
    .refreshable { await load() }
    .task { await load() }
  }

  private func load() async {
    do {
      let list = try await app.watchlist()
      items = await library.matchWatchlist(list)
      error = nil
    } catch {
      self.error = PlexError.describe(error)
    }
    loaded = true
  }
}
