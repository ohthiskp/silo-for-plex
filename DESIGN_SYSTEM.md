# Astra — design system

The approved mockups in [`docs/design/`](docs/design/README.md) are the source of truth. This file records
the tokens and rules that implement them; the `astra-design-system` skill carries the same rules for agents.

## Direction
Cinematic and dark. Disney+/Netflix layout (hero, rows, cards), Apple liquid-glass materials for anything
floating (sidebar, tab bar, player controls, buttons). Violet is the only accent.

## Color
| Token | Hex | Use |
|---|---|---|
| `bg` | `#07060B` | Background |
| `surface` | `#15131D` | Cards |
| `surface2` | `#1C1A26` | Sheets, menus |
| `ink` | `#F2F0F7` | Primary text |
| `muted` | `#F2F0F7` @ 66% | Secondary text |
| `purple` | `#7C4DFF` | Accent, progress, focus |
| `purpleLight` | `#9B74FF` | Hover/highlight |
| `hairline` | white @ 9% | Borders, dividers |

## Type
- Display: Didot (fallback Bodoni 72, Georgia), regular, wide tracking (9–18), soft shadow — titles and logos-as-text.
- UI: system font; labels 500–700; meta line 14 pt with ` • ` separators.

## Shape
Pills and buttons fully rounded; cards 12–16 px; badges 4 px with a 25% white border.

## Materials
| Component | Blur | Fill | Border |
|---|---|---|---|
| `AstraGlass` | 24 | white 15% → 5% gradient over `#100E18` @ 40% | hairline |
| `AstraGlassButton` | 18 | white 18% | white 14% (outlined: 32%) |
| `AstraPlayButton` | — | white, or violet gradient `#8A5CFF → #7246F5` | — |
Blur only over still content; solid translucent fills over scrolling content.

## Motion
| Token | ms | Curve | Use |
|---|---|---|---|
| fast | 150 | easeOutCubic | Press, focus |
| base | 250 | easeOutCubic | Hover, chips |
| page | 380 | easeInOutCubic | Pages, sheets, menus |
| hero | 600 | easeInOutCubic | Hero crossfade, poster → details |
Reduced motion: fades at `fast` only. Animate opacity and transform, not layout.
Current code uses ad-hoc durations (120–650 ms); moving to these tokens is a roadmap item.

## Components
Hero, service pill switcher, content row, art card, continue card (with in-card subtitle and progress),
details header, glass sidebar, liquid-glass tab bar, settings card, player transport. Menus, sheets and
dialogs still use stock Material and are due an Astra version.

## Screens and their mockups
| Screen | Mockup | Implementation |
|---|---|---|
| Desktop home | `docs/design/desktop-home.png` | `lib/astra/home_view.dart` + `sidebar.dart` |
| iPhone home | `docs/design/iphone-home.png` | `home_view.dart` + `tab_bar.dart` |
| Apple TV home | `docs/design/appletv-home.png` | Not yet built (inherited TV home) |
| Desktop player | `docs/design/desktop-player.png` | `desktop_video_controls.dart` |
| iPhone player | `docs/design/iphone-player.png` | `mobile_video_controls.dart` |
| Movie/TV details | `docs/design/details.png` | `lib/astra/detail_screen.dart` |
| Settings | `docs/design/settings.png` | `lib/astra/settings_dashboard.dart` |
