# Astra

A media app for your Plex server on Mac (and iPhone soon), built for smooth playback.

- Plays almost anything straight from your server (HEVC, AV1, Dolby Vision, HDR10+, DTS, TrueHD, ASS/PGS subtitles) using the mpv player, so your server rarely has to convert video.
- Its own native app: own window, own Dock icon, no browser.
- Updates itself from inside the app.

## Install (Mac)

1. Download **Astra.dmg** from the [latest release](https://github.com/ohthiskp/silo-for-plex/releases/latest).
2. Open it and drag **Astra** into **Applications**.
3. The first time, macOS says it can't verify the app. Open **System Settings → Privacy & Security** and click **Open Anyway** next to Astra. You only do this once.

Requires macOS 14 Sonoma or later.

## Based on Plezy

Astra is a fork of [Plezy](https://github.com/edde746/plezy) by Edvard Wikhall ([@edde746](https://github.com/edde746)). Plezy does the heavy lifting: the Plex and Jellyfin clients, the mpv player and much more. Astra changes the look and the name, and turns off services that belong to the Plezy project (crash reporting, log uploads, Discord, and Trakt/MyAnimeList/AniList/Simkl sign-in), as Plezy's [TRADEMARKS.md](TRADEMARKS.md) asks of forks.

Astra is not made or endorsed by the Plezy project. If you like how Astra plays video, consider [supporting Plezy](https://plezy.app).

## License

GPL-3.0, the same as Plezy. See [LICENSE](LICENSE). Playback uses [mpv](https://mpv.io) via [MPVKit](https://github.com/mpvkit/MPVKit).

## Building

Releases are built by the **Astra macOS** GitHub Actions workflow (`.github/workflows/silo-macos.yml`). Run it from the Actions tab; it builds Astra.app, makes Astra.dmg, publishes a release, and updates the in-app update feed on the `appcast` branch (needs the `SPARKLE_ED_SEED` repository secret).

To pull in new Plezy changes: `git fetch upstream && git merge upstream/main`.
