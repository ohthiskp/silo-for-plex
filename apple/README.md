# Astra for Apple platforms (SwiftUI)

The native rewrite of Astra. It lives next to the Flutter app, which keeps working and shipping
from the repository root until this one replaces it. Plex only.

| Folder | What it is |
|---|---|
| `AstraKit/` | Swift package: Plex sign-in (PIN), servers and connection picking, hubs, metadata, direct-play sources, watch progress. No UI; `swift test` runs its tests. |
| `Shared/` | SwiftUI shared by both apps: sign-in, server choice, home (hero, Continue Watching, hubs), details (seasons, episodes, cast, related), library grids, search, settings, player. |
| `AstraMac/` | The Mac app shell: window, menus, docked glass sidebar. |
| `AstraiOS/` | The iPhone/iPad app shell: system tab bar (Liquid Glass on iOS 26) with a search tab. |
| `project.yml` | XcodeGen spec. The Xcode project is generated, not committed. |

## Playback

The apps compile the Flutter app's mpv core directly, unchanged:
`shared/apple/MpvPlayer/MpvPlayerCoreBase.swift`, plus `macos/Runner/MpvPlayer/MpvPlayerCore.swift` (Mac)
or `ios/Runner/MpvPlayer/MpvPlayerCore.swift` and `ExternalDisplayManager.swift` (iPhone),
with libmpv from `edde746/mpv-build` at the same revision as `macos/Runner`. So HDR/EDR handling,
VideoToolbox decoding, occlusion and sleep handling are the same code the Flutter app runs.
The video layer sits under the SwiftUI layers in the window; the player controls are SwiftUI on top.

Not in this first version: picture-in-picture, display-mode (refresh-rate) matching, transcoding,
auto-play next episode, the Auto/HD/4K quality setting (it will mirror `docs/playback-quality.md`),
TestFlight upload for the iPhone app, and Apple TV.

## Build

```sh
brew install xcodegen
cd apple && xcodegen generate && open Astra.xcodeproj   # schemes: AstraMac, AstraiOS
```

CI: `.github/workflows/astra-swiftui-macos.yml` runs the AstraKit tests and builds an ad-hoc signed
`Astra.app` on every pull request that touches `apple/`, and uploads it as `Astra-SwiftUI-macOS`.
It also compiles the iPhone app unsigned. To put the iPhone app on a phone, open the project in Xcode,
pick your team under Signing for `AstraiOS`, and run it on the device. Bundle ids are
`app.astra.swiftui.mac` and `app.astra.swiftui.ios`, so both install alongside the Flutter Astra.

## Rules

- Glass is Apple's Liquid Glass (macOS 26): system `.glass`/`.glassProminent` buttons, `glassEffect`
  for custom floating shapes, `GlassEffectContainer` for groups (`AstraMac/Design/Glass.swift`). Only the
  floating layer gets glass (sidebar, buttons, search, player controls), never artwork or rows; the
  player uses clear glass over a dimming scrim. Before macOS 26 it falls back to materials.
- Tokens and motion come from `DESIGN_SYSTEM.md` (`AstraMac/Design/Theme.swift`). Animate opacity
  and transform only; images are resized by Plex and decoded off the main thread.
- The shared mpv files are owned by `astra-playback`; change them there, not by copying.
