# Astra — instructions for Claude

Astra is KP's personal cinematic Plex player for Mac and iPhone (Apple TV later). The app being built is
the **native SwiftUI app in `apple/`**, Plex only. The Flutter app at the repository root is the
legacy app: it keeps shipping until SwiftUI replaces it and gets maintenance fixes only.
Product intent: [PRODUCT.md](PRODUCT.md). How the code fits together: [ARCHITECTURE.md](ARCHITECTURE.md).

## Technology stack

| Layer | SwiftUI app (`apple/`, active) | Legacy Flutter app (root) |
|---|---|---|
| UI | SwiftUI, Apple Liquid Glass (macOS/iOS 26) | Flutter 3.47.1 / Dart (`lib/`) |
| Logic | `AstraKit` Swift package (Plex, TMDB, downloads, storage) | `lib/services/`, `lib/astra/` |
| Playback | libmpv via the shared Swift core (`shared/apple/MpvPlayer/`, `macos|ios/Runner/MpvPlayer/`), MPVKit pinned in `project.yml` | Same mpv core |
| Data | Keychain token, UserDefaults, JSON files (see `DATABASE.md`) | Drift/SQLite schema v25 |
| Project | XcodeGen `apple/project.yml` (xcodeproj not committed) | Xcode projects in `macos/ ios/ tvos/` |
| Updates | Sparkle 2, feed branch `appcast-swiftui` | Sparkle, feed branch `appcast` |
| CI | `astra-swiftui-macos` (tests + builds), `astra-swiftui-ios` (TestFlight), `astra-swiftui-release` (Mac) | `astra-check`, `astra-macos`, `astra-ios`, `astra-tvos` |

No Tauri, React or Rust. Plex only: no Jellyfin, Emby or other servers in the SwiftUI app.

## Repository structure

```
apple/AstraKit/        Swift package: Plex/ Models/ Networking/ Storage/ TMDB/ Downloads/ + Tests/
apple/Shared/          SwiftUI shared by both apps: App/ (AppModel, LibraryStore, DownloadStore),
                       Design/ (Theme, Glass), Player/, Views/, Resources/
apple/AstraMac/        Mac shell (App/ incl. Sparkle Updater, Views/MainView = sidebar)
apple/AstraiOS/        iPhone shell (App/, Views/ = tab bar, libraries, search, watchlist)
apple/AstraiOSUITests/ UI tests
apple/project.yml      XcodeGen spec
shared/apple/MpvPlayer/, macos/Runner/MpvPlayer/, ios/Runner/MpvPlayer/   mpv core shared by both apps
lib/ test/ macos/ ios/ tvos/   Legacy Flutter app
.github/workflows/     astra-swiftui-* (SwiftUI), astra-* (Flutter)
tool/astra/            Signing, App Store Connect, appcast helpers
docs/design/           Approved mockups — the design source of truth
.claude/agents/ .claude/skills/   Specialist agents and rule skills
```

## Orchestration: how agents collaborate

The main session is the **orchestrator**: it plans, briefs, integrates and reports. It never gives the
same file to two agents at once.

| Agent | Owns (may edit) |
|---|---|
| `astra-engineer` | `apple/AstraMac/App/`, `apple/AstraiOS/App/`, `Shared/App/AppModel.swift`, `Demo.swift`, AstraKit `Networking/` `Storage/` `Package.swift`, `project.yml`, workflows, `tool/astra/`, legacy Flutter maintenance |
| `astra-design` | `Shared/Design/`, `Shared/Views/`, `AstraMac/Views/`, `AstraiOS/Views/`, `PlayerOverlay.swift` look, `DESIGN_SYSTEM.md`, `docs/design/README.md` |
| `astra-playback` | `Shared/Player/`, the shared mpv files, AstraKit `Plex/Playback.swift` `PlayerGeometry.swift` `SeekThumbnails.swift` |
| `astra-media` | Other AstraKit `Plex/` files, `Models/`, `TMDB/`, `Downloads/`, `Shared/App/LibraryStore.swift` `DownloadStore.swift`, `DATABASE.md` |
| `astra-qa` | Nothing (read-only review) |
| `astra-security` | Nothing (read-only review) |

- `project.yml` and `AppModel.swift` are shared hot spots: one agent at a time, named by the orchestrator.
- `ROADMAP.md` and `KNOWN_ISSUES.md` are edited only by the orchestrator.
- Run agents in parallel only when their files don't overlap. A change across two areas is split in
  sequence, or done by one owner with the other reviewing.

## Engineering workflow (every task)

