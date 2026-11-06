# Video quality in Astra

How Astra decides what quality to play. The Flutter app implements this in
`lib/services/playback_quality_manager.dart`; the SwiftUI app should mirror
the same rules so both behave the same way.

## The setting

Settings → Playback → Preferred Quality. It has exactly three choices:

| Choice | Meaning |
| --- | --- |
| **Auto** (default) | The best compatible existing original file. |
| **HD** | Prefer an existing original at 1080p or below. If there is none, play the closest one that exists, as it is. |
| **4K** | Prefer an existing original 4K file. If there is none, play the best one that exists. |

**Astra always plays original files.** The setting only chooses between the
versions a title already has. It never transcodes, re-encodes or downscales,
and a title with only one file plays that file whatever the setting.

- The setting is stored per device (`video_quality_preference` in local
  settings). It is never exported or synced, so a phone and a TV keep their
  own value. Reset All Settings resets it to Auto.
- Playback never asks about quality. The only per-play choice left is
  **Play Version…**, which picks between the real files on the server
  (for example a Director's Cut), not a quality level.
- Captions are separate and unchanged.

## Playback engine

Astra plays everything through **libmpv** (the Swift `MpvPlayerCore` on
Mac, iPhone and Apple TV). AVPlayer is not used for playback; it is only
asked which HDR modes the TV supports. There is no adaptive HLS path on the
client, so `preferredMaximumResolution` and bitrate preferences do not
apply. Quality changes only in two ways:

1. **Picking another version** of the title that the server already has.
2. A Plex server transcode, which the quality setting never requests (see
   below for the two recovery paths that still can).

Astra only uses option 1. A file never switches quality by itself during
playback.

## Choosing the source

Runs once when a title is opened fresh: only when nothing else already
decided the version (no explicit Play Version pick, no downloaded copy, no
Watch Together file, no remembered per-show pick). Reloads, retries and
next-episode carry keep the version that is playing.

1. Take the server's versions of the title.
2. Drop versions whose file is missing, and versions this device should not
   be sent: a codec the user refused (desktop setting) or one the hardware
   probe says it has no decoder for (iPhone/Apple TV). If that leaves
   nothing, use all versions with a file.
3. Work out each version's tier from width and height together, snapped to
   480, 576, 720, 1080, 1440, 2160, 4320. Width counts so wide films stay in
   their tier: 1920×800 is 1080p, 3840×1600 is 4K.
4. Ceiling: Auto has none, HD is 1080, 4K is 2160.
5. Among versions at or under the ceiling, pick the tallest tier; for a tie,
   the higher bitrate; then the earlier one.
6. If every version is above the ceiling (HD with only 4K and 1440p files),
   pick the lowest one and play it as it is.

## No transcoding

Every setting starts playback at Original, so the server sends the file
itself and mpv decodes it on the device's normal hardware path at its native
resolution. Live TV plays channels as broadcast.

Two existing recovery paths can still ask Plex to transcode, and neither
comes from this setting:

- **Server refused the file (HTTP 500).** The player shows a dialog that
  offers a transcode; nothing happens unless you pick it.
- **Refused codecs (Mac only).** Under Playback → Video Codecs you can mark a
  codec this machine can't decode; files in that codec are transcoded. All
  codecs are accepted by default.

Changing the setting applies to the next playback. It does not restart the
one that is playing.

## Badges

The player shows badges for **what is really playing**, refreshed every few
seconds while the controls are visible:

- **Resolution** from mpv's decoded frame (`video-params/w`, `h`):
  `4K UHD` for the 2160 tier, `HD` for 720–1440, nothing below. It is the
  file that is playing, never the setting.
- **Dynamic range** from the native player's `astra-output-range` property,
  which reports what the display actually receives:
  - Apple TV: the display mode Astra asked tvOS for, already narrowed to
    what the TV supports: `Dolby Vision`, `HDR10`, `HLG` or `SDR`. Unknown
    (no mode requested because dynamic-range matching is off) shows nothing.
  - Mac and iPhone: `HDR` when the video layer is in EDR on a screen with
    HDR headroom, otherwise `SDR`. Dart then names it `HDR10` (PQ source) or
    `HLG`; a Dolby Vision file there shows `HDR`, never Dolby Vision.
  - SDR output, or an HDR file shown in SDR, shows no HDR badge.
- **HDR10+** is never shown: no Astra output path passes HDR10+ dynamic
  metadata to the display, so those files show HDR10.
- Dolby Vision is a text label. The official Dolby Vision logo needs a
  licence from Dolby and must follow their brand guidelines, so no logo
  artwork is included.

The detail page shows only the resolution badge of the version this device
would start (`4K UHD` or `HD`). It does not claim HDR or Dolby Vision,
because the output path is only known once playback starts.
