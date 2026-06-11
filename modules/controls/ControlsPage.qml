import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Mpris
import "../../services"
import "../components"

Item {
    id: page

    property bool pageActive: false

    // keep the position ticker alive only while this page is on screen
    Binding {
        target: Players
        property: "trackPosition"
        value: page.pageActive
    }

    function fmtTime(secs) {
        if (!isFinite(secs) || secs < 0)
            secs = 0;
        const m = Math.floor(secs / 60);
        const s = Math.floor(secs % 60);
        return m + ":" + (s < 10 ? "0" : "") + s;
    }

    readonly property real position: {
        Players.active?.position; // re-evaluated via positionChanged ticker
        return Players.active?.position ?? 0;
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: 8
        spacing: 10
        visible: Players.hasPlayer

        RowLayout {
            Layout.fillWidth: true
            spacing: 16

            // album art with placeholder note (port of .mw-art / .mw-art-ph)
            Rectangle {
                Layout.preferredWidth: Config.controls.artSize
                Layout.preferredHeight: Config.controls.artSize
                radius: 6
                color: Theme.alpha(Theme.fg, 0.05)
                clip: true

                Text {
                    anchors.centerIn: parent
                    text: "󰝚"
                    color: Theme.fg
                    opacity: 0.18
                    font.family: Theme.fontFamily
                    font.pixelSize: 38
                    visible: art.status !== Image.Ready
                }

                Image {
                    id: art
                    anchors.fill: parent
                    source: Players.artUrl
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    visible: status === Image.Ready
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 3

                StyledText {
                    Layout.fillWidth: true
                    text: Players.title || "Not playing"
                    font.pixelSize: Theme.fontSize + 1
                    font.bold: true
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Players.artist
                    font.pixelSize: Theme.fontSize - 1
                    opacity: 0.6
                    visible: text.length > 0
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Players.album
                    font.pixelSize: Theme.fontSize - 2
                    opacity: 0.35
                    visible: text.length > 0 && text !== Players.title
                }
            }
        }

        Item { Layout.fillHeight: true }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            StyledText {
                text: page.fmtTime(page.position)
                font.pixelSize: Theme.fontSize - 2
                opacity: 0.4
            }

            MwSlider {
                id: seek
                Layout.fillWidth: true
                enabled: Players.canSeek && Players.length > 0
                value: Players.length > 0 ? page.position / Players.length : 0
                fillColor: Theme.accentBg
                onReleased: v => Players.setPosition(v * Players.length)
            }

            StyledText {
                text: page.fmtTime(Players.length)
                font.pixelSize: Theme.fontSize - 2
                opacity: 0.4
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 6

            IconButton {
                text: "󰒝"
                textSize: 14
                textColor: Players.active?.shuffle ? Theme.accent : Theme.fg
                dimmed: Players.active?.shuffle ? 1.0 : 0.4
                visible: Players.active?.shuffleSupported ?? false
                onClicked: Players.toggleShuffle()
            }

            IconButton {
                text: "󰒮"
                textSize: 18
                dimmed: 0.8
                onClicked: Players.previous()
            }

            IconButton {
                text: Players.isPlaying ? "󰏤" : "󰐊"
                textSize: 22
                dimmed: 1.0
                onClicked: Players.togglePlaying()
            }

            IconButton {
                text: "󰒭"
                textSize: 18
                dimmed: 0.8
                onClicked: Players.next()
            }

            IconButton {
                text: Players.active?.loopState === MprisLoopState.Track ? "󰑘" : "󰑖"
                textSize: 14
                textColor: (Players.active?.loopState ?? MprisLoopState.None) !== MprisLoopState.None
                    ? Theme.accent : Theme.fg
                dimmed: (Players.active?.loopState ?? MprisLoopState.None) !== MprisLoopState.None ? 1.0 : 0.4
                visible: Players.active?.loopSupported ?? false
                onClicked: Players.cycleLoop()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: 4
            spacing: 10
            visible: Players.volumeSupported

            StyledText {
                text: "󰕾"
                font.pixelSize: Theme.fontSize + 1
                opacity: 0.5
            }

            MwSlider {
                Layout.fillWidth: true
                handleSize: 8
                value: Players.volume
                onMoved: v => volDebounce.request(v)
            }
        }
    }

    // debounce volume writes while dragging (port of the 80ms GTK debounce)
    Timer {
        id: volDebounce
        interval: 80
        property real pending: 0

        function request(v) {
            pending = v;
            restart();
        }

        onTriggered: Players.setVolume(pending)
    }

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 6
        visible: !Players.hasPlayer

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: "Not playing"
            opacity: 0.5
        }

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: "Start playback in any player, or play something from the Playlists tab"
            font.pixelSize: Theme.fontSize - 2
            opacity: 0.3
        }
    }
}
