"""Visualizer drawing canvas. Style-agnostic; dispatches to styles.DRAWERS."""

import gi

gi.require_version("Gtk", "4.0")
from gi.repository import Gtk

from music_widget.visualizer.styles import DRAWERS, STYLE_NAMES


class VisualizerCanvas(Gtk.DrawingArea):
    def __init__(self, colors, num_bars: int = 32, smoothing: float = 0.65):
        super().__init__()
        self._n = num_bars
        self.smooth = [0.0] * num_bars
        self.smoothing = smoothing  # 0..1, decay weight for previous frame
        self.style = "bars"
        self._state: dict = {}
        self._ac = colors["accent"]
        self._te = colors["teal"]
        self.set_draw_func(self._draw)
        self.set_vexpand(True)
        self.set_hexpand(True)

    def set_num_bars(self, n: int) -> None:
        if n == self._n:
            return
        self._n = n
        self.smooth = [0.0] * n
        self._state.clear()
        self.queue_draw()

    def set_smoothing(self, s: float) -> None:
        self.smoothing = max(0.0, min(0.95, s))

    def set_style(self, style: str) -> None:
        if style not in STYLE_NAMES:
            return
        self.style = style
        self._state.clear()
        self.queue_draw()

    def update_colors(self, colors) -> None:
        self._ac = colors["accent"]
        self._te = colors["teal"]
        self.queue_draw()

    def push(self, bars):
        # cava may emit a different bar count if its config was just rewritten —
        # adapt without dropping frames.
        if len(bars) != self._n:
            self._n = len(bars)
            self.smooth = [0.0] * self._n
            self._state.clear()
        s = self.smoothing
        self.smooth = [(1 - s) * b + s * prev for b, prev in zip(bars, self.smooth)]
        self.queue_draw()

    def _draw(self, _, cr, w, h):
        cr.set_source_rgba(0, 0, 0, 0)
        cr.paint()
        DRAWERS[self.style](cr, w, h, self.smooth, self._ac, self._te, self._state)
