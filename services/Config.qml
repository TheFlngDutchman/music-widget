pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Live-reloading config at ~/.config/music-widget/config.json.
// External edits apply instantly (watchChanges); the settings UI writes
// through the adapter properties, persisted with a short debounce.
Singleton {
    id: root

    readonly property string configDir: Quickshell.env("HOME") + "/.config/music-widget"

    readonly property alias window: adapter.window
    readonly property alias font: adapter.font
    readonly property alias controls: adapter.controls
    readonly property alias colors: adapter.colors
    readonly property alias visualizer: adapter.visualizer
    readonly property alias spotify: adapter.spotify

    function save() {
        saveTimer.restart();
    }

    Timer {
        id: saveTimer
        interval: 400
        onTriggered: file.writeAdapter()
    }

    FileView {
        id: file
        path: root.configDir + "/config.json"
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: root.save()
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound)
                writeAdapter();
        }

        adapter: JsonAdapter {
            id: adapter

            property JsonObject window: JsonObject {
                // top-left | top | top-right | bottom-left | bottom | bottom-right
                // | floating (free position via marginTop/marginLeft, draggable)
                property string anchor: "top-right"
                // output name (e.g. "DP-1"); empty = compositor default
                property string monitor: ""
                property int width: 560
                property int height: 320
                property int marginTop: 4
                property int marginRight: 4
                property int marginBottom: 0
                property int marginLeft: 0
            }

            property JsonObject font: JsonObject {
                property string family: "JetBrainsMono Nerd Font"
                property int size: 12
            }

            property JsonObject controls: JsonObject {
                property int artSize: 96
            }

            property JsonObject colors: JsonObject {
                // empty = follow omarchy theme
                property string accent: ""
                property string background: ""
                property string foreground: ""
                property string teal: ""
            }

            property JsonObject visualizer: JsonObject {
                property string style: "bars"
                property int bars: 32
                property int sensitivity: 100
                property string channels: "mono"
                property real smoothing: 0.65
                property bool peakHold: true
            }

            property JsonObject spotify: JsonObject {
                property int redirectPort: 19872
            }
        }
    }
}
