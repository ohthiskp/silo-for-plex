# 05 · Settings directions (iPhone and Apple TV)

Nothing here is built. The wireframes are grayscale on purpose (layout, labels, selection and focus only) and
live in `wireframes/settings-wireframes.html`, rendered as:

- iPhone: `wireframes/settings-iphone-a.png`, `-b.png`, `-c.png`
- Apple TV: `wireframes/settings-tv-a.png`, `-b.png`, `-c.png`
- Before/after for the recommendation: `wireframes/before-after-iphone-settings.jpg`,
  `wireframes/before-after-appletv-settings.jpg`

Every direction shows the Settings root plus Appearance, Playback/Quality and Sources (server and index), with the
real option labels from the code.

## The problem in one paragraph

Today's Settings is one long page that leads with its most decorative element (a 420 pt / 520 px Home preview) and
ends with its most used controls, so it never settles. Two settings share the word "Quality", two share the word
"Subtitles", and the explanations that used to sit under them were dropped in the redesign. On Apple TV, a single
remote press cycles values blind and can reload the whole library, and white means both "focused" and "selected".
These are structure problems first; restyling the cards would not fix them.

## Shared settings taxonomy (all directions, all platforms)

Same words and same model everywhere; only layout differs by platform.

| Category | Settings (label → options) | iPhone | Apple TV | Mac |
|---|---|:-:|:-:|:-:|
| **Server** (status card, not a list row) | Omega · status · connection; Library index (progress, titles, last read, opening speed); **Index Now**; **Change Server…**; **Sign Out…** | ✓ | ✓ | ✓ |
| **Appearance** | Theme → Frosted Glass / OLED / Light / Violet; Service colours → On/Off; Coloured logos → On/Off | ✓ | ✓ | ✓ |
| **Playback** | Preferred version → Auto / HD / 4K (footer: "Original files only…"); Next Episode button → On/Off; *Gestures in the player* (iPhone only): Double-tap skips 10/15/30 s, Swipe for brightness and volume, Two-finger tap to pause | ✓ | ✓ (no gestures) | ✓ (no gestures) |
| **Subtitles** | When to show → Automatic / Always / Off; Font → Standard / Rounded / Serif / Condensed; Size → S / M / L / XL; Colour → White / Yellow / Cyan / Green / Grey; Background → Outline / Box; live sample | ✓ | ✓ | ✓ |
| **Library** | Library quality → HD / 4K (footer explains; confirm before reload); HD and 4K badges; Age ratings; "What the badges mean" | ✓ | ✓ | ✓ |
| **Downloads** | Wi-Fi only; Saved titles (count · size) → **Manage Downloads** | ✓ | — | ✓ |
| **Tab Bar** | Order and which tabs | ✓ | — | — |
| **About** | Version, Check for Updates (Mac), Licenses, Diagnostics | ✓ | ✓ | ✓ |

Persistent vs temporary: Settings holds **defaults**. Anything in the player (Apple TV player's Quality, audio track,
subtitle track) is **this film only** and is labelled that way ("This film: 4K · Default: Auto").

### Label changes proposed (each needs KP's OK)

| Today | Proposed | Why |
|---|---|---|
| Playback → Quality | **Preferred version** | It picks a file, it doesn't change quality; avoids clashing with Library quality and the player |
| Playback → Subtitles | **Subtitles → When to show** | Removes the second "Subtitles"; groups with the style editor |
| Saved titles (dead row) | **Downloads → Manage Downloads** | A row that looks tappable should open something |
| My List (TV details) | **Watchlist** | One name everywhere |
| Colour / Coloured | keep KP's spelling, but use it everywhere | Consistency (Mac/iPhone use "Colour", some code comments "Color") |

### Tradeoffs: nothing functional is removed

| Change | Gain | Cost / risk |
|---|---|---|
| Preview moves from the root into Appearance (and shrinks to ~190 pt on iPhone) | Root fits one screen; controls first | KP liked the big preview on top; it is still there, one tap in |
| Subtitle style moves from Settings root into a Subtitles page | One "Subtitles" place | One extra tap to reach style |
| Gestures move under Playback | Fewer top-level groups | Slightly longer Playback page |
| Footers come back | Auto, Library quality, accents explained | More text on screen (KP disliked "a subtitle under every line"; footers go only where a choice has a consequence) |
| TV: values become focusable pills instead of Select-cycles | No blind cycling; choices visible | More focus targets per row |
| TV: confirm before Library quality reload | No accidental reload | One extra press when you mean it |
| Sign Out moves from the footer to the Server page | Destructive action next to server actions | Not visible on the root |

---

## iPhone

### A. Ultra-native, minimal → `wireframes/settings-iphone-a.png`

Apple Settings exactly: grouped list, each row shows its current value, every sub-page a native form with
footers. **Root:** server row + index row, then Appearance, Playback, Subtitles, Library, Downloads, Tab Bar, About.
**Appearance:** theme list with small swatches and a tick. **Playback:** segmented Preferred version + footer, Next
Episode, Gestures. **Server:** status, connection, address, index details, Index Now, Change Server, Sign Out.

