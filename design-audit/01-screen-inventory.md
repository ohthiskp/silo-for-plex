# 01 · Screen inventory and coverage

Routes come from the code on `claude/project-thread-otuzui` (head 59f839c; captures from f0df2ab). Only screens that
exist are listed. Legend: **C** = current CI capture in `evidence/`, **F** = older capture in the project folder
(`/mnt/project-files/screens/…`), **S** = source reading only, **—** = state not applicable, **✗** = no evidence.

## iPhone (`apple/AstraiOS/`, shared views in `apple/Shared/Views/`)

Tabs: Home, Search, Library by default (`TabLayout.defaultTabs`); Watchlist, Downloads and Settings can be added
(max 5). Settings otherwise opens as a sheet from the gear in Library (`LibrariesView.swift:28`).

| Screen | Source | Populated | Empty / first use | Loading | Failure / offline | Interaction state |
|---|---|:-:|:-:|:-:|:-:|:-:|
| Home / For You | `Shared/Views/HomeView.swift` | C `iphone-home.jpg`, `iphone-home-rows.jpg` | ✗ | S | S (`ServerHealthMonitor.swift`) | ✗ (hero swipe) |
| Provider Home | `HomeView.swift` (same layout) | F `hero-2026-11-09/` | ✗ | S | S | ✗ |
| Search | `AstraiOS/Views/PhoneSearchView.swift` | C `iphone-search-dune.jpg` | C `iphone-search.jpg` (idle, Popular Right Now) | S (spinner) | S ("No results" says why, QA P1-1) | C (typed query, scope All) |
| Library: Movies / Shows | `AstraiOS/Views/LibrariesView.swift`, `Shared/Views/LibraryViews.swift` | C `iphone-libraries.jpg` | ✗ | S | S | ✗ (sort sheet) |
| Library: Watchlist | `LibrariesView.swift` | ✗ | S | S | S (#14 error) | ✗ |
| Library: Downloads | `Shared/Views/DownloadViews.swift` | ✗ | S | S | S | ✗ |
| Movie details | `Shared/Views/DetailView.swift` | C `iphone-details-movie.jpg` | — | S | S | ✗ (⋯ menu) |
| Show details / season / episode | `DetailView.swift` (+ PR #16 pending) | C `iphone-details-show.jpg` | — | S | S | ✗ |
| Continue Watching | `HomeView.swift` | C (in `iphone-home-rows.jpg`) | ✗ | S | — | ✗ (long-press menu) |
| Player + overlays | `Shared/Player/PlayerOverlay.swift` | C `iphone-player-controls.jpg` | — | S | S | C `iphone-player-scrub.jpg` |
| Settings root (single page) | `Shared/Views/PhoneSettingsPage.swift` | C `iphone-settings.jpg`, `-subtitles`, `-gestures` | — | S ("Your Home appears here once it loads") | S (server "Checking…") | ✗ |
| Settings → Server (Sources) | `SettingsViews.swift` `SourcesSettings` | ✗ | — | S | S | ✗ |
| Settings → Tab bar | `SettingsViews.swift` `TabsSettings` | ✗ | — | — | — | ✗ |
| Settings → About | `SettingsViews.swift` `AboutSettings` | ✗ | — | — | — | ✗ |
| Sign in / server picker | `Shared/Views/SignInView.swift`, `RootView.swift` | ✗ | S | S | S | ✗ |
| Loading / connecting | `Shared/Views/LoadingView.swift` | ✗ | — | S | S | — |
| Crash report | `Shared/Views/CrashReportView.swift` | C `iphone-crash-report.jpg` | — | — | — | F (details) |

Not tested: compact vs large text sizes (no CI step sets a content size), VoiceOver, landscape transitions other
than the player.

## Apple TV (`apple/AstraTV/Views/`)

Top bar: Search (icon), Home, Movies, Shows, Watchlist, Settings gear on the right (`AstraTV/Views/MainView.swift`).
Provider rail: vertical circles on the left of Home (`TVHome.swift`).

| Screen | Source | Populated | Empty | Loading | Failure | Focused / remote state |
|---|---|:-:|:-:|:-:|:-:|:-:|
| Home / For You + rail | `TVHome.swift` | C `tv-home.jpg` | ✗ | S | S | C (launch focus on Home tab) |
| Provider Home | `TVHome.swift` | F `tv-topbar-icons-2026-11-09/2-hulu-chosen.jpg` | ✗ | S | S | F |
| Movies / Shows | `TVLibraryPage.swift` | C `tv-libraries.jpg` (Movies) | ✗ | S | S | C (Movies tab focused) |
| Search | `TVStyle.swift` / `MainView.swift` | C `tv-search.jpg` (idle) | C | S | S | C (search icon focused) |
| Watchlist | `TVLibraryPage.swift:210-230` | ✗ | S | C `tv-watchlist.jpg` | S (#14) | C |
| Movie details | `TVDetailPage.swift` | C `tv-details-movie.jpg` | — | S | S | ✗ (focus not visible in capture) |
| Show details / episodes | `TVDetailPage.swift` | C `tv-details-show.jpg`, `tv-details-show-episodes.jpg` | — | S | S | ✗ |
| Player controls / scrub | `TVPlayerOverlay.swift` | C `tv-player-controls.jpg`, `tv-player-scrub.jpg` | — | S | S | C |
| Player menu: Info / Settings / Subtitles | `TVPlayerOverlay.swift` | C `tv-player-info.jpg`, `-settings`, `-subtitles` | — | — | — | C (tab focused) |
| Settings | `TVSettingsPage.swift` | C `tv-settings.jpg`, `tv-settings-lower.jpg` | — | S | S | ✗ (no element focused in either capture) |
| Settings → About | `SettingsViews.swift` `AboutSettings` | ✗ | — | — | — | ✗ |
| Crash report (TV) | added in #14 | ✗ | — | — | — | ✗ |

Not tested: directional focus order, focus traps, Menu/back behaviour beyond the passing tvOS UI tests, overscan.

## Mac (`apple/AstraMac/`)

| Screen | Source | Evidence | Notes |
|---|---|---|---|
| Home | `HomeView.swift`, `AstraMac/Views/MainView.swift` | F `mac-nav-2026-11-12/1-home.jpg`, `13-hero-like-iphone.jpg` | From unmerged PR #12 (top-bar nav). Head has the icon sidebar (F `settings-2026-11-13/E-mac-settings-built.jpg`) |
| Details | `DetailView.swift` | F `mac-nav-2026-11-12/2-details.jpg`, `6-details-badges.jpg` | — |
| Movies / Shows | `LibraryViews.swift` | F `8-movies.jpg`, `10/11-movies-sort*.jpg` | — |
| Search | `LibraryViews.swift` | F `4-search.jpg` | — |
| Watchlist | `LibraryViews.swift` | F `9-watchlist.jpg` (error state) | — |
| Settings (in-app page) | `MacSettingsPage.swift` | F `E-mac-settings-built.jpg`, `F-mac-subtitles-built.jpg` | — |
| Settings (⌘, window) | `AstraMacApp.swift:51` → `SettingsView` Form | ✗ | Second, different settings surface |
| Player (window, full screen) | `PlayerWindow.swift`, `PlayerOverlay.swift` | F `player-2026-11-10/11-15` | — |

Not tested: resize and minimum width, keyboard navigation, hover, drag regions, multiple windows.

## Pending changes that will alter these screens

- **PR #16** "Show Details: season dropdown, open on the current episode, tap picks instead of plays" (open, thread
  "Redesign show page with season picker"). Show details grades should be redone after it merges.
- **Thread "Fix light mode and bigger hero logo"** (no PR yet): Light theme and the hero logo size. This audit graded
  Frosted Glass only.
- **PR #12** Mac navigation like Apple TV (open since 11-13). Mac grades depend on which nav ships.
- **PR #9** iPhone Details bigger title logos (open since 11-10, awaiting KP).
- **PR #15** crash report when iOS stops Astra (not UI-heavy).
