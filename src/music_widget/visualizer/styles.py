"""Visualizer draw functions. Each takes (cr, w, h, bars, accent, teal, state)
and draws onto the cairo context.

`state` is a per-canvas dict the canvas owns; styles that need history (flame)
read/write into it.
"""

import cairo
import math


STYLE_NAMES = ["bars", "wave", "blocks", "flame", "mirror", "dots", "ring"]
STYLE_LABELS = {
    "bars": "Bars",
    "wave": "Wave",
    "blocks": "Blocks",
    "flame": "Flame",
    "mirror": "Mirror",
    "dots": "Dots",
    "ring": "Ring",
}


def draw_bars(cr, w, h, bars, accent, teal, _state):
    n = len(bars) or 1
    bw = w / n
    gap = max(1.0, bw * 0.18)
    for i, v in enumerate(bars):
        bh = max(2.0, v / 100 * h)
        x = i * bw + gap / 2
        g = cairo.LinearGradient(x, h, x, h - bh)
        g.add_color_stop_rgba(0, *accent, 0.9)
        g.add_color_stop_rgba(1, *teal, 0.9)
        cr.set_source(g)
        cr.rectangle(x, h - bh, bw - gap, bh)
        cr.fill()


def draw_wave(cr, w, h, bars, accent, teal, _state):
    n = len(bars)
    if n < 2:
        return
    mid = h / 2
    pts = [(i / (n - 1) * w, mid - bars[i] / 100 * mid * 0.85) for i in range(n)]

    def curve(pts_in, col, a):
        cr.set_source_rgba(*col, a)
        cr.set_line_width(2.0)
        cr.move_to(*pts_in[0])
        for j in range(1, n - 2):
            cx = (pts_in[j][0] + pts_in[j + 1][0]) / 2
            cy = (pts_in[j][1] + pts_in[j + 1][1]) / 2
            cr.curve_to(pts_in[j][0], pts_in[j][1], cx, cy, cx, cy)
        cr.line_to(*pts_in[-1])
        cr.stroke()

    curve(pts, accent, 0.9)
    curve([(x, mid + (mid - y)) for x, y in pts], teal, 0.45)


def draw_blocks(cr, w, h, bars, accent, teal, _state):
    n = len(bars) or 1
    bw = w / n
    bh, step = 5, 7
    for i, v in enumerate(bars):
        th = max(bh, v / 100 * h)
        x = i * bw + 1
        y = h - step
        while y > h - th:
            t = (h - y) / h
            r = accent[0] * (1 - t) + teal[0] * t
            g = accent[1] * (1 - t) + teal[1] * t
            b = accent[2] * (1 - t) + teal[2] * t
            cr.set_source_rgba(r, g, b, 0.85)
            cr.rectangle(x, y, bw - 2, bh)
            cr.fill()
            y -= step


_FLAME_ROWS = 20


def draw_flame(cr, w, h, bars, _accent, _teal, state):
    n = len(bars) or 1
    grid = state.get("flame")
    if grid is None or len(grid[0]) != n:
        grid = [[0.0] * n for _ in range(_FLAME_ROWS)]
        state["flame"] = grid

    rows = _FLAME_ROWS
    for r in range(rows - 1):
        for c in range(n):
            left = grid[r + 1][max(0, c - 1)]
            mid = grid[r + 1][c]
            right = grid[r + 1][min(n - 1, c + 1)]
            grid[r][c] = (left + mid * 2 + right) / 4 * 0.93
    for c in range(n):
        grid[rows - 1][c] = bars[c] / 100

    bw, rh = w / n, h / rows
    for row in range(rows):
        for col in range(n):
            v = grid[row][col]
            if v < 0.04:
                continue
            if v < 0.35:
                t = v / 0.35
                clr = (0.7 * t, 0.05 * t, 0, v)
            elif v < 0.65:
                t = (v - 0.35) / 0.30
                clr = (0.7, 0.05 + 0.45 * t, 0, v)
            else:
                t = (v - 0.65) / 0.35
                clr = (0.9, 0.5 + 0.3 * t, 0.1 * t, min(1, v))
            cr.set_source_rgba(*clr)
            cr.rectangle(col * bw, (rows - 1 - row) * rh, bw + 0.5, rh + 0.5)
            cr.fill()


