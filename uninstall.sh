#!/usr/bin/env bash
# music-widget uninstaller. Removes binaries and the venv; preserves user config.

set -euo pipefail

VENV_DIR="${HOME}/.local/share/music-widget/venv"
BIN_DIR="${HOME}/.local/bin"
CFG_DIR="${HOME}/.config/music-widget"

ok()   { echo "✓ $*"; }
info() { echo "→ $*"; }

info "Removing launchers"
rm -f "$BIN_DIR/music-widget"
rm -f "$BIN_DIR/music-waybar-title"
ok "Removed $BIN_DIR/music-widget and $BIN_DIR/music-waybar-title"

if [ -d "$VENV_DIR" ]; then
    info "Removing venv"
    rm -rf "$VENV_DIR"
    rmdir --ignore-fail-on-non-empty "$(dirname "$VENV_DIR")" 2>/dev/null || true
    ok "Removed $VENV_DIR"
fi

if [ -d "$CFG_DIR" ]; then
    echo
    echo "Your config at $CFG_DIR was preserved."
    echo "Delete it manually if you want a clean slate:"
    echo "  rm -rf $CFG_DIR"
fi

ok "Uninstalled music-widget."
