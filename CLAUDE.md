# Astra — instructions for Claude

Astra is KP's personal cinematic media player for Plex, on Mac, iPhone and Apple TV. It is a fork of an
open-source Flutter client, re-skinned with an Astra layer (`lib/astra/`). Product intent lives in
[PRODUCT.md](PRODUCT.md); how the code fits together lives in [ARCHITECTURE.md](ARCHITECTURE.md).

## Technology stack (as it exists)

| Layer | Technology |
|---|---|
| App | Flutter 3.47.1, Dart (`pubspec.yaml`, package name `plezy` — internal, do not rename) |
| UI | Flutter widgets; Astra screens in `lib/astra/`, inherited screens in `lib/screens/` and `lib/widgets/` |
| Playback | mpv via native players: Swift on Apple (`shared/apple/MpvPlayer/`, `macos|ios|tvos/Runner/MpvPlayer/`), Dart API in `lib/mpv/` |
| Apple TV | Custom tvOS Flutter engine (`tvos/engine.version`, `tvos/scripts/`) + Top Shelf extension |
| Metadata | Plex server APIs (`lib/services/plex_client*`), TMDB discovery (`lib/astra/tmdb_client.dart`) |
| Local data | Drift on SQLite (`lib/database/`, schema v25) + SharedPreferences (`lib/services/settings_service.dart`) |
| Updates | Sparkle feed on the `appcast` branch (Mac) |
| CI/CD | GitHub Actions, all `workflow_dispatch`: `astra-check`, `astra-macos`, `astra-ios`, `astra-tvos` |

There is no Tauri, React or Rust in this repo. Android, Windows and Linux code is inherited and not shipped.

## Repository structure

```
lib/astra/            Astra UI layer (home, details, settings dashboard, sidebar, tab bar, glass, TMDB)
lib/screens/          Inherited screens (library, search, player screen, settings subpages, profiles…)
lib/widgets/          Shared widgets incl. video_controls/ (Astra player controls live here)
lib/services/         Plex/Jellyfin clients, downloads, settings, updates, trackers
lib/database/         Drift schema + migrations (see DATABASE.md)
lib/mpv/              Dart side of the player
shared/apple/         Swift shared by macOS, iOS, tvOS (mpv core, deep links)
macos/ ios/ tvos/     Native runners and Xcode projects
test/                 676 Flutter test files (inherited)
tool/astra/           Release helpers (appcast, App Store Connect)
.github/workflows/    astra-check, astra-macos, astra-ios, astra-tvos
docs/design/          Approved mockup screenshots (the design source of truth)
.claude/agents/       Specialist subagents
.claude/skills/       Astra rule skills
```

## Orchestration: how agents collaborate

The main Claude session is the **orchestrator**. It plans, delegates, integrates and reports; it does not
hand the same file to two agents at once.

| Agent | Owns (may edit) | Never edits |
|---|---|---|
| `astra-engineer` | `lib/screens/`, `lib/navigation/`, `lib/providers/`, `lib/main.dart`, `lib/utils/`, native runners outside `MpvPlayer/`, `pubspec.*`, `.github/workflows/`, `tool/astra/` | `lib/astra/` visuals, mpv code, database schema |
| `astra-design` | `lib/astra/` (except `tmdb_client.dart`, `streaming_services.dart`), visual layout in `lib/widgets/video_controls/`, `DESIGN_SYSTEM.md` | Data, playback, services |
| `astra-playback` | `lib/mpv/`, `shared/apple/MpvPlayer/`, `*/Runner/MpvPlayer/`, `lib/screens/video_player*`, playback services (display mode, PiP, decode capabilities) | Control visuals (ask `astra-design`) |
| `astra-media` | `lib/astra/tmdb_client.dart`, `lib/astra/streaming_services.dart`, `lib/services/plex_client*`, `lib/services/catalog/`, `lib/media/`, `lib/models/`, `lib/database/`, `DATABASE.md` | UI |
| `astra-qa` | Nothing. Read-only; runs tests and reports | Any file |
| `astra-security` | Nothing. Read-only; reports | Any file |

Shared files (`pubspec.yaml`, `lib/main.dart`, generated `*.g.dart`, i18n JSON) are edited by one agent at a time,
named by the orchestrator. Docs `ROADMAP.md` and `KNOWN_ISSUES.md` are edited only by the orchestrator.

