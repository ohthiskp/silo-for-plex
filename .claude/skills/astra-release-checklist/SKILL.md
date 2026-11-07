---
name: astra-release-checklist
description: Release checklist for the Astra SwiftUI app — Mac builds through Sparkle (appcast-swiftui) and iPhone builds through TestFlight (com.ohthiskp.astra), with the checks and evidence required before telling KP a build is ready. Load before cutting or announcing any build.
---
# Astra release checklist

## Before any build
- [ ] No open P0 in `KNOWN_ISSUES.md` that this build claims to fix without verification.
- [ ] `astra-swiftui-macos` CI green on the head commit (AstraKit tests, Mac build, iPhone compile). Cite the run.
- [ ] `astra-qa` returned PASS on the diff; `astra-security` approved any new package/permission/host/secret.
- [ ] Purple/violet grep clean; no `Task.sleep(for:)`.

## Mac (Sparkle)
- Workflow `astra-swiftui-release.yml`: builds, signs the update with `SPARKLE_SWIFTUI_ED_SEED`,
  publishes a prerelease tagged `swiftui-v0.1.0-build.<n>`, and force-pushes the feed to `appcast-swiftui`.
- [ ] Run finished green; the release asset and appcast entry exist (check with `gh api`).
- [ ] Build number increased; `SUPublicEDKey` unchanged.
- First install is by hand (KP downloads the DMG/zip once); later builds arrive via Check for Updates.

## iPhone (TestFlight)
- Workflow `astra-swiftui-ios.yml` on push to the SwiftUI branch: temporary signing
  (`tool/astra/asc_tv_signing.py`, `ASTRA_SIGNING_PLATFORM=IOS`), upload to the existing app
  `com.ohthiskp.astra`. Internal testing only.
- [ ] `MARKETING_VERSION` is 3.1.0 or higher (Flutter shipped 3.0.0); build number increased.
- [ ] Upload succeeded and processing finished; temporary certificate revoked.
- [ ] After KP installs: check `astra-testflight-crashes` / `astra-ios-symbolicate` for new crashes.

## Telling KP
- Say what changed, the build number, how to get it, what was verified (with run IDs) and what
  still needs KP's device check. Never call a feature working because it compiled.
- Update `ROADMAP.md` and `KNOWN_ISSUES.md` (orchestrator only).
