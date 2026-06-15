> **PSA:** This project was vibe coded with AI. It works, but don't expect textbook architecture or pristine code. PRs and issues are still very welcome.

# music-widget

A [Quickshell](https://quickshell.org) popup for Waybar / Hyprland that puts playback controls, a cava audio visualizer, Spotify browsing, and MPD file navigation into one floating layer-shell window.

![demo](demo.gif)

Formerly a Python/GTK4 app — rewritten in QML for instant response times: the widget runs resident as a user service (the Waybar button only toggles visibility, zero cold start), playback state is fully event-driven over MPRIS (no polling), and Spotify responses are cached.

## Features

- **Transport controls** — play/pause, previous, next, draggable seek bar with a live position ticker, volume, shuffle, repeat; album art
- **Cava visualizer** — 7 canvas styles (bars, wave, blocks, flame, mirror, dots, ring) with peak-hold caps; sensitivity, bar count, mono/stereo, and smoothing tweakable live from a gear popover; cava only runs while the tab is visible
- **Spotify browser** — playlists, Liked Songs, Saved Albums, Recently Played, queue (with add-to-queue on every row), catalog search, infinite scroll, breadcrumb navigation; responses cached with per-section TTLs
- **Spotify streaming** — headless playback through spotifyd running as a systemd user service; the widget seeds its credentials from your one Spotify login, no second auth flow
- **Track download** — the download button on any Spotify track fetches the best-match audio via `yt-dlp` into `~/Music` as an MP3, with cover art and title/artist metadata embedded
- **Local / MPD browser** — browse and play your music directory via mpc
- **Settings tab** — window anchor/size/margins/monitor (including a free-floating mode with drag-to-move), font, album-art size, per-color theme overrides, Spotify and spotifyd status — all applied live and written back to the config file
- **Theme-aware** — follows the [Omarchy](https://omarchy.org) theme live (no restart), with optional per-color overrides
- **Waybar-friendly** — separate layer-shell surface with no exclusive zone; margins measure from the bar's edge

## Requirements

- **Arch Linux** (developed on Omarchy), Hyprland or another wlroots compositor
- `quickshell`, `cava`, `spotifyd`, `mpd`, `mpc`, `mpd-mpris`, `playerctl`

> `mpd-mpris` bridges MPD onto D-Bus/MPRIS — without it neither Waybar (`playerctl`) nor the widget can see or control MPD playback.

### Quickshell compatibility

The widget is a self-contained Quickshell config at `~/.config/quickshell/music-widget`, run as its own instance by **path** (`qs -p ~/.config/quickshell/music-widget`). Path mode is deliberate: if you also run a Quickshell bar, its `~/.config/quickshell/shell.qml` registers a 'default' config and Quickshell then ignores all *named* subdir configs — so `qs -c music-widget` would fail with "config not found". Loading by path sidesteps that, and it does **not** become your shell: it's a plain layer-shell surface with no exclusive zone, so it coexists with Waybar and with an Omarchy Quickshell bar. One caveat: the `quickshell` package tracks Qt closely — if the widget fails to start after a system upgrade, reinstall/rebuild `quickshell` against the new Qt.

## Install

```bash
./install.sh            # add --install-deps to pull missing packages
```

Idempotent and safe to re-run:

1. Checks system deps (installs with `--install-deps`).
2. Symlinks the repo to `~/.config/quickshell/music-widget`.
3. Installs and enables `music-widget.service` (user) so the widget is always resident.
4. Seeds `~/.config/spotifyd/spotifyd.conf` (device "Music Widget", MPRIS on) and enables spotifyd, and enables the `mpd-mpris` user service so MPD is visible over MPRIS.
5. Migrates an old `config.toml` to `config.json` if you're upgrading from the GTK version.
6. Installs the `music-widget` toggle command and `music-waybar-title`.
7. Injects the Waybar modules if missing (see `docs/waybar.jsonc`).

Toggle from anywhere:

```bash
music-widget                                                      # wrapper, starts the service if needed
qs -p ~/.config/quickshell/music-widget ipc call window toggle    # direct IPC
qs -p ~/.config/quickshell/music-widget ipc call window tab 2     # open straight to a tab (0–3)
```

## Configuration

`~/.config/music-widget/config.json` — every field is editable from the in-app Settings tab (gear icon), and hand edits apply live in the other direction too. Empty color strings mean "follow the omarchy theme".

## Spotify setup

The Playlists → Spotify tab walks you through a one-time OAuth flow:

1. Create a Spotify Developer app at https://developer.spotify.com/dashboard.
2. Add `http://127.0.0.1:19872/login` as a redirect URI (copy/paste from the widget).
3. Paste the Client ID, click Connect, approve in the browser.

That's the only login: the widget seeds spotifyd's credentials from the same authorization automatically (and re-seeds them at every start, since the token kind spotifyd accepts is short-lived). If you ever want spotifyd to hold its own permanent credentials instead, the Authenticate button in Settings runs the classic `spotifyd authenticate` flow and the widget will leave those untouched.

Tokens live in `~/.local/state/music-widget/auth.json` (chmod 600) and refresh silently. Playback control requires **Spotify Premium** (Web API limitation).

If spotifyd can't reach Spotify on hostile networks (port 4070 blocked), set `proxy` in `~/.config/spotifyd/spotifyd.conf` — see `man spotifyd`.

## Uninstall

```bash
./uninstall.sh
```

Removes the service, symlink, launchers and the injected Waybar modules (with a `.bak` backup of your Waybar config). Asks before disabling spotifyd, and optionally removes your config and tokens too — both are kept by default.
