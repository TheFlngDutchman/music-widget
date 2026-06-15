#!/usr/bin/env bash
# music-widget installer (Quickshell edition).
#
# What this does (idempotent, re-runnable):
#   1. Verifies system packages (or installs them with --install-deps).
#   2. Symlinks this repo to ~/.config/quickshell/music-widget.
#   3. Installs + enables the music-widget user service (resident widget,
#      zero cold-start — the Waybar button only toggles visibility).
#   4. Seeds ~/.config/spotifyd/spotifyd.conf and enables spotifyd.
#   5. Migrates an old config.toml to config.json (once, if present).
#   6. Installs ~/.local/bin/music-widget (toggle) and music-waybar-title.
#   7. Injects Waybar modules if missing (on-click toggles the widget).
#   8. Removes the old Python install (venv) if it's still around.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${HOME}/.local/bin"
CFG_DIR="${HOME}/.config/music-widget"
QS_LINK="${HOME}/.config/quickshell/music-widget"
UNIT_DIR="${HOME}/.config/systemd/user"
APPS_DIR="${HOME}/.local/share/applications"
DESKTOP_FILE="${APPS_DIR}/music-widget.desktop"
SPOTIFYD_CONF="${HOME}/.config/spotifyd/spotifyd.conf"
OLD_VENV="${HOME}/.local/share/music-widget/venv"

PKGS=(quickshell cava spotifyd mpd mpc playerctl yt-dlp ffmpeg)

color() { printf "\033[%sm%s\033[0m" "$1" "$2"; }
info()  { echo "$(color "1;34" "→") $*"; }
ok()    { echo "$(color "1;32" "✓") $*"; }
warn()  { echo "$(color "1;33" "!") $*"; }
die()   { echo "$(color "1;31" "✗") $*" >&2; exit 1; }

INSTALL_DEPS=0
for arg in "$@"; do
    case "$arg" in
        --install-deps) INSTALL_DEPS=1 ;;
        -h|--help)
            sed -n '2,14p' "$0"
            echo
            echo "Flags:"
            echo "  --install-deps    install missing packages (omarchy pkg add / pacman)"
            exit 0
            ;;
        *) die "Unknown flag: $arg" ;;
    esac
done

# ── 1. System deps ─────────────────────────────────────────────────────
info "Checking system dependencies"

missing=()
for p in "${PKGS[@]}"; do
    pacman -Q "$p" &>/dev/null || missing+=("$p")
done

