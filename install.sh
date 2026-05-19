#!/usr/bin/env bash
# music-widget installer.
#
# What this does (idempotent, re-runnable):
#   1. Verifies system packages (or installs them with --install-deps).
#   2. Creates a uv-managed venv at ~/.local/share/music-widget/venv
#      with --system-site-packages so PyGObject is available.
#   3. Installs the widget into that venv via `uv pip install`.
#   4. Symlinks `music-widget` and `music-waybar-title` into ~/.local/bin.
#   5. Seeds default config under ~/.config/music-widget/ if not present.
#   6. Prints the Waybar snippet (does NOT touch your waybar config).

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="${HOME}/.local/share/music-widget/venv"
BIN_DIR="${HOME}/.local/bin"
CFG_DIR="${HOME}/.config/music-widget"
APPS_DIR="${HOME}/.local/share/applications"
DESKTOP_FILE="${APPS_DIR}/music-widget.desktop"

PKGS=(playerctl cava spotifyd mpd mpc gtk4 libadwaita python python-gobject)
# uv may be installed standalone (not via pacman); we'll check the binary too.

color() { printf "\033[%sm%s\033[0m" "$1" "$2"; }
info()  { echo "$(color "1;34" "→") $*"; }
ok()    { echo "$(color "1;32" "✓") $*"; }
warn()  { echo "$(color "1;33" "!") $*"; }
die()   { echo "$(color "1;31" "✗") $*" >&2; exit 1; }

INSTALL_DEPS=0
LAUNCHER_MODE=ask   # ask|yes|no
for arg in "$@"; do
    case "$arg" in
        --install-deps) INSTALL_DEPS=1 ;;
        --with-launcher) LAUNCHER_MODE=yes ;;
        --no-launcher)   LAUNCHER_MODE=no  ;;
        -h|--help)
            sed -n '2,20p' "$0"
            echo
            echo "Flags:"
            echo "  --install-deps    pass missing packages to 'omarchy pkg add'"
            echo "  --with-launcher   install ~/.local/share/applications entry without asking"
            echo "  --no-launcher     skip the .desktop entry prompt"
            exit 0
            ;;
        *) die "Unknown flag: $arg" ;;
    esac
done

# ── 1. System deps ─────────────────────────────────────────────────────
info "Checking system dependencies"

missing=()
for p in "${PKGS[@]}"; do
    if ! pacman -Q "$p" &>/dev/null; then
        missing+=("$p")
    fi
done

if ! command -v uv &>/dev/null; then
    # uv might not be pacman-managed (curl-installed binaries are common).
    warn "uv binary not found on PATH"
    missing+=(uv)
fi

