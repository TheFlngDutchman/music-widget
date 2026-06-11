// Visualizer draw styles, ported from the cairo originals (styles.py).
// Each drawer takes (ctx, w, h, bars, accent, teal, state) where bars are
// floats in [0,1] and accent/teal are QML color values. `state` is a
// per-canvas object for styles needing history (flame, peak-hold).
.pragma library

var STYLE_NAMES = ["bars", "wave", "blocks", "flame", "mirror", "dots", "ring"];

function rgba(c, a) {
    return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + ","
        + Math.round(c.b * 255) + "," + a + ")";
}

function lerpRgba(c1, c2, t, a) {
    return "rgba("
        + Math.round((c1.r * (1 - t) + c2.r * t) * 255) + ","
        + Math.round((c1.g * (1 - t) + c2.g * t) * 255) + ","
        + Math.round((c1.b * (1 - t) + c2.b * t) * 255) + "," + a + ")";
}

// Decaying per-band peak markers shared by bars/mirror.
function updatePeaks(state, key, bars) {
    var peaks = state[key];
    if (!peaks || peaks.length !== bars.length)
        peaks = new Array(bars.length).fill(0);
    for (var i = 0; i < bars.length; i++)
        peaks[i] = Math.max(peaks[i] - 0.008, bars[i]);
    state[key] = peaks;
    return peaks;
}

function drawBars(ctx, w, h, bars, accent, teal, state, peakHold) {
    var n = bars.length || 1;
    var bw = w / n;
    var gap = Math.max(1, bw * 0.18);
    var peaks = peakHold ? updatePeaks(state, "peaks", bars) : null;
    for (var i = 0; i < n; i++) {
        var bh = Math.max(2, bars[i] * h);
        var x = i * bw + gap / 2;
        var g = ctx.createLinearGradient(x, h, x, h - bh);
        g.addColorStop(0, rgba(accent, 0.9));
        g.addColorStop(1, rgba(teal, 0.9));
        ctx.fillStyle = g;
        ctx.fillRect(x, h - bh, bw - gap, bh);
        if (peaks && peaks[i] > 0.02) {
            ctx.fillStyle = rgba(teal, 0.9);
            ctx.fillRect(x, h - peaks[i] * h - 2, bw - gap, 2);
        }
    }
}

function drawWave(ctx, w, h, bars, accent, teal) {
    var n = bars.length;
    if (n < 4)
        return;
    var mid = h / 2;
    var pts = [];
    for (var i = 0; i < n; i++)
        pts.push([i / (n - 1) * w, mid - bars[i] * mid * 0.85]);

    function curve(p, col, a) {
        ctx.strokeStyle = rgba(col, a);
        ctx.lineWidth = 2;
        ctx.beginPath();
        ctx.moveTo(p[0][0], p[0][1]);
        for (var j = 1; j < n - 2; j++) {
            var cx = (p[j][0] + p[j + 1][0]) / 2;
            var cy = (p[j][1] + p[j + 1][1]) / 2;
            ctx.quadraticCurveTo(p[j][0], p[j][1], cx, cy);
        }
        ctx.lineTo(p[n - 1][0], p[n - 1][1]);
        ctx.stroke();
    }

    curve(pts, accent, 0.9);
    var mirrored = pts.map(function (pt) {
        return [pt[0], mid + (mid - pt[1])];
    });
    curve(mirrored, teal, 0.45);
}

function drawBlocks(ctx, w, h, bars, accent, teal) {
    var n = bars.length || 1;
    var bw = w / n;
    var bh = 5, step = 7;
    for (var i = 0; i < n; i++) {
        var th = Math.max(bh, bars[i] * h);
        var x = i * bw + 1;
        var y = h - step;
        while (y > h - th) {
            var t = (h - y) / h;
            ctx.fillStyle = lerpRgba(accent, teal, t, 0.85);
            ctx.fillRect(x, y, bw - 2, bh);
            y -= step;
        }
    }
}

var FLAME_ROWS = 20;

function drawFlame(ctx, w, h, bars, accent, teal, state) {
    var n = bars.length || 1;
    var grid = state.flame;
    if (!grid || grid[0].length !== n) {
        grid = [];
        for (var r0 = 0; r0 < FLAME_ROWS; r0++)
            grid.push(new Array(n).fill(0));
        state.flame = grid;
    }

    for (var r = 0; r < FLAME_ROWS - 1; r++) {
        for (var c = 0; c < n; c++) {
            var left = grid[r + 1][Math.max(0, c - 1)];
            var mid = grid[r + 1][c];
            var right = grid[r + 1][Math.min(n - 1, c + 1)];
            grid[r][c] = (left + mid * 2 + right) / 4 * 0.93;
        }
    }
    for (var c2 = 0; c2 < n; c2++)
        grid[FLAME_ROWS - 1][c2] = bars[c2];

    var bw = w / n, rh = h / FLAME_ROWS;
    for (var row = 0; row < FLAME_ROWS; row++) {
        for (var col = 0; col < n; col++) {
            var v = grid[row][col];
            if (v < 0.04)
                continue;
            var clr;
            if (v < 0.35) {
                var t1 = v / 0.35;
                clr = "rgba(" + Math.round(0.7 * t1 * 255) + "," + Math.round(0.05 * t1 * 255) + ",0," + v + ")";
            } else if (v < 0.65) {
                var t2 = (v - 0.35) / 0.30;
                clr = "rgba(179," + Math.round((0.05 + 0.45 * t2) * 255) + ",0," + v + ")";
            } else {
                var t3 = (v - 0.65) / 0.35;
                clr = "rgba(230," + Math.round((0.5 + 0.3 * t3) * 255) + "," + Math.round(0.1 * t3 * 255) + "," + Math.min(1, v) + ")";
            }
            ctx.fillStyle = clr;
            ctx.fillRect(col * bw, (FLAME_ROWS - 1 - row) * rh, bw + 0.5, rh + 0.5);
        }
    }
}

