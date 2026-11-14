# 00 · Executive summary: Astra UI/UX audit (2026-11-14)

Audit only. No production UI was changed. Scope: the SwiftUI app in `apple/` on `claude/project-thread-otuzui`
(head 59f839c; screenshots from f0df2ab, the build with the Settings redesign KP shipped today).

## Scores by platform

| Platform | Mean (0-100) | Band | Best screen | Weakest screen | Confidence |
|---|---:|---|---|---|---|
| iPhone (P0) | **67** | weak | Crash report 79, Movie details 75 | **Settings 54** | Medium-high: 13 current CI captures |
| Apple TV (P0) | **61** | weak | Movie details 70 | **Settings 51**, Watchlist 52 | Medium: 14 captures, focus only from code |
| Mac (P1) | **68** | weak (provisional) | Details 74 | Settings 58 | Low: older captures, partly from unmerged PR #12 |

Bands: 90+ excellent, 80s strong, 70s acceptable, 60s weak, under 60 redesign candidate. UX and UI are scored
separately in each scorecard: on almost every screen the **visual (UI) score beats the experience (UX) score**,
which matches KP's sense that Astra looks premium but Settings is hard to settle into. Settings UI is 60 on both
platforms; Settings UX is 52 (iPhone) and 47 (TV). The structure is the problem more than the styling.

## Biggest friction points

1. **Settings leads with decoration and ends with the controls** (iPhone 420 pt / TV 520 px Home preview first,
   everyday controls under the tab bar or below the fold).
2. **Two "Quality" settings and two "Subtitles"**, and the explanations were removed; Auto silently follows Library
   quality.
3. **Apple TV focus is ambiguous**: white means focused *and* selected *and* "primary"; Index Now looks focused at
   rest. (P0)
4. **Apple TV cycles values blind** on Select, and one stray press on Library quality reloads the whole library.
5. **10-foot legibility on TV**: chips, captions, badges and the provider rail are 16 to 22 px at 1080p.
6. **Library on iPhone stacks four rows of controls** before the first poster; Settings hides behind its gear.
7. **System states are thin**: "Checking…" never settles in any capture; TV Watchlist loads with plain text only;
   no captures exist for offline or empty states.

## Top 10 fixes (full list in `06-prioritized-backlog.md`)

1. B-01 TV: focus is the only white fill (P0, small look change, needs KP).
2. B-02 TV: confirm before a Library quality reload (P0, keeps the look).
3. B-03 Settings redesign, Direction C on iPhone and Apple TV (needs KP's pick).
4. B-04 iPhone: restore the three explanation footers (quality, library quality, service colours).
5. B-05 iPhone: Downloads row in Settings opens Downloads.
6. B-07 TV: scrim behind the top bar; fix overlap on scroll.
7. B-08 TV: tvOS type floor (29 px body, 25 px captions, 28 px badges).
8. B-11 iPhone Library: one control row, filters in a menu (needs KP).
9. B-13 Status line that settles instead of "Checking…".
10. B-15 KP decides the Mac navigation, then B-16 one Mac Settings surface.

## Settings recommendation

Direction **C, refined hybrid**, on both platforms (`05-settings-directions.md`, wireframes in `wireframes/`).
It keeps what KP approved today (server band first, live preview, quiet glass, no icon tiles) and fixes the
structure: a one-screen root with every value visible, previews inside their own pages, one name per concept, and
on Apple TV a list-and-pane layout where every choice is a focusable pill and focus is the only white fill.

## Skills used

- **Intent** (plugin, installed): `evaluate`, `journey`, `organize`, `fortify`, `include`, `wireframe` were read and
  their methods applied (Nielsen heuristics, cognitive walkthrough with the four questions, state inventory, WCAG
  checks, grayscale wireframes). Their HTML/Figma visualization prompts were not used; wireframes are plain HTML.
- **Impeccable**: **not available in this session.** The installed launcher (`anthropic-skills:impeccable`) points to
  the full skill inside KP's `mixa` repository, which this session can't read (repository access is limited to
  `silo-for-plex`). `critique` and `audit` were applied by hand from the guide's description (composition,
  hierarchy, spacing, states, contrast, focus, native code checks). **No Impeccable command was run.** `polish` is
  only for after approval anyway. To run it for real, add the `mixa` repo to this project or copy its
  `.claude/skills/impeccable/` folder into `silo-for-plex`.

## Evidence gaps

- No device or simulator run from this session; all visuals are CI captures (iPhone 17 Pro sim, Apple TV 4K sim) or
  older project-folder captures. Focus order, VoiceOver, Dynamic Type at large sizes, landscape transitions and Mac
  keyboard/resize were **not tested**; findings about them are from code and marked so.
- No captures for: iPhone Watchlist, Downloads, Settings sub-pages, sign-in, offline/server-down; TV Shows, About,
  crash screen; anything on the Mac head build except Settings.
- Only the Frosted Glass theme was graded (Light is being fixed in another thread).
- Pending work that will change grades: PR #16 (show page season picker), the light-mode/hero-logo thread, PR #12
  (Mac nav), PR #9 (bigger Details logos).

## Files

`01-screen-inventory.md` · `02-iphone-scorecard.md` · `03-appletv-scorecard.md` · `04-mac-scorecard.md` ·
`05-settings-directions.md` · `06-prioritized-backlog.md` · `07-design-system-rules.md` · `evidence/` (CI
screenshots) · `wireframes/` · `tools/scores.py` (recomputes every score).
