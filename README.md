# music-widget

A self-contained Waybar music popup for Omarchy / Hyprland.

- **Controls** — album art, seek, play/pause/skip, shuffle/repeat, volume
- **Visualizer** — Cava-driven, four styles (bars/wave/blocks/flame), live-tweakable sensitivity / bar count / mono–stereo / smoothing from inside the widget. Colors follow the Omarchy theme.
- **Spotify** — browse playlists, **Liked Songs**, Saved Albums, Recently Played, and search the catalog. Streams via spotifyd (managed by the widget — no Spotify desktop app, no separate TUI to launch).
- **Local** — browse and play your MPD library.

## Install

Requires Arch / Omarchy. From a clone:

```bash
./install.sh
```

The installer:

1. Verifies pacman deps (`playerctl`, `cava`, `spotifyd`, `mpd`, `mpc`, `gtk4`, `libadwaita`, `python-gobject`, `uv`). Tells you exactly what to install if anything is missing.
2. Creates a uv-managed venv at `~/.local/share/music-widget/venv` (using `--system-site-packages` so `gi` is available) and installs the widget into it.
3. Symlinks `music-widget` and `music-waybar-title` into `~/.local/bin`.
4. Seeds default config at `~/.config/music-widget/` only if it's missing.
5. Prints the Waybar JSON snippet to paste into your config.

Re-running it is safe; nothing destructive happens.

## Waybar integration

See `docs/waybar.jsonc` for the snippet. The relevant module names are:

- `custom/music-prev`, `custom/music-play`, `custom/music-next` — buttons
- `custom/music-title` — scrolling track title; click to open the widget

## Uninstall

```bash
./uninstall.sh
```

Leaves your `~/.config/music-widget/` in place. Delete it manually if you want a clean slate.

## Spotify setup

On first run, the Playlists → Spotify tab walks you through:

1. Create a Spotify developer app at https://developer.spotify.com/dashboard.
2. Add `http://127.0.0.1:19872/login` as a redirect URI (copy/paste from the widget).
3. Paste the Client ID into the widget, click Connect, finish OAuth in the browser.

The widget handles spotifyd lifecycle, device discovery, and credential bootstrapping. Playback control requires Spotify Premium (Spotify Web API limitation).
