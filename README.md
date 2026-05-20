> **PSA:** This project was vibe coded with AI. It works, but don't expect textbook architecture or pristine code. PRs and issues are still very welcome.

# music-widget

A GTK4/Libadwaita popup for Waybar / Hyprland that puts playback controls, a cava audio visualizer, Spotify browsing, and MPD file navigation into one floating window anchored to the top-right of the screen.

## Features

- **Transport controls** — play/pause, previous, next, seek (draggable progress bar), volume slider
- **Shuffle / repeat** — toggle from the controls page, persists across context changes
- **Album art** — fetched from URL or local file, displayed at 72×72 with crossfade
- **Cava visualizer** — 7 draw styles (bars, wave, blocks, flame, mirror, dots, ring) on a Cairo canvas; live-tweakable sensitivity, bar count, mono/stereo, smoothing from a gear popover
- **Spotify browser** — browse playlists, Liked Songs, Saved Albums, Recently Played; search catalog (tracks, albums, artists, playlists); view and clear queue; add-to-queue button on every track; paginated infinite scroll; breadcrumb back navigation
- **Spotify streaming** — spotifyd lifecycle managed by the widget (auto-start, OAuth bootstrap, device discovery, proxy workaround for port 4070); no separate Spotify desktop app or TUI needed
- **Local / MPD browser** — browse your music directory, navigate into folders, play files; path bar for manual entry; Start MPD button if the daemon isn't running
- **In-memory filter** — type to filter any list view locally (no network call)
- **Tabbed interface** — three tabs: Controls, Visualizer, Playlists (Spotify + Local)
- **Theme-aware** — pulls accent colors from the Omarchy theme system (`~/.config/omarchy/current/theme/`), falls back to built-in defaults
- **Layer-shell anchored** — docks to the top-right of the screen via gtk4-layer-shell (falls back to a plain window if the library isn't available)

## How it works

The widget reads the current track via **playerctl** (spotifyd, spotify, MPD). When a Spotify session is authenticated it uses the **Spotify Web API** (spotipy) for richer control — browse playlists, Liked Songs, Saved Albums, Recently Played, search the catalog, and manage the playback queue. Playback itself streams through **spotifyd**, whose lifecycle the widget owns (start, stop, OAuth bootstrap). For local files it browses your **MPD** library.

The **visualizer** spawns **cava** as a subprocess piping raw ASCII frame data to stdout, reads it on a background thread, then draws via **Cairo** on a `Gtk.DrawingArea`. Seven draw styles are available: bars, wave, blocks, flame, mirror, dots, ring. Sensitivity, bar count, mono/stereo, and smoothing are tweakable live from a settings popover.

Colors are pulled from the Omarchy theme system (`~/.config/omarchy/current/theme/`), with a fallback to built-in defaults.

## Requirements

- **Arch Linux** (developed on [Omarchy](https://omarchy.org))
- `playerctl`, `cava`, `spotifyd`, `mpd`, `mpc`, `gtk4`, `libadwaita`, `gtk4-layer-shell`, `python`, `python-gobject`, `uv`

## Install

```bash
./install.sh
```

The installer is idempotent and safe to re-run:

1. Checks pacman for system deps; lists missing packages (or installs them with `--install-deps`).
2. Creates a uv-managed venv at `~/.local/share/music-widget/venv` with `--system-site-packages` so `gi` (PyGObject) is available.
3. Installs the package via `uv pip install`.
4. Writes a launcher wrapper to `~/.local/bin/music-widget` (LD_PRELOADs libgtk4-layer-shell.so) and copies `music-waybar-title` into place.
5. Seeds default config at `~/.config/music-widget/` if missing.
6. Optionally installs a `.desktop` file and injects the music modules into `~/.config/waybar/config.jsonc`.

## Waybar integration

The installer can auto-inject these modules into your Waybar config. See `docs/waybar.jsonc` for the snippet:

- `custom/music-prev`, `custom/music-play`, `custom/music-next` — transport buttons
- `custom/music-title` — scrolling track title (click to open the widget)

## Spotify setup

The Playlists → Spotify tab walks you through a one-time OAuth flow:

1. Create a Spotify Developer app at https://developer.spotify.com/dashboard.
2. Add `http://127.0.0.1:19872/login` as a redirect URI (copy/paste from the widget).
3. Paste the Client ID, click Connect, finish the PKCE flow in your browser.

The widget also runs `spotifyd authenticate` to give spotifyd its own credentials for actual audio playback. Playback control requires **Spotify Premium** (Web API limitation).

## Uninstall

```bash
./uninstall.sh
```

Removes the venv and launchers; preserves `~/.config/music-widget/`.
