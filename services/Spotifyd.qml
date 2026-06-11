pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// spotifyd is a systemd user service the widget never spawns. This watches
// its credentials file (event-driven — replaces the old 120s busy-wait) and
// surfaces unit state, plus a one-click `spotifyd authenticate`.
Singleton {
    id: root

    property bool hasCredentials: false
    property bool serviceActive: false
    property string deviceName: "Music Widget"
    property bool authenticating: false
    property string authError: ""

    function refreshState() {
        if (!check.running)
            check.running = true;
    }

    function authenticate() {
        authError = "";
        authenticating = true;
        authProc.running = true;
    }

    function startService() {
        startProc.running = true;
    }

    onHasCredentialsChanged: {
        if (authenticating && hasCredentials) {
            authenticating = false;
            restartProc.running = true;
        }
    }

    FileView {
        path: Quickshell.env("HOME") + "/.cache/spotifyd/oauth/credentials.json"
        watchChanges: true
        preload: true
        onFileChanged: reload()
        onLoaded: {
            let ok = false;
            try {
                ok = JSON.parse(text()).auth_data !== undefined;
            } catch (e) {}
            root.hasCredentials = ok;
        }
        onLoadFailed: root.hasCredentials = false
    }

    // device_name from spotifyd.conf so playback can target the right device
    FileView {
        path: Quickshell.env("HOME") + "/.config/spotifyd/spotifyd.conf"
        preload: true
        onLoaded: {
            const m = text().match(/^\s*device_name\s*=\s*"?([^"\n]+)"?/m);
            if (m)
                root.deviceName = m[1].trim();
        }
    }

    Process {
        id: check
        command: ["systemctl", "--user", "is-active", "spotifyd"]

        stdout: SplitParser {
            onRead: data => root.serviceActive = data.trim() === "active"
        }
    }

    Process {
        id: startProc
        command: ["systemctl", "--user", "start", "spotifyd"]
        onExited: root.refreshState()
    }

    Process {
        id: restartProc
        command: ["systemctl", "--user", "restart", "spotifyd"]
        onExited: root.refreshState()
    }

    Process {
        id: authProc
        command: ["spotifyd", "authenticate", "--oauth-port", "19876"]
        onExited: (code, status) => {
            if (root.authenticating) {
                root.authenticating = false;
                if (code !== 0)
                    root.authError = "spotifyd authenticate failed (exit " + code + ")";
            }
        }
    }
}
