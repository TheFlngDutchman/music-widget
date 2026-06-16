#!/usr/bin/env bash
# music-widget uninstaller.
#
# Default (interactive): removes the service, symlink, launchers, desktop
# entry and the injected Waybar modules, then asks before touching shared
# services, configs, caches and packages.
#
#   ./uninstall.sh            interactive
#   ./uninstall.sh --purge    remove EVERYTHING without asking: services,
#                             configs, caches, the MPD/spotifyd setup and the
#                             music-widget packages
#   ./uninstall.sh --help     show this help
#
# Never touched: your music library (~/Music), and the general-purpose
# packages quickshell, playerctl, ffmpeg and yt-dlp.

set -euo pipefail

PURGE=0
for arg in "$@"; do
    case "$arg" in
        --purge|--all) PURGE=1 ;;
        -h|--help)
            # print the header comment block (skip shebang, stop at first non-#)
            awk 'NR==1{next} /^#/{sub(/^# ?/,"");print;next} {exit}' "$0"
            exit 0 ;;
        *) echo "unknown option: $arg (try --help)" >&2; exit 1 ;;
    esac
done

BIN_DIR="${HOME}/.local/bin"
CFG_DIR="${HOME}/.config/music-widget"
STATE_DIR="${HOME}/.local/state/music-widget"
QS_LINK="${HOME}/.config/quickshell/music-widget"
UNIT_FILE="${HOME}/.config/systemd/user/music-widget.service"
APPS_DIR="${HOME}/.local/share/applications"
DESKTOP_FILE="${APPS_DIR}/music-widget.desktop"
OLD_VENV="${HOME}/.local/share/music-widget/venv"
WAYBAR_CFG="${HOME}/.config/waybar/config.jsonc"
SPOTIFYD_DIR="${HOME}/.config/spotifyd"
SPOTIFYD_CACHE="${HOME}/.cache/spotifyd"
MPD_DIR="${HOME}/.config/mpd"
MPD_DATA="${HOME}/.local/share/mpd"
# music-widget-specific packages. quickshell, playerctl, ffmpeg and yt-dlp are
# general-purpose / shared, so they are left installed.
PKGS_REMOVE=(spotifyd mpd mpc mpd-mpris cava)

ok()   { echo "✓ $*"; }
info() { echo "→ $*"; }
warn() { echo "! $*"; }

# yes/no prompt; auto-yes under --purge. Returns 0 for yes.
confirm() {
    [ "$PURGE" -eq 1 ] && return 0
    local reply=""
    read -r -p "$1 [y/N] " reply || true
    case "${reply,,}" in y|yes) return 0 ;; *) return 1 ;; esac
}

# ── always: the widget itself ──────────────────────────────────────────
info "Stopping widget service"
systemctl --user disable --now music-widget.service 2>/dev/null || true
rm -f "$UNIT_FILE"
systemctl --user daemon-reload
ok "Removed music-widget.service"

info "Removing quickshell config link"
[ -L "$QS_LINK" ] && rm -f "$QS_LINK"
ok "Removed $QS_LINK"

info "Removing launchers"
rm -f "$BIN_DIR/music-widget" "$BIN_DIR/music-waybar-title" \
      "$BIN_DIR/music-waybar-player" "$BIN_DIR/music-waybar-status"
ok "Removed launchers"

if [ -e "$DESKTOP_FILE" ]; then
    rm -f "$DESKTOP_FILE"
    command -v update-desktop-database &>/dev/null \
        && update-desktop-database "$APPS_DIR" &>/dev/null || true
    ok "Removed launcher entry"
fi

# leftover from the old Python install
if [ -d "$OLD_VENV" ]; then
    rm -rf "$OLD_VENV"
    rmdir --ignore-fail-on-non-empty "$(dirname "$OLD_VENV")" 2>/dev/null || true
    ok "Removed old Python venv"
fi

# ── always: reverse the Waybar injection ───────────────────────────────
if [ -f "$WAYBAR_CFG" ] && grep -q '"custom/music-title"' "$WAYBAR_CFG"; then
    info "Removing music-widget modules from Waybar config"
    cp "$WAYBAR_CFG" "${WAYBAR_CFG}.bak"
    python3 - "$WAYBAR_CFG" <<'PYEOF'
import re, sys

path = sys.argv[1]
with open(path) as f:
    content = f.read()