def draw_mirror(cr, w, h, bars, accent, teal, _state):
    """Bars mirrored from the horizontal midline — classic spectrum analyzer."""
    n = len(bars) or 1
    bw = w / n
    gap = max(1.0, bw * 0.18)
    mid = h / 2
    for i, v in enumerate(bars):
        half = max(1.5, v / 100 * mid * 0.95)
        x = i * bw + gap / 2
        # Upper half — accent on top, teal at midline
        g_up = cairo.LinearGradient(x, mid, x, mid - half)
        g_up.add_color_stop_rgba(0, *teal, 0.85)
        g_up.add_color_stop_rgba(1, *accent, 0.9)
        cr.set_source(g_up)
        cr.rectangle(x, mid - half, bw - gap, half)
        cr.fill()
        # Lower half — symmetric
        g_dn = cairo.LinearGradient(x, mid, x, mid + half)
        g_dn.add_color_stop_rgba(0, *teal, 0.85)
        g_dn.add_color_stop_rgba(1, *accent, 0.9)
        cr.set_source(g_dn)
        cr.rectangle(x, mid, bw - gap, half)
        cr.fill()


def draw_dots(cr, w, h, bars, accent, teal, _state):
    """A single filled dot per band at its current peak height."""
    n = len(bars) or 1
    bw = w / n
    r_max = max(2.5, bw * 0.35)
    for i, v in enumerate(bars):
        t = max(0.0, min(1.0, v / 100))
        # Color lerps from teal (quiet) to accent (loud)
        r = teal[0] * (1 - t) + accent[0] * t
        g = teal[1] * (1 - t) + accent[1] * t
        b = teal[2] * (1 - t) + accent[2] * t
        radius = max(2.0, r_max * (0.4 + 0.6 * t))
        cx = i * bw + bw / 2
        cy = h - max(radius + 2, t * (h - radius - 2))
        cr.set_source_rgba(r, g, b, 0.55 + 0.45 * t)
        cr.arc(cx, cy, radius, 0, 2 * math.pi)
        cr.fill()


def draw_ring(cr, w, h, bars, accent, teal, _state):
    """Bars radiating from a central ring."""
    n = len(bars) or 1
    cx, cy = w / 2, h / 2
    r_inner = min(w, h) * 0.18
    r_max = min(w, h) / 2 - 4
    for i, v in enumerate(bars):
        angle = (i / n) * 2 * math.pi - math.pi / 2  # start from top
        t = max(0.0, min(1.0, v / 100))
        length = max(2.0, t * (r_max - r_inner))
        x0 = cx + math.cos(angle) * r_inner
        y0 = cy + math.sin(angle) * r_inner
        x1 = cx + math.cos(angle) * (r_inner + length)
        y1 = cy + math.sin(angle) * (r_inner + length)
        # Per-spoke gradient teal → accent outward
        g = cairo.LinearGradient(x0, y0, x1, y1)
        g.add_color_stop_rgba(0, *teal, 0.85)
        g.add_color_stop_rgba(1, *accent, 0.95)
        cr.set_source(g)
        cr.set_line_width(max(2.0, 2 * math.pi * r_inner / n * 0.6))
        cr.move_to(x0, y0)
        cr.line_to(x1, y1)
        cr.stroke()
    # Subtle inner ring
    cr.set_source_rgba(*accent, 0.4)
    cr.set_line_width(1.5)
    cr.arc(cx, cy, r_inner, 0, 2 * math.pi)
    cr.stroke()


DRAWERS = {
    "bars": draw_bars,
    "wave": draw_wave,
    "blocks": draw_blocks,
    "flame": draw_flame,
    "mirror": draw_mirror,
    "dots": draw_dots,
    "ring": draw_ring,
}
