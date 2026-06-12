import QtQuick
import QtQuick.Layouts
import "../../services"

// − value + integer stepper. Emits stepped(v); the owner writes the config
// property, so the displayed value always reflects the stored state.
RowLayout {
    id: root

    property int value: 0
    property int from: 0
    property int to: 100
    property int step: 1

    signal stepped(int v)

    spacing: 3

    Rectangle {
        Layout.preferredWidth: 18
        Layout.preferredHeight: 18
        radius: 3
        color: minusMouse.containsMouse ? Theme.alpha(Theme.fg, 0.08) : "transparent"
        border.color: Theme.border
        opacity: root.value > root.from ? 1.0 : 0.3

        Text {
            anchors.centerIn: parent
            text: "−"
            color: Theme.fg
            opacity: 0.7
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
        }

        MouseArea {
            id: minusMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.stepped(Math.max(root.from, root.value - root.step))
        }
    }

    StyledText {
        text: root.value
        font.pixelSize: Theme.fontSize - 1
        opacity: 0.8
        horizontalAlignment: Text.AlignHCenter
        Layout.preferredWidth: 34
    }

    Rectangle {
        Layout.preferredWidth: 18
        Layout.preferredHeight: 18
        radius: 3
        color: plusMouse.containsMouse ? Theme.alpha(Theme.fg, 0.08) : "transparent"
        border.color: Theme.border
        opacity: root.value < root.to ? 1.0 : 0.3

        Text {
            anchors.centerIn: parent
            text: "+"
            color: Theme.fg
            opacity: 0.7
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
        }

        MouseArea {
            id: plusMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.stepped(Math.min(root.to, root.value + root.step))
        }
    }
}
