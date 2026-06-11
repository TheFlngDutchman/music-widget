import QtQuick
import "../../services"
import "../components"

Item {
    // true only while the window is visible and this tab is selected;
    // gates the cava process so it costs nothing when hidden.
    property bool pageActive: false

    StyledText {
        anchors.centerIn: parent
        text: "Visualizer — coming in M3"
        opacity: 0.4
    }
}