if [ ${#missing[@]} -gt 0 ]; then
    if [ "$INSTALL_DEPS" -eq 1 ]; then
        info "Installing: ${missing[*]}"
        if command -v omarchy &>/dev/null; then
            omarchy pkg add "${missing[@]}"
        else
            sudo pacman -S --needed --noconfirm "${missing[@]}"
        fi
    else
        warn "Missing packages: ${missing[*]}"
        echo "  Install with: sudo pacman -S --needed ${missing[*]}"
        echo "  Or re-run with: $0 --install-deps"
        die "System deps not satisfied"
    fi
fi
ok "System dependencies OK"

# ── 2. Quickshell config symlink ───────────────────────────────────────
info "Linking $QS_LINK"
mkdir -p "$(dirname "$QS_LINK")"
if [ -L "$QS_LINK" ] || [ ! -e "$QS_LINK" ]; then
    ln -sfn "$REPO_DIR" "$QS_LINK"
    ok "Symlinked → $REPO_DIR"
else
    die "$QS_LINK exists and is not a symlink — move it aside and re-run"
fi

# ── 3. Widget user service ─────────────────────────────────────────────
info "Installing music-widget.service"
mkdir -p "$UNIT_DIR"
cat > "$UNIT_DIR/music-widget.service" <<'EOF'
[Unit]
Description=Music widget (Quickshell)
PartOf=graphical-session.target
After=graphical-session.target

[Service]
ExecStart=/usr/bin/qs -c music-widget
Restart=on-failure
RestartSec=2

[Install]
WantedBy=graphical-session.target
EOF
systemctl --user daemon-reload
systemctl --user enable music-widget.service >/dev/null 2>&1
# restart (not start): pick up code changes when re-running the installer
systemctl --user restart music-widget.service
ok "music-widget.service enabled and running"

# ── 4. spotifyd ────────────────────────────────────────────────────────
if [ ! -f "$SPOTIFYD_CONF" ]; then
    info "Seeding $SPOTIFYD_CONF"
    mkdir -p "$(dirname "$SPOTIFYD_CONF")"
    cat > "$SPOTIFYD_CONF" <<EOF
[global]
device_name = "Music Widget"
device_type = "computer"
use_mpris = true
cache_path = "${HOME}/.cache/spotifyd"
EOF
    ok "Wrote spotifyd.conf"
else
    ok "spotifyd.conf already exists — preserved"
fi
systemctl --user enable --now spotifyd.service >/dev/null 2>&1 || true
ok "spotifyd enabled ($(systemctl --user is-active spotifyd.service || true))"
if [ ! -f "${HOME}/.cache/spotifyd/oauth/credentials.json" ]; then
    warn "spotifyd has no credentials yet — use Settings → spotifyd → Authenticate in the widget"
fi

# ── 5. Config migration (old TOML → JSON) ──────────────────────────────
OLD_TOML="$CFG_DIR/config.toml"
NEW_JSON="$CFG_DIR/config.json"
if [ -f "$OLD_TOML" ] && [ ! -f "$NEW_JSON" ]; then
    info "Migrating config.toml → config.json"
    python3 - "$OLD_TOML" "$NEW_JSON" <<'PYEOF'
import json, sys, tomllib

old = tomllib.load(open(sys.argv[1], "rb"))
w, s, v = old.get("widget", {}), old.get("spotify", {}), old.get("visualizer", {})
new = {
    "window": {
        "width": w.get("width", 560),
        "height": w.get("height", 320),
        "marginTop": w.get("margin_top", 4),
        "marginRight": w.get("margin_right", 4),
    },
    "spotify": {"redirectPort": s.get("redirect_port", 19872)},
    "visualizer": {k: v[o] for k, o in [
        ("style", "style"), ("bars", "bars"), ("sensitivity", "sensitivity"),
        ("channels", "channels"), ("smoothing", "smoothing"),
    ] if o in v},
}
json.dump(new, open(sys.argv[2], "w"), indent=2)
PYEOF
    ok "Migrated (old file kept at $OLD_TOML)"
fi

# ── 6. Launchers ───────────────────────────────────────────────────────
info "Installing launchers to $BIN_DIR"
mkdir -p "$BIN_DIR"

cat > "$BIN_DIR/music-widget" <<'EOF'
#!/usr/bin/env bash
# music-widget toggle — autogenerated by install.sh.
# The widget runs resident as a user service; this only flips visibility.
if ! qs -c music-widget ipc call window toggle 2>/dev/null; then
    systemctl --user start music-widget.service
    for _ in 1 2 3 4 5; do
        sleep 0.4
        qs -c music-widget ipc call window open 2>/dev/null && exit 0
    done
    echo "music-widget: could not reach the widget service" >&2
    exit 1
fi
EOF
chmod +x "$BIN_DIR/music-widget"

install -m 755 "$REPO_DIR/bin/music-waybar-title" "$BIN_DIR/music-waybar-title"
ok "Installed music-widget and music-waybar-title"

mkdir -p "$APPS_DIR"
install -m 644 "$REPO_DIR/data/music-widget.desktop" "$DESKTOP_FILE"
command -v update-desktop-database &>/dev/null \
    && update-desktop-database "$APPS_DIR" &>/dev/null || true
ok "Installed launcher entry"

# ── 7. Waybar config ───────────────────────────────────────────────────
WAYBAR_CFG="${HOME}/.config/waybar/config.jsonc"

inject_waybar() {
    if [ ! -f "$WAYBAR_CFG" ]; then
        warn "No waybar config at $WAYBAR_CFG — see docs/waybar.jsonc for the snippet"
        return
    fi

    if python3 -c "
import re, sys
text = open('$WAYBAR_CFG').read()
sys.exit(0 if re.search(r'\"custom/music-title\"\s*:', text) else 1)
" 2>/dev/null; then
        ok "Waybar already has music-widget modules — nothing changed"
        return
    fi

    info "Injecting music-widget modules into $WAYBAR_CFG"
    cp "$WAYBAR_CFG" "${WAYBAR_CFG}.bak"

    python3 - "$WAYBAR_CFG" <<'PYEOF'
import re, sys

path = sys.argv[1]
with open(path) as f:
    content = f.read()

names = [
    '"custom/music-prev"',
    '"custom/music-play"',
    '"custom/music-next"',
    '"custom/music-title"',
]

defs = '''\
  "custom/music-prev": {
    "format": "󰒮   ",
    "on-click": "playerctl --player=spotifyd,spotify,mpd previous",
    "tooltip": false
  },
  "custom/music-play": {
    "exec": "playerctl --player=spotifyd,spotify,mpd status -F | sed -u 's/Playing/󰏤/;s/Paused/󰐊/;s/Stopped/󰐊/'",
    "return-type": "raw",
    "on-click": "playerctl --player=spotifyd,spotify,mpd play-pause",
    "tooltip": false
  },
  "custom/music-next": {
    "format": "   󰒭  ",
    "on-click": "playerctl --player=spotifyd,spotify,mpd next",
    "tooltip": false
  },
  "custom/music-title": {
    "exec": "music-waybar-title",
    "return-type": "raw",
    "max-length": 30,
    "on-click": "music-widget",
    "tooltip": false
  }'''

inject = ',\n    '.join(names) + ','
new = re.sub(
    r'("modules-right"\s*:\s*\[)',
    r'\1\n    ' + inject,
    content,
    count=1,
)

pos = new.rfind('\n}')
if pos != -1:
    new = new[:pos] + ',\n\n' + defs + '\n' + new[pos:]

with open(path, 'w') as f:
    f.write(new)
PYEOF

    if [ $? -eq 0 ]; then
        ok "Injected music-widget into $WAYBAR_CFG (backup: ${WAYBAR_CFG}.bak)"
        if command -v omarchy &>/dev/null && omarchy restart waybar 2>/dev/null; then
            ok "Restarted Waybar via omarchy"
        elif pkill -SIGUSR2 waybar 2>/dev/null; then
            ok "Reloaded Waybar via SIGUSR2"
        elif systemctl --user restart waybar 2>/dev/null; then
            ok "Restarted Waybar via systemd"
        else
            warn "Could not restart Waybar — restart it manually"
        fi
    else
        warn "Injection failed — restoring backup"
        cp "${WAYBAR_CFG}.bak" "$WAYBAR_CFG"
        info "Snippet saved at docs/waybar.jsonc — paste it manually."
    fi
}

inject_waybar

# ── 8. Old Python install cleanup ──────────────────────────────────────
if [ -d "$OLD_VENV" ]; then
    info "Removing old Python venv"
    rm -rf "$OLD_VENV"
    rmdir --ignore-fail-on-non-empty "$(dirname "$OLD_VENV")" 2>/dev/null || true
    ok "Removed $OLD_VENV"
fi

ok "Done. Toggle with the Waybar button or: music-widget"
