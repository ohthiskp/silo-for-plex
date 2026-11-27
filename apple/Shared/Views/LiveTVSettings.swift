import AstraKit
import SwiftUI

/// Settings → Live TV (KP, 2026-11-16): show or hide the Live tab, add an
/// Xtream login or an M3U link (with an optional guide link), refresh the
/// guide, choose which categories show, or remove the source. The same
/// content on iPhone (its own page), Mac (a block) and Apple TV (a pane).
struct LiveTVSettingsContent: View {
  @Environment(AppModel.self) private var app
  @AppStorage(LiveTVStore.shownKey) private var liveShown = true
  @State private var editing = false
  @State private var confirmRemove = false

  private var store: LiveTVStore { app.liveTV }

  var body: some View {
    VStack(alignment: .leading, spacing: LiveSettingsMetrics.gap) {
      LiveSettingsCard(
        title: LiveSettingsMetrics.sectionTitle, footer: "Turn off to hide Live on this device. Your login stays saved."
      ) {
        LiveSettingsRow(title: "Show Live tab") {
          Toggle("Show Live tab", isOn: $liveShown).labelsHidden().tint(Astra.Color.switchOn)
        }
      }
      if let source = store.source, !editing {
        sourceCard(source)
        categories
      } else {
        LiveSourceForm(existing: store.source) { editing = false }
      }
    }
    .confirmationDialog("Remove Live TV?", isPresented: $confirmRemove, titleVisibility: .visible) {
      Button("Remove", role: .destructive) { store.remove() }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Astra forgets this login and its channels on this device.")
    }
  }

  private func sourceCard(_ source: LiveTVSource) -> some View {
    LiveSettingsCard(title: source.kindTitle, footer: footer) {
      LiveSettingsRow(title: "Server") { LiveSettingsValue(text: source.displayHost) }
      if case .xtream(_, let username, _) = source {
        LiveSettingsRow(title: "Username") { LiveSettingsValue(text: username) }
      }
      LiveSettingsRow(title: "Status") { LiveSettingsValue(text: status, good: store.phase == .ready) }
      LiveSettingsAction(title: store.loadingGuide ? "Refreshing…" : "Refresh Guide Now") { store.reload() }
      LiveSettingsAction(title: "Edit Login") { editing = true }
      LiveSettingsAction(title: "Remove", destructive: true) { confirmRemove = true }
    }
  }

  private var status: String {
    switch store.phase {
    case .ready: "Connected · \(store.channels.count) channels"
    case .loading: "Loading…"
    case .failed(let message): message
    case .idle: "Not loaded yet"
    }
  }

  private var footer: String {
    let updated = store.guideUpdated.map { "Guide updated \($0.formatted(date: .omitted, time: .shortened)). " } ?? ""
    return updated + "Streams play as your provider sends them, with no transcoding."
  }

  /// Every category with a switch; hidden ones leave the chips and Live Guide.
  @ViewBuilder private var categories: some View {
    let groups = store.allGroups
    if !groups.isEmpty {
      LiveSettingsCard(title: "Categories", footer: "Turn off the ones you never watch.") {
        ForEach(groups, id: \.self) { group in
          LiveSettingsRow(title: group) {
            Toggle(
              group,
              isOn: Binding(get: { !store.hiddenGroups.contains(group) }, set: { store.setHidden(group, !$0) })
            )
            .labelsHidden()
            .tint(Astra.Color.switchOn)
          }
        }
      }
    }
  }
}

/// Adding or editing the source: Xtream (server, username, password) or an
/// M3U link with an optional guide link. Connect checks it before saving.
private struct LiveSourceForm: View {
  @Environment(AppModel.self) private var app
  var existing: LiveTVSource?
  var done: () -> Void

  enum Kind: String, CaseIterable, Identifiable {
    case xtream, m3u
    var id: String { rawValue }
    var title: String { self == .xtream ? "Xtream" : "M3U link" }
  }

  @State private var kind: Kind = .xtream
  @State private var server = ""
  @State private var username = ""
  @State private var password = ""
  @State private var playlist = ""
  @State private var guide = ""
  @State private var connecting = false
  @State private var error: String?

  var body: some View {
    LiveSettingsCard(
      title: existing == nil ? "Add Live TV" : "Edit Live TV",
      footer: error ?? (kind == .xtream
        ? "Use the server address, username and password from your IPTV provider."
        : "Paste your playlist link (.m3u). Add a guide link (XMLTV) for what's on, if your playlist doesn't include one.")
    ) {
      LiveSettingsRow(title: "Type") {
        Picker("Type", selection: $kind) {
          ForEach(Kind.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: LiveSettingsMetrics.pickerWidth)
      }
      if kind == .xtream {
        field("Server", "http://tv.example.com:8080", $server)
        field("Username", "", $username)
        LiveSettingsRow(title: "Password") {
          SecureField("Password", text: $password)
            .textContentType(.password)
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: LiveSettingsMetrics.fieldWidth)
        }
      } else {
        field("Playlist link", "http://…/playlist.m3u", $playlist)
        field("Guide link", "Optional", $guide)
      }
      LiveSettingsAction(title: connecting ? "Connecting…" : "Connect", disabled: !ready || connecting) { connect() }
      if existing != nil {
        LiveSettingsAction(title: "Cancel", disabled: connecting) { done() }
      }
    }
    .onAppear(perform: fill)
  }

