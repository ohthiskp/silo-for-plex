# 06 · Prioritized backlog

Nothing here is started. Items marked **needs KP** change how something looks or what it's called and wait for KP's
OK; the rest are fixes that keep the approved look. Effort: S (under half a day), M (a day or two), L (several
days). Owners follow `CLAUDE.md` (design = `astra-design`, player = `astra-playback`, models = `astra-media`).

| ID | Pri | Platform / view | Change | Evidence | Expected benefit | Effort | Regression risk | Acceptance criteria |
|---|---|---|---|---|---|---|---|---|
| B-01 | P0 **needs KP** | TV Settings (`TVSettingsPage.swift`) | Focus is the only white fill: Index Now and selected segments become glass/outlined at rest | `tv-settings.jpg`; line 147 | Viewer always knows where focus is | S | Low (styles only) | In every TV Settings capture exactly one element is white-filled, and only when focused |
| B-02 | P0 | TV Settings | Confirm before Library quality reloads the library; no change on a single stray press | line 525, `AppModel.libraryQualityChanged` | No accidental full reload | S | Low | Pressing Select on Library quality shows a confirmation; Cancel leaves the library untouched (UI test) |
| B-03 | P1 **needs KP** | iPhone + TV Settings | Implement the chosen Settings direction (recommended C) | `05`, wireframes | Settings score 54→75+ (iPhone), 51→75+ (TV) target | L | Medium: many bindings move; keep keys | Every control in the `02`/`03` inventory still reachable and saving to the same key (test per key); KP approves screenshots |
| B-04 | P1 | iPhone Settings | Bring back the explanation footers for Quality/Preferred version, Library quality and Service colours (text exists in `SettingsViews.swift`) | K2, K3 | Auto/HD/4K and Library quality understood | S | Low | Footer text under those three controls; no other row gains a subtitle |
| B-05 | P1 | iPhone Settings | Downloads "Saved titles" opens Downloads | `PhoneSettingsPage.swift:416` | No dead row | S | Low | Tap opens Library → Downloads |
| B-06 | P1 | iPhone Settings | Footer and Sign Out fully above the tab bar; content doesn't scroll under the Dynamic Island without an edge | K2, K3 | Nothing hidden | S | Low | At the end of the scroll the footer's bottom is ≥ 16 pt above the tab bar |
| B-07 | P1 | TV all pages | Scrim behind the top bar when content scrolls under it; settings bar overlap fixed | `tv-settings-lower.jpg`, `tv-home.jpg` | Legible nav, no overlap | S | Low | Bar text contrast ≥ 4.5:1 over any artwork |
| B-08 | P1 | TV Library, Search, Details badges | tvOS type floor: body 29 px, captions 25 px, chips 29 px, badges ≥ 28 px tall | `tv-libraries.jpg`, `tv-search.jpg` | Readable at 3 m | M | Medium (layout reflow) | No text under 23 px at 1080p in the five TV captures |
| B-09 | P1 | TV Home rail | Provider circles 80 to 96 px with the service name shown on focus | `tv-home.jpg` | Rail usable from the couch | S | Low | Focused circle shows a readable name |
| B-10 | P1 | TV Watchlist | Spinner + skeleton grid while loading; keep #14's error + Try Again | `tv-watchlist.jpg` | No blank screen | S | Low | Loading state shows progress within 300 ms |
| B-11 | P1 | iPhone Library | One row for Movies / Shows / Watchlist / Downloads; filters and sort in one menu **needs KP** | `iphone-libraries.jpg` | Posters start ~100 pt higher | M | Medium | Library shows ≤ 2 control rows above posters |
| B-12 | P1 | iPhone + TV states | CI captures for offline, server down, empty Continue Watching, empty Watchlist, Downloads | `01` gaps | Evidence for fortify findings | M | None (CI only) | New `shot` lines in both launch workflows |
| B-13 | P1 | iPhone + TV Settings status | Settle "Checking…": show Connected/Unreachable once the check finishes, with time | all Settings captures | Trustworthy status | S | Low | Status text changes from Checking within 10 s in demo |
| B-14 | P2 **needs KP** | All | One name for the watchlist ("Watchlist", not "My List") | `TVDetailPage.swift:116` | Consistent language | S | Low | grep finds no "My List" in UI strings |
| B-15 | P1 **needs KP** | Mac nav | Decide Mac nav: icon sidebar (guide) or top bar (KP 11-13, PR #12) | `04` | Unblocks Mac audit | S | — | KP's decision recorded in memory and `DESIGN_SYSTEM.md` |
| B-16 | P1 | Mac Settings | One settings surface: ⌘, window shows the same pages as the in-app page | `AstraMacApp.swift:51`, `SettingsViews.swift:80` | No contradicting Settings | M | Medium | Both entry points render the same view |
| B-17 | P2 | iPhone + TV Home, Search | "Not on Omega" caption where Play is greyed | `iphone-home.jpg`, `tv-home.jpg` | Users know why they can't play | S | Low | Disabled Play always has a visible reason |
| B-18 | P2 | iPhone Search | Show that more filter chips exist (wrap or edge fade) | `iphone-search.jpg` | Bollywood chip findable | S | Low | All five chips visible or a fade at the edge |
| B-19 | P2 | iPhone + Mac player | VoiceOver adjustable actions for volume and brightness; verify Mac keyboard shortcuts on device | `PlayerOverlay.swift` | Player usable without gestures | M | Medium (player is sensitive) | VoiceOver can change volume; Space/←/→/F/Esc work on Mac |
| B-20 | P2 | iPhone Settings | Wrap labels instead of shrinking (`minimumScaleFactor(0.8)`); colour dots 44 pt targets | `PhoneSettingsPage.swift:91` | Large text works | S | Low | At xxxLarge no Settings label is truncated or shrunk |
| B-21 | P2 | TV player menu | Value-next-to-label rows; "This film" label for per-film quality | `tv-player-settings.jpg` | Persistent vs temporary clear | S | Low | Player Settings shows "This film: Auto (default Auto)" |
| B-22 | P2 | iPhone details | Hide the floating tab bar on the stacked details card | `iphone-details-movie.jpg` | Less clutter over actions and cast | S | Medium (navigation) | Tab bar hidden while a details card is open; returns on close |
| B-23 | P3 | All | Remove dead settings code (`AppearanceSettings`, `PlaybackSettings`, `LibrarySettings`, `DownloadSettings`, `SubtitleStyleSection`, `AccentPreset`, unused keys) once the new Settings lands | `02` inventory | Less confusion for agents | S | Low | Builds green; no reference left |
| B-24 | P3 | iPhone + TV | Artwork fallback for missing stills and posters (title on tinted card) | `iphone-home-rows.jpg`, `tv-player-info.jpg` | No empty grey boxes | S | Low | No blank card in any capture |

Order of work after approval (guide §8): B-02 (keeps the look) and B-01 (small look change, needs KP) → B-03 iPhone Settings
→ B-03 TV Settings → B-04 to B-13 → second wave screens → Mac.
