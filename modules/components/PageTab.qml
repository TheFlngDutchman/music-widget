import QtQuick
import "../../services"

// Top-level page tab: accent underline when active (port of .mw-page-tab).
Item {
    id: root

    property string text
    property bool active: false
    signal clicked

    implicitWidth: label.implicitWidth + 8
    implicitHeight: label.implicitHeight + 12

    Text {
        id: label
        anchors.centerIn: parent
        text: root.text
        color: root.active ? Theme.accent : Theme.fg
        opacity: root.active ? 1.0 : (mouse.containsMouse ? 0.75 : 0.45)
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 1

        Behavior on opacity {
            NumberAnimation { duration: 120 }
        }
    }

    Rectangle {
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width
        height: 2
        color: Theme.accent
        visible: root.active
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
