"""User config — TOML at ~/.config/music-widget/config.toml.

Defaults are baked in (DEFAULTS) so the file is optional. The widget rewrites
this file when settings are changed via the UI.
"""

import os
import sys
from pathlib import Path

if sys.version_info >= (3, 11):
    import tomllib
else:  # pragma: no cover - we require 3.11+
    import tomli as tomllib

CONFIG_DIR = Path(os.path.expanduser("~/.config/music-widget"))
CONFIG_TOML = CONFIG_DIR / "config.toml"
CAVA_CONF = CONFIG_DIR / "cava.conf"

DEFAULTS: dict = {
    "widget": {
        # Popup size in pixels. Fixed so the surface doesn't grow with the
        # Playlists tab's content.
        "width": 560,
        "height": 320,
        # Pixels from screen top to the widget. Default matches a 26px
        # Waybar with 4px top margin (4 + 26 = 30), so the widget sits
        # flush with Waybar's bottom edge.
        "margin_top": 30,
        # Pixels from screen right to the widget — match Hyprland's gaps_out.
        "margin_right": 4,
    },
    "spotify": {
        "redirect_port": 19872,
    },
    "visualizer": {
        "style": "bars",
        "bars": 32,
        "sensitivity": 100,
        "channels": "mono",
        "smoothing": 0.65,
    },
}


def _deep_merge(base: dict, overlay: dict) -> dict:
    out = {k: v for k, v in base.items()}
    for k, v in overlay.items():
        if isinstance(v, dict) and isinstance(out.get(k), dict):
            out[k] = _deep_merge(out[k], v)
        else:
            out[k] = v
    return out


def load() -> dict:
    """Load config, deep-merged over DEFAULTS so missing keys are filled in."""
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    if not CONFIG_TOML.exists():
        return {k: dict(v) if isinstance(v, dict) else v for k, v in DEFAULTS.items()}
    try:
        with open(CONFIG_TOML, "rb") as f:
            data = tomllib.load(f)
        return _deep_merge(DEFAULTS, data)
    except (OSError, tomllib.TOMLDecodeError):
        return {k: dict(v) if isinstance(v, dict) else v for k, v in DEFAULTS.items()}


def save_visualizer(section: dict) -> None:
    """Persist visualizer section, preserving other sections.

    Hand-written TOML rather than depending on tomli-w so the package has zero
    extra runtime deps beyond spotipy + python-mpd2.
    """
    cfg = load()
    cfg["visualizer"] = {**cfg.get("visualizer", {}), **section}
    _write(cfg)


def _quote(v):
    if isinstance(v, str):
        escaped = v.replace("\\", "\\\\").replace('"', '\\"')
        return f'"{escaped}"'
    if isinstance(v, bool):
        return "true" if v else "false"
    return str(v)


def _write(cfg: dict) -> None:
    """Write only keys that differ from DEFAULTS so a later default change
    actually propagates to users who never touched that section."""
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    lines = ["# Music Widget configuration — managed by the widget UI.", ""]
    for section, body in cfg.items():
        if not isinstance(body, dict):
            continue
        defaults_section = DEFAULTS.get(section, {})
        overrides = {
            k: v for k, v in body.items()
            if defaults_section.get(k) != v
        }
        if not overrides:
            continue
        lines.append(f"[{section}]")
        for k, v in overrides.items():
            lines.append(f"{k} = {_quote(v)}")
        lines.append("")
    CONFIG_TOML.write_text("\n".join(lines))
