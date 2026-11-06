import AstraKit
import SwiftUI

/// One library section as a poster grid, loaded a page at a time.
struct LibraryGridView: View {
  var library: LibraryStore
  var section: PlexLibrarySection

  @State private var items: [PlexMetadata] = []
  @State private var reachedEnd = false
  @State private var loading = false
  @State private var sort = "addedAt:desc"

  private let columns = [GridItem(.adaptive(minimum: 160, maximum: 190), spacing: 18, alignment: .top)]

  var body: some View {
    ScrollView(.vertical) {
      VStack(alignment: .leading, spacing: 22) {
        HStack {
          Text(section.title).astraDisplay(38, tracking: 6)
          Spacer()
          Picker("Sort", selection: $sort) {
            Text("Recently Added").tag("addedAt:desc")
            Text("Title").tag("titleSort")
            Text("Release Date").tag("originallyAvailableAt:desc")
            Text("Rating").tag("audienceRating:desc")
          }
          .labelsHidden()
          .frame(width: 180)
        }
        LazyVGrid(columns: columns, alignment: .leading, spacing: 26) {
          ForEach(items) { item in
            PosterCard(library: library, item: item)
              .onAppear {
                if item.id == items.last?.id { Task { await loadMore() } }
              }
          }
        }
        if loading { ProgressView().frame(maxWidth: .infinity) }
      }
      .padding(.leading, Astra.Layout.leading)
      .padding(.trailing, 40)
      .padding(.top, 56)
      .padding(.bottom, 60)
    }
    .scrollIndicators(.never)
    .astraScrollEdges()
    .ignoresSafeArea(edges: .top)
    .task(id: sort) {
      items = []
      reachedEnd = false
      await loadMore()
    }
  }

  private func loadMore() async {
    guard !loading, !reachedEnd else { return }
    loading = true
    defer { loading = false }
    let page = (try? await library.client.libraryItems(sectionKey: section.key, sort: sort, start: items.count)) ?? []
    reachedEnd = page.isEmpty
    items += page.filter { new in !items.contains { $0.id == new.id } }
  }
}

struct SearchView: View {
  var library: LibraryStore

  @State private var query = ""
  @State private var results: [PlexMetadata] = []
  @FocusState private var focused: Bool

  private let columns = [GridItem(.adaptive(minimum: 160, maximum: 190), spacing: 18, alignment: .top)]

  var body: some View {
    ScrollView(.vertical) {
      VStack(alignment: .leading, spacing: 26) {
        HStack(spacing: 12) {
          Image(systemName: "magnifyingglass").foregroundStyle(Astra.Color.muted)
          TextField("Movies, shows and episodes", text: $query)
            .textFieldStyle(.plain)
            .font(.system(size: 18))
            .focused($focused)
        }
        .padding(.horizontal, 20)
        .frame(height: 52)
        .astraGlass(in: Capsule())
        .frame(maxWidth: 620)

        LazyVGrid(columns: columns, alignment: .leading, spacing: 26) {
          ForEach(results) { PosterCard(library: library, item: $0) }
        }
        .animation(Astra.Motion.base, value: results.map(\.id))
      }
      .padding(.leading, Astra.Layout.leading)
      .padding(.trailing, 40)
      .padding(.top, 56)
    }
    .scrollIndicators(.never)
    .astraScrollEdges()
    .ignoresSafeArea(edges: .top)
    .onAppear { focused = true }
    .task(id: query) {
      let text = query.trimmingCharacters(in: .whitespaces)
      guard text.count >= 2 else { return results = [] }
      // Debounce typing.
      try? await Task.sleep(for: .milliseconds(250))
      guard !Task.isCancelled else { return }
      results = (try? await library.client.search(text)) ?? []
    }
  }
}

struct SettingsView: View {
  @Environment(AppModel.self) private var app

  var body: some View {
    Form {
      Section("Plex") {
        LabeledContent("Server", value: app.server?.serverName ?? "Not connected")
        LabeledContent("Address", value: app.server?.baseURL.host() ?? "—")
        HStack {
          Button("Change Server…") { Task { await app.chooseServer() } }
          Button("Sign Out", role: .destructive) { app.signOut() }
        }
      }
      Section("About") {
        LabeledContent(
          "Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
        Text("Astra is licensed under GPL-3.0.").foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .frame(width: 460)
    .padding(.vertical, 8)
  }
}
