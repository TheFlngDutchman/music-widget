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
    // librespot auth_type from the credentials file: 1 = reusable stored
    // credentials (permanent, from `spotifyd authenticate`), 3 = seeded
    // access token (expires ~hourly — must be re-seeded before restarts)
    property int credsAuthType: 0
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
    // scope, which librespot accepts as token credentials (auth_type 3),
    // skipping the separate `spotifyd authenticate` browser round-trip.
    // spotifyd never swaps the token for reusable credentials in the file,
    // so the seed goes stale within the hour — ensureFreshSeed() rewrites
    // it at every widget start and bounces spotifyd so it can't be stuck
    // retrying a stale token from boot (it exits after 4 failed retries,
    // while `systemctl is-active` reports active throughout).
    function ensureFreshSeed() {
        if (!SpotifyAuth.hasTokens)
            return;
        if (hasCredentials && credsAuthType !== 3)
            return; // permanent credentials from `spotifyd authenticate`
        seedFromWidgetAuth(true);
    }

    // the auth store loads asynchronously at startup, so tokens are not
    // available yet when shell.qml calls ensureFreshSeed — catch them here
    Connections {
        id: tokenWatch
        target: SpotifyAuth

        function onHasTokensChanged() {
            if (SpotifyAuth.hasTokens) {
                tokenWatch.enabled = false;
                root.ensureFreshSeed();
            }
        }
    }

    function seedFromWidgetAuth(forceRestart) {
        // no credentials at all → spotifyd idles uselessly; restart it
        const mustRestart = forceRestart || !hasCredentials;
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
                seedProc.force = mustRestart;
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
            root.seedFromWidgetAuth(true);
        }
    }

    Process {
        id: seedProc

        property string creds: ""
        property bool force: false

        command: ["/bin/sh", "-c",
            "mkdir -p \"$HOME/.cache/spotifyd/oauth\" && umask 077 && "
            + "printf '%s' \"$MW_SPOTIFYD_CREDS\" > \"$HOME/.cache/spotifyd/oauth/credentials.json\" && "
            + "if [ \"$MW_RESTART\" = 1 ] || ! systemctl --user is-active --quiet spotifyd; then "
            + "systemctl --user restart spotifyd; fi"]
        environment: ({
            MW_SPOTIFYD_CREDS: seedProc.creds,
            MW_RESTART: seedProc.force ? "1" : "0"
        })
        onExited: {
            root.refreshState();
            credsFile.reload();
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
            let type = 0;
            try {
                const parsed = JSON.parse(text());
                ok = parsed.auth_data !== undefined;
                type = parsed.auth_type ?? 0;
            } catch (e) {}
            root.hasCredentials = ok;
            root.credsAuthType = type;
        }
        onLoadFailed: {
            root.hasCredentials = false;
            root.credsAuthType = 0;
        }
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
