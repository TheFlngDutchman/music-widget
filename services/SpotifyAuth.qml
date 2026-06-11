pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Single Spotify PKCE flow. The python helper owns the port preflight, PKCE
// pair generation and the one-shot redirect listener; token exchange and
// refresh live here so there is exactly one place that touches tokens.
// Tokens persist in ~/.local/state/music-widget/auth.json (chmod 600).
Singleton {
    id: root

    readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/music-widget"
    readonly property string redirectUri: "http://127.0.0.1:" + Config.spotify.redirectPort + "/login"
    readonly property string scopes: "user-read-playback-state user-modify-playback-state "
        + "user-read-currently-playing playlist-read-private playlist-read-collaborative "
        + "user-library-read user-read-recently-played"

    property bool authorizing: false
    property string errorMessage: ""

    readonly property string clientId: store.clientId
    readonly property bool hasClientId: store.clientId !== ""
    readonly property bool hasTokens: store.refreshToken !== ""

    // "no-client-id" | "unauthenticated" | "authorizing" | "authenticated"
    readonly property string authState: authorizing ? "authorizing"
        : !hasClientId ? "no-client-id"
        : !hasTokens ? "unauthenticated"
        : "authenticated"

    property string _verifier: ""
    property bool _refreshing: false
    property var _waiters: []

    function begin(newClientId) {
        errorMessage = "";
        if (newClientId !== undefined && newClientId.trim() !== "")
            store.clientId = newClientId.trim();
        if (store.clientId === "") {
            errorMessage = "Paste your Spotify app's Client ID first.";
            return;
        }
        authorizing = true;
        helper.running = true;
    }

    function cancel() {
        helper.running = false;
        authorizing = false;
    }

    // drops the access token so the next withToken() refreshes
    function invalidateAccess() {
        store.accessToken = "";
    }

    function signOut() {
        store.accessToken = "";
        store.refreshToken = "";
        store.expiresAt = 0;
    }

    // cb(token | null, errKind). Proactively refreshes 60s before expiry;
    // concurrent callers queue behind a single refresh request.
    function withToken(cb) {
        if (store.accessToken !== "" && Date.now() < store.expiresAt - 60000) {
            cb(store.accessToken, "");
            return;
        }
        if (store.refreshToken === "") {
            cb(null, "unauthenticated");
            return;
        }
        _waiters.push(cb);
        if (_refreshing)
            return;
        _refreshing = true;
        _tokenRequest({
            grant_type: "refresh_token",
            refresh_token: store.refreshToken,
            client_id: store.clientId
        }, res => {
            _refreshing = false;
            const waiters = _waiters;
            _waiters = [];
            if (res.ok) {
                _storeTokens(res.data);
                for (const w of waiters)
                    w(store.accessToken, "");
            } else {
                // invalid_grant = refresh token revoked → full reauth needed
                if (res.data && res.data.error === "invalid_grant")
                    signOut();
                for (const w of waiters)
                    w(null, res.kind);
            }
        });
    }

    function _storeTokens(data) {
        store.accessToken = data.access_token;
        if (data.refresh_token)
            store.refreshToken = data.refresh_token;
        store.expiresAt = Date.now() + data.expires_in * 1000;
    }

    function _handleHelper(line) {
        let msg;
        try {
            msg = JSON.parse(line);
        } catch (e) {
            return;
        }
        if (msg.event === "ready") {
            _verifier = msg.verifier;
            const url = "https://accounts.spotify.com/authorize"
                + "?client_id=" + encodeURIComponent(store.clientId)
                + "&response_type=code"
                + "&redirect_uri=" + encodeURIComponent(redirectUri)
                + "&code_challenge_method=S256"
                + "&code_challenge=" + msg.challenge
                + "&scope=" + encodeURIComponent(scopes);
            Qt.openUrlExternally(url);
        } else if (msg.event === "code") {
            _tokenRequest({
                grant_type: "authorization_code",
                code: msg.code,
                redirect_uri: redirectUri,
                client_id: store.clientId,
                code_verifier: _verifier
            }, res => {
                authorizing = false;
                if (res.ok) {
                    _storeTokens(res.data);
                } else {
                    errorMessage = _classify(res);
                }
            });
        } else if (msg.event === "error") {
            authorizing = false;
            errorMessage = msg.message;
        }
    }

    function _classify(res) {
        if (res.kind === "network")
            return "Network error talking to accounts.spotify.com — check your connection.";
        const err = res.data ? res.data.error : "";
        const desc = res.data ? (res.data.error_description || "") : "";
        if (err === "invalid_client")
            return "Spotify rejected the Client ID. Double-check it in your app at developer.spotify.com/dashboard.";
        if (desc.toLowerCase().includes("redirect"))
            return "Redirect URI mismatch. Add exactly " + redirectUri + " to your Spotify app's Redirect URIs.";
        return "Token exchange failed: " + (desc || err || ("HTTP " + res.status));
    }

    function _tokenRequest(params, done) {
        const xhr = new XMLHttpRequest();
        const guard = guardComp.createObject(root, { interval: 15000 });
        guard.triggered.connect(() => {
            xhr.abort();
            guard.destroy();
        });
        guard.start();
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            guard.stop();
            guard.destroy();
            let data = null;
            try {
                data = JSON.parse(xhr.responseText);
            } catch (e) {}
            if (xhr.status >= 200 && xhr.status < 300 && data)
                done({ ok: true, status: xhr.status, data: data });
            else if (xhr.status === 0)
                done({ ok: false, status: 0, kind: "network", data: data });
            else
                done({ ok: false, status: xhr.status, kind: "auth", data: data });
        };
        xhr.open("POST", "https://accounts.spotify.com/api/token");
        xhr.setRequestHeader("Content-Type", "application/x-www-form-urlencoded");
        const body = Object.keys(params)
            .map(k => k + "=" + encodeURIComponent(params[k]))
            .join("&");
        xhr.send(body);
    }

    Component {
        id: guardComp
        Timer {}
    }

    Process {
        id: helper
        command: ["python3", Quickshell.shellDir + "/helpers/oauth-helper.py",
            "--port", String(Config.spotify.redirectPort)]

        stdout: SplitParser {
            onRead: line => root._handleHelper(line)
        }
    }

    // tighten permissions every save; also creates the state dir up front
    Process {
        id: chmodProc
        command: ["/bin/sh", "-c",
            "mkdir -p '" + root.stateDir + "' && chmod 700 '" + root.stateDir
            + "' && [ -f '" + root.stateDir + "/auth.json' ] && chmod 600 '"
            + root.stateDir + "/auth.json' || true"]
        running: true
    }

    FileView {
        id: authFile
        path: root.stateDir + "/auth.json"
        onAdapterUpdated: writeAdapter()
        onSaved: {
            // restart, not just start: a no-op if it's still mid-run would
            // leave a fresh token file world-readable
            chmodProc.running = false;
            chmodProc.running = true;
        }
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound)
                writeAdapter();
        }

        adapter: JsonAdapter {
            id: store
            property string clientId: ""
            property string accessToken: ""
            property string refreshToken: ""
            property real expiresAt: 0
        }
    }
}
