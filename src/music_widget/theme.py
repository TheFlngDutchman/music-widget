"""Read Omarchy theme colors for the Cairo (non-CSS) visualizer drawing.

GTK CSS pulls colors from `~/.config/omarchy/current/theme/gtk.css` via the
@-variable system; this module only handles the raw RGB values needed by
cairo paths in the visualizer.
"""

import os

THEME_TOML = os.path.expanduser("~/.config/omarchy/current/theme/colors.toml")
THEME_CSS = os.path.expanduser("~/.config/omarchy/current/theme/gtk.css")


def _hex_to_rgb(s: str) -> tuple[float, float, float]:
    s = s.lstrip("#")
    return tuple(int(s[i : i + 2], 16) / 255 for i in (0, 2, 4))


def cairo_colors() -> dict[str, tuple[float, float, float]]:
    """Return accent + secondary colors as cairo-friendly RGB floats."""
    vals = {"accent": "#b59790", "teal": "#87a9b0"}
    try:
        with open(THEME_TOML) as f:
            for line in f:
                k, _, v = line.partition("=")
                k, v = k.strip(), v.strip().strip('"')
                if k == "accent":
                    vals["accent"] = v
                elif k == "color2":
                    vals["teal"] = v
    except OSError:
        pass
    return {k: _hex_to_rgb(v) for k, v in vals.items()}