function drawMirror(ctx, w, h, bars, accent, teal, state, peakHold) {
    var n = bars.length || 1;
    var bw = w / n;
    var gap = Math.max(1, bw * 0.18);
    var mid = h / 2;
    var peaks = peakHold ? updatePeaks(state, "peaksM", bars) : null;
    for (var i = 0; i < n; i++) {
        var half = Math.max(1.5, bars[i] * mid * 0.95);
        var x = i * bw + gap / 2;
        var gUp = ctx.createLinearGradient(x, mid, x, mid - half);
        gUp.addColorStop(0, rgba(teal, 0.85));
        gUp.addColorStop(1, rgba(accent, 0.9));
        ctx.fillStyle = gUp;
        ctx.fillRect(x, mid - half, bw - gap, half);
        var gDn = ctx.createLinearGradient(x, mid, x, mid + half);
        gDn.addColorStop(0, rgba(teal, 0.85));
        gDn.addColorStop(1, rgba(accent, 0.9));
        ctx.fillStyle = gDn;
        ctx.fillRect(x, mid, bw - gap, half);
        if (peaks && peaks[i] > 0.02) {
            var ph = peaks[i] * mid * 0.95;
            ctx.fillStyle = rgba(accent, 0.9);
            ctx.fillRect(x, mid - ph - 2, bw - gap, 1.5);
            ctx.fillRect(x, mid + ph + 0.5, bw - gap, 1.5);
        }
    }
}

function drawDots(ctx, w, h, bars, accent, teal) {
    var n = bars.length || 1;
    var bw = w / n;
    var rMax = Math.max(2.5, bw * 0.35);
    for (var i = 0; i < n; i++) {
        var t = Math.max(0, Math.min(1, bars[i]));
        var radius = Math.max(2, rMax * (0.4 + 0.6 * t));
        var cx = i * bw + bw / 2;
        var cy = h - Math.max(radius + 2, t * (h - radius - 2));
        ctx.fillStyle = lerpRgba(teal, accent, t, 0.55 + 0.45 * t);
        ctx.beginPath();
        ctx.arc(cx, cy, radius, 0, 2 * Math.PI);
        ctx.fill();
    }
}

function drawRing(ctx, w, h, bars, accent, teal) {
    var n = bars.length || 1;
    var cx = w / 2, cy = h / 2;
    var rInner = Math.min(w, h) * 0.18;
    var rMax = Math.min(w, h) / 2 - 4;
    ctx.lineWidth = Math.max(2, 2 * Math.PI * rInner / n * 0.6);
    for (var i = 0; i < n; i++) {
        var angle = (i / n) * 2 * Math.PI - Math.PI / 2;
        var t = Math.max(0, Math.min(1, bars[i]));
        var length = Math.max(2, t * (rMax - rInner));
        var x0 = cx + Math.cos(angle) * rInner;
        var y0 = cy + Math.sin(angle) * rInner;
        var x1 = cx + Math.cos(angle) * (rInner + length);
        var y1 = cy + Math.sin(angle) * (rInner + length);
        var g = ctx.createLinearGradient(x0, y0, x1, y1);
        g.addColorStop(0, rgba(teal, 0.85));
        g.addColorStop(1, rgba(accent, 0.95));
        ctx.strokeStyle = g;
        ctx.beginPath();
        ctx.moveTo(x0, y0);
        ctx.lineTo(x1, y1);
        ctx.stroke();
    }
    ctx.strokeStyle = rgba(accent, 0.4);
    ctx.lineWidth = 1.5;
    ctx.beginPath();
    ctx.arc(cx, cy, rInner, 0, 2 * Math.PI);
    ctx.stroke();
}

function draw(style, ctx, w, h, bars, accent, teal, state, peakHold) {
    if (!bars || bars.length === 0)
        return;
    if (style === "wave")
        drawWave(ctx, w, h, bars, accent, teal);
    else if (style === "blocks")
        drawBlocks(ctx, w, h, bars, accent, teal);
    else if (style === "flame")
        drawFlame(ctx, w, h, bars, accent, teal, state);
    else if (style === "mirror")
        drawMirror(ctx, w, h, bars, accent, teal, state, peakHold);
    else if (style === "dots")
        drawDots(ctx, w, h, bars, accent, teal);
    else if (style === "ring")
        drawRing(ctx, w, h, bars, accent, teal);
    else
        drawBars(ctx, w, h, bars, accent, teal, state, peakHold);
}
