# Astra — design system (SwiftUI)

The approved mockups in [`docs/design/`](docs/design/README.md) are the source of truth. Tokens live in
`apple/Shared/Design/Theme.swift`; glass helpers in `Glass.swift`. The `astra-design-system` skill
carries the same rules for agents.

## Direction
Cinematic and dark. Disney+/Netflix layout (hero, rows, cards); Apple Liquid Glass for anything floating.
The chrome is neutral white and grey; colour comes from the artwork. **No purple or violet anywhere.**

## Colour (`Astra.Color`)
| Token | Value | Use |
|---|---|---|
| `bg` | `#0A0A0B` | Background |
| `surface` | `#161618` | Cards |
| `surface2` | `#1E1E21` | Sheets, menus |
| `ink` | `#F5F5F7` | Primary text |
| `muted` | ink @ 62% | Secondary text |
| `accent` | white by default | Progress, switches, selected chips (Settings → Appearance → Accent) |
| `theme` | white by default | Settings icons, the lit tab, the Mac sidebar pill (Settings → Appearance → Theme) |
| `hairline` | white @ 9% | Borders, dividers |

## Type (`Astra.Font`)
System font only. `display(size)` bold for titles; `rowTitle` 19 bold; `meta` 14 medium (` • ` separators);
`card` 13 medium. Title sizes per platform in `Astra.Layout` (Mac 52/38, iPhone 38/30).

## Shape and spacing
Cards radius 14, badges 4; pills and buttons fully rounded. Spacing `xs 6 · s 10 · m 14 · l 22 · xl 34`.
Mac: leading 104, hero 620, art card 240×135, continue card 360×202. iPhone: leading 20, hero 560,
art card 168×95, continue card 270×152. Sidebar: margin 14, collapsed width 62.

## Materials (Liquid Glass)
Apple APIs only: `glassEffect`, `GlassEffectContainer`, `.glass` / `.glassProminent` button styles.
Glass goes on the floating layer (sidebar, tab bar, streaming switcher, buttons, search, player
controls, menus), never on artwork or rows. The player uses clear glass over a dimming scrim.
No blur-and-gradient imitations.

## Motion (`Astra.Motion`)
| Token | ms | Curve | Use |
|---|---|---|---|
| fast | 150 | ease-out cubic | Press, focus |
| base | 250 | ease-out cubic | Hover, chips |
| page | 380 | ease-in-out cubic | Pages, sheets, menus |
| hero | 600 | ease-in-out cubic | Hero crossfade, card → details |
Animate opacity and transform, not layout. The goal is "very smooth": nothing should snap or flicker.
Reduce Motion: use `astraWithAnimation`, `.astraAnimation(_:value:)` and `.astraTransition(_:)` (Theme.swift)
instead of the plain SwiftUI calls. They route through `Astra.Motion.resolved` and turn moving or scaling
transitions into fades only when the setting is on.

## Screens
| Screen | Mockup | Implementation |
|---|---|---|
| Mac home + sidebar | `desktop-home.png` | `Shared/Views/HomeView.swift`, `AstraMac/Views/MainView.swift` |
| iPhone home + tab bar | `iphone-home.png` | `HomeView.swift`, `AstraiOS/Views/MainView.swift` (Liquid Glass tab bar with a draggable lens) |
| Apple TV home | `appletv-home.png` | Not in the SwiftUI app yet |
| Mac player | `desktop-player.png` | `Shared/Player/PlayerOverlay.swift`, `PlayerWindow.swift` |
| iPhone player | `iphone-player.png` | `PlayerOverlay.swift` (landscape, Infuse-style) |
| Apple TV player | `appletv-player.png` | Not in the SwiftUI app yet |
| Details | `details.png` | `Shared/Views/DetailView.swift` (stacked card with an X) |
| Settings | `settings.png` | Settings views in `Shared/Views/` |

## Behaviour rules (KP's current rules, 2026-11-08)
- **Mac sidebar:** Home, Library, Search, Settings. Icons only; it expands on hover to icons plus names
  (KP, 2026-11-08), floating over the page. A click lights the chosen icon at once, no sliding indicator. Library holds Libraries (with a smaller
  Movies / Shows switch), Watchlist and Downloads. The Mac matches the iPhone.
- **iPhone tab bar:** Astra's own wide Liquid Glass bar (52 pt, darker glass) with a draggable lens.
  Default tabs Home, Search, Library. Settings → Navigation reorders them and adds Watchlist,
  Downloads or Settings, up to five. Home and Library can't be removed. Tapping Home returns to For You.
- **Streaming switcher:** a centered glass pill at the top, clear of the hero title: For You, Netflix,
  Apple TV+, Prime Video, Disney+, HBO Max, Hulu.
- **Home (For You and every service, one shared layout), exactly five sections:** Hero, Continue Watching,
  Top Trending (Movies | Series), Recently Released (Movies | Series), All-Time Greats (Movies | Series).
  Each switch keeps its own choice. No View All buttons. No title appears twice across rows
  (dedupe by type + TMDB id).
- **Sources ("bring back cineby", KP 2026-11-08):** For You's hero, Top Trending, Recently Released and
  All-Time Greats follow cineby.tech, filled from TMDB. Service pages show the service's full TMDB
  lists. Titles on Plex play; titles not on Plex show Play greyed out. Never filter Home to Plex-only.
- **Hero:** one title at a time, never glitchy; changed by swiping only (the swipe follows the finger),
  stretching-pill dots, no arrows. White Apple TV-style Play plus a round grey glass "+" (Plex Watchlist).
  A tap elsewhere opens Details.
- **Top Trending:** Netflix-style big outlined rank number beside each poster.
- **Continue Watching:** a card tap opens Details; only its Play plays. The menu ends with a red
  "Remove" with a minus-circle icon.
- **Details:** a card stacked over the page with an X; logo left (KP's mockup); the backdrop stays still;
  content rating pill first in the badge row, a plain "HDR" badge, official Dolby Vision and Atmos logos.
- **Long-press a title:** Details, Play, Download, Mark watched/unwatched, Go to season/show.
- **Search:** TMDB only, most popular first, spinner while loading.
- **Player:** iPhone landscape only, Infuse layout, double-tap skips (10 s default), swipe left side =
  brightness and right side = volume (toggle in Settings). Mac: a click on the picture only shows or hides
  the controls. Next Episode is a tap-only glass button in the last 15 s; nothing autoplays.
  Always the original file; Auto / HD / 4K only picks between existing versions.
- **Settings:** a server card, then Appearance, Navigation (iPhone), Playback, Library, Downloads,
  then Sources and About.
- **Loading screen:** the logo, and under it the server name with "Connecting…", then a checkmark and
  "Connected" before Home (KP, 2026-11-08). White and grey only.

The legacy Flutter app's tokens (`lib/astra/`) predate these rules and still contain violet; they are not
the reference.