if [ ${#missing[@]} -gt 0 ]; then
    if [ "$INSTALL_DEPS" -eq 1 ]; then
        info "Installing missing packages via omarchy pkg add: ${missing[*]}"
        if command -v omarchy &>/dev/null; then
            omarchy pkg add "${missing[@]}"
        else
            warn "omarchy not on PATH — falling back to pacman"
            sudo pacman -S --needed --noconfirm "${missing[@]}"
        fi
    else
        warn "Missing packages: ${missing[*]}"
        if command -v omarchy &>/dev/null; then
            echo "  Install with: omarchy pkg add ${missing[*]}"
        else
            echo "  Install with: sudo pacman -S --needed ${missing[*]}"
        fi
        echo "  Or re-run with: $0 --install-deps"
        die "System deps not satisfied"
    fi
fi
ok "System dependencies OK"

# ── 2. uv venv ─────────────────────────────────────────────────────────
info "Preparing venv at $VENV_DIR"
mkdir -p "$(dirname "$VENV_DIR")"

# Use the system Python so we can pick up the pacman-managed PyGObject
# from /usr/lib/pythonX.Y/site-packages. If we let uv pick its own Python,
# `import gi` fails because PyGObject is only installed for the system one.
SYS_PYTHON="$(command -v python3 || true)"
if [ -z "$SYS_PYTHON" ]; then
    die "python3 not found on PATH"
fi
SYS_PY_VER="$("$SYS_PYTHON" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"

NEED_REBUILD=0
if [ -d "$VENV_DIR" ]; then
    EXISTING_VER="$("$VENV_DIR/bin/python" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null || echo "")"
    if [ "$EXISTING_VER" != "$SYS_PY_VER" ]; then
        warn "Venv was built against Python $EXISTING_VER but system Python is $SYS_PY_VER — rebuilding"
        rm -rf "$VENV_DIR"
        NEED_REBUILD=1
    fi
fi

if [ ! -d "$VENV_DIR" ]; then
    uv venv --python "$SYS_PYTHON" --system-site-packages "$VENV_DIR"
    ok "Created venv (Python $SYS_PY_VER)"
else
    ok "Venv already exists (Python $SYS_PY_VER)"
fi

# ── 3. Install the package ─────────────────────────────────────────────
info "Installing music-widget into venv"
uv pip install --python "$VENV_DIR/bin/python" --upgrade "$REPO_DIR" >/dev/null
ok "Installed package"

# ── 4. Symlinks ────────────────────────────────────────────────────────
info "Installing launchers to $BIN_DIR"
mkdir -p "$BIN_DIR"

ln -sf "$VENV_DIR/bin/music-widget" "$BIN_DIR/music-widget"
install -m 755 "$REPO_DIR/bin/music-waybar-title" "$BIN_DIR/music-waybar-title"
ok "Installed music-widget and music-waybar-title"

# ── 5. Seed configs ────────────────────────────────────────────────────
info "Seeding default config (if missing) in $CFG_DIR"
mkdir -p "$CFG_DIR"

seed() {
    local src="$1" dst="$2"
    if [ ! -e "$dst" ]; then
        cp "$src" "$dst"
        ok "Wrote $dst"
    else
        ok "$dst already exists — preserved"
    fi
}

seed "$REPO_DIR/data/cava.conf"           "$CFG_DIR/cava.conf"
seed "$REPO_DIR/data/default-config.toml" "$CFG_DIR/config.toml"

# ── 6. App launcher (.desktop) entry ───────────────────────────────────
install_launcher_entry() {
    mkdir -p "$APPS_DIR"
    install -m 644 "$REPO_DIR/data/music-widget.desktop" "$DESKTOP_FILE"
    if command -v update-desktop-database &>/dev/null; then
        update-desktop-database "$APPS_DIR" &>/dev/null || true
    fi
    ok "Installed $DESKTOP_FILE (visible in Walker / app launcher)"
}

case "$LAUNCHER_MODE" in
    yes)
        install_launcher_entry
        ;;
    no)
        info "Skipping app-launcher entry (--no-launcher)"
        ;;
    ask)
        echo
        if [ -e "$DESKTOP_FILE" ]; then
            prompt="Reinstall app-launcher entry ($DESKTOP_FILE)? [Y/n] "
        else
            prompt="Install app-launcher entry so 'Music Widget' shows up in Walker / your launcher? [Y/n] "
        fi
        # Default Yes; if stdin isn't a TTY (e.g. piped), assume Yes.
        if [ -t 0 ]; then
            read -r -p "$prompt" reply
        else
            reply=""
        fi
        case "${reply,,}" in
            ""|y|yes) install_launcher_entry ;;
            *)        info "Skipping app-launcher entry" ;;
        esac
        ;;
esac

# ── 7. Waybar snippet ──────────────────────────────────────────────────
cat <<'EOF'

────────────────────────────────────────────────────────────────────
Waybar wiring (paste into ~/.config/waybar/config.jsonc):

  "modules-right": [
    "custom/music-prev",
    "custom/music-play",
    "custom/music-next",
    "custom/music-title",
    ...
  ],

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
  }

A copy of this snippet is at docs/waybar.jsonc.
────────────────────────────────────────────────────────────────────
EOF

ok "Done. Launch: music-widget"
