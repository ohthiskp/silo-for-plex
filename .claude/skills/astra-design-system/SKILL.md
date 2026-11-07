---
name: astra-design-system
description: Astra's visual rules for the SwiftUI app — tokens in Theme.swift, Apple Liquid Glass usage, typography, motion, layout per platform, KP's standing UI rules (no purple, one hero, no duplicates, sidebar, streaming switcher, long-press menu). Load before any UI work in apple/.
---
# Astra design system (SwiftUI)

Source of truth, in order: KP's latest instruction → the mockups in `docs/design/` → this skill →
`DESIGN_SYSTEM.md`. When they conflict, stop and ask; don't redesign approved screens.

## Tokens (`apple/Shared/Design/Theme.swift`)
- Colour: `Astra.Color.bg` #0A0A0B, `surface` #161618, `surface2` #1E1E21, `ink` #F5F5F7, `muted` (ink 62%),
  `accent` = white, `hairline` = white 9%. Colour on screen comes from artwork, not from the chrome.
- **No purple or violet anywhere** (selection, progress, timeline, buttons, focus). Grep before finishing.
- Type: `Astra.Font` — system font, bold display weights. No Didot or decorative faces.
- Motion: `Astra.Motion` fast 150 ms, base 250, page 380, hero 600. Animate opacity/transform only;
  honour Reduce Motion. Everything should feel smooth and calm, never Plezy-like snaps.
- Layout/spacing: `Astra.Layout` (per platform, see `Platform.swift`) and `Astra.Spacing`. Add tokens, not literals.

## Liquid Glass
- Only Apple's APIs: `.glassEffect`, `GlassEffectContainer`, `.buttonStyle(.glass/.glassProminent)`,
  helpers in `Glass.swift`. No blur+gradient imitations.
- Glass lives on the floating layer (sidebar, tab bar, streaming switcher, player controls, menus);
  never on artwork, rows or the hero image.

## Screens and KP's rules
- **Mac sidebar:** exactly Home, Movies, Shows, Downloads, Search, Settings. Icons only, click to expand
  (no hover expand), one sliding selection indicator.
- **Streaming switcher:** centered glass pill along the top; must not overlap the hero title.
- **Home:** one hero at a time (cineby trending), never glitchy; Continue Watching, then numbered Top 10
  with a Movies/Series pill; no title appears twice across rows (dedupe by type + TMDB id).
  Continue Watching is the same on every tab; tapping a card opens Details (only Play plays).
- **Streaming tabs:** full TMDB lists; titles on Plex are marked; others show a greyed-out Play.
- **Details:** opens as a card stacked over the page, with an X to close.
- **Long-press a title:** Details, Play, Download, Mark watched/unwatched, Go to season/show.
- **Loading screen:** the logo only, no text.
- **iPhone player:** landscape only, Infuse layout (incl. progress bar), double-tap ±10 s, no ring
  around Play. iPhone tab bar: wait for KP's mockup before changing it.
- **Library quality:** HD/4K setting lives in Settings > Content; lists show one version per title.

## Checking your work
- Compare with the matching image in `docs/design/` and list differences.
- Screenshots come from CI or the UI tests (`Demo.swift` flags drive a demo state); KP judges feel on device.
