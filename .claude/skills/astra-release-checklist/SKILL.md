---
name: astra-release-checklist
description: Step-by-step checklist for shipping an Astra build — version bump, verification gates, Mac DMG and update feed, iOS/tvOS TestFlight, and post-release docs. Use when preparing or publishing a release.
---
# Astra release checklist

Do the steps in order. Stop at the first failure, fix it, and restart from that step.

## 1. Ready to release
- [ ] No open P0 in `KNOWN_ISSUES.md`.
- [ ] All milestone PRs merged into `main`; `ROADMAP.md` is current.
- [ ] `astra-security` approved any new dependency, permission or host since the last release.

## 2. Version
- [ ] Bump `version:` in `pubspec.yaml` (`MAJOR.MINOR.PATCH+BUILD`; build number always increases).

## 3. Verify
- [ ] `flutter pub get --enforce-lockfile --no-example`
- [ ] `flutter analyze lib test` — no errors
- [ ] Full `flutter test` — no failures beyond the baseline in `KNOWN_ISSUES.md`
- [ ] `astra-qa` independent review: PASS
- [ ] UI screens compared with `docs/design/`

## 4. Mac
- [ ] Run **Astra macOS** (`astra-macos.yml`) with `publish: false` first; download the artifact and smoke test:
      launch, sign in, home loads, play a HEVC/HDR file with subtitles, resume works, quit.
- [ ] Run again with `publish: true` → GitHub release with `Astra.dmg` and `Astra.zip`, appcast updated.
- [ ] On an installed older build, **Check for updates** finds and installs the new version.

## 5. iPhone / Apple TV (when changed)
- [ ] Run **astra-ios** / **astra-tvos**; confirm the TestFlight build processes.
- [ ] Smoke test on device: sign in, home, details, play, Apple TV focus navigation.

## 6. After release
- [ ] Tag noted in `ROADMAP.md` with the date; fixed items closed in `KNOWN_ISSUES.md`.
- [ ] Report to KP: version, what changed, what was tested, what wasn't.
