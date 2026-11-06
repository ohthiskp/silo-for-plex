# Astra — product

Astra is KP's personal cinematic media player for a Plex server. It should feel like Disney+ or Netflix,
with Apple's liquid-glass materials, while playing almost any file directly through mpv.

## Who it's for
One user: KP, on Mac, iPhone and Apple TV. Not distributed to others; no accounts beyond Plex.

## Platforms
| Platform | Minimum | Status |
|---|---|---|
| macOS | 14 Sonoma | Shipping: DMG + in-app updates |
| iPhone / iPad | iOS 15.5 | TestFlight pipeline |
| Apple TV | tvOS 15 | TestFlight pipeline (custom tvOS Flutter engine) |

## Core experience
1. **Home:** full-bleed hero, streaming-service switcher, Continue Watching, rows from Plex and TMDB.
2. **Details:** art, logo, badges, Play/Resume, Watchlist, Overview / Cast / Trailers / Related, episodes.
3. **Player:** minimal glass controls (close, 10 s back / pause / 10 s forward, title and track chips over a
   violet timeline); direct play for HEVC, AV1, Dolby Vision, HDR10+, DTS, TrueHD, ASS/PGS.
4. **Search, Downloads, Settings** (card dashboard).

## Principles
- Image first, chrome last. Content runs edge to edge; controls float in glass.
- Smooth over flashy: one motion system, no stutter on scroll, instant back navigation.
- Plays anything: the server should almost never transcode.
- Approved mockups (`docs/design/`) are the spec; changes to them need KP's approval.

## Out of scope (for now)
Social features, third-party tracker sign-in, Discord presence, crash-reporting services, Android/Windows/Linux releases.
