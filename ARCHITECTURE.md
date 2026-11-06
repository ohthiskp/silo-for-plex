# Astra — architecture

Astra is a Flutter app forked from an open-source Plex/Jellyfin client. The inherited app does the heavy
lifting (server clients, playback, downloads); Astra adds a visual layer and TMDB discovery on top.

## Layers
```
┌──────────────────────────── Flutter (Dart) ────────────────────────────┐
│ Astra UI  lib/astra/        home_view · detail_screen · settings_dashboard│
│                             sidebar · tab_bar · astra_style · service_pill│
│ Screens   lib/screens/      main_screen (shell) · discover_screen (home)  │
│                             video_player_screen · search · libraries …    │
│ Widgets   lib/widgets/      video_controls/ (Astra player controls)       │
│ State     lib/providers/    Provider-based app state                      │
│ Services  lib/services/     plex_client · catalog · downloads · settings  │
│ Discovery lib/astra/tmdb_client.dart · streaming_services.dart            │
│ Data      lib/database/     Drift (SQLite) · SharedPreferences settings   │
│ Player    lib/mpv/          Dart API over platform channels               │
└───────────────┬────────────────────────────────────────────────────────┘
                │ MethodChannels (com.plezy/*)
┌───────────────┴──────────── Native (Swift) ────────────────────────────┐
│ shared/apple/MpvPlayer   mpv core shared by macOS / iOS / tvOS          │
│ macos/Runner             window, display modes, Sparkle updates         │
│ ios/Runner               PiP, app delegate                              │
│ tvos/Runner              custom Flutter engine host, Top Shelf          │
└────────────────────────────────────────────────────────────────────────┘
```

## How the Astra layer plugs in
| Hook | File | Behavior |
|---|---|---|
| Home | `lib/screens/discover_screen.dart` `_buildContent` | Returns `AstraHomeView` on phone/tablet/Mac; TV still uses `_buildTvContent` |
| Details | `lib/utils/media_navigation_helper.dart`, `catalog_navigation_helper.dart` | Movies/shows open `AstraDetailScreen`; episodes and TV use the inherited page |
| Navigation | `lib/screens/main_screen.dart` | `AstraSidebar` (Mac/iPad), `AstraTabBar` (iPhone) |
| Settings | `lib/screens/settings/settings_screen.dart` | `AstraSettingsDashboard` unless `classic: true` or TV |
| Player | `lib/widgets/video_controls/desktop_video_controls.dart`, `mobile_video_controls.dart` | Astra control layout |

## External services
| Service | Used for | Config |
|---|---|---|
| Plex (plex.tv + user servers) | Auth, libraries, playback, progress | User sign-in |
| TMDB API v3 | Discovery rows, art, logos, providers | `--dart-define=TMDB_TOKEN` |
| GitHub Releases + `appcast` branch | Mac updates (Sparkle) | `SPARKLE_ED_SEED` secret |
| App Store Connect | iOS/tvOS TestFlight | `ASC_*`, `APPLE_TEAM_ID` secrets |

Upstream-hosted services (`ice.plezy.app`, `bugs.plezy.app`, Discord) are disabled and must stay so.

## Build and release
- `astra-check`: `flutter analyze` on Linux.
- `astra-macos`: builds `Astra.app`, `Astra.dmg`, `Astra.zip`, publishes a release, updates the appcast.
- `astra-ios`, `astra-tvos`: archive and upload to TestFlight.
All run on demand (`workflow_dispatch`).

## Upstream merges
`git fetch upstream && git merge upstream/main`. Internal identifiers are kept so merges stay clean;
Astra edits in inherited files are marked `// Astra:`.
