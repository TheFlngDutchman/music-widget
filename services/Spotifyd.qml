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

    // Single-auth path: the widget's PKCE token carries the "streaming"
    // scope, which librespot accepts as token credentials (auth_type 3).
    // Seeding spotifyd's credentials file with it skips the separate
    // `spotifyd authenticate` browser round-trip; on first login librespot
    // swaps it for reusable stored credentials, so expiry doesn't matter.
    function seedFromWidgetAuth() {
        if (hasCredentials)
            return;
        SpotifyAuth.withToken((token, err) => {
            if (!token)
                return;
            const xhr = new XMLHttpRequest();
            xhr.onreadystatechange = () => {
                if (xhr.readyState !== XMLHttpRequest.DONE)
                    return;
                if (xhr.status !== 200)
                    return;
                let username = "";
                try {
                    username = JSON.parse(xhr.responseText).id || "";
                } catch (e) {}
                if (username === "")
                    return;
                seedProc.creds = JSON.stringify({
                    username: username,
                    auth_type: 3,
                    auth_data: Qt.btoa(token)
                });
                seedProc.running = true;
            };
            xhr.open("GET", "https://api.spotify.com/v1/me");
            xhr.setRequestHeader("Authorization", "Bearer " + token);
            xhr.send();
        });
    }

    Connections {
        target: SpotifyAuth

        function onAuthorized() {
            root.seedFromWidgetAuth();
        }
    }

    Process {
        id: seedProc

        property string creds: ""

        command: ["/bin/sh", "-c",
            "mkdir -p \"$HOME/.cache/spotifyd/oauth\" && umask 077 && "
            + "printf '%s' \"$MW_SPOTIFYD_CREDS\" > \"$HOME/.cache/spotifyd/oauth/credentials.json\""]
        environment: ({ MW_SPOTIFYD_CREDS: seedProc.creds })
        onExited: code => {
            if (code === 0) {
                restartProc.running = false;
                restartProc.running = true;
            }
        }
    }

    FileView {
        id: credsFile
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
        onExited: {
            root.refreshState();
            // watcher can miss file *creation*; re-read explicitly
            credsFile.reload();
        }
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
