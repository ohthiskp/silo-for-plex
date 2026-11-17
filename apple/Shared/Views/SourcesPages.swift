import AstraKit
import SwiftUI

// Settings → Sources (KP, 2026-11-17: "add support for all that infuse has").
// The pages pushed from the Sources rows on iPhone, Mac and Apple TV. Each
// platform's Settings lists the sources in its own cards; these Form pages
// add, show and remove them, the same on all three.

extension SourceConfig {
  /// The SF Symbol for a source's kind.
  var symbol: String { kind.symbol }

  /// "2 libraries" / "Movies, TV" under the source's name.
  var librarySummary: String {
    let names = kind.isMediaServer ? libraries.map(\.title) : folders.map(\.title)
    if names.isEmpty { return "No libraries" }
    return names.count <= 3 ? names.joined(separator: ", ") : "\(names.count) libraries"
  }
}

extension SourceKind {
  var symbol: String {
    switch self {
    case .jellyfin, .emby: "server.rack"
    case .smb: "externaldrive.connected.to.line.below"
    }
  }
}

extension SourcesModel {
  /// "Movies, TV" or "Looking for titles…" or the last error, for a source's row.
  func line(for config: SourceConfig) -> String {
    guard config.enabled else { return "Off" }
    switch status[config.id] {
    case .working(let text): return text
    case .failed(let text): return text
    default: return "\(config.kind.title) · \(config.librarySummary)"
    }
  }
}

// MARK: - One source

struct SourceDetailPage: View {
  let id: String
  @Environment(AppModel.self) private var app
  @Environment(\.dismiss) private var dismiss
  @State private var confirmRemove = false

  private var config: SourceConfig? { app.sources.configs.first { $0.id == id } }

  var body: some View {
    SettingsForm {
      if let config {
        Section {
          LabeledContent("Type", value: config.kind.title)
          LabeledContent("Address", value: config.address)
          if !config.username.isEmpty { LabeledContent("User", value: config.username) }
          LabeledContent("Status", value: statusText(config))
        } header: {
          Text(config.name)
        }
        Section {
          Toggle("Show in Astra", isOn: Binding(get: { config.enabled }, set: { app.sources.setEnabled(id, $0) }))
        } footer: {
          Text("Off hides this source's titles everywhere without forgetting it.")
        }
        if config.kind.isMediaServer {
          Section {
            ForEach(config.libraries) { library in
              LabeledContent(library.title, value: library.type == "movie" ? "Movies" : "TV Shows")
            }
            Button("Refresh Libraries") { Task { await app.sources.refreshLibraries(id) } }
          } header: {
            Text("Libraries")
          } footer: {
            Text("Watched state and progress stay in sync with the server. Astra plays the original file, never a transcode.")
          }
        } else {
          Section {
            ForEach(config.folders) { folder in
              LabeledContent {
                Text(folder.content.title)
              } label: {
                VStack(alignment: .leading, spacing: 2) {
                  Text(folder.title)
                  Text("\(folder.share)/\(folder.path)")
                    .astraFont(.meta)
                    .foregroundStyle(Astra.Color.muted)
                }
              }
              #if !os(tvOS)
                .contextMenu {
                  Button("Remove Folder", role: .destructive) { app.sources.removeFolder(folder.id, from: id) }
                }
              #endif
            }
            NavigationLink("Add Folder…") {
              AddSharePage(existing: config)
            }
            Button(app.sources.isScanning(id) ? "Looking for Titles…" : "Look for New Titles") { app.sources.scan(id) }
              .disabled(app.sources.isScanning(id))
          } header: {
            Text("Folders")
          } footer: {
            Text("Astra reads file names, finds each title on TMDB for artwork and details, and keeps watched state on this device.")
          }
        }
        Section {
          Button("Remove Source", role: .destructive) { confirmRemove = true }
        }
      }
    }
    .navigationTitle(config?.name ?? "Source")
    .confirmationDialog("Remove \(config?.name ?? "this source")?", isPresented: $confirmRemove, titleVisibility: .visible) {
      Button("Remove", role: .destructive) {
        app.sources.remove(id)
        dismiss()
      }
    } message: {
      Text("Its titles leave Astra. Nothing is deleted on the server or share.")
    }
  }

