# Astra — architecture

Two apps live in this repository:

- **SwiftUI app (`apple/`)** — the app being built. Native SwiftUI for Mac and iPhone, Plex only.
- **Flutter app (root)** — the legacy app, forked from an open-source Plex client. Still ships; maintenance only.

Both play video through the same Swift mpv core.

## SwiftUI app

```
AstraMac / AstraiOS  (app shells: scenes, sidebar or tab bar, Sparkle updater on Mac)
        │
Shared/App      AppModel (sign-in, server session, settings) · LibraryStore (home rows, hero,
                streaming tabs, quality filtering) · DownloadStore
Shared/Views    Home, Detail, Library, Search, Downloads, Settings, Cards, Navigation, Loading, SignIn
Shared/Design   Theme tokens, Liquid Glass helpers, RemoteImage, logo
Shared/Player   PlayerController → mpv core · PlayerOverlay (controls) · PlayerWindow · PiP · seek previews
        │
AstraKit (Swift package, no UI, tested with `swift test`)
  Plex/        PlexAccount (PIN sign-in, servers) · ConnectionPicker · ServerSession · PlexServerClient
               (hubs, metadata, search, progress) · ForYou · LibraryQuality · Playback (version choice,
               direct-play URL) · PlayerGeometry · SeekThumbnails (BIF)
  TMDB/        TMDBClient (trending, provider lists, images) · CinebyTrending (hero/Top 10 order)
  Models/      Plex containers and metadata, lenient decoding
  Networking/  HTTPTransport (mockable) · NetworkLog · PlexClientInfo · Task.pause
  Storage/     TokenStore (Keychain)
  Downloads/   Download tasks for original files
        │
shared/apple/MpvPlayer/MpvPlayerCoreBase.swift + macos|ios/Runner/MpvPlayer/*  (libmpv via MPVKit)
```

### Key flows
- **Sign-in:** plex.tv PIN → token in Keychain → server list → `ConnectionPicker` tests connections →
  `ServerSession`. Switching servers validates the new one before dropping the old.
- **Home:** `LibraryStore` loads Plex hubs and Continue Watching, TMDB/cineby trending for the hero and
  Top 10, matches titles to the library, applies library quality, and dedupes by type + TMDB id.
- **Playback:** Details → `Playback` picks an existing version (never a transcode) → `PlayerController`
  opens the direct file URL in mpv and reports the timeline to Plex.
- **Downloads:** `DownloadStore` queues original files, persists `queue.json`/`index.json`, and the player
  uses the local file when offline.

### Build and ship
- XcodeGen `apple/project.yml` → `Astra.xcodeproj` (not committed). Packages: MPVKit (pinned revision), Sparkle 2.6.4.
- `astra-swiftui-macos.yml`: AstraKit tests, ad-hoc Mac build, unsigned iPhone compile on PRs touching `apple/` or mpv files.
- `astra-swiftui-release.yml`: Mac prerelease + Sparkle feed on branch `appcast-swiftui`.
- `astra-swiftui-ios.yml`: TestFlight upload (`com.ohthiskp.astra`, temporary signing via `tool/astra/asc_tv_signing.py`).
- Crash tooling: `astra-testflight-crashes.yml`, `astra-ios-symbolicate.yml`.

## Legacy Flutter app

`lib/main.dart` → Astra layer `lib/astra/` (home, details, settings, sidebar, glass, TMDB) on top of the
inherited `lib/screens/`, `lib/widgets/`, `lib/services/` (Plex/Jellyfin clients, downloads, settings),
Drift database `lib/database/`, Dart player API `lib/mpv/` over the same Swift mpv core. Native
runners in `macos/ ios/ tvos/` (Apple TV uses a custom tvOS Flutter engine). CI: `astra-check`,
`astra-macos`, `astra-ios`, `astra-tvos`.

## Boundaries
- Changes to the shared mpv files affect both apps (owner `astra-playback`).
- The two apps share no storage; the SwiftUI Mac app has its own bundle ID and update feed.