Run agents in parallel only when their owned files do not overlap. A change crossing two areas is split into
two tasks run in sequence, or given to one agent with the other area's owner reviewing.

## Engineering workflow (every task)

1. **Inspect before editing.** Read the code involved and its tests. Reproduce a bug before fixing it.
2. **Smallest task.** Cut the request into the smallest change that can be verified on its own.
3. **Delegate** to the owning specialist with a brief: goal, files, constraints, done criteria.
4. **Implement** the change.
5. **Verify:** `flutter analyze` (no new errors or warnings in touched files), the relevant `flutter test` files, and
   visual verification against `docs/design/` for any UI change (screenshot at the platform's size).
6. **Independent QA:** `astra-qa` reviews the diff and re-runs the checks without the implementer's summary.
7. **Fix failures** before moving on. Never mark a step done with a red check.
8. **Report** what was verified (commands + results) and what was not.
9. **Git checkpoint:** commit on a branch after validation passes; open or update a PR.
10. **Update** `ROADMAP.md` (milestone state) and `KNOWN_ISSUES.md` (new, fixed, still open).

Hard rules:
- Never report a feature as working unless it was tested; say "not tested" plainly when it wasn't.
- No new features while a P0 item in `KNOWN_ISSUES.md` is open, unless KP explicitly asks.
- No two agents edit the same file concurrently.

## Engineering standards

- Dart: follow `analysis_options.yaml`; run `dart format` on touched files (line length from the repo config).
- Keep Astra code in `lib/astra/` where possible; touch inherited files minimally and mark Astra edits with
  an `// Astra:` comment so upstream merges stay readable.
- Do not rename internal identifiers (`package:plezy`, `com.plezy/*` channels, bundle IDs, DB file names,
  `com.edde746.plezy` Kotlin package): they keep upstream merges and existing installs working.
- No secrets in code. Tokens arrive via `--dart-define` from GitHub secrets (see `astra-security`).
- Upstream-hosted services (`ice.plezy.app`, `bugs.plezy.app`, the Discord app, tracker app registrations)
  stay disabled.
- Swift: match the existing style in `shared/apple/`; `.swift-format` is the reference.

## Testing requirements

- Every behavior change ships with a test in `test/` mirroring the `lib/` path (`lib/astra/x.dart` → `test/astra/x_test.dart`).
- Bug fixes start with a failing test that reproduces the bug.
- Commands:
  - `flutter pub get --enforce-lockfile --no-example`
  - `flutter analyze lib test`
  - `flutter test <files>` for the touched area; the full `flutter test` before a release.
- Baseline: the suite already has failing tests (see `KNOWN_ISSUES.md`). Compare against the baseline; a change
  may not add failures.
- Native code (Swift/Xcode) cannot be built on Linux. Mac/iOS/tvOS builds are verified by running the
  `astra-macos` / `astra-ios` / `astra-tvos` workflow on the branch, or on KP's Mac.

## Design references

- The approved mockups are in `docs/design/` (filenames listed in `docs/design/README.md`):
  desktop home, iPhone home, Apple TV home, desktop player, iPhone player, movie/TV details, settings.
- They are the source of truth. Do not redesign these screens without KP's approval; implement toward them.
- Tokens, glass, typography and motion rules: [DESIGN_SYSTEM.md](DESIGN_SYSTEM.md) and the
  `astra-design-system` skill.

## Preserving existing functionality

- Astra plays real media daily. Playback, sign-in, server connection, Continue Watching, watch-progress
  sync and in-app updates must keep working after every change.
- Before editing an inherited file, read its tests; keep them passing.
- Prefer adding an Astra widget and switching to it over rewriting an inherited one in place.
- Never delete inherited features (downloads, Jellyfin, live TV, music) as a side effect; removing a
  feature is its own task, approved by KP.
- Database changes need a migration and a migration test (see `DATABASE.md`).

## How a milestone is completed

A milestone in `ROADMAP.md` is done only when:
1. Every task in it passed the workflow above, including independent QA.
2. Analyzer and tests are at or better than the baseline; new code has tests.
3. UI screens were compared to `docs/design/` and KP has seen screenshots.
4. Mac build ran via `astra-macos` (and iOS/tvOS when touched).
5. `astra-security` reviewed any new dependency, permission, credential or network host.
6. The PR is merged, `ROADMAP.md` marks it done with the date, and `KNOWN_ISSUES.md` is current.

Release steps: the `astra-release-checklist` skill.
