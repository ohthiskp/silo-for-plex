# Astra roadmap

Milestones run in order. A milestone is done only when it meets the completion rules in `CLAUDE.md`.
The orchestrator updates this file; dates are when the state changed.

| # | Milestone | State | Updated |
|---|---|---|---|
| M0 | Foundation | In progress | 2026-11-06 |
| M1 | Stabilize | Not started | — |
| M2 | Smooth motion and Astra menus | Not started | — |
| M3 | Apple TV home | Not started | — |
| M4 | Astra look everywhere | Not started | — |
| M5 | Release polish | Not started | — |

## M0 — Foundation
- [x] Audit current status (2026-11-06)
- [x] Rename visible Silo/Plezy wording to Astra (PR #1, awaiting Mac build + merge)
- [x] Agents, skills and project docs (this PR)
- [ ] Approved mockups added to `docs/design/` (needs KP)
- [ ] Test baseline recorded in `KNOWN_ISSUES.md`

## M1 — Stabilize
- [ ] Triage the failing baseline tests: fix, or record why they fail
- [ ] Run `astra-check` (analyze + tests) automatically on pull requests
- [ ] First tests for `lib/astra/` (home view, details, settings dashboard, TMDB client)
- [ ] Clear the analyzer warnings in Astra-edited files

## M2 — Smooth motion and Astra menus (KP: "very smooth")
- [ ] Motion tokens in `astra_style.dart`; move Astra widgets onto them
- [ ] Astra glass context menu, bottom sheet and dialog; replace the stock ones on Astra screens
- [ ] Poster → details transition; consistent page transitions
- [ ] Blur budget: no `BackdropFilter` over scrolling content
- [ ] Device check with the performance overlay on Mac, iPhone, Apple TV: no dropped frames on home scroll

## M3 — Apple TV home
- [ ] Build the Apple TV home to `docs/design/appletv-home.png` with remote focus states
- [ ] Details page on TV

## M4 — Astra look everywhere
- [ ] Search, library browse, downloads, profiles
- [ ] Settings subpages
- [ ] Episode details

## M5 — Release polish
- [ ] Notarize the Mac build
- [ ] Decide the update feed if the repo goes private

## Decisions pending
- Swift/SwiftUI rewrite: revisit after M2 (scope in the audit report).
