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
| `accent` | white | Selection, progress, timeline, focus |
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
`Astra.Motion.resolved(_:reduceMotion:)` turns motion into fades for Reduce Motion. Animate opacity and
transform, not layout. The goal is "very smooth": nothing should snap or flicker.

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

## Behaviour rules
- Mac sidebar: Home, Movies, Shows, Downloads, Search, Settings; icons only; click to expand; one sliding indicator.
- One hero at a time; Continue Watching then numbered Top 10; no duplicate titles across rows.
- Streaming switcher: centered glass pill at the top, clear of the hero title.
- Long-press a title: Details, Play, Download, Mark watched/unwatched, Go to season/show.
- Loading screen: logo only, no text.

The legacy Flutter app's tokens (`lib/astra/`) predate these rules and still contain violet; they are not
the reference.