1. **Inspect** the code and tests involved; reproduce a bug before fixing it.
2. **Smallest task** that can be verified on its own.
3. **Delegate** to the owner with goal, files, constraints and done criteria.
4. **Implement.**
5. **Verify:** push the branch and read the `astra-swiftui-macos` run (AstraKit `swift test`, Mac build,
   iPhone compile). Swift can't build in the Linux container. UI changes: compare a screenshot with `docs/design/`.
6. **Independent QA:** `astra-qa` reviews the diff and CI without the implementer's summary.
7. **Fix** failures; never mark a step done on a red or missing check.
8. **Report** what was verified (run IDs) and what wasn't, including "needs KP's device check".
9. **Git checkpoint:** commit on the branch, update the PR.
10. **Update** `ROADMAP.md` and `KNOWN_ISSUES.md`.

Hard rules:
- Never report a feature as working unless it was tested; a compile is not a test.
- Fix defects before new features (KP's stabilization order S1–S5 in `ROADMAP.md`), unless KP asks.
- No two agents edit the same file concurrently.

## KP's standing rules

- No purple or violet anywhere. Only Apple's official Liquid Glass.
- Always play original files: never transcode or downscale; quality picks between existing versions.
- Navigation = Home, Library (Libraries / Watchlist / Downloads), Search, Settings; Mac sidebar icons only,
  no hover expand, no sliding indicator. iPhone tabs are customizable (Home and Library always stay).
- Home (4.0): Hero, Continue Watching, Top Trending, Recently Released, All-Time Greats, each with its own
  Movies | Series switch; full cineby/TMDB lists (titles not on Plex show greyed Play); no View All.
- One hero at a time; no duplicate titles across rows; streaming switcher is a top glass pill.
- Details opens as a stacked card with an X. Long-press a title for Details/Play/Download/Mark/Go to.
- iPhone player is landscape, Infuse-style, double-tap ±10 s, swipe left side = brightness and
  right side = volume. iPhone tab bar is Liquid Glass with a draggable lens.
- Details for each are in the skills; KP's latest message beats everything written here.

## Engineering standards

- Swift 6 concurrency: UI state on `@MainActor`; no main-thread blocking.
- Never `Task.sleep(for:)` (aborts on iOS 27); use `Task.pause` from AstraKit.
- Design tokens from `Theme.swift`; no colour or spacing literals in views.
- Logic that can live in AstraKit goes there, with a test; views stay thin.
- Never commit `Astra.xcodeproj`. iPhone `MARKETING_VERSION` stays ≥ 3.1.0.
- No secrets in code: `TMDB_TOKEN`, `ASC_*`, `SPARKLE_SWIFTUI_ED_SEED` come from GitHub secrets.
- The shared mpv files must keep compiling for the Flutter app too.
- Keep LICENSE (GPL-3.0) and inherited copyright headers.

## Testing requirements

- New AstraKit logic ships with an XCTest in `apple/AstraKit/Tests/`; bug fixes start with a failing test.
- HTTP is mocked through `HTTPTransport`; no live Plex/TMDB/cineby calls in tests.
- UI behaviour with a test hook goes in `apple/AstraiOSUITests/` (use the `Demo.swift` launch flags).
- CI is the build: `astra-swiftui-macos` must be green on the head commit. KP's Mac checkout is
  `~/Developer/silo-for-plex` (`cd apple && xcodegen generate && open Astra.xcodeproj`).
- Legacy Flutter changes: `flutter analyze` + the touched tests; baseline 8,287 pass / 116 fail (`KNOWN_ISSUES.md`).

## Design references

- Approved mockups in `docs/design/` (listed in its README): desktop/iPhone/Apple TV home, desktop/iPhone/
  Apple TV player, details, settings. Implement toward them; don't redesign without KP's approval.
- Rules: [DESIGN_SYSTEM.md](DESIGN_SYSTEM.md) and the `astra-design-system` skill.

## Preserving existing functionality

- KP uses Astra daily. Sign-in, server connection, home, details, playback, resume/progress sync,
  downloads and updates must keep working after every change.
- Never remove a feature as a side effect; removal is its own task KP approves.
- Changing a stored format needs a migration and a test (`DATABASE.md`).
- The Flutter app keeps working until KP retires it.

## How a milestone is completed

1. Every task passed the workflow, including `astra-qa`.
2. `astra-swiftui-macos` green; new logic has tests.
3. UI compared to `docs/design/`; KP has tried the build on device and said it's good.
4. `astra-security` reviewed any new package, permission, host or secret.
5. Merged; `ROADMAP.md` marks it done with the date; `KNOWN_ISSUES.md` current.

Release steps: the `astra-release-checklist` skill.
