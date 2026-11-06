# Claude tools for Astra

Agents and skills that Claude Code loads when it works in this repo, locally and in cloud sessions. They
only help Claude build Astra; none of this ships in the app. The main session is the orchestrator — see
`CLAUDE.md` for the workflow and file ownership.

| Agent | Role | Edits |
|---|---|---|
| `astra-engineer` | Flutter/Dart architecture, navigation, native runners, CI | Yes |
| `astra-design` | UI to the approved mockups, glass, motion, menus | Yes |
| `astra-playback` | mpv, native Apple players, subtitles, HDR, performance | Yes |
| `astra-media` | Plex/TMDB metadata, discovery, SQLite | Yes |
| `astra-qa` | Independent testing and UI verification | No (read-only) |
| `astra-security` | Dependencies, credentials, permissions, licensing | No (read-only) |

| Skill | Use |
|---|---|
| `astra-design-system` | Before any UI change |
| `astra-playback-rules` | Before touching player code |
| `astra-metadata-rules` | Before metadata, discovery or database changes |
| `astra-release-checklist` | When shipping a build |

All of these were written for Astra; no third-party skills are bundled.
