import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../services"
import "components"
import "controls"
import "visualizer"
import "browser"
import "settings"

PanelWindow {
    id: win

    readonly property string anchorCfg: Config.window.anchor
    // floating pins top-left and uses the top/left margins as a free
    // position; the header becomes a drag handle
    readonly property bool floating: anchorCfg === "floating"
    property int currentTab: 0 // 0 controls, 1 visualizer, 2 playlists, 3 settings

    anchors {
        top: win.floating || win.anchorCfg.indexOf("top") !== -1
        bottom: !win.floating && win.anchorCfg.indexOf("bottom") !== -1
        left: win.floating || win.anchorCfg.indexOf("left") !== -1
        right: !win.floating && win.anchorCfg.indexOf("right") !== -1
    }

    margins {
        top: win.floating ? Config.window.floatY : Config.window.marginTop
        right: win.floating ? 0 : Config.window.marginRight
        bottom: win.floating ? 0 : Config.window.marginBottom
        left: win.floating ? Config.window.floatX : Config.window.marginLeft
    }

    screen: {
        const name = Config.window.monitor;
        if (name) {
            for (let i = 0; i < Quickshell.screens.length; i++) {
                if (Quickshell.screens[i].name === name)
                    return Quickshell.screens[i];
            }
        }
        return null;
    }

    implicitWidth: Config.window.width
    implicitHeight: Config.window.height
    // start hidden: the service launches at login, the bar button reveals it
    visible: false
    color: "transparent"
    // reserve nothing, but respect other zones (waybar) — margins measure
    // from the bar's edge, not the screen edge
    exclusiveZone: 0

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "music-widget"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    onVisibleChanged: {
        if (visible)
            Spotifyd.refreshState();
    }

    Rectangle {
        anchors.fill: parent
        radius: 6
        color: Theme.bg
        border.color: Theme.border
        border.width: 1

        // drag-to-move via the header strip in floating mode. Sits below
        // the ColumnLayout, so the header buttons still get their clicks.
        // Position tracking uses the global cursor (hyprctl cursorpos):
        // window-relative coordinates lag the asynchronous surface moves
        // and feed back into the delta, causing runaway oscillation.
        MouseArea {
            id: dragArea

            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 34
            enabled: win.floating
            cursorShape: win.floating ? Qt.SizeAllCursor : Qt.ArrowCursor

            property bool haveBase: false
            property int baseX: 0
            property int baseY: 0
            property int basePosX: 0
            property int basePosY: 0

            onPressedChanged: {
                haveBase = false;
                if (pressed) {
                    basePosX = Config.window.floatX;
                    basePosY = Config.window.floatY;
                }
            }
        }

        Timer {
            interval: 33
            repeat: true
            triggeredOnStart: true
            running: dragArea.pressed
            onTriggered: {
                if (!cursorProc.running)
                    cursorProc.running = true;
            }
        }

        Process {
            id: cursorProc
            command: ["hyprctl", "cursorpos"]

            stdout: SplitParser {
                onRead: line => {
                    const m = line.match(/(-?\d+),\s*(-?\d+)/);
                    if (!m || !dragArea.pressed)
                        return;
                    const x = parseInt(m[1]);
                    const y = parseInt(m[2]);
                    if (!dragArea.haveBase) {
                        dragArea.baseX = x;
                        dragArea.baseY = y;
                        dragArea.haveBase = true;
                        return;
                    }
                    Config.window.floatX = Math.max(0,
                        dragArea.basePosX + (x - dragArea.baseX));
                    Config.window.floatY = Math.max(0,
                        dragArea.basePosY + (y - dragArea.baseY));
                }
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 4

            RowLayout {
                Layout.fillWidth: true
                spacing: 0

                Text {
                    text: "󰝚  MUSIC"
                    color: Theme.fg
                    opacity: 0.5
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    font.bold: true
                    font.letterSpacing: 3
                }

                Item { Layout.fillWidth: true }

                IconButton {
                    text: "󰒓"
                    textColor: win.currentTab === 3 ? Theme.accent : Theme.fg
                    dimmed: win.currentTab === 3 ? 1.0 : 0.4
                    onClicked: win.currentTab = win.currentTab === 3 ? 0 : 3
                }

                IconButton {
                    text: "󰅖"
                    textSize: 12
                    onClicked: win.visible = false
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 14

                PageTab {
                    text: "󰐎  Controls"
                    active: win.currentTab === 0
                    onClicked: win.currentTab = 0
                }
                PageTab {
                    text: "󰺢  Visualizer"
                    active: win.currentTab === 1
                    onClicked: win.currentTab = 1
                }
                PageTab {
                    text: "󰲸  Playlists"
                    active: win.currentTab === 2
                    onClicked: win.currentTab = 2
                }
                Item { Layout.fillWidth: true }
            }

            StackLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: win.currentTab

                ControlsPage {
                    pageActive: win.visible && win.currentTab === 0
                }
                VisualizerPage {
                    pageActive: win.visible && win.currentTab === 1
                }
                PlaylistsPage {}
                SettingsPage {}
            }
        }
    }
}
