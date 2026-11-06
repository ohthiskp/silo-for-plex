# Astra known issues

Severity: **P0** core flow broken (no new features until fixed) · **P1** wrong behavior · **P2** polish.
The orchestrator keeps this file current. Newest first within each severity.

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
