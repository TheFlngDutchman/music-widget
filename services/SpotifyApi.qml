pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Spotify Web API client: response cache with per-endpoint TTLs, in-flight
// dedupe, timeout guard, and error classification. Results are
// {ok, status, data, kind, message} where kind ∈
// "" | "network" | "auth" | "rate-limited" | "premium" | "no-device" | "api".
Singleton {
    id: root

    readonly property string base: "https://api.spotify.com/v1"

    // surfaced to the UI
    property bool networkDown: false
    property bool reauthNeeded: false
    // "" | "waiting-device" | "starting"
    property string playbackPhase: ""

    property var _cache: ({})
    property var _inflight: ({})

    // ---- TTLs (ms) ----
    readonly property int ttlLists: 5 * 60000
    readonly property int ttlLiked: 2 * 60000
    readonly property int ttlRecent: 60000
    readonly property int ttlQueue: 15000
    readonly property int ttlDevices: 10000

    function get(path, ttl, cb) {
        request("GET", path, { ttl: ttl }, cb);
    }

    function request(method, path, opts, cb) {
        opts = opts || {};
        const key = method + " " + path;
        const cacheable = method === "GET" && (opts.ttl || 0) > 0;
        if (cacheable) {
            const hit = _cache[key];
            if (hit && Date.now() - hit.at < hit.ttl) {
                cb({ ok: true, status: 200, data: hit.data, kind: "", cached: true });
                return;
            }
        }
        if (method === "GET") {
            if (_inflight[key]) {
                _inflight[key].push(cb);
                return;
            }
            _inflight[key] = [cb];
        }
        _do(method, path, opts, 0, method === "GET"
            ? res => {
                const cbs = _inflight[key] || [];
                delete _inflight[key];
                for (const c of cbs)
                    c(res);
            }
            : cb, key, cacheable);
    }

    function invalidate(prefix) {
        for (const k in _cache) {
            if (k.includes(prefix))
                delete _cache[k];
        }
    }

    function _do(method, path, opts, attempt, finish, key, cacheable) {
        SpotifyAuth.withToken((token, errKind) => {
            if (!token) {
                if (errKind === "unauthenticated" || errKind === "auth")
                    reauthNeeded = true;
                finish({ ok: false, status: 0, data: null, kind: errKind || "auth",
                         message: "Not authenticated" });
                return;
            }
            reauthNeeded = false;
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

                if (xhr.status >= 200 && xhr.status < 300) {
                    networkDown = false;
                    if (cacheable)
                        _cache[key] = { at: Date.now(), ttl: opts.ttl, data: data };
                    finish({ ok: true, status: xhr.status, data: data, kind: "" });
                    return;
                }
                if (xhr.status === 0) {
                    networkDown = true;
                    finish({ ok: false, status: 0, data: null, kind: "network",
                             message: "Network error — Spotify unreachable" });
                    return;
                }
                if (xhr.status === 401 && attempt === 0) {
                    // expired mid-flight: drop the token so the retry refreshes
                    SpotifyAuth.invalidateAccess();
                    _do(method, path, opts, 1, finish, key, cacheable);
                    return;
                }
                if (xhr.status === 401) {
                    reauthNeeded = true;
                    finish({ ok: false, status: 401, data: data, kind: "auth",
                             message: "Session expired — reconnect Spotify" });
                    return;
                }
                if (xhr.status === 429 && attempt < 2) {
                    const wait = (parseInt(xhr.getResponseHeader("Retry-After"), 10) || 1) * 1000;
                    _retryLater(wait, () => _do(method, path, opts, attempt + 1, finish, key, cacheable));
                    return;
                }
                const reason = data && data.error ? (data.error.reason || "") : "";
                const msg = data && data.error ? (data.error.message || "") : "";
                if (xhr.status === 403 && (reason === "PREMIUM_REQUIRED" || msg.toLowerCase().includes("premium"))) {
                    finish({ ok: false, status: 403, data: data, kind: "premium",
                             message: "Spotify Premium is required for playback control" });
                    return;
                }
                if (xhr.status === 404 && reason === "NO_ACTIVE_DEVICE") {
                    finish({ ok: false, status: 404, data: data, kind: "no-device",
                             message: "No active Spotify device" });
                    return;
                }
                finish({ ok: false, status: xhr.status, data: data, kind: "api",
                         message: msg || ("Spotify API error (HTTP " + xhr.status + ")") });
            };
            xhr.open(method, base + path);
            xhr.setRequestHeader("Authorization", "Bearer " + token);
            if (opts.body) {
                xhr.setRequestHeader("Content-Type", "application/json");
                xhr.send(JSON.stringify(opts.body));
            } else {
                xhr.send();
            }
        });
    }

    function _retryLater(ms, fn) {
        const t = guardComp.createObject(root, { interval: ms });
        t.triggered.connect(() => {
            t.destroy();
            fn();
        });
        t.start();
    }

    Component {
        id: guardComp
        Timer {}
    }

    // ---- playback orchestration ----

    // body: {context_uri, offset} or {uris, offset}. Finds a target device
    // (active one, else spotifyd by name), retrying device discovery for up
    // to 10s with visible progress instead of the old blind 30s busy-wait.
    function play(body, cb) {
        playbackPhase = "waiting-device";
        _findDevice(0, deviceId => {
            if (!deviceId) {
                playbackPhase = "";
                cb({ ok: false, kind: "no-device",
                     message: "No Spotify device found. Is spotifyd running? (systemctl --user status spotifyd)" });
                return;
            }
            playbackPhase = "starting";
            request("PUT", "/me/player/play?device_id=" + deviceId, { body: body }, res => {
                playbackPhase = "";
                if (res.ok)
                    invalidate("/me/player");
                cb(res);
            });
        });
    }

    function _findDevice(attempt, cb) {
        // bypass cache while actively waiting for spotifyd to register
        get("/me/player/devices", attempt === 0 ? ttlDevices : 0, res => {
            if (res.ok && res.data && res.data.devices) {
                const devs = res.data.devices;
                let pick = devs.find(d => d.is_active)
                    || devs.find(d => d.name === Spotifyd.deviceName)
                    || devs[0];
                if (pick) {
                    cb(pick.id);
                    return;
                }
            }
            if (attempt >= 10) {
                cb(null);
                return;
            }
            _retryLater(1000, () => _findDevice(attempt + 1, cb));
        });
    }

    function addToQueue(uri, cb) {
        request("POST", "/me/player/queue?uri=" + encodeURIComponent(uri), {}, res => {
            if (res.ok)
                invalidate("/me/player/queue");
            cb(res);
        });
    }
}
