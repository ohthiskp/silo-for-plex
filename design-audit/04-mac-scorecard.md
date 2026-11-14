# 04 · Mac scorecard (P1, all grades provisional)

**Why provisional:** there is no Mac screenshot step in CI for the head commit, and the Mac couldn't be run from
this cloud session. Evidence is the most recent captures in the project folder, which come from different builds:

- `/mnt/project-files/screens/mac-nav-2026-11-12/` (Home, Details, Movies, Search, Watchlist, Settings): these are
  from **PR #12 "Mac navigation like Apple TV" (branch `claude/project-thread-da7j4r`), which is not merged**. The head
  build still has the icon sidebar on the left.
- `/mnt/project-files/screens/settings-2026-11-13/E-mac-settings-built.jpg` (head-equivalent Settings, icon sidebar).
- `/mnt/project-files/screens/player-2026-11-10/11-15` (Mac player).

Untested and therefore not graded as passing: window resize below 900 px, keyboard focus order, keyboard shortcuts,
hover states, multiple windows, drag regions. These need a real Mac run (see evidence gaps in `00`).

## Scores

| Screen | IA | Visual | Task | Platform | Consistency | A11y | States | **Total** | UX | UI | Band | Confidence |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---|
| Home | 7 | 8 | 7 | 6 | 7 | 6 | 6 | **69** | 66 | 77 | weak | Low (provisional) |
| Details | 8 | 8 | 8 | 6 | 7 | 6 | 7 | **74** | 72 | 77 | acceptable | Low (provisional) |
| Movies / Shows browse | 7 | 7 | 7 | 7 | 7 | 6 | 6 | **68** | 68 | 70 | weak | Low (provisional) |
| Search | 7 | 7 | 7 | 7 | 6 | 6 | 7 | **68** | 69 | 67 | weak | Low (provisional) |
| Watchlist (error state) | 7 | 7 | 7 | 7 | 7 | 6 | 8 | **70** | 69 | 70 | acceptable | Low (provisional) |
| Settings (in-app page + Settings window) | 5 | 7 | 6 | 5 | 5 | 6 | 6 | **58** | 55 | 63 | redesign candidate | Low (provisional) |
| Player | 7 | 8 | 7 | 6 | 7 | 5 | 7 | **68** | 65 | 77 | weak | Low (provisional) |

**Mac mean: 68 (weak, provisional).**

## Findings

| Screen | Score | Evidence | Top 3 problems | Sev | Recommended change | Conf |
|---|---:|---|---|---|---|---|
| Home | 69 | `mac-nav-2026-11-12/13-hero-like-iphone.jpg` (PR #12) | 1 [Intent] Navigation differs between head (icon sidebar) and PR #12 (top bar + provider circles); the guide asks for an icon-only expandable sidebar, KP's 11-13 ask is the Apple TV-style top bar. This must be settled before any Mac polish. 2 [Impeccable] Provider circles are small for pointer targets (about 36 px). 3 [Intent] Grey Play with no reason, as on iPhone. | P1 | KP to confirm Mac nav (backlog B-15); then grade again. | Low |
| Details | 74 | `6-details-badges.jpg` | Stacked card with ⋯ and X works well with a pointer; badges small; long synopsis line length (~110 characters) is long for reading. | P2 | Cap synopsis width ~70 characters. | Low |
| Movies | 68 | `11-movies-sort-v2.jpg` | Sort options as inline segmented pills are clear; five posters per row at 1400 px wastes width; no visible keyboard focus in capture. | P2 | Adaptive grid; check focus ring. | Low |
| Search | 68 | `4-search.jpg` | Same small chip sizes as TV; good results grid. | P3 | — | Low |
| Watchlist | 70 | `9-watchlist.jpg` | Good error state: icon, reason, Try Again. This is the pattern iPhone and TV should copy. | P3 | Reuse on TV/iPhone. | Low |
| Settings | 58 | `E-mac-settings-built.jpg`; `Shared/Views/MacSettingsPage.swift`; `AstraMac/App/AstraMacApp.swift:51`; `SettingsViews.swift` root Form | 1 [Intent] **Two Settings on the Mac**: the in-app page (`MacSettingsPage`, from the sidebar) and the ⌘, Settings window (`SettingsView` → old Form with icon tiles and subtitles under each row, `SettingsViews.swift:80-130`), with different layouts and wording. 2 [Intent] Same quality/subtitles duplication as iPhone. 3 [Impeccable] Status line truncates ("Checking… · Internet (remote) · demo…"). | P1 | One settings model; the ⌘, window shows the same pages as the in-app page. | Low |
| Player | 68 | `player-2026-11-10/11-15` | 1 [Intent: include] Keyboard control exists in code (Esc, F, Space, ←/→ in `PlayerOverlay.swift:244-553`) but no capture or test shows it working. 2 [Impeccable] Small 10 s icons, as on iPhone. 3 Title over a busy frame without scrim in the windowed player. | P2 | Verify keyboard shortcuts on device; add to backlog acceptance. | Low |
