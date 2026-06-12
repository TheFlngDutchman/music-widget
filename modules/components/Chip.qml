import QtQuick
import "../../services"

// Small clickable pill for option pickers (style/anchor/channel choices).
Rectangle {
    id: root

    property string label: ""
    property bool current: false

    signal clicked()

    width: lbl.implicitWidth + 14
    height: lbl.implicitHeight + 6
    radius: 3
    color: current ? Theme.alpha(Theme.fg, 0.07) : "transparent"

    Text {
        id: lbl
        anchors.centerIn: parent
        text: root.label
        color: root.current ? Theme.accent : Theme.fg
        opacity: root.current ? 1.0 : 0.38
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 2
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
