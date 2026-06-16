#!/usr/bin/env bash
# music-widget uninstaller. Removes the service, symlink and launchers;
# preserves user config and Spotify tokens. Prompts before touching spotifyd.

set -euo pipefail

BIN_DIR="${HOME}/.local/bin"
CFG_DIR="${HOME}/.config/music-widget"
QS_LINK="${HOME}/.config/quickshell/music-widget"
UNIT_FILE="${HOME}/.config/systemd/user/music-widget.service"
APPS_DIR="${HOME}/.local/share/applications"
DESKTOP_FILE="${APPS_DIR}/music-widget.desktop"
OLD_VENV="${HOME}/.local/share/music-widget/venv"

ok()   { echo "✓ $*"; }
info() { echo "→ $*"; }
warn() { echo "! $*"; }

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

# remove the injected Waybar modules (reverses install.sh's injection)
WAYBAR_CFG="${HOME}/.config/waybar/config.jsonc"
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

if systemctl --user is-enabled spotifyd.service &>/dev/null; then
    echo
    read -r -p "Disable spotifyd too? Other tools may use it. [y/N] " reply
    case "${reply,,}" in
        y|yes)
            systemctl --user disable --now spotifyd.service
            ok "Disabled spotifyd"
            ;;
        *) info "Left spotifyd enabled" ;;
    esac
fi

if systemctl --user is-enabled mpd-mpris.service &>/dev/null; then
    echo
    read -r -p "Disable mpd-mpris too? Other tools may use it. [y/N] " reply
    case "${reply,,}" in
        y|yes)
            systemctl --user disable --now mpd-mpris.service
            ok "Disabled mpd-mpris"
            ;;
        *) info "Left mpd-mpris enabled" ;;
    esac
fi

STATE_DIR="${HOME}/.local/state/music-widget"
if [ -d "$CFG_DIR" ] || [ -d "$STATE_DIR" ]; then
    echo
    echo "Config and auth data:"
    [ -d "$CFG_DIR" ]   && echo "  $CFG_DIR — widget config"
    [ -d "$STATE_DIR" ] && echo "  $STATE_DIR — Spotify tokens"
    read -r -p "Remove these too? [y/N] " reply
    case "${reply,,}" in
        y|yes)
            rm -rf "$CFG_DIR" "$STATE_DIR"
            ok "Removed config and tokens"
            ;;
        *) info "Preserved — a reinstall will pick them up again" ;;
    esac
fi

ok "Uninstalled music-widget."
