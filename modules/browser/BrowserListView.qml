import QtQuick
import "../../services"

// Shared list for browse/search results. Items are plain JS objects:
//   {kind, icon, label, sub}  kind ∈ nav|playlist|album|artist|track|
//                                     header|loading|error|note
// Track rows get an add-to-queue button. Emits loadMore() near the end
// for infinite scroll.
ListView {
    id: list

    property bool canLoadMore: false
    property bool showQueueButton: true

    // index included because model conversion copies the JS row objects —
    // the receiver can't find `item` in its source array by identity
    signal activated(var item, int index)
    signal queueRequested(var item)
    signal downloadRequested(var item)
    signal loadMore

    clip: true
    spacing: 1
    boundsBehavior: Flickable.StopAtBounds

    // The model is a plain JS array that gets wholesale-reassigned on every
    // append (see appendRows in the browsers), which makes ListView rebuild
    // and snap contentY to 0. Capture the offset when a load-more fires —
    // we're at atYEnd, so it's the old max scroll — and restore it once the
    // new rows land (count grows). On navigation the new list is short, so
    // the clamp drops the restore to ~top, which is what we want there.
    property real _restoreY: -1

    onAtYEndChanged: {
        if (atYEnd && canLoadMore && count > 0) {
            _restoreY = contentY;
            loadMore();
        }
    }

    onCountChanged: {
        if (_restoreY >= 0) {
            const y = _restoreY;
            _restoreY = -1;
            Qt.callLater(() => {
                contentY = Math.min(y, Math.max(0, contentHeight - height));
            });
        }
    }

    delegate: Rectangle {
        id: row

        required property var modelData
        required property int index

        readonly property bool interactive: ["nav", "playlist", "album", "artist", "track"].includes(modelData.kind)
        readonly property bool isHeader: modelData.kind === "header"

        width: list.width
        height: isHeader ? 30 : (modelData.sub ? 36 : 28)
        radius: 3
        color: rowMouse.containsMouse && interactive ? Theme.alpha(Theme.fg, 0.05) : "transparent"

        Row {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 4
            anchors.right: downloadBtn.visible ? downloadBtn.left : (queueBtn.visible ? queueBtn.left : parent.right)
            anchors.rightMargin: 6
            spacing: 8

            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: 22
                text: row.modelData.icon || ""
                color: row.modelData.kind === "error" ? Theme.error : Theme.accent
                opacity: 0.7
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize + 1
                visible: text.length > 0
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 30
                spacing: 1

                Text {
                    width: parent.width
                    text: row.modelData.label || ""
                    color: row.modelData.kind === "error" ? Theme.error : Theme.fg
                    opacity: row.isHeader ? 0.75
                        : row.modelData.kind === "loading" || row.modelData.kind === "note" ? 0.4 : 0.9
                    font.family: Theme.fontFamily
                    font.pixelSize: row.isHeader ? Theme.fontSize + 1 : Theme.fontSize
                    font.bold: row.isHeader
                    font.italic: row.modelData.kind === "loading"
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    text: row.modelData.sub || ""
                    color: Theme.fg
                    opacity: 0.4
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 2
                    elide: Text.ElideRight
                    visible: text.length > 0
                }
            }
        }

        Text {
            id: downloadBtn
            anchors.right: queueBtn.left
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            text: "\uF019"
            color: downloadMouse.containsMouse ? Theme.accent : Theme.fg
            opacity: downloadMouse.containsMouse ? 1 : (rowMouse.containsMouse ? 0.5 : 0)
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize + 1
            visible: row.modelData.kind === "track"

            MouseArea {
                id: downloadMouse
                anchors.fill: parent
                anchors.margins: -6
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: list.downloadRequested(row.modelData)
            }
        }

        Text {
            id: queueBtn
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: "󰐕"
            color: queueMouse.containsMouse ? Theme.accent : Theme.fg
            opacity: queueMouse.containsMouse ? 1 : (rowMouse.containsMouse ? 0.5 : 0)
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize + 1
            visible: list.showQueueButton && row.modelData.kind === "track"

            MouseArea {
                id: queueMouse
                anchors.fill: parent
                anchors.margins: -6
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: list.queueRequested(row.modelData)
            }
        }

        MouseArea {
            id: rowMouse
            anchors.fill: parent
            anchors.rightMargin: (downloadBtn.visible ? 28 : 0) + (queueBtn.visible ? 28 : 0)
            hoverEnabled: true
            cursorShape: row.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: {
                if (row.interactive)
                    list.activated(row.modelData, row.index);
            }
        }
    }
}
