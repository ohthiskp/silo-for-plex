# Astra — local data

Plex is the source of truth for libraries, versions and watch state. Local data is configuration,
cache and offline downloads. Owner: `astra-media` (token storage: `astra-engineer`, reviewed by `astra-security`).

## SwiftUI app (`apple/`)

There is no SQLite database. Data lives in three places:

| Where | What | Code |
|---|---|---|
| Keychain | Plex account token | AstraKit `Storage/TokenStore.swift` (`KeychainTokenStore`; `MemoryTokenStore` in tests) |
| UserDefaults | Chosen server, selected streaming service, library quality (`LibraryQuality.stored`), playback quality, Plex client identifier, UI state via `@AppStorage` (`astra.libraries.*`, `astra.search.recent`, `player.panelX`), demo flags (`AstraDemo*`) | `AppModel.swift`, `LibraryStore.swift`, `LibraryQuality.swift`, `Playback.swift`, `PlexClientInfo.swift`, views |
| JSON files in Application Support | Server session cache `<server>.json`; cineby/TMDB trending `Trending.json`; downloads `index.json` (finished) and `queue.json` (pending) plus the downloaded original files | `ServerSession.swift`, `CinebyTrending.swift`, `Shared/App/DownloadStore.swift`, `LibraryStore.swift` |

In memory only: TMDB responses and images (`RemoteImage.swift`).

### Changing a stored format
1. Prefer additive changes: new optional fields, decoded leniently (`Models/LenientDecoding.swift`).
2. If a file or key changes shape, read the old shape and migrate on first launch.
3. Add an AstraKit test that decodes a file written by the previous build.
4. Never delete downloads or the token as a side effect.
5. Update this table.

## Legacy Flutter app (repository root)

Drift (SQLite) database `plezy_downloads.db`, schema **v25** (`lib/database/tables.dart`,
`app_database.dart`, generated `app_database.g.dart`), plus SharedPreferences
(`lib/services/settings_service.dart`; secrets via `credential_vault.dart`). Tables: `ApiCache`,
`DownloadQueue`, `DownloadedMedia`, `DownloadOwners`, `SyncRules`, `SyncRuleDownloads`,
`DownloadCollections`, `Connections`, `Profiles`, `ProfileConnections`, `OfflineWatchProgress`,
`MusicSessions`. Schema changes: bump `schemaVersion`, add an `if (from < N)` step, regenerate with
build_runner, add a migration test. The two apps don't share storage.
