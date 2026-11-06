---
name: astra-playback-rules
description: Rules for changing Astra playback — mpv integration, native Apple players, direct play, subtitles, audio, HDR/Dolby Vision, display modes, progress reporting and performance checks. Use before touching player code.
---
# Astra playback rules

## Where things live
- Dart API: `lib/mpv/` (player interface, channels `com.plezy/mpv_player`)
- Shared Apple core: `shared/apple/MpvPlayer/MpvPlayerCoreBase.swift`, `MpvPlayerPluginShared.swift`
- Platform cores: `macos/Runner/MpvPlayer/` (incl. `DisplayModeManager.swift`), `ios/Runner/MpvPlayer/` (incl. PiP), `tvos/Runner/`
- Player screen: `lib/screens/video_player_screen.dart` + `lib/screens/video_player/parts/`
- Controls (visual, owned by design): `lib/widgets/video_controls/`
- mpv build pin: `mpv-build.lock.json` (changing it needs security review)

## Non-negotiables
1. **Direct play first.** Prefer direct play/stream for anything mpv decodes (HEVC, AV1, VP9, DV, HDR10/10+,
   DTS, TrueHD, ASS/PGS). Transcode only when the file can't play.
2. **Progress reporting.** Timeline updates and stopped/watched state reach Plex; resume points are correct
   after seek, pause, background and crash.
3. **Display mode.** Frame-rate/HDR switching restores the user's display mode on exit, error and crash.
4. **HDR.** Pass through on HDR displays; tone-map on SDR. Never wash out SDR content.
5. **Subtitles.** ASS/SSA render with libass styles intact; PGS as bitmaps; text subs follow user size/colour
   settings. Track selection persists per show where the setting says so.
6. **Audio.** Pass-through only where the output supports it; otherwise decode. Remember the user's language choice.
7. **Never block the UI thread** on mpv calls; long work goes to the player queue.

## Performance checks
- Startup to first frame, seek latency, dropped frames during playback and while controls animate.
- Record numbers before and after (mpv stats overlay / `performance_stats.dart`); report both.

## Testing
- Dart: `flutter test test/mpv/ test/screens/video_player/`
- Native: can't build on Linux — list the device checks (Mac, iPhone, Apple TV) and the media types to try.
- Mark anything not run as "not tested".
