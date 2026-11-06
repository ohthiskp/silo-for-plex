---
name: astra-design-system
description: Astra's visual rules — palette, glass materials, typography, spacing, motion tokens, menus and sheets, and how to check UI against the approved mockups in docs/design. Use before any UI change in Astra.
---
# Astra design system

Astra is a cinematic media player: dark, image-led, calm. References: Disney+ and Netflix for layout and
rows, Apple liquid glass for materials. The approved mockups in `docs/design/` win over this file.

## Before you change UI
1. Open the mockup for the screen (see `docs/design/README.md`). No mockup → ask the orchestrator; do not invent one.
2. Find the existing Astra widget in `lib/astra/` and reuse its tokens.
3. Never redesign an approved screen without KP's written approval.

## Tokens (source: `lib/astra/astra_style.dart`)
| Token | Value | Use |
|---|---|---|
| `AstraColors.bg` | `#07060B` | App background |
| `AstraColors.surface` / `surface2` | `#15131D` / `#1C1A26` | Cards, sheets |
| `AstraColors.ink` / `muted` | `#F2F0F7` / 66% ink | Text |
| `AstraColors.purple` / `purpleLight` | `#7C4DFF` / `#9B74FF` | Accent, focus, progress |
| `AstraColors.hairline` | 9% white | Dividers, glass borders |

- Display titles: `AstraTitleText` — Didot (fallback Bodoni 72, Georgia), wide letter spacing, soft shadow.
- Body: system font, weights 500–700 for labels.
- Pills and glass buttons: fully rounded (`radius = height / 2`); badges 4 px radius.

## Glass
- `AstraGlass` (blur 24, white 15→5% gradient, 9% hairline) for floating bars and panels.
- `AstraGlassButton` (blur 18) for secondary actions; `AstraPlayButton` (white or violet gradient) for primary.
- Blur only over still content (hero, player). Over scrolling lists use a solid translucent fill instead:
  `BackdropFilter` re-renders every frame and is the main cause of dropped frames.

## Motion
Use one set of tokens everywhere (define them in `astra_style.dart` as `AstraMotion` if missing):
| Token | Duration | Curve | Use |
|---|---|---|---|
| `fast` | 150 ms | `easeOutCubic` | Press feedback, focus ring |
| `base` | 250 ms | `easeOutCubic` | Hover, chips, small reveals |
| `page` | 380 ms | `easeInOutCubic` | Page and sheet transitions |
| `hero` | 600 ms | `easeInOutCubic` | Hero crossfade, poster → details |
- Respect `MediaQuery.disableAnimations` (reduced motion): drop to fades of `fast`.
- Animate transform and opacity only; never animate layout size in scrolling lists.

## Menus, sheets, dialogs
Use Astra versions (glass surface, `surface2` fill, 16 px radius, `page` motion) instead of stock
`showMenu`, `PopupMenuButton`, `showModalBottomSheet`, `showDialog`. Keep every action and keyboard/remote path.

## Platform notes
- Mac/iPad: floating glass sidebar; content runs full width beneath it.
- iPhone: floating liquid-glass tab bar (Home, Search, Downloads + Settings); respect safe areas.
- Apple TV: 10-foot sizes, clear focus scale (1.06–1.1) with violet glow; every element reachable by remote.

## Verify
Screenshot the screen at the mockup's size, compare side by side, and list differences. A golden test
(`matchesGoldenFile`) for stable widgets.
