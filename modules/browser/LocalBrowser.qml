import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "../../services"
import "../components"

// MPD library browser via mpc. Directory listing with breadcrumb descent;
// clicking a file replaces the MPD queue with that directory's contents
// and plays from the clicked entry.
Item {
    id: lb

    property string path: ""
    property var crumbs: []
    property var entries: []   // {name, full, isDir}
    property var shown: []
    property string filterText: ""
    property bool mpdUp: true
    property bool loading: false

    readonly property var audioExts: ["mp3", "flac", "ogg", "opus", "m4a", "wav", "aac", "wma", "aiff", "ape"]

    function filter(q) {
        filterText = q.toLowerCase();
        applyFilter();
    }

    function applyFilter() {
        shown = filterText === ""
            ? entries
            : entries.filter(e => e.name.toLowerCase().includes(filterText));
    }

    function isAudio(name) {
        const dot = name.lastIndexOf(".");
        return dot >= 0 && audioExts.includes(name.slice(dot + 1).toLowerCase());
    }

    function load(newPath) {
        path = newPath;
        loading = true;
        entries = [];
        shown = [];
        lsProc.buf = [];
        lsProc.command = newPath === "" ? ["mpc", "ls"] : ["mpc", "ls", newPath];
        lsProc.running = true;
    }

    function descend(entry) {
        crumbs = crumbs.concat([path]);
        load(entry.full);
    }

    function back() {
        if (crumbs.length === 0)
            return;
        const prev = crumbs[crumbs.length - 1];
        crumbs = crumbs.slice(0, -1);
        load(prev);
    }

    function play(entry) {
        playProc.command = ["/bin/sh", "-c",
            "playerctl -p spotifyd stop 2>/dev/null; mpc -q clear"
            + " && mpc -q add " + _shq(path === "" ? "/" : path)
            + " && pos=$(mpc playlist -f '%file%' | grep -nxF " + _shq(entry.full)
            + " | head -1 | cut -d: -f1) && mpc -q play \"${pos:-1}\""];
        playProc.running = true;
    }

    function _shq(s) {
        return "'" + s.replace(/'/g, "'\\''") + "'";
    }

    function startMpd() {
        mpdStart.running = true;
    }

    onVisibleChanged: {
        if (visible)
            load(path);
    }

    Process {
        id: lsProc
        property var buf: []

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                const line = data.trim();
                if (line !== "")
                    lsProc.buf.push(line);
            }
        }

        onExited: (code, status) => {
            lb.loading = false;
            if (code !== 0) {
                lb.mpdUp = false;
                return;
            }
            lb.mpdUp = true;
            lb.entries = lsProc.buf.map(full => {
                const name = full.split("/").pop();
                return { name: name, full: full, isDir: !lb.isAudio(name) };
            });
            lb.applyFilter();
        }
    }

    Process {
        id: playProc
    }

    Process {
        id: mpdStart
        command: ["systemctl", "--user", "start", "mpd"]
        onExited: retryTimer.start()
    }

    Timer {
        id: retryTimer
        interval: 1800
        onTriggered: lb.load(lb.path)
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 4
        visible: lb.mpdUp

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            IconButton {
                text: "󰁍"
                textSize: 12
                visible: lb.crumbs.length > 0
                onClicked: lb.back()
            }

            StyledText {
                Layout.fillWidth: true
                text: lb.path === "" ? "Library" : lb.path
                font.bold: true
                font.pixelSize: Theme.fontSize - 1
                opacity: 0.6
            }

            IconButton {
                text: "󰑓"
                textSize: 12
                onClicked: lb.load(lb.path)
            }
        }

        BrowserListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            showQueueButton: false
            model: lb.loading
                ? [{ kind: "loading", label: "Loading…" }]
                : (lb.shown.length === 0
                    ? [{ kind: "note", label: lb.filterText !== "" ? "No matches" : "Empty directory" }]
                    : lb.shown.map(e => ({
                        kind: "nav",
                        icon: e.isDir ? "󰉋" : "󰝚",
                        label: e.name,
                        entry: e
                    })))
            onActivated: item => {
                if (!item.entry)
                    return;
                if (item.entry.isDir)
                    lb.descend(item.entry);
                else
                    lb.play(item.entry);
            }
        }
    }

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 8
        visible: !lb.mpdUp

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: "MPD is not running"
            opacity: 0.6
        }

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: startLbl.implicitWidth + 28
            implicitHeight: startLbl.implicitHeight + 10
            radius: 4
            color: startMouse.containsMouse ? Theme.accent : Theme.accentBg

            Text {
                id: startLbl
                anchors.centerIn: parent
                text: "Start MPD"
                color: Theme.accentFg
                font.family: Theme.fontFamily
                font.bold: true
                font.pixelSize: Theme.fontSize - 1
            }

            MouseArea {
                id: startMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: lb.startMpd()
            }
        }
    }
}
