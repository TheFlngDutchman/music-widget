import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../services"
import "../components"

// Spotify browse/search UI. Views are plain JS item arrays + an optional
// fetchMore closure; navigation pushes/pops snapshots. A view generation
// counter guards against stale async responses landing after navigation.
Item {
    id: sb

    property string title: "Library"
    property var items: []
    property var fetchMoreFn: null
    property var crumbs: []
    property bool loadingMore: false
    property string flash: ""
    property int viewGen: 0
    property bool initialized: false

    onVisibleChanged: {
        if (visible && !initialized && SpotifyAuth.authState === "authenticated") {
            initialized = true;
            showHome();
        }
    }

    Connections {
        target: SpotifyAuth

        function onAuthStateChanged() {
            if (SpotifyAuth.authState === "authenticated" && sb.visible && !sb.initialized) {
                sb.initialized = true;
                sb.showHome();
            }
        }
    }

    // ---- view plumbing ----

    function setView(newTitle, newItems, newFetchMore) {
        viewGen++;
        title = newTitle;
        items = newItems;
        fetchMoreFn = newFetchMore || null;
        loadingMore = false;
        flash = "";
    }

    function push(newTitle, newItems, newFetchMore) {
        crumbs = crumbs.concat([{ title: title, items: items, fetchMore: fetchMoreFn }]);
        setView(newTitle, newItems, newFetchMore);
    }

    function back() {
        if (crumbs.length === 0)
            return;
        const prev = crumbs[crumbs.length - 1];
        crumbs = crumbs.slice(0, -1);
        setView(prev.title, prev.items, prev.fetchMore);
    }

    function appendRows(gen, rows, nextFetch) {
        if (gen !== viewGen)
            return;
        items = items.filter(r => r.kind !== "loading").concat(rows);
        fetchMoreFn = nextFetch || null;
        loadingMore = false;
    }

    function failRows(gen, message) {
        appendRows(gen, [{ kind: "error", icon: "󰀪", label: message }], null);
    }

    function loadingRow() {
        return { kind: "loading", label: "Loading…" };
    }

    // ---- item mapping ----

    function trackRow(t, ctx, idx, group) {
        return {
            kind: "track", icon: "󰝚", label: t.name,
            sub: (t.artists || []).map(a => a.name).join(", "),
            uri: t.uri, contextUri: ctx || "", index: idx, group: group || null
        };
    }

    // ---- home ----

    function showHome() {
        setView("Library", [
            { kind: "nav", icon: "󰒟", label: "Queue", action: "queue" },
            { kind: "nav", icon: "󰋑", label: "Liked Songs", action: "liked" },
            { kind: "nav", icon: "󰀥", label: "Saved Albums", action: "albums" },
            { kind: "nav", icon: "󰋚", label: "Recently Played", action: "recent" },
            { kind: "header", label: "Your Playlists" },
            loadingRow()
        ], null);
        crumbs = [];
        fetchPlaylists(viewGen, 0);
    }

    function fetchPlaylists(gen, offset) {
        SpotifyApi.get("/me/playlists?limit=50&offset=" + offset, SpotifyApi.ttlLists, res => {
            if (!res.ok) {
                failRows(gen, res.message);
                return;
            }
            const rows = res.data.items.filter(p => p).map(p => ({
                kind: "playlist", icon: "󰲸", label: p.name,
                sub: p.tracks ? p.tracks.total + " tracks" : "", id: p.id, uri: p.uri
            }));
            const next = offset + res.data.items.length;
            appendRows(gen, rows, res.data.next ? (() => fetchPlaylists(viewGen, next)) : null);
        });
    }

    // ---- views ----

    function openPlaylist(item) {
        push(item.label, [loadingRow()], null);
        fetchPlaylistTracks(viewGen, item.id, item.uri, 0);
    }

    function fetchPlaylistTracks(gen, pid, ctx, offset) {
        SpotifyApi.get("/playlists/" + pid + "/tracks?limit=100&offset=" + offset, SpotifyApi.ttlLists, res => {
            if (!res.ok) {
                failRows(gen, res.message);
                return;
            }
            const rows = res.data.items
                .filter(it => it && it.track)
                .map((it, i) => trackRow(it.track, ctx, offset + i));
            const next = offset + res.data.items.length;
            appendRows(gen, rows, res.data.next
                ? (() => fetchPlaylistTracks(viewGen, pid, ctx, next)) : null);
        });
    }

    function openLiked() {
        push("Liked Songs", [loadingRow()], null);
        fetchLiked(viewGen, 0);
    }

    function fetchLiked(gen, offset) {
        SpotifyApi.get("/me/tracks?limit=50&offset=" + offset, SpotifyApi.ttlLiked, res => {
            if (!res.ok) {
                failRows(gen, res.message);
                return;
            }
            // liked songs have no playable context — play as a uris batch
            const rows = res.data.items.filter(it => it && it.track)
                .map(it => trackRow(it.track, "", 0, "liked"));
            const next = offset + res.data.items.length;
            appendRows(gen, rows, res.data.next ? (() => fetchLiked(viewGen, next)) : null);
        });
    }

    function openAlbums() {
        push("Saved Albums", [loadingRow()], null);
        fetchAlbums(viewGen, 0);
    }

    function fetchAlbums(gen, offset) {
        SpotifyApi.get("/me/albums?limit=50&offset=" + offset, SpotifyApi.ttlLists, res => {
            if (!res.ok) {
                failRows(gen, res.message);
                return;
            }
            const rows = res.data.items.filter(it => it && it.album).map(it => ({
                kind: "album", icon: "󰀥", label: it.album.name,
                sub: (it.album.artists || []).map(a => a.name).join(", "),
                id: it.album.id, uri: it.album.uri
            }));
            const next = offset + res.data.items.length;
            appendRows(gen, rows, res.data.next ? (() => fetchAlbums(viewGen, next)) : null);
        });
    }

    function openAlbum(item) {
        push(item.label, [loadingRow()], null);
        const gen = viewGen;
        SpotifyApi.get("/albums/" + item.id + "/tracks?limit=50", SpotifyApi.ttlLists, res => {
            if (!res.ok) {
                failRows(gen, res.message);
                return;
            }
            appendRows(gen, res.data.items.filter(t => t)
                .map((t, i) => trackRow(t, item.uri, i)), null);
        });
    }

    function openRecent() {
        push("Recently Played", [loadingRow()], null);
        fetchRecent(viewGen, "");
    }

    function fetchRecent(gen, before) {
        const q = "/me/player/recently-played?limit=50" + (before ? "&before=" + before : "");
        SpotifyApi.get(q, SpotifyApi.ttlRecent, res => {
            if (!res.ok) {
                failRows(gen, res.message);
                return;
            }
            const rows = res.data.items.filter(it => it && it.track)
                .map(it => trackRow(it.track, "", 0, "recent"));
            const cursor = res.data.cursors ? res.data.cursors.before : "";
            appendRows(gen, rows, (res.data.next && cursor)
                ? (() => fetchRecent(viewGen, cursor)) : null);
        });
    }

    function openQueue() {
        push("Queue", [loadingRow()], null);
        const gen = viewGen;
        SpotifyApi.get("/me/player/queue", SpotifyApi.ttlQueue, res => {
            if (!res.ok) {
                failRows(gen, res.message);
                return;
            }
            let rows = [];
            if (res.data.currently_playing) {
                rows.push({ kind: "header", label: "Now playing" });
                rows.push(trackRow(res.data.currently_playing, "", 0, "queue"));
            }
            const up = (res.data.queue || []).filter(t => t);
            if (up.length > 0) {
                rows.push({ kind: "header", label: "Up next" });
                rows = rows.concat(up.map(t => trackRow(t, "", 0, "queue")));
            }
            if (rows.length === 0)
                rows.push({ kind: "note", label: "Queue is empty" });
            appendRows(gen, rows, null);
        });
    }

    function openArtist(item) {
        push(item.label, [loadingRow()], null);
        const gen = viewGen;
        SpotifyApi.get("/artists/" + item.id + "/top-tracks?market=from_token", SpotifyApi.ttlLists, res => {
            if (!res.ok) {
                failRows(gen, res.message);
                return;
            }
            appendRows(gen, (res.data.tracks || []).filter(t => t)
                .map(t => trackRow(t, "", 0, "artist")), null);
        });
    }

    function searchWeb(q) {
        if (!q || q.trim() === "")
            return;
        push("Search: " + q, [loadingRow()], null);
        const gen = viewGen;
        SpotifyApi.get("/search?q=" + encodeURIComponent(q)
            + "&type=track,album,artist,playlist&limit=20", SpotifyApi.ttlLists, res => {
            if (!res.ok) {
                failRows(gen, res.message);
                return;
            }
            let rows = [];
            const d = res.data;
            const tracks = d.tracks ? d.tracks.items.filter(t => t) : [];
            if (tracks.length > 0) {
                rows.push({ kind: "header", label: "Tracks" });
                rows = rows.concat(tracks.map(t => trackRow(t, "", 0, "search")));
            }
            const artists = d.artists ? d.artists.items.filter(a => a) : [];
            if (artists.length > 0) {
                rows.push({ kind: "header", label: "Artists" });
                rows = rows.concat(artists.map(a => ({
                    kind: "artist", icon: "󰠃", label: a.name, id: a.id, uri: a.uri
                })));
            }
            const albums = d.albums ? d.albums.items.filter(a => a) : [];
            if (albums.length > 0) {
                rows.push({ kind: "header", label: "Albums" });
                rows = rows.concat(albums.map(a => ({
                    kind: "album", icon: "󰀥", label: a.name,
                    sub: (a.artists || []).map(x => x.name).join(", "),
                    id: a.id, uri: a.uri
                })));
            }
            const playlists = d.playlists ? d.playlists.items.filter(p => p) : [];
            if (playlists.length > 0) {
                rows.push({ kind: "header", label: "Playlists" });
                rows = rows.concat(playlists.map(p => ({
                    kind: "playlist", icon: "󰲸", label: p.name,
                    sub: p.owner ? "by " + p.owner.display_name : "",
                    id: p.id, uri: p.uri
                })));
            }
            if (rows.length === 0)
                rows.push({ kind: "note", label: "No results" });
            appendRows(gen, rows, null);
        });
    }

    // ---- playback ----

    function playTrack(item, rowIndex) {
        stopMpdProc.running = true;
        let body;
        if (item.contextUri !== "") {
            body = { context_uri: item.contextUri, offset: { position: item.index } };
        } else if (item.group) {
            // contextless lists (liked/recent/search): play loaded uris from
            // the clicked row onward (API caps uris around 100). The model
            // copies row objects, so locate the row by list index, falling
            // back to the first uri match.
            let start = rowIndex !== undefined && items[rowIndex]?.uri === item.uri
                ? rowIndex
                : items.findIndex(r => r.kind === "track" && r.uri === item.uri);
            const uris = [];
            for (let i = Math.max(0, start); i < items.length && uris.length < 100; i++) {
                if (items[i].kind === "track")
                    uris.push(items[i].uri);
            }
            if (uris.length === 0)
                uris.push(item.uri);
            body = { uris: uris };
        } else {
            body = { uris: [item.uri] };
        }
        flash = "Starting…";
        SpotifyApi.play(body, res => {
            flash = res.ok ? "" : res.message;
        });
    }

    function downloadTrack(item) {
        downloadProcess._step = "mkdir";
        var home = Quickshell.env("HOME");
        downloadProcess._musicDir = home + "/Music";
        downloadProcess._query = item.label + " " + (item.sub || "");
        downloadProcess.command = ["mkdir", "-p", downloadProcess._musicDir];
        downloadProcess.running = true;
        flash = "Downloading: " + item.label + "…";
    }

    Process {
        id: downloadProcess
        property string _step: ""
        property string _musicDir: ""
        property string _query: ""
        onExited: (exitCode, exitStatus) => {
            if (downloadProcess._step === "mkdir") {
                if (exitCode !== 0) {
                    sb.flash = "Failed to create Music directory";
                    flashClear.restart();
                    return;
                }
                downloadProcess._step = "dl";
                // --embed-thumbnail writes the cover into the mp3's ID3 APIC
                // frame (via ffmpeg); convert to jpg first since webp APIC
                // art is mishandled by many players. --embed-metadata tags
                // title/artist/etc.
                downloadProcess.command = ["yt-dlp", "-x", "--audio-format", "mp3",
                                           "--audio-quality", "0", "--no-playlist",
                                           "--embed-thumbnail", "--embed-metadata",
                                           "--convert-thumbnails", "jpg",
                                           "ytsearch1:" + downloadProcess._query,
                                           "-o", downloadProcess._musicDir + "/%(title)s.%(ext)s"];
                downloadProcess.running = true;
            } else {
                sb.flash = exitCode === 0 ? "Download complete" : "Download failed";
                flashClear.restart();
                downloadProcess._step = "";
                downloadProcess._musicDir = "";
                downloadProcess._query = "";
            }
        }
    }

    Process {
        id: stopMpdProc
        command: ["mpc", "-q", "stop"]
        running: false
    }

    function activate(item, rowIndex) {
        if (item.kind === "track")
            playTrack(item, rowIndex);
        else if (item.kind === "playlist")
            openPlaylist(item);
        else if (item.kind === "album")
            openAlbum(item);
        else if (item.kind === "artist")
            openArtist(item);
        else if (item.action === "queue")
            openQueue();
        else if (item.action === "liked")
            openLiked();
        else if (item.action === "albums")
            openAlbums();
        else if (item.action === "recent")
            openRecent();
    }

    // ---- layout ----

    ColumnLayout {
        anchors.fill: parent
        spacing: 4
        visible: SpotifyAuth.authState === "authenticated" && !SpotifyApi.reauthNeeded

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            IconButton {
                text: "󰁍"
                textSize: 12
                visible: sb.crumbs.length > 0
                onClicked: sb.back()
            }

            StyledText {
                Layout.fillWidth: true
                text: sb.title
                font.bold: true
                font.pixelSize: Theme.fontSize - 1
                opacity: 0.6
            }

            StyledText {
                text: SpotifyApi.playbackPhase === "waiting-device" ? "finding device…"
                    : SpotifyApi.playbackPhase === "starting" ? "starting…"
                    : sb.flash
                color: sb.flash && SpotifyApi.playbackPhase === "" ? Theme.error : Theme.fg
                font.pixelSize: Theme.fontSize - 2
                opacity: 0.7
                visible: text.length > 0
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: netLbl.implicitHeight + 8
            radius: 4
            color: Theme.alpha(Theme.error, 0.15)
            visible: SpotifyApi.networkDown

            StyledText {
                id: netLbl
                anchors.centerIn: parent
                text: "󰤭  Network unreachable — showing cached data where possible"
                color: Theme.error
                font.pixelSize: Theme.fontSize - 2
            }
        }

        // spotifyd state strip — only when something needs attention
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: !Spotifyd.serviceActive || !Spotifyd.hasCredentials

            StyledText {
                Layout.fillWidth: true
                text: !Spotifyd.serviceActive
                    ? "spotifyd (this device's player) is not running"
                    : "spotifyd needs a one-time authentication"
                color: Theme.error
                font.pixelSize: Theme.fontSize - 2
                opacity: 0.85
            }

            Rectangle {
                implicitWidth: fixLbl.implicitWidth + 20
                implicitHeight: fixLbl.implicitHeight + 6
                radius: 4
                color: fixMouse.containsMouse ? Theme.accent : Theme.accentBg

                Text {
                    id: fixLbl
                    anchors.centerIn: parent
                    text: !Spotifyd.serviceActive ? "Start"
                        : Spotifyd.authenticating ? "Waiting…" : "Authenticate"
                    color: Theme.accentFg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 2
                    font.bold: true
                }

                MouseArea {
                    id: fixMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (!Spotifyd.serviceActive)
                            Spotifyd.startService();
                        else if (!Spotifyd.authenticating)
                            Spotifyd.authenticate();
                    }
                }
            }
        }

        BrowserListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            model: sb.items
            canLoadMore: sb.fetchMoreFn !== null && !sb.loadingMore
            onActivated: (item, index) => sb.activate(item, index)
            onQueueRequested: item => {
                SpotifyApi.addToQueue(item.uri, res => {
                    sb.flash = res.ok ? "Added to queue" : res.message;
                    if (res.ok)
                        flashClear.restart();
                });
            }
            onDownloadRequested: item => sb.downloadTrack(item)
            onLoadMore: {
                if (sb.fetchMoreFn && !sb.loadingMore) {
                    sb.loadingMore = true;
                    sb.fetchMoreFn();
                }
            }
        }
    }

    Timer {
        id: flashClear
        interval: 2000
        onTriggered: sb.flash = ""
    }

    AuthOnboarding {
        anchors.fill: parent
        visible: SpotifyAuth.authState !== "authenticated"
    }

    // refresh token revoked mid-session: one-click recovery
    ColumnLayout {
        anchors.centerIn: parent
        spacing: 8
        visible: SpotifyAuth.authState === "authenticated" && SpotifyApi.reauthNeeded

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: "Spotify session expired"
            opacity: 0.7
        }

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: reauthLbl.implicitWidth + 28
            implicitHeight: reauthLbl.implicitHeight + 10
            radius: 4
            color: reauthMouse.containsMouse ? Theme.accent : Theme.accentBg

            Text {
                id: reauthLbl
                anchors.centerIn: parent
                text: "Reconnect"
                color: Theme.accentFg
                font.family: Theme.fontFamily
                font.bold: true
                font.pixelSize: Theme.fontSize - 1
            }

            MouseArea {
                id: reauthMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    SpotifyApi.reauthNeeded = false;
                    SpotifyAuth.begin();
                }
            }
        }
    }
}
