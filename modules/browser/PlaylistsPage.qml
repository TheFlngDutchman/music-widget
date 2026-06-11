import QtQuick
import QtQuick.Layouts
import "../../services"
import "../components"

Item {
    id: page

    property int source: 0 // 0 spotify, 1 local

    ColumnLayout {
        anchors.fill: parent
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 4

            Repeater {
                model: ["Spotify", "Local"]

                Rectangle {
                    required property string modelData
                    required property int index
                    readonly property bool current: page.source === index

                    width: srcLbl.implicitWidth + 20
                    height: srcLbl.implicitHeight + 8
                    radius: 4
                    color: current ? Theme.alpha(Theme.fg, 0.08) : "transparent"

                    Text {
                        id: srcLbl
                        anchors.centerIn: parent
                        text: parent.modelData
                        color: parent.current ? Theme.accent : Theme.fg
                        opacity: parent.current ? 1.0 : 0.45
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 1
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: page.source = parent.index
                    }
                }
            }

            // search box (port of .mw-search): web search on Spotify,
            // instant filter on Local
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: searchInput.implicitHeight + 10
                radius: 4
                color: Theme.alpha(Theme.fg, searchInput.activeFocus ? 0.10 : 0.07)
                border.color: Theme.border

                TextInput {
                    id: searchInput
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 1
                    clip: true
                    selectByMouse: true
                    onAccepted: {
                        if (page.source === 0)
                            spotifyBrowser.searchWeb(text)
                    }
                    onTextChanged: {
                        if (page.source === 1)
                            localBrowser.filter(text)
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: page.source === 0 ? "Search Spotify (Enter)" : "Filter"
                        color: Theme.fg
                        opacity: 0.3
                        font: searchInput.font
                        visible: searchInput.text.length === 0
                    }
                }
            }
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: page.source

            SpotifyBrowser {
                id: spotifyBrowser
            }

            LocalBrowser {
                id: localBrowser
            }
        }
    }
}
