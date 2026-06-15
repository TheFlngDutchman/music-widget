pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Omarchy theme colors with live reload and config overrides.
//
// Omarchy swaps ~/.config/omarchy/current/theme wholesale (new inodes), so
// watching files inside it breaks after a switch. theme.name is rewritten in
// place after every swap — that is the reliable watch target; on change we
// re-read gtk.css and colors.toml by path.
Singleton {
    id: root

    readonly property string omarchyDir: Quickshell.env("HOME") + "/.config/omarchy/current"

    property var gtkColors: ({})
    property var tomlColors: ({})

    readonly property color bg: pick(Config.colors.background, "window_bg_color", "background", "#0c0b0c")
    readonly property color fg: pick(Config.colors.foreground, "window_fg_color", "foreground", "#fafcfb")
    readonly property color accent: pick(Config.colors.accent, "accent_color", "accent", "#b59790")
    readonly property color accentBg: pick(Config.colors.accent, "accent_bg_color", "accent", "#b59790")
    readonly property color accentFg: pick("", "accent_fg_color", "selection_foreground", "#0c0b0c")
    readonly property color teal: pick(Config.colors.teal, "", "color2", "#87a9b0")
    readonly property color error: pick("", "red", "color1", "#c38b7b")
    readonly property color border: Qt.alpha(fg, 0.35)

    readonly property string fontFamily: Config.font.family
    readonly property int fontSize: Config.font.size

    function alpha(c, a) {
        return Qt.alpha(c, a);
    }

    function pick(override, gtkKey, tomlKey, fallback) {
        if (override && override.length > 0)
            return override;
        if (gtkKey && gtkColors[gtkKey] !== undefined)
            return gtkColors[gtkKey];
        if (tomlKey && tomlColors[tomlKey] !== undefined)
            return tomlColors[tomlKey];
        return fallback;
    }

    // "@define-color name value;" where value is hex/rgba()/@reference.
    function parseGtkCss(text) {
        const defs = {};
        const re = /@define-color\s+([\w-]+)\s+([^;]+);/g;
        let m;
        while ((m = re.exec(text)) !== null)
            defs[m[1]] = m[2].trim();
        // resolve @references (themes chain at most a couple of levels)
        for (let pass = 0; pass < 4; pass++) {
            let changed = false;
            for (const k in defs) {
                const v = defs[k];
                if (v.startsWith("@") && defs[v.slice(1)] !== undefined && !defs[v.slice(1)].startsWith("@")) {
                    defs[k] = defs[v.slice(1)];
                    changed = true;
                }
            }
            if (!changed)
                break;
        }
        // resolve alpha(color, factor) function calls
        for (const k in defs) {
            const m2 = defs[k].match(/^alpha\s*\(\s*@?([\w-]+)\s*,\s*([\d.]+)\s*\)\s*$/i);
            if (m2) {
                const baseName = m2[1];
                const alphaVal = parseFloat(m2[2]);
                const base = defs[baseName];
                if (base && base.startsWith("#")) {
                    const hex = base.replace("#", "");
                    if (hex.length >= 6) {
                        const r = parseInt(hex.substring(0, 2), 16);
                        const g = parseInt(hex.substring(2, 4), 16);
                        const b = parseInt(hex.substring(4, 6), 16);
                        defs[k] = `rgba(${r},${g},${b},${alphaVal})`;
                    }
                }
            }
        }
        return defs;
    }

    // flat `key = "#hex"` lines
    function parseFlatToml(text) {
        const out = {};
        const re = /^\s*(\w+)\s*=\s*"(#[0-9a-fA-F]{3,8})"/gm;
        let m;
        while ((m = re.exec(text)) !== null)
            out[m[1]] = m[2];
        return out;
    }

    function reloadAll() {
        gtkCss.reload();
        colorsToml.reload();
    }

    FileView {
        id: themeName
        path: root.omarchyDir + "/theme.name"
        watchChanges: true
        onFileChanged: {
            reload();
            root.reloadAll();
        }
    }

    FileView {
        id: gtkCss
        path: root.omarchyDir + "/theme/gtk.css"
        onLoaded: root.gtkColors = root.parseGtkCss(text())
        onLoadFailed: root.gtkColors = {}
    }

    FileView {
        id: colorsToml
        path: root.omarchyDir + "/theme/colors.toml"
        onLoaded: root.tomlColors = root.parseFlatToml(text())
        onLoadFailed: root.tomlColors = {}
    }
}
