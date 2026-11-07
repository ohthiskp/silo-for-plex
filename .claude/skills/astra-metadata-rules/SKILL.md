---
name: astra-metadata-rules
description: Rules for Astra's data in the SwiftUI app — Plex-only sources, sign-in and connection picking, hubs and For You, library quality and deduplication, TMDB and cineby trending, streaming-service lists, downloads and on-device storage. Load before touching AstraKit Plex/TMDB/Models/Downloads or LibraryStore/DownloadStore.
---
# Astra metadata rules

## Sources
- **Plex only** (plex.tv account via PIN sign-in, then a server). No Jellyfin, Emby or others.
- Plex is the truth for ownership, versions, progress and watched state. TMDB enriches (logos, backdrops,
  trending, streaming lists). Cineby trending (scraped `/movie|tv/<tmdb id>` links) orders the hero and
  Top 10; it can break at any time, so fall back to TMDB trending week silently.
- TMDB token: Info.plist `AstraTMDBToken` = `$(TMDB_TOKEN)` from CI. The app must work with no token.

## Connections (`ConnectionPicker.swift`, `ServerSession.swift`, `AppModel.swift`)
- Test candidate connections and pick the fastest working one; prefer local, then remote, then relay.
- Switching server: validate the new one first, keep the old session until it succeeds, and drop results
  from stale requests (generation token).
- Log requests to `NetworkLog` without tokens.

## Lists
- **For You order** (`Plex/ForYou.swift`): hero of up to 5 trending titles on the server (manual change,
  no auto-advance), Continue Watching, Top 10 (library titles only), Recommended For You, Because You
  Watched, Hidden Gems. Never Plex's Recently Added.
- Provider rail order: Netflix, Apple TV+, Prime Video, Disney+, HBO Max, Hulu.
- Library quality per device (`LibraryQuality.swift`, Settings > Content): iPhone defaults HD,
  Apple TV 4K. HD hides 4K libraries (name has 4K/UHD/2160). 4K shows one entry per title, using
  the 4K version when present; titles without one show as HD.
- Never show a title twice in a row, in search, or across Home rows (dedupe by type + TMDB id,
  falling back to Plex GUID).
- Streaming tabs: full TMDB provider lists; mark what's on Plex; others get a greyed-out Play.
- Mark watched/unwatched updates every row immediately (optimistic, then confirm with Plex).

## Storage (see `DATABASE.md`)
- Plex token: Keychain (`KeychainTokenStore`). Settings: UserDefaults/`@AppStorage` with `astra.*` keys.
- JSON in Application Support: server session cache (`<server>.json`), `Trending.json`,
  downloads `index.json` + `queue.json`. Keep old files readable or migrate them, with a test.

## Downloads
- iOS uses a background `URLSession`; files of 200 MB or more download over 4 byte ranges
  (`DownloadSegments`) and are joined into the original file.
- Download the original file; real progress; visible failure reasons; no silent cancel; queue and
  finished items survive relaunch; offline playback uses the local file.

## Tests
- Mock HTTP through `HTTPTransport`; never hit live Plex, TMDB or cineby in tests.
