# 02 · iPhone scorecard (P0)

Build audited: `claude/project-thread-otuzui` at f0df2ab (the Settings redesign KP shipped 2026-11-14 16:43), CI run
[43617198676](https://github.com/ohthiskp/silo-for-plex/actions/runs/43617198676), iPhone 17 Pro simulator, demo server,
default text size, Frosted Glass theme. Screenshots are in `evidence/` (`iphone-*.jpg`). The newest head (59f839c,
QA fixes #14) only changed error copy, Sign Out confirmation and the TV crash screen, so these captures still represent it.

How to read the scores: each dimension is 0 to 10; **Total** = Σ(score ÷ 10 × weight) with weights IA 20, Visual 20,
Task 20, Platform 15, Consistency 10, Accessibility 10, States 5. **UX** = the five experience dimensions rescaled
to 100, **UI** = Visual + Consistency rescaled to 100. `tools/scores.py` recomputes every number. These are internal
heuristics, not Apple scores. "Provisional" means no current capture of that screen exists, so the grade leans on code.

Finding tags: **[Intent]** experience (Intent evaluate / journey / organize / fortify / include method),
**[Impeccable]** interface (Impeccable critique / audit method), **[Both]** when both passes found it (counted once).

## Scores

| Screen | IA | Visual | Task | Platform | Consistency | A11y | States | **Total** | UX | UI | Band | Confidence |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---|
| Settings | 5 | 6 | 5 | 6 | 6 | 5 | 5 | **54** | 52 | 60 | redesign candidate | High |
| Home / For You | 7 | 8 | 7 | 7 | 7 | 6 | 6 | **70** | 68 | 77 | acceptable | Medium |
| Provider Home (Netflix, Hulu...) | 7 | 7 | 7 | 7 | 8 | 6 | 6 | **70** | 68 | 73 | acceptable | Low (provisional) |
| Search: idle, results, filters | 7 | 7 | 7 | 7 | 6 | 6 | 7 | **68** | 69 | 67 | weak | Medium |
| Library: Movies / Shows browse | 6 | 6 | 6 | 7 | 6 | 6 | 6 | **62** | 62 | 60 | weak | Medium |
| Library: Watchlist | 6 | 6 | 6 | 7 | 7 | 6 | 6 | **62** | 62 | 63 | weak | Low (provisional) |
| Library: Downloads | 6 | 6 | 6 | 7 | 7 | 6 | 6 | **62** | 62 | 63 | weak | Low (provisional) |
| Movie details | 8 | 8 | 8 | 7 | 7 | 6 | 7 | **75** | 74 | 77 | acceptable | Medium |
| Show details, seasons, episodes | 6 | 7 | 6 | 7 | 7 | 6 | 5 | **64** | 61 | 70 | weak | Medium |
| Player and overlays | 7 | 8 | 8 | 8 | 7 | 5 | 7 | **74** | 72 | 77 | acceptable | Medium |
| Crash report | 8 | 8 | 8 | 8 | 8 | 7 | 8 | **79** | 79 | 80 | acceptable | High |
| Loading, offline, server-down states | 6 | 7 | 6 | 7 | 7 | 6 | 6 | **64** | 62 | 70 | weak | Low (provisional) |

**iPhone mean: 67 (weak).** The browsing and playing screens are acceptable to strong-looking; Settings, Library
and the system states pull the platform down. Visual UI scores (60 to 80) run ahead of UX scores (52 to 79)
almost everywhere: Astra looks better than it explains itself.

## Per-screen findings

`Platform | Screen | Weighted score | Evidence | Top 3 problems | Severity | Recommended change | Confidence`

| Screen | Score | Evidence | Top 3 problems | Sev | Recommended change | Conf |
|---|---:|---|---|---|---|---|
| Settings | 54 | `iphone-settings.jpg`, `-subtitles`, `-gestures`; `/mnt/project-files/screens/settings-2026-11-14/K1-K3`; `apple/Shared/Views/PhoneSettingsPage.swift` | 1 [Both] The non-interactive Home preview is 420 pt tall (`PhoneSettingsPage.swift:210`), so the first screen is a poster and the theme tiles you actually tap sit under the tab bar. 2 [Intent] Two "quality" controls (Playback Quality Auto/HD/4K, Library quality HD/4K) and two "Subtitles" (style editor, Playback row) with every explanation footer removed; Auto silently follows Library quality (`LibraryQuality.swift`, `PlaybackQuality.current`). 3 [Intent] By default Settings is only reachable from Library → gear (a sheet, `LibrariesView.swift:28`); Downloads "Saved titles" is a dead row; the version + Sign Out footer ends up behind the tab bar (K3). | P1 | Direction C in `05-settings-directions.md`: one-screen root with values, previews inside their own pages, footers back. | High |
| Home / For You | 70 | `iphone-home.jpg`, `iphone-home-rows.jpg` | 1 [Intent] Hero Play is grey for titles not on Plex with no words saying why (`iphone-home.jpg`); greyed titles in Recently Released read as disabled, not as "not on your server". 2 [Impeccable] Provider pills run off the right edge with no fade or count, and the tiny service wordmarks are hard to read. 3 [Impeccable] Continue Watching cards show an empty grey card when art is missing (demo shows it; real servers can hit it). | P2 | Add a one-line "Not on Omega" caption under a disabled Play; edge fade on the pill row; artwork fallback (title on a tinted card). | Medium |
| Provider Home | 70 (prov.) | Code (`HomeView.swift`); older `/mnt/project-files/screens/hero-2026-11-09/` | Same as For You, plus: service colour tint can lower text contrast on light provider colours; no current capture. | P2 | Capture each provider in CI; check contrast of tinted backgrounds. | Low |
| Search | 68 | `iphone-search.jpg`, `iphone-search-dune.jpg` | 1 [Impeccable] The Bollywood chip exists (`PhoneSearchView.swift:31`) but is off-screen with no scroll cue, so it looks missing. 2 [Intent] Result rows mix a white Play and grey disabled Play circles with no legend. 3 [Impeccable] Result cards are heavy glass boxes, about three results per screen; grid titles truncate ("The Super Mario…"). | P2 | Wrap the filter chips or fade the edge; label unavailable results; lighter list rows. | Medium |
| Library browse | 62 | `iphone-libraries.jpg`; `AstraiOS/Views/LibrariesView.swift` | 1 [Intent] Four stacked control rows (Libraries/Watchlist/Downloads, Movies/Shows, All/Unwatched/sort, grid/list) before any poster; the guide's target is Movies / Shows / Downloads. 2 [Intent] The gear here is the default way to Settings, an unexpected place. 3 [Impeccable] Two different pill styles (glass segmented vs white chips) on adjacent rows. | P1 | Merge the two switches into one segmented row (Movies, Shows, Watchlist, Downloads), filters into one menu; decide Settings' home (see backlog B-03). | Medium |
| Watchlist | 62 (prov.) | Code (`LibrariesView.swift`, `AppModel.swift:440-494`) | Error state exists since #14; no current capture; same four-row chrome as browse. | P2 | Capture in CI. | Low |
| Downloads | 62 (prov.) | Code (`DownloadViews.swift`) | No capture; Settings shows count and size but cannot open this page. | P2 | Link from Settings → Downloads; capture in CI. | Low |
| Movie details | 75 | `iphone-details-movie.jpg` | 1 [Impeccable] Format badges are small (about 9 pt text in the DOLBY marks). 2 [Intent] The floating tab bar stays over the details card, competing with the action row and cast. 3 [Intent] Secondary actions hide behind ⋯ with no hint. | P2 | Hide the tab bar on the stacked card; badge minimum height 18 pt. | Medium |
| Show details | 64 | `iphone-details-show.jpg`; PR #16 pending | 1 [Intent] Season list starts below the fold and the tab bar covers the episode strip (KP already flagged; PR #16 adds the season picker, opening on the current episode). 2 [Intent] Tapping an episode plays (fixed by PR #16: tap shows details, Resume or double-tap plays). 3 [Impeccable] Episode cards are blank without stills. | P1 | Land PR #16, then re-grade; this audit does not duplicate it. | Medium |
| Player | 74 | `iphone-player-controls.jpg`, `-scrub.jpg`; KP's 2026-11-10 spec | 1 [Intent: include] Brightness and volume are gesture-only (whole halves of the screen), with no VoiceOver alternative. 2 [Impeccable] 10 s skip icons are small (about 30 pt) next to a large Play. 3 [Intent] Subtitle glyph menu is tracks + Off only (KP's rule) so the subtitle style can only change in Settings. | P2 | VoiceOver adjustable actions for volume and brightness; keep KP's control set. | Medium |
| Crash report | 79 | `iphone-crash-report.jpg` | Clear and calm. "Not Now" is low contrast; technical details disclosure is small. | P3 | Raise "Not Now" contrast. | High |
| States | 64 (prov.) | Code: `LoadingView.swift`, `ServerHealthMonitor.swift`, `HomeView.swift`; settings shows "Checking…" in every capture | 1 [Intent: fortify] The server line reads "Checking… · Internet (remote)" in every capture and never settles. 2 No offline/server-down capture exists. 3 Empty Continue Watching and empty Watchlist copy unverified. | P1 | CI captures for offline and empty states; settle the health check text. | Low |

## Settings deep-dive (iPhone)

### Inventory: what Settings holds today

Source: `apple/Shared/Views/PhoneSettingsPage.swift` (page), `apple/Shared/Views/SettingsViews.swift` (pushed
pages), `apple/AstraKit/Sources/AstraKit/Storage/Preferences.swift` and siblings (keys). All values are per device in
`UserDefaults`.

| # | Group on screen | Control | Options (default) | Stored key | What it really does | Depends on / notes |
|---|---|---|---|---|---|---|
| 1 | Server card | Server name + status, chevron | — | session | Pushes Sources: name, type, health, address, connection, Library Index details, Change Server, Sign Out | The only way to Change Server or Sign Out besides the footer |
| 2 | Server card | Library index bar + **Index Now** | — | `LibraryStore.indexStatus` | Re-reads the whole server library in the background | Disabled while indexing |
| 3 | Appearance | Live Home preview (420 pt) | not a control | — | Shows Home's hero in the current theme | Takes about half the first screen |
| 4 | Appearance | Theme tiles | Frosted Glass (default), OLED, Light, Violet | `astra.appearance.appTheme` | Whole-app palette | Light theme is being fixed in another thread |
| 5 | Streaming services | Service colours | On | `astra.appearance.serviceAccents` | Tints a provider's Home page | Footer explaining it was dropped |
| 6 | Streaming services | Coloured logos | On | `astra.appearance.serviceLogoColors` | Off = plain white logos | — |
| 7 | Subtitles | Sample + Font | Standard, Rounded, Serif, Condensed | `astra.subtitles.font` | Player subtitle font, applied live | — |
| 8 | Subtitles | Size | S, M (default), L, XL | `SubtitleSize` key | — | — |
| 9 | Subtitles | Colour | White (default), Yellow, Cyan, Green, Grey | `astra.subtitles.color` | — | Swatches have no text labels on screen |
| 10 | Subtitles | Background | Outline (default), Box | `astra.subtitles.background` | — | Old `SubtitleLook` key migrates |
| 11 | Playback | Quality | Auto (default), HD, 4K | `astra.playback.preferredQuality` | Picks between existing files, never transcodes | **Auto follows Library quality**, invisible on screen |
| 12 | Playback | Subtitles | Automatic (default), Always, Off | `astra.playback.subtitles` | When subtitles turn on | Same word as group 7 to 10 |
| 13 | Playback | Next Episode button | On | `astra.playback.nextEpisode` | Tap-only button in the last 15 s | — |
| 14 | Gestures | Double-tap skips | 10 s (default), 15 s, 30 s | `astra.gestures.skipSeconds` | — | Player-only |
| 15 | Gestures | Swipe for brightness and volume | On | `astra.gestures.swipe` | — | — |
| 16 | Gestures | Two-finger tap to pause | On | `astra.gestures.twoFingerPause` | — | — |
| 17 | Library | Library quality | HD (iPhone default), 4K | `astra.content.libraryQuality` | HD hides 4K libraries everywhere; 4K swaps in 4K copies | Changing it rebuilds the library store (`AppModel.libraryQualityChanged`) |
| 18 | Library | HD and 4K badges | On | `astra.library.qualityBadges` | — | — |
| 19 | Library | Age ratings | On | `astra.library.ratings` | — | — |
| 20 | Downloads | Wi-Fi only | Off | `astra.downloads.wifiOnly` | Downloads wait for Wi-Fi | — |
| 21 | Downloads | Saved titles | read-only "0 · Zero KB" | — | — | Not tappable: no way to manage downloads from here |
| 22 | Links | Tab bar | Home, Search, Library | `astra.navigation.tabs` | Pushes the tab editor | Home and Library can't be removed |
| 23 | Links | About and licenses | — | — | Version, licenses, network diagnostics | — |
| 24 | Footer | Version · Sign Out | — | — | Sign Out asks first (since #14) | Sits behind the tab bar at the end of the scroll |

Dead or duplicate code (not user-facing, listed so the redesign doesn't lose or revive it by accident):
`AppearanceSettings`, `PlaybackSettings`, `LibrarySettings`, `DownloadSettings`, `SubtitleStyleSection` in
`SettingsViews.swift` are no longer reachable on iPhone (only `.tabs`, `.about`, `.sources` panes are pushed); they
still carry the good footers that the new page dropped. `Preferences.accentKey`, `Preferences.themeKey` and
`AccentPreset` are unused. No functional control should be removed in the redesign; the tradeoffs table in `05`
lists every move.

### Journeys (Intent journey + cognitive walkthrough)

Steps counted from the Home tab with default tabs (Home, Search, Library). "Fail" = two or more "no" answers on
the four walkthrough questions.

| Task | Today | Steps today | Walkthrough | Direction C | Steps in C |
|---|---|---:|---|---|---:|
| Change default playback quality | Library → gear → scroll past preview, appearance, streaming, subtitles → Playback Quality | 4 taps + 2 screens of scroll | Hesitation: "Quality" vs "Library quality", no explanation of Auto | Library → gear → Playback → segment (or Settings tab if added) | 4 taps, no scroll |
| Make sure original files play | No control (always original, by KP's rule); only said in a footer that is no longer shown | n/a | Fail: nothing tells the user it is guaranteed | Footer under Preferred version: "Original files only" | 0 extra |
| Change appearance / provider accents | gear → theme tile (often under tab bar) → scroll for Service colours | 2 to 3 taps + scroll | Pass for theme, hesitation for "Service colours" (no description) | gear → Appearance → tile / switch | 3 taps |
| Connect or reconnect Plex | gear → server card → Change Server… | 3 taps | Hesitation: server card doesn't look tappable for "change" | gear → server card → Change Server | 3 taps |
| Check indexing status | gear → read bar | 2 taps | Pass, but detail line truncates ("read 4 mi…") | gear → status card (full line) | 2 taps |
| Manage downloads | Settings row is dead; real path is Library → Downloads segment | 2 taps (not from Settings) | Fail from Settings | gear → Downloads → Manage Downloads, or Library → Downloads | 3 taps |
| Understand content badges | Toggles only; no legend | n/a | Fail: no place explains 4K / HDR / Dolby / rating boxes | Library page footer + a "What the badges mean" row | 3 taps |
| Persistent vs temporary | Settings Quality vs the player has no quality control on iPhone (KP's rule) but does on Apple TV ("Quality Auto" in the player's Settings tab) | — | Hesitation on TV, see 03 | Settings says "Default"; the player says "This film" | — |

### Impeccable critique (by hand, method of `critique`)

- **Header:** large "Settings" title is good; content then scrolls under the Dynamic Island and clock with no scroll
  edge material (K2: "Coloured logos" sits under 7:34). Use the system large-title nav bar or a soft top edge.
- **Grouped rows:** quiet glass cards, 52 pt rows, hairlines: calm and consistent. Section titles (15 pt muted) are
  smaller than row text (17 pt), which is right, but "Appearance" is a 26 pt bold header while every other group is a
  15 pt caption: two header systems on one page.
- **Icons:** none in rows (KP's "less AI" rule), which works; chevrons only where a page opens.
- **Typography:** single family, good weights. Row titles use `minimumScaleFactor(0.8)` and `lineLimit(1)`
  (`PhoneSettingsPage.swift:91`), so at larger text sizes labels shrink instead of wrapping.
- **Spacing:** 28 pt between groups, 16 pt side margins: fine. The preview breaks the rhythm.
- **Selected states:** themes use a 2 pt ring + bold label; segmented controls use the system grey thumb; switches
  use `switchOn` white. Three selection languages on one page, all readable.
- **Status indicator:** a 7 pt dot in ink vs muted is the only connection signal; "Checking…" never resolves in
  captures.
- **Premium feel:** strongest at the top (art), weakest at the bottom (a long list of same-weight cards, footer
  under the tab bar). The page is "hard to settle into" because the most decorative element is at the top and the
  most used controls are at the bottom.

### Impeccable audit (technical, by hand)

- Dynamic Type is supported through `ScaledMetric` (`Theme.swift:393`) but capped at xxxLarge in `RootView.swift:78`;
  accessibility sizes never apply.
- VoiceOver: theme tiles carry `.isSelected`; colour swatches rely on `SubtitleColorPicker` labels (not verified on
  device); the preview is grouped as "Preview of Home". Only 2 explicit accessibility labels in the file.
- Tap targets: 52 pt rows pass; colour dots are 24 pt (below the 44 pt guideline) on iPhone.
- Bottom inset: `contentMargins(.bottom, tabBarRoom)` exists but K3 still shows the footer behind the bar.

### Severity summary (Settings)

P1: the 420 pt preview pushing controls down; unexplained quality pair; no default route to Settings beyond a gear
in Library; dead Downloads row. P2: header collision with the Dynamic Island; text shrinking instead of wrapping;
24 pt colour targets; footer behind tab bar. P3: two header systems; mixed selection styles.
