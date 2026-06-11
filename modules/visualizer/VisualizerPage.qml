import QtQuick
import QtQuick.Layouts
import "../../services"
import "../components"
import "styles.js" as Styles

Item {
    id: page

    // true only while the window is visible and this tab is selected;
    // gates the cava process so it costs nothing when hidden.
    property bool pageActive: false
    property bool settingsOpen: false

    Binding {
        target: Cava
        property: "active"
        value: page.pageActive
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 6

        RowLayout {
            Layout.fillWidth: true

            StyledText {
                Layout.fillWidth: true
                text: Players.hasPlayer && Players.title
                    ? Players.title + (Players.artist ? "  —  " + Players.artist : "")
                    : "Nothing playing"
                font.pixelSize: Theme.fontSize - 1
                font.italic: true
                opacity: 0.55
            }

            IconButton {
                text: "󰢻"
                textColor: page.settingsOpen ? Theme.accent : Theme.fg
                dimmed: page.settingsOpen ? 1.0 : 0.5
                onClicked: page.settingsOpen = !page.settingsOpen
            }
        }

        VisualizerCanvas {
            Layout.fillWidth: true
            Layout.fillHeight: true
        }
    }

    // gear settings overlay (port of the GTK popover)
    Rectangle {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 30
        width: 320
        visible: page.settingsOpen
        color: Theme.bg
        border.color: Theme.border
        border.width: 1
        radius: 6
        height: settingsCol.implicitHeight + 24

        ColumnLayout {
            id: settingsCol
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                StyledText {
                    text: "Style"
                    font.pixelSize: Theme.fontSize - 1
                    opacity: 0.7
                    Layout.preferredWidth: 80
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 2

                    Repeater {
                        model: Styles.STYLE_NAMES

                        Rectangle {
                            required property string modelData
                            readonly property bool current: Config.visualizer.style === modelData

                            width: styleLbl.implicitWidth + 14
                            height: styleLbl.implicitHeight + 6
                            radius: 3
                            color: current ? Theme.alpha(Theme.fg, 0.07) : "transparent"

                            Text {
                                id: styleLbl
                                anchors.centerIn: parent
                                text: parent.modelData
                                color: parent.current ? Theme.accent : Theme.fg
                                opacity: parent.current ? 1.0 : 0.38
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 2
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Config.visualizer.style = parent.modelData
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                StyledText {
                    text: "Bars"
                    font.pixelSize: Theme.fontSize - 1
                    opacity: 0.7
                    Layout.preferredWidth: 80
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 2

                    Repeater {
                        model: [8, 16, 32, 64, 96]

                        Rectangle {
                            required property int modelData
                            readonly property bool current: Config.visualizer.bars === modelData

                            width: barsLbl.implicitWidth + 14
                            height: barsLbl.implicitHeight + 6
                            radius: 3
                            color: current ? Theme.alpha(Theme.fg, 0.07) : "transparent"

                            Text {
                                id: barsLbl
                                anchors.centerIn: parent
                                text: parent.modelData
                                color: parent.current ? Theme.accent : Theme.fg
                                opacity: parent.current ? 1.0 : 0.38
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 2
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Config.visualizer.bars = parent.modelData
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                StyledText {
                    text: "Sensitivity"
                    font.pixelSize: Theme.fontSize - 1
                    opacity: 0.7
                    Layout.preferredWidth: 80
                }

                MwSlider {
                    Layout.fillWidth: true
                    handleSize: 8
                    value: (Config.visualizer.sensitivity - 10) / 490
                    onReleased: v => Config.visualizer.sensitivity = Math.round(10 + v * 490)
                }

                StyledText {
                    text: Config.visualizer.sensitivity
                    font.pixelSize: Theme.fontSize - 2
                    opacity: 0.5
                    Layout.preferredWidth: 28
                    horizontalAlignment: Text.AlignRight
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                StyledText {
                    text: "Smoothing"
                    font.pixelSize: Theme.fontSize - 1
                    opacity: 0.7
                    Layout.preferredWidth: 80
                }

                MwSlider {
                    Layout.fillWidth: true
                    handleSize: 8
                    value: Config.visualizer.smoothing / 0.9
                    onReleased: v => Config.visualizer.smoothing = Math.round(v * 90) / 100
                }

                StyledText {
                    text: Config.visualizer.smoothing.toFixed(2)
                    font.pixelSize: Theme.fontSize - 2
                    opacity: 0.5
                    Layout.preferredWidth: 28
                    horizontalAlignment: Text.AlignRight
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                StyledText {
                    text: "Channels"
                    font.pixelSize: Theme.fontSize - 1
                    opacity: 0.7
                    Layout.preferredWidth: 80
                }

                Repeater {
                    model: ["mono", "stereo"]

                    Rectangle {
                        required property string modelData
                        readonly property bool current: Config.visualizer.channels === modelData

                        width: chLbl.implicitWidth + 14
                        height: chLbl.implicitHeight + 6
                        radius: 3
                        color: current ? Theme.alpha(Theme.fg, 0.07) : "transparent"

                        Text {
                            id: chLbl
                            anchors.centerIn: parent
                            text: parent.modelData
                            color: parent.current ? Theme.accent : Theme.fg
                            opacity: parent.current ? 1.0 : 0.38
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 2
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Config.visualizer.channels = parent.modelData
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                StyledText {
                    text: "Peaks"
                    font.pixelSize: Theme.fontSize - 1
                    opacity: 0.7
                }

                Rectangle {
                    readonly property bool on: Config.visualizer.peakHold

                    width: pkLbl.implicitWidth + 14
                    height: pkLbl.implicitHeight + 6
                    radius: 3
                    color: on ? Theme.alpha(Theme.fg, 0.07) : "transparent"

                    Text {
                        id: pkLbl
                        anchors.centerIn: parent
                        text: parent.on ? "on" : "off"
                        color: parent.on ? Theme.accent : Theme.fg
                        opacity: parent.on ? 1.0 : 0.38
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 2
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Config.visualizer.peakHold = !Config.visualizer.peakHold
                    }
                }
            }
        }
    }
}
