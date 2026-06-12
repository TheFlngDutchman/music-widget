pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Mpris

// Event-driven playback state. Mpris.players updates via D-Bus signals, so
// there is no polling: metadata/state changes propagate instantly. The only
// timer is the position ticker, since MprisPlayer.position is interpolated
// on read but not reactive — and it runs only while something is visible
// and playing (gated via trackPosition).
Singleton {
    id: root

    // bumped on any player's state change to re-evaluate the active pick
    property int rev: 0

    readonly property MprisPlayer active: {
        rev;
        const players = Mpris.players.values;
        let best = null;
        let bestScore = -1;
        for (let i = 0; i < players.length; i++) {
            const s = score(players[i]);
            if (s > bestScore) {
                best = players[i];
                bestScore = s;
            }
        }
        return best;
    }

    readonly property bool hasPlayer: active !== null
    readonly property string title: active?.trackTitle || ""
    readonly property string artist: active?.trackArtist || ""
    readonly property string album: active?.trackAlbum || ""
    readonly property string artUrl: active?.trackArtUrl || ""
    readonly property bool isPlaying: active?.isPlaying ?? false
    readonly property real length: active?.length ?? 0
    // capability props reference rev: when a player appears mid-session,
    // quickshell sets canSeek/positionSupported without emitting their
    // change signals, so plain bindings go stale. Direct reads are always
    // correct — re-evaluating on any rev bump picks up the real value.
    readonly property bool canSeek: {
        rev;
        return (active?.canSeek ?? false) && (active?.positionSupported ?? false);
    }
    readonly property bool volumeSupported: {
        rev;
        return active?.volumeSupported ?? false;
    }
    readonly property real volume: active?.volume ?? 0

    // set true by UI while a position-consuming page is visible
    property bool trackPosition: false

    function score(p) {
        let s = 0;
        const id = ((p.identity || "") + " " + (p.dbusName || "")).toLowerCase();
        if (id.includes("spotifyd"))
            s += 30;
        else if (id.includes("spotify"))
            s += 20;
        else if (id.includes("mpd"))
            s += 10;
        if (p.isPlaying)
            s += 100;
        return s;
    }

    function togglePlaying() {
        if (active && active.canTogglePlaying)
            active.togglePlaying();
    }

    function next() {
        if (active && active.canGoNext)
            active.next();
    }

    function previous() {
        if (active && active.canGoPrevious)
            active.previous();
    }

    function setPosition(secs) {
        if (active && root.canSeek)
            active.position = secs;
    }

    function setVolume(v) {
        if (active && active.volumeSupported)
            active.volume = Math.max(0, Math.min(1, v));
    }

    function toggleShuffle() {
        if (active && active.shuffleSupported)
            active.shuffle = !active.shuffle;
    }

    function cycleLoop() {
        if (!active || !active.loopSupported)
            return;
        if (active.loopState === MprisLoopState.None)
            active.loopState = MprisLoopState.Playlist;
        else if (active.loopState === MprisLoopState.Playlist)
            active.loopState = MprisLoopState.Track;
        else
            active.loopState = MprisLoopState.None;
    }

    Instantiator {
        model: Mpris.players
        delegate: Connections {
            required property MprisPlayer modelData
            target: modelData

            function onPlaybackStateChanged() {
                root.rev++;
            }

            // fires once track info loads on a fresh player — re-checks the
            // capability props above, whose own change signals never arrive
            function onMetadataChanged() {
                root.rev++;
            }
        }
        onObjectAdded: root.rev++
        onObjectRemoved: root.rev++
    }

    Timer {
        interval: 500
        repeat: true
        running: root.trackPosition && root.isPlaying && root.canSeek
        onTriggered: root.active.positionChanged()
    }

    // spotifyd flips CanSeek/Volume true a few seconds after its MPRIS
    // object appears — after every rev bump above, still with no change
    // signal. Nudge rev until the caps converge (or give up: the player
    // genuinely doesn't support them).
    property int _capRetries: 0
    onActiveChanged: _capRetries = 0

    Timer {
        interval: 1000
        repeat: true
        running: root.hasPlayer && root._capRetries < 15
            && (!root.canSeek || !root.volumeSupported)
        onTriggered: {
            root._capRetries++;
            root.rev++;
        }
    }
}
