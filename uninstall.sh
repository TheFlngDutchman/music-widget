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

info "Stopping widget service"
systemctl --user disable --now music-widget.service 2>/dev/null || true
rm -f "$UNIT_FILE"
systemctl --user daemon-reload
ok "Removed music-widget.service"

info "Removing quickshell config link"
[ -L "$QS_LINK" ] && rm -f "$QS_LINK"
ok "Removed $QS_LINK"

info "Removing launchers"
rm -f "$BIN_DIR/music-widget" "$BIN_DIR/music-waybar-title"
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

echo
echo "Preserved (delete manually if you want a clean slate):"
echo "  $CFG_DIR                            — widget config"
echo "  ${HOME}/.local/state/music-widget   — Spotify tokens"
echo "  Waybar custom/music-* modules in ~/.config/waybar/config.jsonc"

ok "Uninstalled music-widget."
