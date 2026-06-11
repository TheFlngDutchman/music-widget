import QtQuick
import "../../services"

// Flat slider (port of .mw-seek/.mw-vol): thin track, accent fill, round
// handle. Shows the drag position locally while pressed so external value
// updates don't fight the user's drag.
Item {
    id: root

    property real value: 0 // 0..1
    property color fillColor: Theme.accent
    property int handleSize: 10
    property int trackHeight: 3
    property bool enabled: true

    signal moved(real v)
    signal released(real v)

    readonly property bool dragging: mouse.pressed
    property real dragValue: 0
    readonly property real shown: dragging ? dragValue : Math.max(0, Math.min(1, value))

    implicitHeight: handleSize + 4
    opacity: enabled ? 1.0 : 0.35

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: root.trackHeight
        radius: 2
        color: Theme.alpha(Theme.fg, 0.12)
    }

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: root.shown * parent.width
        height: root.trackHeight
        radius: 2
        color: root.fillColor
    }

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        x: root.shown * (parent.width - root.handleSize)
        width: root.handleSize
        height: root.handleSize
        radius: root.handleSize / 2
        color: Theme.fg
        visible: root.enabled
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        anchors.margins: -4
        enabled: root.enabled
        cursorShape: Qt.PointingHandCursor

        function fraction(mx) {
            return Math.max(0, Math.min(1, (mx - 4) / root.width));
        }

        onPressed: mouse => {
            root.dragValue = fraction(mouse.x);
            root.moved(root.dragValue);
        }
        onPositionChanged: mouse => {
            if (pressed) {
                root.dragValue = fraction(mouse.x);
                root.moved(root.dragValue);
            }
        }
        onReleased: root.released(root.dragValue)
    }
}