# module definitions: "custom/music-X": { ... } with optional leading comma.
# The body can contain literal braces (e.g. "format": "{}  "), so match
# lazily up to the closing brace on its own line rather than [^{}]* — which
# would stop at the first brace inside a value and leave a keyless ": {".
content = re.sub(
    r',?\s*"custom/music-(?:prev|play|next|title)"\s*:\s*\{.*?\n[ \t]*\}',
    '', content, flags=re.DOTALL)
# module names inside modules-* arrays
content = re.sub(r'\s*"custom/music-(?:prev|play|next|title)"\s*,?', '\n    ', content)
# tidy any comma left dangling before a closing bracket
content = re.sub(r',(\s*[\]}])', r'\1', content)

with open(path, 'w') as f:
    f.write(content)
PYEOF
    ok "Removed Waybar modules (backup: ${WAYBAR_CFG}.bak)"
    if command -v omarchy &>/dev/null && omarchy restart waybar 2>/dev/null; then
        ok "Restarted Waybar via omarchy"
    elif pkill -SIGUSR2 waybar 2>/dev/null; then
        ok "Reloaded Waybar via SIGUSR2"
    elif systemctl --user restart waybar 2>/dev/null; then
        ok "Restarted Waybar via systemd"
    else
        warn "Could not restart Waybar — restart it manually"
    fi
fi

# ── optional: spotifyd setup (service + seeded config + cache) ──────────
if systemctl --user is-enabled spotifyd.service &>/dev/null \
   || [ -d "$SPOTIFYD_DIR" ] || [ -d "$SPOTIFYD_CACHE" ]; then
    echo
    if confirm "Remove spotifyd setup (disable the service and delete $SPOTIFYD_DIR + $SPOTIFYD_CACHE)? Other tools may use spotifyd."; then
        systemctl --user disable --now spotifyd.service 2>/dev/null || true
        rm -rf "$SPOTIFYD_DIR" "$SPOTIFYD_CACHE"
        ok "Removed spotifyd setup"
    else
        info "Left spotifyd setup in place"
    fi
fi

# ── optional: MPD setup (service + seeded config + database) ────────────
if systemctl --user is-enabled mpd.service &>/dev/null \
   || [ -d "$MPD_DIR" ] || [ -d "$MPD_DATA" ]; then
    echo
    if confirm "Remove MPD setup (disable the service and delete $MPD_DIR + the database at $MPD_DATA)? Your music in ~/Music is kept."; then
        systemctl --user disable --now mpd.service 2>/dev/null || true
        rm -rf "$MPD_DIR" "$MPD_DATA"
        ok "Removed MPD setup"
    else
        info "Left MPD setup in place"
    fi
fi

# ── optional: mpd-mpris ────────────────────────────────────────────────
if systemctl --user is-enabled mpd-mpris.service &>/dev/null; then
    echo
    if confirm "Disable mpd-mpris? Other tools may use it."; then
        systemctl --user disable --now mpd-mpris.service 2>/dev/null || true
        ok "Disabled mpd-mpris"
    else
        info "Left mpd-mpris enabled"
    fi
fi

# ── optional: widget config + Spotify tokens ───────────────────────────
if [ -d "$CFG_DIR" ] || [ -d "$STATE_DIR" ]; then
    echo
    echo "Config and auth data:"
    [ -d "$CFG_DIR" ]   && echo "  $CFG_DIR — widget config"
    [ -d "$STATE_DIR" ] && echo "  $STATE_DIR — Spotify tokens"
    if confirm "Remove these too?"; then
        rm -rf "$CFG_DIR" "$STATE_DIR"
        ok "Removed config and tokens"
    else
        info "Preserved — a reinstall will pick them up again"
    fi
fi

# ── optional: packages ─────────────────────────────────────────────────
installed=()
for p in "${PKGS_REMOVE[@]}"; do
    pacman -Q "$p" &>/dev/null && installed+=("$p")
done
if [ ${#installed[@]} -gt 0 ]; then
    echo
    if confirm "Remove the packages installed for music-widget (${installed[*]})? quickshell, playerctl, ffmpeg and yt-dlp are kept."; then
        # -Rns also drops now-orphaned deps; pacman still refuses anything a
        # kept package needs. Without --purge, let pacman show the list first.
        if [ "$PURGE" -eq 1 ]; then
            sudo pacman -Rns --noconfirm "${installed[@]}" \
                || warn "Some packages couldn't be removed (still required by other software)"
        else
            sudo pacman -Rns "${installed[@]}" \
                || warn "Some packages couldn't be removed (still required by other software)"
        fi
        ok "Removed packages"
    else
        info "Left packages installed"
    fi
fi

ok "Uninstalled music-widget."
