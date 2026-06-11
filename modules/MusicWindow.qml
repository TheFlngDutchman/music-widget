import QtQuick
import QtQuick.Layouts
import Quickshell
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
    property int currentTab: 0 // 0 controls, 1 visualizer, 2 playlists, 3 settings

    anchors {
        top: win.anchorCfg.indexOf("top") !== -1
        bottom: win.anchorCfg.indexOf("bottom") !== -1
        left: win.anchorCfg.indexOf("left") !== -1
        right: win.anchorCfg.indexOf("right") !== -1
    }

    margins {
        top: Config.window.marginTop
        right: Config.window.marginRight
        bottom: Config.window.marginBottom
        left: Config.window.marginLeft
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
    color: "transparent"
    // reserve nothing, but respect other zones (waybar) — margins measure
    // from the bar's edge, not the screen edge
    exclusiveZone: 0

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "music-widget"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    Rectangle {
        anchors.fill: parent
        radius: 6
        color: Theme.bg
        border.color: Theme.border
        border.width: 1

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
