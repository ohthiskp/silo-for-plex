---
name: astra-design-system
description: Astra's visual rules for the SwiftUI app — tokens in Theme.swift, Apple Liquid Glass usage, typography, motion, layout per platform, KP's standing UI rules (no purple, one hero, no duplicates, sidebar, streaming switcher, long-press menu). Load before any UI work in apple/.
---
# Astra design system (SwiftUI)

Source of truth, in order: KP's latest instruction → the mockups in `docs/design/` → this skill →
`DESIGN_SYSTEM.md`. When they conflict, stop and ask; don't redesign approved screens.

## Tokens (`apple/Shared/Design/Theme.swift`)
- Colour: `Astra.Color.bg` #0A0A0B, `surface` #161618, `surface2` #1E1E21, `ink` #F5F5F7, `muted` (ink 62%),
  `accent` and `theme` = white by default (user-set in Settings → Appearance), `hairline` = white 9%. Colour on screen comes from artwork, not from the chrome.
- **No purple or violet anywhere** (selection, progress, timeline, buttons, focus). Grep before finishing.
  The only colour exception is brand-coloured streaming-provider logos.
- Type: `Astra.Font` — system font, bold display weights. No Didot or decorative faces.
- Motion: `Astra.Motion` fast 150 ms, base 250, page 380, hero 600. Animate opacity/transform only.
  Reduce Motion: always use `astraWithAnimation`, `.astraAnimation(_:value:)` and `.astraTransition(_:)`
  (Theme.swift), never plain `withAnimation` / `.animation` / moving `.transition`. Everything should feel smooth and calm, never Plezy-like snaps.
- Layout/spacing: `Astra.Layout` (per platform, see `Platform.swift`) and `Astra.Spacing`. Add tokens, not literals.

## Liquid Glass
- Only Apple's APIs: `.glassEffect`, `GlassEffectContainer`, `.buttonStyle(.glass/.glassProminent)`,
  helpers in `Glass.swift`. No blur+gradient imitations.
- Glass lives on the floating layer (sidebar, tab bar, streaming switcher, player controls, menus);
  never on artwork, rows or the hero image.

## Screens and KP's rules (current as of 2026-11-08; KP's latest message still wins)
- **Mac sidebar:** Home, Library, Search, Settings. Icons only; expands on HOVER to icons plus names
  (KP, 2026-11-08, replaces the old no-hover rule), floating over the page; a click lights the icon at
  once; no sliding indicator. Library = Libraries (smaller Movies / Shows switch),
  Watchlist, Downloads. The Mac matches the iPhone.
- **iPhone tab bar:** Astra's wide Liquid Glass bar (52 pt, darker glass) with a draggable lens. Default
  Home, Search, Library; Settings → Navigation reorders and adds Watchlist / Downloads / Settings, max 5;
  Home and Library can't be removed. Tapping Home returns to For You.
- **Streaming switcher:** centered glass pill along the top, clear of the hero title. For You, Netflix,
  Apple TV+, Prime Video, Disney+, HBO Max, Hulu.
- **Home (For You and every service share one layout), exactly five sections:** Hero → Continue Watching →
  Top Trending (Movies | Series) → Recently Released (Movies | Series) → All-Time Greats (Movies | Series).
  Each switch has its own state. "Top Trending" everywhere (never "Top 10"); no View All buttons.
  No title twice across rows (dedupe by type + TMDB id, `LibraryStore.homeRecent/homeGreats`).
- **Sources (KP, 2026-11-08 "bring back cineby"):** For You's hero, Top Trending, Recently Released and
  All-Time Greats come from cineby.tech, filled from TMDB. Service pages show the full TMDB lists.
  Plex titles play; others show Play greyed. Never filter Home to Plex-only.
- **Hero:** one title at a time, never glitchy; swipe follows the finger, stretching-pill dots, no arrows,
  no auto-advance. White Apple TV-style Play + round grey glass "+" (Plex Watchlist); a tap elsewhere opens Details.
- **Top Trending card:** Netflix-style big outlined rank beside the poster.
- **Continue Watching:** same on every tab; card tap opens Details, only Play plays; red
  "Remove" (minus.circle) at the bottom of its menu (KP, 2026-11-08: less cluttered).
- **Details:** card stacked over the page with an X; logo left (KP's mockup); backdrop stays still;
  badge row starts with the grey content-rating pill, then plain "HDR", official Dolby Vision / Atmos logos.
- **Long-press a title:** Details, Play, Download, Mark watched/unwatched, Go to season/show.
- **Search:** TMDB only, popularity-ranked, spinner while loading.
- **Loading screen:** the logo only, no text.
- **iPhone player:** landscape only, Infuse layout (incl. progress bar), double-tap skip (10 s default),
  no ring around Play; swipe left = brightness, right = volume (toggle in Settings). **Mac player:** a click
  on the picture only toggles the controls. **Next Episode:** tap-only glass button in the last 15 s, no autoplay.
- **Quality:** always the original file; Auto / HD / 4K picks between versions on the server.
- **Settings:** server card, then Appearance, Navigation (iPhone only), Playback, Library, Downloads,
  then Sources and About. Same Astra background on every page.

## Checking your work
- Compare with the matching image in `docs/design/` and list differences.
- Screenshots come from demo mode in CI: launch arguments `-AstraDemo YES` plus `AstraDemoTab`,
  `AstraDemoQuery`, `AstraDemoOpen`, `AstraDemoPlay <video path>` (`Demo.swift`). The launch-check workflow
  (`astra-swiftui-ios-launch`) prints each screenshot as base64 between `ASTRA-SHOT-BEGIN` and
  `ASTRA-SHOT-END` in the log, because artifacts can't be downloaded through the proxy. KP judges feel on device.
