import QtQuick
import "../../services"

// Borderless icon button: dim by default, brightens + subtle bg on hover.
Rectangle {
    id: root

    property string text
    property int textSize: 14
    property color textColor: Theme.fg
    property real dimmed: 0.4
    signal clicked

    implicitWidth: label.implicitWidth + 14
    implicitHeight: label.implicitHeight + 6
    radius: 4
    color: mouse.containsMouse ? Theme.alpha(Theme.fg, 0.08) : "transparent"

    Text {
        id: label
        anchors.centerIn: parent
        text: root.text
        color: root.textColor
        opacity: mouse.containsMouse ? 1.0 : root.dimmed
        font.family: Theme.fontFamily
        font.pixelSize: root.textSize
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