  private func field(_ title: String, _ prompt: String, _ text: Binding<String>) -> some View {
    LiveSettingsRow(title: title) {
      TextField(title, text: text, prompt: Text(prompt))
        .autocorrectionDisabled()
        #if os(iOS) || os(tvOS)
          .textInputAutocapitalization(.never)
          .keyboardType(.URL)
        #endif
        .multilineTextAlignment(.trailing)
        .frame(maxWidth: LiveSettingsMetrics.fieldWidth)
    }
  }

  private var ready: Bool {
    kind == .xtream
      ? !server.trimmingCharacters(in: .whitespaces).isEmpty && !username.isEmpty && !password.isEmpty
      : !playlist.trimmingCharacters(in: .whitespaces).isEmpty
  }

  private func fill() {
    switch existing {
    case .xtream(let s, let u, let p)?:
      kind = .xtream
      server = s
      username = u
      password = p
    case .m3u(let p, let g)?:
      kind = .m3u
      playlist = p
      guide = g ?? ""
    case nil:
      break
    }
  }

  private func connect() {
    let source: LiveTVSource =
      kind == .xtream
      ? .xtream(server: server.trimmingCharacters(in: .whitespaces), username: username, password: password)
      : .m3u(playlist: playlist.trimmingCharacters(in: .whitespaces), guide: guide.isEmpty ? nil : guide)
    connecting = true
    error = nil
    Task {
      do {
        try await app.liveTV.connect(source)
        done()
      } catch {
        self.error = error.localizedDescription
      }
      connecting = false
    }
  }
}

// MARK: - Building blocks (quiet cards like the rest of Settings)

private struct LiveSettingsCard<Content: View>: View {
  var title: String?
  var footer: String?
  @ViewBuilder var content: Content

  private static var shape: RoundedRectangle {
    RoundedRectangle(cornerRadius: LiveSettingsMetrics.corner, style: .continuous)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let title {
        Text(title)
          .font(.system(size: LiveSettingsMetrics.caption, weight: .semibold))
          .foregroundStyle(Astra.Color.muted)
          .padding(.leading, 6)
          .accessibilityAddTraits(.isHeader)
      }
      VStack(spacing: 0) { content }
        .background(Self.shape.fill(Astra.Color.ink.opacity(0.06)))
        .overlay(Self.shape.strokeBorder(Astra.Color.hairline, lineWidth: 1))
        .clipShape(Self.shape)
      if let footer {
        Text(footer)
          .font(.system(size: LiveSettingsMetrics.caption))
          .foregroundStyle(Astra.Color.muted)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.horizontal, 6)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct LiveSettingsRow<Control: View>: View {
  var title: String
  @ViewBuilder var control: Control

  var body: some View {
    HStack(spacing: 12) {
      Text(title)
        .font(.system(size: LiveSettingsMetrics.row, weight: .medium))
        .foregroundStyle(Astra.Color.ink)
        .lineLimit(1)
      Spacer(minLength: 8)
      control
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 6)
    .frame(minHeight: LiveSettingsMetrics.rowHeight)
    .overlay(alignment: .top) { Rectangle().fill(Astra.Color.hairline).frame(height: 1) }
  }
}

private struct LiveSettingsValue: View {
  var text: String
  var good = false

  var body: some View {
    Text(text)
      .font(.system(size: LiveSettingsMetrics.row * 0.9))
      .foregroundStyle(good ? Color.green : Astra.Color.muted)
      .lineLimit(2)
      .multilineTextAlignment(.trailing)
  }
}

private struct LiveSettingsAction: View {
  var title: String
  var destructive = false
  var disabled = false
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      LiveSettingsRow(title: title) { EmptyView() }
        .foregroundStyle(destructive ? Color.red : Astra.Color.ink)
        .contentShape(Rectangle())
    }
    #if os(tvOS)
      .buttonStyle(TVSettingRowStyle())
    #else
      .buttonStyle(.plain)
    #endif
    .disabled(disabled)
    .opacity(disabled ? 0.45 : 1)
  }
}

enum LiveSettingsMetrics {
  /// iPhone's page already says "Live TV" in its title; Mac and Apple TV show it over the first card.
  #if os(iOS)
    static let sectionTitle: String? = nil
  #else
    static let sectionTitle: String? = "Live TV"
  #endif
  #if os(tvOS)
    static let row: CGFloat = 29
    static let caption: CGFloat = 22
    static let rowHeight: CGFloat = 76
    static let gap: CGFloat = 28
    static let corner: CGFloat = 24
    static let fieldWidth: CGFloat = 640
    static let pickerWidth: CGFloat = 460
  #elseif os(macOS)
    static let row: CGFloat = 14.5
    static let caption: CGFloat = 12.5
    static let rowHeight: CGFloat = 46
    static let gap: CGFloat = 18
    static let corner: CGFloat = 14
    static let fieldWidth: CGFloat = 300
    static let pickerWidth: CGFloat = 220
  #else
    static let row: CGFloat = 17
    static let caption: CGFloat = 13
    static let rowHeight: CGFloat = 52
    static let gap: CGFloat = 24
    static let corner: CGFloat = 18
    static let fieldWidth: CGFloat = 220
    static let pickerWidth: CGFloat = 200
  #endif
}
