# 07 · Design system rules (inferred, not new styling)

These rules are read off what KP already approved (project memory, `DESIGN_SYSTEM.md`, the
`astra-design-system` skill, the shipped 2026-11-14 Settings and the mockups in
`/mnt/project-files/screens/settings-2026-11-13/`). They add no new colours or fonts. Where a rule is a proposal
from this audit, it says so; those need KP's OK.

## Tokens already in use (source: `apple/Shared/Design/Theme.swift`, `Platform.swift`)

| Token | Value / use | Keep |
|---|---|---|
| `Astra.Color.bg / surface / surface2` | #0A0A0B / #161618 / #1E1E21 (Frosted Glass, OLED) | ✓ |
| `Astra.Color.ink`, `muted` (ink 62%), `hairline` (white 9%) | text, secondary text, separators | ✓ |
| Accent | white by default; **no purple anywhere except the Violet theme** (KP 2026-11-09) | ✓ |
| Glass | Apple Liquid Glass APIs only (`Glass.swift`), on the floating layer (tab bar, top bar, switcher, player controls, menus), never on artwork or rows | ✓ |
| Type | system font, bold display; `astraFont` scales with Dynamic Type (`ScaledMetric`), tvOS via `textScale` | ✓ |
| Motion | fast 150 / base 250 / page 380 / hero 600 ms, Reduce Motion via `astraWithAnimation` | ✓ |
| Card radius | 18 pt (iPhone settings cards), 26 to 30 px (TV) | ✓ |
| Rows | 52 pt min (iPhone), 88 px (TV) | ✓ |

## Cross-platform rules

1. **Image first, chrome last.** Colour on screen comes from artwork; chrome is ink, muted and glass.
2. **One word per concept:** Watchlist (never My List), Preferred version (proposal), Library quality, Server,
   Index Now, Change Server, Sign Out. Same labels on iPhone, TV and Mac.
3. **Defaults vs this film:** Settings sets defaults; the player changes only the current title and says so.
4. **Every disabled action says why** in a short caption (e.g. "Not on Omega"). Proposal.
5. **Footers only where a choice has a consequence** (quality, library quality, accents). No subtitle under every row
   (KP 2026-11-13, "less AI").
6. **No icon tiles in Settings rows; chevron only where a page opens** (KP 2026-11-13).
7. **Every row that looks tappable does something.** Read-only values are plain text without chevrons.
8. **Status is a sentence that settles** ("Connected · Local network"), never an endless "Checking…". Proposal.
9. **Original files only** is stated next to the quality choice, never offered as a toggle (KP's standing rule).

## iPhone

- Safe areas: content scrolls under the Dynamic Island only with a scroll-edge effect or the system nav bar; the
  last item ends ≥ 16 pt above the floating tab bar.
- Tab bar: Liquid Glass, 52 pt; default Home, Search, Library; customizable (Home and Library fixed).
- Targets ≥ 44 pt (colour dots included). Text wraps; no `minimumScaleFactor` on labels. Proposal.
- Dynamic Type: support to xxxLarge today (cap in `RootView.swift:78`); lifting the cap is a separate decision.
- Player: landscape, Infuse-style, KP's 2026-11-10 control set (no ⋯, no PiP, subtitle glyph = tracks + Off).

## Apple TV

- **Focus is the only white fill on screen.** Selected-but-unfocused = tick and/or 2 px outline. Proposal (fixes P0).
- Focus lift: 1.04 for rows, 1.08 for pills, shadow on focus only (existing `TVSettingRowStyle`, `TVPillStyle`).
- **Select never cycles a value with more than two options**; choices are visible pills or a pushed list. Proposal.
- Anything that reloads data or signs out asks first.
- Type floor at 1080p: body 29 px, captions 25 px, nothing under 23 px. Badges ≥ 28 px tall. Proposal.
- Top bar: search icon, Home, Movies, Shows, Watchlist, gear on the right (KP 2026-11-09); scrim behind it when
  content scrolls under. Every page has a defined initial focus.
- No touch-only interactions; no downloads (KP 2026-11-08).

## Mac

- Navigation: **pending KP** (icon sidebar per guide vs Apple TV-style top bar per KP 2026-11-13 and PR #12).
- One Settings surface for ⌘, and in-app. Proposal.
- Pointer targets ≥ 28 pt; visible keyboard focus ring; player shortcuts Space, ←/→, F, Esc (present in code).
- Clicking the picture only toggles controls (KP 2026-11-07).
