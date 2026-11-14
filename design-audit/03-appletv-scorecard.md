# 03 · Apple TV scorecard (P0)

Build audited: f0df2ab on `claude/project-thread-otuzui`, CI run
[43617198731](https://github.com/ohthiskp/silo-for-plex/actions/runs/43617198731), Apple TV 4K simulator at
1920×1080 (captured as 1280×720 JPEGs), demo server, Frosted Glass. Screenshots: `evidence/tv-*.jpg`. Scoring rules
and tags as in `02-iphone-scorecard.md`.

**Evidence gap:** CI captures are static frames from launch arguments. They show where focus lands at launch but
cannot prove focus order, focus traps or Menu-button behaviour. The tvOS UI tests in that run passed (step "Remote
UI tests"), which covers some remote navigation; everything else about focus here is from code reading and is
marked as such. No focus claim below says "passed" unless a test or capture shows it.

## Scores

| Screen | IA | Visual | Task | Platform | Consistency | A11y | States | **Total** | UX | UI | Band | Confidence |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---|
| Settings | 5 | 6 | 4 | 5 | 6 | 5 | 5 | **51** | 47 | 60 | redesign candidate | High |
| Home / For You + provider rail | 7 | 8 | 7 | 6 | 7 | 5 | 6 | **68** | 64 | 77 | weak | Medium |
| Movies / Shows browse | 6 | 6 | 6 | 6 | 7 | 5 | 6 | **60** | 59 | 63 | weak | Medium (Shows provisional) |
| Search | 6 | 6 | 6 | 6 | 6 | 5 | 6 | **59** | 59 | 60 | redesign candidate | Medium |
| Watchlist | 5 | 5 | 5 | 6 | 6 | 5 | 4 | **52** | 51 | 53 | redesign candidate | Medium (captured before the #14 error-state fix) |
| Movie details | 8 | 7 | 7 | 7 | 6 | 6 | 7 | **70** | 71 | 67 | acceptable | Medium |
| Show details, seasons, episodes | 6 | 7 | 6 | 7 | 6 | 6 | 5 | **63** | 61 | 67 | weak | Medium |
| Player and overlays | 7 | 6 | 7 | 8 | 7 | 6 | 7 | **68** | 71 | 63 | weak | Medium |

**Apple TV mean: 61 (weak).** The biggest gap is 10-foot legibility: many labels that read fine on a phone are
drawn at 16 to 22 px on a 1080p screen (see `evidence/tv-libraries.jpg`, `tv-search.jpg`).

## Per-screen findings

| Screen | Score | Evidence | Top 3 problems | Sev | Recommended change | Conf |
|---|---:|---|---|---|---|---|
| Settings | 51 | `tv-settings.jpg`, `tv-settings-lower.jpg`; `apple/AstraTV/Views/TVSettingsPage.swift` | 1 [Both] **Focus is not the only white thing.** "Index Now" is white at rest (`TVPillStyle(prominent: true)`, line 147 `let white = focused \|\| prominent`), selected segments are white, the selected-tab gear is white, so a viewer can't tell where focus is from across the room. 2 [Intent] Every multi-choice row cycles on Select (`selection = choices[(index + 1) % count]`, line 254): Font has four values and shows only the current one, so you press blind until you get there. 3 [Intent] Library quality has two values, so one stray press flips HD↔4K and immediately rebuilds the whole library (`.onChange(of: libraryQuality) { app.libraryQualityChanged() }`, line 525) with no warning. Also: the top bar sits over scrolled content with no scrim (`tv-settings-lower.jpg`, "Coloured logos" under the bar); no index details or Server page on TV. | **P0** (focus) / P1 | Direction C in `05`: left category list + right pane, each choice its own focusable pill, focus = only white fill, confirm before a library reload. | High |
| Home | 68 | `tv-home.jpg` | 1 [Impeccable] The provider rail on the left is circles about 38 px wide with wordmarks too small to read at 3 m. 2 [Intent] Hero Play is a grey pill for titles not on Plex with no reason given. 3 [Impeccable] The top bar text lies directly on busy hero art ("Movies", "Shows" over Avatar) without a scrim. | P1 | Rail circles at 80 to 96 px with a focused label; "Not on Omega" caption; top scrim behind the bar. | Medium |
| Movies / Shows | 60 | `tv-libraries.jpg` | 1 [Impeccable] Filter chips (All, Unwatched, Recently Added) and poster captions are about 16 to 20 px at 1080p, under the 29 px tvOS body size. 2 [Intent] Filters sit tight under the top bar and read as part of it. 3 [Intent] Shows view not captured. | P1 | tvOS type scale (body 29, caption 25 minimum); filter row below a page title. | Medium |
| Search | 59 | `tv-search.jpg` | 1 [Impeccable] The search field is a dim pill with low-contrast placeholder; nothing shows it is focusable. 2 [Impeccable] Scope and filter chips are tiny (about 18 px). 3 [Intent] Results grid density is phone-like (6 small posters per row). | P1 | System search field (`.searchable` keyboard row) or a large focusable field; 29 px chips. | Medium |
| Watchlist | 52 | `tv-watchlist.jpg`; `TVLibraryPage.swift:210-230` | 1 [Intent: fortify] Captured before #14: "Loading your Watchlist…" in small grey text, no spinner, nothing else on screen. #14 adds an error + Try Again, but loading still has no progress indicator. 2 Empty state copy is good ("Press + on any title") but small. 3 Called "My List" on Details, "Watchlist" in the top bar. | P1 | Spinner + skeleton grid while loading; one name (Watchlist) everywhere. | Medium |
| Movie details | 70 | `tv-details-movie.jpg` | 1 [Intent] "My List" label here vs "Watchlist" in the top bar (`TVDetailPage.swift:116`). 2 [Impeccable] Format badges (4K, Dolby) about 14 px tall, unreadable at distance. 3 [Impeccable] Resume at rest is grey glass, focus white; good, but the progress label "2h 21m left" is small. | P2 | Rename to Watchlist; badges ≥ 28 px tall. | Medium |
| Show details | 63 | `tv-details-show.jpg`, `tv-details-show-episodes.jpg` | 1 [Intent] Season and episodes start near the bottom edge, so the first Down press lands on a half-visible row. 2 [Intent] No season picker yet (PR #16 targets the show page; check whether it covers TV). 3 [Impeccable] Episode cards blank without stills. | P1 | Follow PR #16's model on TV: season menu + episode list in view on first Down. | Medium |
| Player | 68 | `tv-player-controls.jpg`, `-scrub`, `-info`, `-settings`, `-subtitles` | 1 [Impeccable] The Settings tab is a narrow table with labels far from values and "Audio —" for an empty value. 2 [Intent] "Quality Auto" in the player and "Quality" in Settings use the same word for a per-film choice and a default. 3 [Impeccable] Info tab poster is an empty grey box when art is missing. | P2 | Value-next-to-label rows; call the player one "This film" or show "Default (Auto)"; artwork fallback. | Medium |

## Settings deep-dive (Apple TV)

### Inventory

Source: `apple/AstraTV/Views/TVSettingsPage.swift`. Same keys as iPhone (see the table in `02`), minus Downloads,
Gestures and Tab bar, which the TV app doesn't have (KP: no downloads on TV).

| # | Group | Control | Options (default) | How it's operated today | Notes |
|---|---|---|---|---|---|
| 1 | Server band | Name, status line, index bar | — | not focusable | "Checking…" in every capture |
| 2 | Server band | Change Server | — | Select | Glass pill |
| 3 | Server band | Index Now | — | Select | **White at rest**: looks focused |
| 4 | Appearance | Live Home preview, 520 px tall | not focusable | — | Good use of space on TV |
| 5 | Appearance | Theme rows | Frosted Glass ✓, OLED, Light, Violet | Select picks | Tick for saved choice: good |
| 6 | Appearance | Service colours, Coloured logos | On, On | Select toggles | — |
| 7 | Subtitles | Sample + Font | Standard… Condensed | **Select cycles**, only current value shown | 4 values, blind |
| 8 | Subtitles | Size | S, M ✓, L, XL | Select cycles, segments shown | Visible but not directly choosable |
| 9 | Subtitles | Colour | 5 dots | Select cycles | — |
| 10 | Subtitles | Background | Outline, Box | Select cycles | — |
| 11 | Playback | Quality | Auto, HD, 4K | Select cycles | Auto follows Library quality (unexplained) |
| 12 | Playback | Subtitles | Automatic, Always, Off | Select cycles, only current shown | Same word as the Subtitles group |
| 13 | Playback | Next Episode button | On | Select toggles | — |
| 14 | Library | Library quality | HD, 4K (TV default 4K) | Select cycles | **Each press rebuilds the library** |
| 15 | Library | HD and 4K badges, Age ratings | On, On | Select toggles | — |
| 16 | Links | About and licenses | — | pushes About | — |
| 17 | Footer | Version, Sign Out | — | Select; asks first since #14 | — |

### Remote focus walk (from code; not run on a device)

Top bar → Down: lands in the server band (`.focusSection()` on the pills) → Down: Appearance column (themes,
switches, `.focusSection()`) → Down: the lower two columns; Left/Right moves between Subtitles and the
Playback/Library column (each a focus section) → Down to About → footer Sign Out. Back (Menu) leaves the page to the
top bar. Risks: (a) the preview is not focusable, so Up from the theme list jumps to the server band, skipping the
picture (fine); (b) from "Age ratings", Left goes to the Subtitles card at whatever row lines up, which can land on
"Colour" unexpectedly; (c) there's no visible focus on first arrival because the page has no default focus
(`tv-settings.jpg` shows no focused element). Severity P1 until tested on device.

### Journeys (remote presses from the Settings gear)

| Task | Today | Presses | Direction C | Presses |
|---|---|---:|---|---:|
| Change default quality to 4K | Down ×5 or so to Playback/Quality, Select ×2 (Auto→HD→4K) | ~7 | Down to Playback in list, Right, Right ×2 to 4K, Select | ~5 |
| Change subtitle font to Serif | Down to Font, Select ×2 (Standard→Rounded→Serif), no preview of options | ~6 | List → Subtitles, Right, Down, Right ×2, Select | ~6, all visible |
| Switch Library quality | One Select = instant reload | 1 (too easy) | Right to HD, Select, confirm | 3 (deliberate) |
| Check index status | Visible in the band | 0 | Visible in the band | 0 |
| Reconnect Plex | Down, Select "Change Server" | 2 | Same | 2 |

### Impeccable critique (Apple TV Settings)

The page is a scaled-up phone page: same cards, same 28 px rows. On TV the strongest moments are the large live
preview and the server band. The weakest: white as both "selected" and "focused"; segmented controls that look
directly choosable but aren't; a two-column lower half that makes Left/Right ambiguous; a footer Sign Out pill that
looks like a primary action. Type: 28 px row titles are at the low end for tvOS (29 px body); 23 to 24 px meta
lines ("16 titles open instantly · read 3 minutes ago") are too small at 3 m.
