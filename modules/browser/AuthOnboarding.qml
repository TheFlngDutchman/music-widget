import QtQuick
import QtQuick.Layouts
import "../../services"
import "../components"

// Spotify connect screen: paste client ID once, click Connect, approve in
// the browser. Shown again only if the refresh token is revoked.
ColumnLayout {
    id: root

    spacing: 10

    StyledText {
        text: "Connect Spotify"
        font.bold: true
        font.pixelSize: Theme.fontSize + 1
        opacity: 0.75
    }

    StyledText {
        Layout.fillWidth: true
        visible: SpotifyAuth.authState !== "authorizing"
        text: "Create an app at developer.spotify.com/dashboard, add the redirect URI below, then paste its Client ID."
        font.pixelSize: Theme.fontSize - 2
        opacity: 0.4
        wrapMode: Text.WordWrap
        elide: Text.ElideNone
    }

    // redirect URI display (click hint: it must match the dashboard exactly)
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: uriText.implicitHeight + 10
        radius: 4
        color: Theme.alpha(Theme.fg, 0.07)
        border.color: Theme.border
        visible: SpotifyAuth.authState !== "authorizing"

        StyledText {
            id: uriText
            anchors.centerIn: parent
            text: SpotifyAuth.redirectUri
            color: Theme.accent
            font.pixelSize: Theme.fontSize - 1
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        visible: SpotifyAuth.authState !== "authorizing"

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: clientIdInput.implicitHeight + 12
            radius: 4
            color: Theme.alpha(Theme.fg, clientIdInput.activeFocus ? 0.10 : 0.07)
            border.color: Theme.border

            TextInput {
                id: clientIdInput
                anchors.fill: parent
                anchors.margins: 6
                text: SpotifyAuth.clientId
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 1
                clip: true
                selectByMouse: true
                onAccepted: SpotifyAuth.begin(text)

                Text {
                    anchors.fill: parent
                    text: "Spotify app Client ID"
                    color: Theme.fg
                    opacity: 0.3
                    font: clientIdInput.font
                    visible: clientIdInput.text.length === 0
                }
            }
        }

        Rectangle {
            implicitWidth: connectLbl.implicitWidth + 36
            implicitHeight: connectLbl.implicitHeight + 12
            radius: 4
            color: connectMouse.containsMouse ? Theme.accent : Theme.accentBg

            Text {
                id: connectLbl
                anchors.centerIn: parent
                text: "Connect"
                color: Theme.accentFg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 1
                font.bold: true
            }

            MouseArea {
                id: connectMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: SpotifyAuth.begin(clientIdInput.text)
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 6
        visible: SpotifyAuth.authState === "authorizing"

        StyledText {
            text: "Waiting for you to approve in the browser…"
            font.italic: true
            opacity: 0.55
        }

        Rectangle {
            implicitWidth: cancelLbl.implicitWidth + 24
            implicitHeight: cancelLbl.implicitHeight + 8
            radius: 4
            color: cancelMouse.containsMouse ? Theme.alpha(Theme.fg, 0.08) : "transparent"
            border.color: Theme.border

            Text {
                id: cancelLbl
                anchors.centerIn: parent
                text: "Cancel"
                color: Theme.fg
                opacity: 0.7
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 1
            }

            MouseArea {
                id: cancelMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: SpotifyAuth.cancel()
            }
        }
    }

    StyledText {
        Layout.fillWidth: true
        text: SpotifyAuth.errorMessage
        color: Theme.error
        font.pixelSize: Theme.fontSize - 1
        wrapMode: Text.WordWrap
        elide: Text.ElideNone
        visible: text.length > 0
    }

    StyledText {
        Layout.fillWidth: true
        text: "Browsing works on any account; playback control needs Premium."
        font.pixelSize: Theme.fontSize - 2
        opacity: 0.35
    }

    Item { Layout.fillHeight: true }
}
