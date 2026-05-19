"""Visualizer page — canvas + 'Now playing' label + gear-popover settings."""

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Pango", "1.0")
from gi.repository import GLib, Gtk, Pango

from music_widget import config as cfg_mod
from music_widget.visualizer import cava as cava_mod
from music_widget.visualizer.canvas import VisualizerCanvas
from music_widget.visualizer.styles import STYLE_LABELS, STYLE_NAMES

BAR_CHOICES = [8, 16, 32, 64, 96]


class VisualizerPage(Gtk.Box):
    def __init__(self, colors):
        super().__init__(orientation=Gtk.Orientation.VERTICAL)

        cfg = cfg_mod.load()["visualizer"]
        self._cfg = dict(cfg)

        # Header: now-playing label on the left, gear button on the right
        header = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
        header.set_margin_top(6)
        header.set_margin_bottom(2)
        header.set_margin_start(12)
        header.set_margin_end(8)

        self._now = Gtk.Label(label="")
        self._now.set_halign(Gtk.Align.START)
        self._now.set_hexpand(True)
        self._now.set_ellipsize(Pango.EllipsizeMode.END)
        self._now.add_css_class("mw-vis-now")
        header.append(self._now)

        gear = Gtk.MenuButton()
        gear.set_label("⚙")
        gear.add_css_class("mw-vis-gear")
        gear.set_tooltip_text("Visualizer settings")
        gear.set_popover(self._build_popover())
        header.append(gear)

        self.append(header)

        self.canvas = VisualizerCanvas(
            colors,
            num_bars=int(self._cfg["bars"]),
            smoothing=float(self._cfg["smoothing"]),
        )
        self.canvas.set_style(self._cfg["style"])
        self.canvas.set_margin_start(8)
        self.canvas.set_margin_end(8)
        self.canvas.set_margin_bottom(8)
        self.append(self.canvas)

        # Spawn cava with the configured settings
        cava_mod.write_cava_conf(
            bars=int(self._cfg["bars"]),
            sensitivity=int(self._cfg["sensitivity"]),
            channels=str(self._cfg["channels"]),
        )
        self._cava = cava_mod.CavaRunner(
            on_bars=lambda bars: GLib.idle_add(self.canvas.push, bars)
        )
        self._cava.start()

    def shutdown(self) -> None:
        self._cava.stop()

    def update_track(self, title, artist):
        text = f"{title} — {artist}" if (title and artist) else (title or "")
        self._now.set_text(text)

    # ── Settings popover ────────────────────────────────────────────────

    def _build_popover(self) -> Gtk.Popover:
        pop = Gtk.Popover()
        pop.add_css_class("mw-vis-popover")
        body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        body.set_size_request(280, -1)

        body.append(self._row_style())
        body.append(self._row_bars())
        body.append(Gtk.Separator())
        body.append(self._row_sensitivity())
        body.append(self._row_smoothing())
        body.append(self._row_channels())
        body.append(Gtk.Separator())

        reset = Gtk.Button(label="Reset to defaults")
        reset.add_css_class("mw-nav-btn")
        reset.connect("clicked", self._on_reset)
        body.append(reset)

        pop.set_child(body)
        return pop

    def _row(self, label_text: str) -> tuple[Gtk.Box, Gtk.Box]:
        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        row.add_css_class("mw-vis-popover-row")
        lbl = Gtk.Label(label=label_text)
        lbl.set_halign(Gtk.Align.START)
        lbl.add_css_class("mw-vis-popover-lbl")
        row.append(lbl)
        content = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
        content.set_hexpand(True)
        content.set_halign(Gtk.Align.END)
        row.append(content)
        return row, content

    def _row_style(self) -> Gtk.Box:
        row, content = self._row("Style")
        first = None
        self._style_btns: dict[str, Gtk.ToggleButton] = {}
        for name in STYLE_NAMES:
            b = Gtk.ToggleButton(label=STYLE_LABELS[name])
            b.add_css_class("mw-vis-style-btn")
            if first is None:
                first = b
            else:
                b.set_group(first)
            b.set_active(name == self._cfg["style"])
            b.connect("toggled", self._on_style, name)
            self._style_btns[name] = b
            content.append(b)
        return row

    def _row_bars(self) -> Gtk.Box:
        row, content = self._row("Bar count")
        first = None
        self._bar_btns: dict[int, Gtk.ToggleButton] = {}
        for n in BAR_CHOICES:
            b = Gtk.ToggleButton(label=str(n))
            b.add_css_class("mw-vis-style-btn")
            if first is None:
                first = b
            else:
                b.set_group(first)
            b.set_active(int(n) == int(self._cfg["bars"]))
            b.connect("toggled", self._on_bars, n)
            self._bar_btns[n] = b
            content.append(b)
        return row

    def _row_channels(self) -> Gtk.Box:
        row, content = self._row("Channels")
        first = None
        self._chan_btns: dict[str, Gtk.ToggleButton] = {}
        for name in ("mono", "stereo"):
            b = Gtk.ToggleButton(label=name.capitalize())
            b.add_css_class("mw-vis-style-btn")
            if first is None:
                first = b
            else:
                b.set_group(first)
            b.set_active(name == self._cfg["channels"])
            b.connect("toggled", self._on_channels, name)
            self._chan_btns[name] = b
            content.append(b)
        return row

    def _row_sensitivity(self) -> Gtk.Box:
        row, content = self._row("Sensitivity")
        self._sens = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 10, 500, 10)
        self._sens.set_value(int(self._cfg["sensitivity"]))
        self._sens.set_size_request(160, -1)
        self._sens.set_draw_value(True)
        self._sens.set_value_pos(Gtk.PositionType.RIGHT)
        self._sens.connect("change-value", self._on_sensitivity)
        content.append(self._sens)
        return row

    def _row_smoothing(self) -> Gtk.Box:
        row, content = self._row("Smoothing")
        self._smo = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 0.0, 0.9, 0.05)
        self._smo.set_value(float(self._cfg["smoothing"]))
        self._smo.set_size_request(160, -1)
        self._smo.set_draw_value(True)
        self._smo.set_value_pos(Gtk.PositionType.RIGHT)
        self._smo.set_digits(2)
        self._smo.connect("change-value", self._on_smoothing)
        content.append(self._smo)
        return row

    # ── Handlers ────────────────────────────────────────────────────────

    def _persist(self) -> None:
        cfg_mod.save_visualizer(self._cfg)

    def _on_style(self, btn, name):
        if not btn.get_active():
            return
        self._cfg["style"] = name
        self.canvas.set_style(name)
        self._persist()

    def _on_bars(self, btn, n):
        if not btn.get_active():
            return
        self._cfg["bars"] = int(n)
        self.canvas.set_num_bars(int(n))
        cava_mod.write_cava_conf(
            bars=int(n),
            sensitivity=int(self._cfg["sensitivity"]),
            channels=str(self._cfg["channels"]),
        )
        self._cava.restart()
        self._persist()

    def _on_channels(self, btn, name):
        if not btn.get_active():
            return
        self._cfg["channels"] = name
        cava_mod.write_cava_conf(
            bars=int(self._cfg["bars"]),
            sensitivity=int(self._cfg["sensitivity"]),
            channels=name,
        )
        self._cava.restart()
        self._persist()

    def _on_sensitivity(self, _scale, _t, v):
        v = int(max(10, min(500, v)))
        self._cfg["sensitivity"] = v
        cava_mod.write_cava_conf(
            bars=int(self._cfg["bars"]),
            sensitivity=v,
            channels=str(self._cfg["channels"]),
        )
        # Debounce restarts a bit while the user drags
        if hasattr(self, "_sens_timer") and self._sens_timer:
            GLib.source_remove(self._sens_timer)
        self._sens_timer = GLib.timeout_add(250, self._restart_cava_debounced)
        self._persist()
        return False

    def _restart_cava_debounced(self):
        self._sens_timer = None
        self._cava.restart()
        return False

    def _on_smoothing(self, _scale, _t, v):
        v = float(max(0.0, min(0.9, v)))
        self._cfg["smoothing"] = round(v, 2)
        self.canvas.set_smoothing(v)
        self._persist()
        return False

    def _on_reset(self, _btn):
        defaults = dict(cfg_mod.DEFAULTS["visualizer"])
        self._cfg = defaults
        # Style
        self._style_btns[defaults["style"]].set_active(True)
        # Bars
        if int(defaults["bars"]) in self._bar_btns:
            self._bar_btns[int(defaults["bars"])].set_active(True)
        # Channels
        self._chan_btns[defaults["channels"]].set_active(True)
        # Sliders
        self._sens.set_value(int(defaults["sensitivity"]))
        self._smo.set_value(float(defaults["smoothing"]))
        # Apply
        self.canvas.set_num_bars(int(defaults["bars"]))
        self.canvas.set_smoothing(float(defaults["smoothing"]))
        self.canvas.set_style(defaults["style"])
        cava_mod.write_cava_conf(
            bars=int(defaults["bars"]),
            sensitivity=int(defaults["sensitivity"]),
            channels=str(defaults["channels"]),
        )
        self._cava.restart()
        self._persist()
