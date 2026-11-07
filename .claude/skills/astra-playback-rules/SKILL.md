---
name: astra-playback-rules
description: Rules for Astra playback in the SwiftUI app — original files only, libmpv core shared with the Flutter app, version choice by library quality, progress sync, HDR, PiP, iPhone player gestures and performance checks. Load before touching apple/Shared/Player, the mpv files, or AstraKit Playback.
---
# Astra playback rules

## Architecture
- `apple/Shared/Player/PlayerController.swift` drives one mpv instance through the shared core:
  `shared/apple/MpvPlayer/MpvPlayerCoreBase.swift` + `macos/Runner/MpvPlayer/MpvPlayerCore.swift`
  (Mac) or `ios/Runner/MpvPlayer/MpvPlayerCore.swift`, `ExternalDisplayManager.swift`,
  `MpvPipController.swift` (iPhone). The Flutter app compiles the same files: keep them free of Flutter
  types, and check both apps build after a change.
- MPVKit is pinned in `apple/project.yml` (edde746/mpv-build revision). Changing it needs `astra-security`.
- `PlayerWindow.swift` (Mac window, default size, drag, mini window), `PipCoordinator.swift`,
  `SeekPreviewGenerator.swift` + AstraKit `SeekThumbnails.swift` (Plex BIF first), `PlayerGeometry.swift`.

## Hard rules
1. **Always play the original file.** No transcoding, no downscaling, no Plex "universal" decision
   that re-encodes. Quality only picks between versions Plex already has (`Playback.swift`,
   `LibraryQuality.swift`; see `docs/playback-quality.md`).
2. Resume and progress: report timeline to Plex while playing, on pause, seek, stop, background and
   app quit. Mark watched at Plex's threshold. Never lose a resume point.
3. Subtitles and audio: honour the Plex stream selection and the user's language defaults; external
   and embedded subs both work; switching never restarts the file from the start.
4. HDR: report what mpv actually outputs. No Dolby Vision badge on Mac/iPhone.
5. iPhone: landscape only; Infuse-style controls; double-tap right/left = +/-10 s; swipe
   up/down on the left = brightness, right = volume; no ring around Play.
6. Never block the main thread on mpv; observe properties instead of polling. No `Task.sleep(for:)`
   (use `Task.pause`).

## Before calling it done
- AstraKit tests pass in `astra-swiftui-macos` CI. Any player or gesture change keeps `AstraiOSUITests`
  green in the launch-check workflow (demo mode, `AstraDemoPlay <video path>`).
- Shared mpv file touched → the Flutter Mac build (`astra-macos`) still compiles.
- Measure first-frame time and dropped frames before/after for performance work.
- List formats not tried (DV profiles, PGS subs, 4K HEVC 10-bit, Atmos passthrough) as untested.
