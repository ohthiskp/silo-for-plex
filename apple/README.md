# Astra for Apple platforms (SwiftUI)

The native rewrite of Astra. It lives next to the Flutter app, which keeps working and shipping
from the repository root until this one replaces it. Plex only.

| Folder | What it is |
|---|---|
| `AstraKit/` | Swift package: Plex sign-in (PIN), servers and connection picking, hubs, metadata, direct-play sources, watch progress. No UI; `swift test` runs its tests. |
| `AstraMac/` | The SwiftUI Mac app: sign-in, server choice, home (hero, Continue Watching, hubs), details (seasons, episodes, cast, related), library grids, search, player. |
| `project.yml` | XcodeGen spec. The Xcode project is generated, not committed. |

## Playback

The app compiles the Flutter app's mpv core directly, unchanged:
`shared/apple/MpvPlayer/MpvPlayerCoreBase.swift` and `macos/Runner/MpvPlayer/MpvPlayerCore.swift`,
with libmpv from `edde746/mpv-build` at the same revision as `macos/Runner`. So HDR/EDR handling,
VideoToolbox decoding, occlusion and sleep handling are the same code the Flutter app runs.
The video layer sits under the SwiftUI layers in the window; the player controls are SwiftUI on top.

Not in this first version: picture-in-picture, display-mode (refresh-rate) matching, transcoding,
auto-play next episode, the Auto/HD/4K quality setting (it will mirror the rules the Flutter
quality work writes up under `docs/`), and iPhone/Apple TV targets.

## Build

```sh
brew install xcodegen
cd apple && xcodegen generate && open Astra.xcodeproj   # scheme: AstraMac
```

CI: `.github/workflows/astra-swiftui-macos.yml` runs the AstraKit tests and builds an ad-hoc signed
`Astra.app` on every pull request that touches `apple/`, and uploads it as `Astra-SwiftUI-macOS`.
The bundle id is `app.astra.swiftui.mac`, so it installs alongside the Flutter Astra.

## Rules

- Glass is Apple's Liquid Glass (macOS 26): system `.glass`/`.glassProminent` buttons, `glassEffect`
  for custom floating shapes, `GlassEffectContainer` for groups (`AstraMac/Design/Glass.swift`). Only the
  floating layer gets glass (sidebar, buttons, search, player controls), never artwork or rows; the
  player uses clear glass over a dimming scrim. Before macOS 26 it falls back to materials.
- Tokens and motion come from `DESIGN_SYSTEM.md` (`AstraMac/Design/Theme.swift`). Animate opacity
  and transform only; images are resized by Plex and decoded off the main thread.
- The shared mpv files are owned by `astra-playback`; change them there, not by copying.
