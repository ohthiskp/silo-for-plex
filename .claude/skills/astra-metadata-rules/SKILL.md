---
name: astra-metadata-rules
description: Rules for Astra metadata and discovery — Plex as source of truth, TMDB usage and token handling, streaming-provider rows, caching, and SQLite/Drift schema changes. Use before touching metadata, discovery or the database.
---
# Astra metadata rules

## Sources
- **Plex** (`lib/services/plex_client*`): what KP owns, libraries, hubs, Continue Watching, watch state,
  playback decisions. Always authoritative for "can I play this" and progress.
- **TMDB** (`lib/astra/tmdb_client.dart`): discovery rows, hero art, logos, provider lists. Enrichment only.
- **Streaming providers** (`lib/astra/streaming_services.dart`): the switcher's services and their TMDB
  watch-provider IDs. Region defaults to the user's locale.

## TMDB
- Token only via `--dart-define=TMDB_TOKEN` (GitHub secret `TMDB_TOKEN`). Never log it or embed it in code.
- Guard every call with `tmdbAvailable`; the app must work with no token (Plex-only rows).
- Use the client's cache (30 min TTL) and in-flight de-duplication; don't add parallel fetch loops.
- Images through `image.tmdb.org/t/p/<size>` with the smallest size that fits the card.
- Show TMDB attribution in Settings/About.

## Matching TMDB to Plex
- Match by GUID (`tmdb://`, `imdb://`, `tvdb://`) from Plex `includeGuids=1`; never by title alone.
- A TMDB title KP doesn't own opens the request/details flow, never a broken Play button.

## Database (Drift/SQLite)
- Schema in `lib/database/tables.dart`, version in `app_database.dart` (`schemaVersion`, currently 25).
- Every schema change: bump the version, add an `if (from < N)` migration step, run
  `dart run build_runner build --delete-conflicting-outputs`, add a migration test, update `DATABASE.md`.
- Never drop or rewrite user data (downloads, profiles, connections, offline progress) in a migration.
- Don't rename the DB file (`plezy_downloads.db`); existing installs depend on it.

## Testing
`flutter test test/services/ test/database/ test/models/` for touched areas; mock HTTP, never call live TMDB in tests.
