# Astra — product

Astra is KP's personal cinematic player for a Plex server. It should feel like Disney+ or Netflix, built
with Apple's own Liquid Glass, and play almost any file directly through mpv.

## Who it's for
One user: KP. Not distributed; the only account is Plex.

## Platforms
| Platform | App | Status |
|---|---|---|
| macOS 26 | SwiftUI (`apple/AstraMac`) | Prerelease builds with Sparkle in-app updates |
| iPhone (iOS 26) | SwiftUI (`apple/AstraiOS`) | TestFlight, internal testing, version 3.1.x |
| Apple TV | Flutter (legacy) | Out of scope for the SwiftUI app for now |
| Mac/iPhone legacy | Flutter (root) | Still works; maintenance only until replaced |

## Core experience
1. **Home:** one trending hero (cineby order), top glass streaming switcher, Continue Watching,
   numbered Top 10, Plex and TMDB rows with no duplicate titles.
2. **Streaming tabs:** full TMDB provider lists; Plex titles marked, others greyed-out Play.
3. **Details:** stacked card with an X; art, logo, badges, Play/Resume, seasons/episodes, cast, related.
4. **Player:** minimal glass controls, white timeline, seek thumbnails; iPhone is landscape, Infuse-style.
5. **Movies, Shows, Downloads, Search, Settings** (Library quality HD/4K in Settings > Content).
6. **Long-press any title:** Details, Play, Download, Mark watched/unwatched, Go to season/show.

## Principles
- Image first, chrome last; colour comes from artwork. No purple.
- Very smooth: one motion system, no stutter, nothing that feels like the old Plezy UI.
- Original files only: never transcode or downscale.
- Approved mockups (`docs/design/`) are the spec; changing them needs KP's approval.
- Stability before features (ROADMAP S1–S5).

## Out of scope (for now)
Other server types, Apple TV and AirPlay in SwiftUI, social features, trackers, Discord, crash-reporting
services, Android/Windows/Linux.