  private func statusText(_ config: SourceConfig) -> String {
    switch app.sources.status[config.id] {
    case .working(let text): text
    case .failed(let text): text
    default: config.enabled ? "Connected" : "Off"
    }
  }
}

// MARK: - Adding

/// Which kind of source to add.
struct AddSourcePage: View {
  var body: some View {
    SettingsForm {
      Section {
        ForEach([SourceKind.jellyfin, .emby]) { kind in
          NavigationLink { AddMediaServerPage(kind: kind) } label: { AddSourceKindRow(kind: kind) }
        }
      } header: {
        Text("Media servers")
      }
      Section {
        NavigationLink { AddSharePage(existing: nil) } label: { AddSourceKindRow(kind: .smb) }
      } header: {
        Text("Network shares")
      } footer: {
        Text("More sources, like cloud drives, NFS and WebDAV, are on the way.")
      }
    }
    .navigationTitle("Add Source")
  }
}

private struct AddSourceKindRow: View {
  let kind: SourceKind

  var body: some View {
    HStack(spacing: 14) {
      SettingsIcon(symbol: kind.symbol)
      VStack(alignment: .leading, spacing: 2) {
        Text(kind.title)
          .astraFont(size: 16, weight: .semibold)
          .foregroundStyle(Astra.Color.ink)
        Text(kind.blurb)
          .astraFont(size: 13)
          .foregroundStyle(Astra.Color.muted)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(.vertical, 3)
  }
}

/// Jellyfin or Emby: address, username and password.
struct AddMediaServerPage: View {
  let kind: SourceKind
  @Environment(AppModel.self) private var app
  @Environment(\.dismiss) private var dismiss
  @State private var address = ""
  @State private var username = ""
  @State private var password = ""
  @State private var working = false
  @State private var error: String?
  @State private var added = false

  var body: some View {
    SettingsForm {
      Section {
        TextField("Address", text: $address, prompt: Text(kind == .emby ? "192.168.1.20:8096" : "192.168.1.20:8096"))
          .sourceFieldStyle(url: true)
        TextField("Username", text: $username)
          .sourceFieldStyle()
        SecureField("Password", text: $password)
      } header: {
        Text(kind.title)
      } footer: {
        Text("The address you open \(kind.title) at in a browser. The password goes to your server only; Astra keeps its sign-in in the Keychain.")
      }
      Section {
        Button {
          signIn()
        } label: {
          HStack {
            Text(working ? "Signing In…" : "Sign In")
            if working {
              Spacer()
              ProgressView()
            }
          }
        }
        .disabled(working || address.trimmingCharacters(in: .whitespaces).isEmpty || username.isEmpty)
        if let error {
          Text(error)
            .astraFont(.meta)
            .foregroundStyle(Astra.Color.muted)
        }
      }
    }
    .navigationTitle("Add \(kind.title)")
    .onChange(of: added) { if added { dismiss() } }
  }

  private func signIn() {
    working = true
    error = nil
    Task {
      do {
        try await app.sources.addMediaServer(kind: kind, address: address, username: username, password: password)
        added = true
      } catch {
        self.error = PlexError.describe(error)
      }
      working = false
    }
  }
}

/// SMB: the server and sign-in, then a share, then a folder in it.
struct AddSharePage: View {
  /// Adding a folder to a share source already set up: its server and sign-in are reused.
  let existing: SourceConfig?
  @Environment(AppModel.self) private var app
  @State private var host = ""
  @State private var username = ""
  @State private var password = ""
  @State private var working = false
  @State private var error: String?
  @State private var shares: [String]?

  var body: some View {
    SettingsForm {
      if existing == nil {
        Section {
          TextField("Server", text: $host, prompt: Text("nas.local or 192.168.1.20"))
            .sourceFieldStyle(url: true)
          TextField("Username", text: $username, prompt: Text("Leave empty for guest"))
            .sourceFieldStyle()
          SecureField("Password", text: $password)
        } header: {
          Text("Network Share (SMB)")
        } footer: {
          Text("Your NAS, Mac or PC's file sharing. Astra only reads; it never changes or deletes files.")
        }
      }
      Section {
        if existing == nil {
          Button {
            connect()
          } label: {
            HStack {
              Text(working ? "Connecting…" : (shares == nil ? "Connect" : "Connect Again"))
              if working {
                Spacer()
                ProgressView()
              }
            }
          }
          .disabled(working || host.trimmingCharacters(in: .whitespaces).isEmpty)
        } else if working {
          ProgressView()
        }
        if let error {
          Text(error)
            .astraFont(.meta)
            .foregroundStyle(Astra.Color.muted)
        }
      }
      if let shares {
        Section {
          if shares.isEmpty {
            Text("This server doesn't share any folders with this user.")
              .foregroundStyle(Astra.Color.muted)
          }
          ForEach(shares, id: \.self) { share in
            NavigationLink(share) {
              ShareFolderPage(login: login, share: share, path: "")
            }
          }
        } header: {
          Text("Shares")
        } footer: {
          Text("Pick the share, then the folder with your movies or shows.")
        }
      }
    }
    .navigationTitle(existing == nil ? "Add Network Share" : "Add Folder")
    .task {
      guard let existing, shares == nil else { return }
      host = existing.address
      username = existing.username
      connect()
    }
  }

  private var login: ShareLogin {
    ShareLogin(name: existing?.name ?? "", host: host, username: username, password: password, existingID: existing?.id)
  }

  private func connect() {
    working = true
    error = nil
    Task {
      do {
        shares = try await app.sources.shareNames(login)
      } catch {
        self.error = PlexError.describe(error)
      }
      working = false
    }
  }
}

/// The server and sign-in being added, passed down the folder pages.
struct ShareLogin: Hashable {
  var name: String
  var host: String
  var username: String
  var password: String
  /// The share source this folder joins (its saved password is used).
  var existingID: String?
}

/// One folder of a share: its subfolders, and "Use This Folder".
struct ShareFolderPage: View {
  let login: ShareLogin
  let share: String
  let path: String
  @Environment(AppModel.self) private var app
  @State private var folders: [String]?
  @State private var error: String?
  @State private var content: FolderContent = .movies
  @State private var added = false

  var body: some View {
    SettingsForm {
      Section {
        Picker("Holds", selection: $content) {
          ForEach(FolderContent.allCases) { Text($0.title).tag($0) }
        }
        Button("Use This Folder") {
          Task {
            await app.sources.addShare(login: login, share: share, path: path, content: content)
            added = true
          }
        }
        .disabled(added)
        if added {
          Text("Added. Astra is looking for titles; they appear in Library as they're found.")
            .astraFont(.meta)
            .foregroundStyle(Astra.Color.muted)
        }
      } header: {
        Text(path.isEmpty ? share : "\(share)/\(path)")
      } footer: {
        Text("Movies: one movie per file or folder. TV Shows: a folder per show, with Season folders or names like S01E02.")
      }
      Section {
        if let folders {
          if folders.isEmpty {
            Text("No folders inside.")
              .foregroundStyle(Astra.Color.muted)
          }
          ForEach(folders, id: \.self) { folder in
            NavigationLink(folder.split(separator: "/").last.map(String.init) ?? folder) {
              ShareFolderPage(login: login, share: share, path: folder)
            }
          }
        } else if let error {
          Text(error).foregroundStyle(Astra.Color.muted)
        } else {
          ProgressView()
        }
      } header: {
        Text("Folders inside")
      }
    }
    .navigationTitle(path.split(separator: "/").last.map(String.init) ?? share)
    .task {
      guard folders == nil else { return }
      do {
        folders = try await app.sources.folders(login, share: share, path: path)
      } catch {
        self.error = PlexError.describe(error)
      }
    }
  }
}

extension View {
  /// Text fields for addresses and usernames: no capitals or autocorrect.
  @ViewBuilder fileprivate func sourceFieldStyle(url: Bool = false) -> some View {
    #if os(macOS)
      self.autocorrectionDisabled()
    #else
      self.textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .keyboardType(url ? .URL : .default)
    #endif
  }
}
