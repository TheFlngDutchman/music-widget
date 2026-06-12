> **PSA:** This project was vibe coded with AI. It works, but don't expect textbook architecture or pristine code. PRs and issues are still very welcome.

# music-widget

A [Quickshell](https://quickshell.org) popup for Waybar / Hyprland that puts playback controls, a cava audio visualizer, Spotify browsing, and MPD file navigation into one floating layer-shell window.

Formerly a Python/GTK4 app — rewritten in QML for instant response times: the widget runs resident as a user service (the Waybar button only toggles visibility, zero cold start), playback state is fully event-driven over MPRIS (no polling), and Spotify responses are cached.

## Features

- **Transport controls** — play/pause, previous, next, draggable seek bar with a live position ticker, volume, shuffle, repeat; album art
- **Cava visualizer** — 7 canvas styles (bars, wave, blocks, flame, mirror, dots, ring) with peak-hold caps; sensitivity, bar count, mono/stereo, and smoothing tweakable live from a gear popover; cava only runs while the tab is visible
- **Spotify browser** — playlists, Liked Songs, Saved Albums, Recently Played, queue (with add-to-queue on every row), catalog search, infinite scroll, breadcrumb navigation; responses cached with per-section TTLs
- **Spotify streaming** — headless playback through spotifyd running as a systemd user service; one-click authenticate from the widget
- **Local / MPD browser** — browse and play your music directory via mpc
- **Settings tab** — window anchor/size/margins/monitor, font, album-art size, per-color theme overrides, Spotify and spotifyd status — all applied live and written back to the config file
- **Theme-aware** — follows the [Omarchy](https://omarchy.org) theme live (no restart), with optional per-color overrides
- **Waybar-friendly** — separate layer-shell surface with no exclusive zone; margins measure from the bar's edge

## Requirements

- **Arch Linux** (developed on Omarchy), Hyprland or another wlroots compositor
- `quickshell`, `cava`, `spotifyd`, `mpd`, `mpc`, `playerctl`

## Install

```bash
./install.sh            # add --install-deps to pull missing packages
```

Idempotent and safe to re-run:

1. Checks system deps (installs with `--install-deps`).
2. Symlinks the repo to `~/.config/quickshell/music-widget`.
3. Installs and enables `music-widget.service` (user) so the widget is always resident.
4. Seeds `~/.config/spotifyd/spotifyd.conf` (device "Music Widget", MPRIS on) and enables spotifyd.
5. Migrates an old `config.toml` to `config.json` if you're upgrading from the GTK version.
6. Installs the `music-widget` toggle command and `music-waybar-title`.
7. Injects the Waybar modules if missing (see `docs/waybar.jsonc`).

Toggle from anywhere:

```bash
music-widget                                    # wrapper, starts the service if needed
qs -c music-widget ipc call window toggle       # direct IPC
qs -c music-widget ipc call window tab 2        # open straight to a tab (0–3)
```

## Configuration

`~/.config/music-widget/config.json` — every field is editable from the in-app Settings tab (gear icon), and hand edits apply live in the other direction too. Empty color strings mean "follow the omarchy theme".

## Spotify setup

The Playlists → Spotify tab walks you through a one-time OAuth flow:

1. Create a Spotify Developer app at https://developer.spotify.com/dashboard.
2. Add `http://127.0.0.1:19872/login` as a redirect URI (copy/paste from the widget).
3. Paste the Client ID, click Connect, approve in the browser.

Tokens live in `~/.local/state/music-widget/auth.json` (chmod 600) and refresh silently. spotifyd gets its own credentials via the widget's Authenticate button (Settings tab or the strip above the browser). Playback control requires **Spotify Premium** (Web API limitation).

If spotifyd can't reach Spotify on hostile networks (port 4070 blocked), set `proxy` in `~/.config/spotifyd/spotifyd.conf` — see `man spotifyd`.

## Uninstall

```bash
./uninstall.sh
```

Removes the service, symlink and launchers; preserves your config and tokens, and asks before disabling spotifyd.
