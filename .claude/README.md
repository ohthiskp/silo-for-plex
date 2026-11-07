# Astra Claude setup

The main session is the orchestrator: it plans, briefs one specialist per area, runs `astra-qa` on the
result, and reports. Ownership and the workflow are in `../CLAUDE.md`.

| Agent | Area | Edits? |
|---|---|---|
| `astra-engineer` | App shells, AppModel, AstraKit networking/storage, project.yml, CI, release tooling, legacy Flutter | Yes |
| `astra-design` | Views, Theme/Glass, motion, mockup fidelity | Yes |
| `astra-playback` | mpv core (shared with Flutter), player, PiP, seek thumbnails, HDR | Yes |
| `astra-media` | Plex client, TMDB/cineby, library quality, downloads, storage formats | Yes |
| `astra-qa` | Independent review via diff, CI runs and KP's rules | No |
| `astra-security` | Packages, entitlements, ATS, secrets, signing, Sparkle | No |

Skills: `astra-design-system`, `astra-playback-rules`, `astra-metadata-rules`, `astra-release-checklist`.

Swift can't be built in the Linux cloud container: builds and tests run in GitHub Actions
(`astra-swiftui-macos`) or on KP's Mac (`~/Developer/silo-for-plex`, `cd apple && xcodegen && open Astra.xcodeproj`).
