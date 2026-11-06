# Astra — local data

Astra stores data in two places: a Drift (SQLite) database for structured data, and SharedPreferences for
settings. Plex remains the source of truth for libraries and watch state; local data is cache, offline
state and configuration.

## SQLite (Drift)
- Schema: `lib/database/tables.dart`; database class and migrations: `lib/database/app_database.dart`
- Generated code: `lib/database/app_database.g.dart` (never hand-edit; run `dart run build_runner build --delete-conflicting-outputs`)
- File: `plezy_downloads.db` (internal name, kept so existing installs keep their data)
- Schema version: **25**

| Table | Holds | Key columns |
|---|---|---|
| `ApiCache` | Cached server responses | `cacheKey`, `data`, `cachedAt`, `pinned` |
| `DownloadQueue` | Pending downloads | `mediaGlobalKey`, `priority`, `downloadSubtitles`, `downloadArtwork` |
| `DownloadedMedia` | Downloaded files and their state | `serverId`, `ratingKey`, `globalKey`, `status`, `progress`, `videoFilePath` |
| `DownloadOwners` | Which profile owns a download | `profileId`, `globalKey`, `backend` |
| `SyncRules` | Auto-download rules (e.g. next N episodes) | `profileId`, `ratingKey`, `episodeCount`, `enabled` |
| `SyncRuleDownloads` | Downloads created by a rule | `syncRuleId`, `downloadGlobalKey` |
| `DownloadCollections` / `DownloadCollectionSyncs` | Downloaded collections | `collectionId`, `memberIds` |
| `Connections` | Server/account connections | `kind`, `displayName`, `configJson` (tokens via the credential vault) |
| `Profiles` / `ProfileConnections` | Local and Plex Home profiles, their tokens | `kind`, `displayName`, `userToken`, `isDefault` |
| `OfflineWatchProgress` | Watch progress recorded offline, synced later | `viewOffset`, `shouldMarkWatched`, `syncAttempts` |
| `MusicSessions` | Music queue state | `queueJson`, `cursor`, `positionMs` |

## Settings (SharedPreferences)
`lib/services/settings_service.dart` defines every key. Sensitive values go through
`lib/services/sensitive_prefs.dart` / `credential_vault.dart`, never plain prefs.

## In-memory caches
- TMDB responses: 30 minutes, in `TmdbClient` (not persisted).
- Images: `lib/services/image_cache_service.dart`.

## Changing the schema
1. Edit `tables.dart`.
2. Bump `schemaVersion` in `app_database.dart` and add an `if (from < N) { … }` step.
3. Regenerate code with build_runner.
4. Add a migration test that opens a v(N-1) database and checks the data survives.
5. Update this file (version and table list).
Never drop or rewrite user data in a migration. Owner: `astra-media`.