- Strengths: fastest to learn, perfect Dynamic Type and VoiceOver behaviour for free, cheapest to build.
- Weaknesses: loses the live preview KP liked and the cinematic tone; looks like any app.

### B. Cinematic editorial → `wireframes/settings-iphone-b.png`

A short magazine: full-bleed art header carrying the server status, then chapters ("Look", "Watch") with big
titles, one sentence and a big preview. **Appearance (Look):** full-height theme carousel, swipe between themes.
**Playback (Watch):** player-frame preview with the subtitle sample, big choice buttons. **Server:** index ring,
large Index Now.

- Strengths: most "Astra"; every page shows its effect.
- Weaknesses: longest scroll; renaming categories ("Look", "Watch") breaks platform convention; carousels hide
  options (H6 recognition over recall); heaviest to build and to keep accessible.

### C. Refined hybrid (recommended) → `wireframes/settings-iphone-c.png`

Keeps what KP approved in the shipped page (server band first, a live preview, quiet glass cards, no icon tiles,
no glow) but **moves each preview into its own page** so the root fits above the tab bar. **Root:** status card
(name, connection, index bar, Index Now) + five categories with values (Appearance, Playback, Subtitles, Library,
Downloads), then Tab Bar and About, version line. **Appearance:** ~190 pt live hero, four theme tiles,
streaming-service switches with one footer. **Playback:** Preferred version + "Original files only" footer, Next
Episode, Gestures. **Server:** status, per-library index counts, last read, opening speed, Index Now, Change Server,
Sign Out.

- Strengths: every value visible on one screen; previews kept where they help; native push navigation and
  scroll-edge behaviour; reuses existing `PhoneCard`/`PhoneRow` building blocks and the pages in
  `SettingsViews.swift`.
- Weaknesses: one more tap to see the theme preview than today.

**Why C for iPhone:** it fixes every P1 in the Settings deep-dive (preview pushing controls down, unexplained
quality pair, dead Downloads row, footer behind the tab bar) without throwing away the look KP signed off on
2026-11-14. A wins on pure usability but drops the cinematic feel that is Astra's point; B is the most beautiful and
the least usable.

## Apple TV

### A. Ultra-native, minimal → `wireframes/settings-tv-a.png`

tvOS's own Settings layout: a big context picture on the left, a focusable list on the right. Select pushes a
choice list with ticks (Preferred Version → Auto ✓ / HD / 4K); Menu goes back. Focus = filled row; selection = tick.

- Strengths: zero learning, standard focus engine behaviour, no ambiguity.
- Weaknesses: every change is a push and a pop; the live Home preview becomes a small side picture.

### B. Cinematic editorial → `wireframes/settings-tv-b.png`

A shelf of big category cards over a full-bleed backdrop that turns into the focused category's live preview
(Appearance → Home in that theme). Select opens a full-screen category page with big type and choice pills.

- Strengths: feels like the rest of the TV app (shelves, art); great for Appearance.
- Weaknesses: Server, Playback and Library don't have pictures worth a full screen; two levels of navigation for
  simple toggles; long press counts.

### C. Refined hybrid (recommended) → `wireframes/settings-tv-c.png`

Keeps the top bar and the server band KP approved; replaces the long page with a **left category list and a right
pane**. Right moves focus into the pane, Menu returns to the list. Each choice is its own focusable pill, so Left /
Right walks the options and Select saves (tick moves). **Focus is the only white fill on screen**; the saved choice
is a tick and a bold outline. Library quality asks before reloading. Appearance keeps a large live hero at the top of
its pane; Subtitles keeps the sample.

- Strengths: fixes the P0 focus ambiguity and blind cycling; Server band stays at a glance; matches tvOS split-view
  mental model; short press counts.
- Weaknesses: more custom focus code than A; pills must be at least 29 px text and 66 px tall to stay legible.

**Why C for Apple TV:** it is the smallest change that makes focus unambiguous and every choice visible, and it keeps
the pieces KP liked (band, live preview, top bar with gear). A is the safe fallback if C's custom focus handling
proves fragile on device.

## Remote focus behaviour for Direction C (spec level)

- Initial focus: first category ("Appearance") in the list. Never on Sign Out or Index Now.
- Up from the list's first row → top bar; Down from the last row stays (no wrap).
- Right from a category → first row of the pane, on the saved choice's pill (not the first pill).
- Left from the first pill of a row → back to the category list (not to another row).
- Menu: pane → list → top bar → leaves Settings.
- Selected-but-unfocused pill: tick + 2 px outline, no fill. Focused pill: white fill, black text, 1.08 lift.
- Index Now / Change Server: glass at rest, white only when focused.

## Approval needed

KP picks one direction per platform (or mixes, e.g. iPhone C + TV A) and confirms or rejects each label change
above. Implementation then goes one screen group at a time, per the guide's gates, starting with iPhone Settings.
