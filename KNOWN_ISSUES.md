# Astra known issues

Severity: **P0** core flow broken (no new features until fixed) · **P1** wrong behavior · **P2** polish.
The orchestrator keeps this file current. Newest first within each severity.

## SwiftUI app (`apple/`), 2026-11-07
Tracked in the stabilization plan (ROADMAP "S" milestones). Verified = CI build + `swift test`; nothing below
has been clicked through on a Mac by Claude (no Swift or screen access here).

| Sev | Issue | State |
|---|---|---|
| P0 | Change Server breaks Home/Shows (spinner, "No shows library") | **Fixed in code** (S1, e11f36f): validate before commit, old session kept on failure, generation tokens. Unit-tested; not yet tried by KP |
| P0 | Streaming-service switching slow, times out, endless spinner | **Fixed in code** (S1): paged shared library index, cancellable loads, errors with Try Again. Not yet tried by KP |
| P1 | Downloads stuck at 0%, second click cancels silently | **Fixed in code** (S3, 34d13cf): progress from bytes when size unknown, file checked on finish, reasons shown with Retry, cancel asks first, queue survives relaunch. Not yet tried by KP |
| P1 | Player black ~8 s before first frame | **Partly fixed** (S2): "Starting…" shows until mpv's first frame instead of black. Startup time itself not measured |
| P1 | Mac player window too big, not draggable; mini window keeps mini controls when enlarged | **Fixed in code** (S2): ~70% default size fitted to the video, drag anywhere, mini exits when resized past 720 pt or on full screen. Not yet tried by KP |
| P1 | Sidebar shows two selections / icons vanish mid-switch | **Fixed in code** (S4, 9f69097): one sliding white pill. Not yet tried by KP; snapshot tests not added |
| P2 | Streaming switcher overlaps hero title when scrolled | **Fixed in code** (S4): fades out once scrolled. Not yet tried by KP |
| P2 | Blue system accent | Fixed in 2f1d436, not yet confirmed by KP |
| P2 | No seek thumbnails; loading screen still the old one | **Fixed in code** (S5, c776f03): Plex BIF previews, white/grey loading screen ending on "Connected". Not yet tried by KP |
| P1 | No in-app updates | **Added** (Sparkle 2.6.4, feed branch `appcast-swiftui`, secret `SPARKLE_SWIFTUI_ED_SEED`). KP must install one build by hand. End-to-end update not tested |
| P2 | Hero showed old films | **Fixed in code**: TMDB trending matched to the library; fallback limited to the last 2 years |
| P2 | For You hero waits for the full library index on big libraries | Open |
| P3 | Downloads queued for a different server stay queued with no label until that server is chosen | Open |

## Test baseline (2026-11-06)
Full `flutter test` on Linux, Flutter 3.47.1, branch `astra-rename`: **8,287 passed, 8 skipped, 116 failed**
(the same suite on `main` has 118 failures; the rename fixed 2 and added none). A change may not add failures.

Failures by file (count). Most are tests that still expect pre-Astra behavior after the Astra redesign
(deep-link scheme changed to `astra://`, purple default theme, settings dashboard, new player controls,
hidden app-icon picker); each needs a decision: update the test or fix the code.

| File | Fails | Likely cause |
|---|---|---|
| `test/screens/settings/settings_screen_test.dart` | 22 | Settings now opens the Astra dashboard |
| `test/widgets/deep_link_dialog_test.dart` | 14 | Deep-link scheme `plezy://` → `astra://` |
| `test/services/deep_links/deep_link_service_test.dart` | 11 | Same |
| `test/services/deep_links/item_links_test.dart` | 10 | Same |
| `test/providers/theme_provider_test.dart` | 9 | Astra default theme and theme gating changes |
| `test/services/external_player_service_test.dart` | 8 | x-callback scheme |
| `test/services/deep_links/deep_link_test.dart` | 6 | Scheme |
| `test/screens/settings/theme_settings_screen_test.dart` | 6 | Theme changes |
| `test/screens/settings/app_icon_setting_test.dart` | 4 | Icon picker hidden in Astra |
| `test/models/external_player_models_test.dart` | 4 | Scheme |
| `test/widgets/video_controls_test.dart`, `_select_key_`, `_desktop_click_`, `_window_focus_` | 10 | Astra player controls (no clock, new layout) |
| `test/screens/discover_screen_test.dart` | 3 | Astra home replaces the hero/hub layout |
| `test/screens/catalog_search_screen_test.dart` | 3 | To triage |
| `test/screens/settings/logs_screen_test.dart` | 2 | Log upload disabled |
| `test/widgets/media_context_menu_test.dart` | 1 | To triage |
| `test/utils/memory_pressure_breadcrumbs_test.dart` | 1 | To triage |
| `test/screens/profile/profile_switch_screen_test.dart` | 1 | To triage |
| `test/android/network_security_config_test.dart` | 1 | Android only (not shipped) |

## P1
- **No automatic CI.** Every workflow is `workflow_dispatch`; nothing runs on pull requests.
- **Apple TV home not built to the mockup.** TV still uses the inherited home (`_buildTvContent`), details and settings.
- **No tests for `lib/astra/`** (3,583 lines).
- **Approved mockups missing from `docs/design/`.** UI can't be verified against them until added.

## P2
- Menus, sheets and dialogs are stock Material, not Astra glass; no shared motion tokens; page transitions
  are platform defaults. KP: wants it "very smooth" (ROADMAP M2).
- `BackdropFilter` blurs over moving content may drop frames (not yet measured on device).
- Mac build is not notarized (Gatekeeper "Open Anyway" on first launch).
- TMDB read token ships inside the app binary (low risk, read-only).
- Upstream-hosted service URLs (`ice.plezy.app`) remain in code although disabled in the UI.
- Analyzer warnings in Astra-edited files: unused import in `lib/astra/sidebar.dart`, `@visibleForTesting`
  use in `lib/astra/settings_dashboard.dart:531`, unused `_buildBottomNavigationBar` / `hideLabels` in
  `main_screen.dart`, unused `showHeroSection` in `discover_screen.dart`.
