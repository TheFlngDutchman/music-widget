import QtQuick
import "../../services"
import "styles.js" as Styles

Canvas {
    id: canvas

    // per-canvas history for flame / peak-hold
    property var drawState: ({})

    // tracked so a live theme switch repaints mid-animation
    readonly property color accent: Theme.accent
    readonly property color teal: Theme.teal

    onAccentChanged: requestPaint()
    onTealChanged: requestPaint()

    Connections {
        target: Cava

        function onValuesChanged() {
            canvas.requestPaint();
        }
    }

    onPaint: {
        const ctx = getContext("2d");
        ctx.clearRect(0, 0, width, height);
        Styles.draw(Config.visualizer.style, ctx, width, height, Cava.values,
                    accent, teal, drawState, Config.visualizer.peakHold);
    }
}
