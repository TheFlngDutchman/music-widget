pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Cava subprocess → smoothed bar values in [0,1].
// Runs only while `active` (visualizer tab on a visible window). Structural
// config changes (bars/sensitivity/channels) restart cava; smoothing is
// applied QML-side per frame. The conf file is written by the wrapper shell
// before exec'ing cava, so spawn never races the write.
Singleton {
    id: root

    property bool active: false
    property var values: []
    property var _smooth: []

    readonly property string confPath: Config.configDir + "/cava.conf"

    readonly property string conf: "[general]\n"
        + "bars = " + Config.visualizer.bars + "\n"
        + "framerate = 60\n"
        + "sensitivity = " + Config.visualizer.sensitivity + "\n"
        + "lower_cutoff_freq = 50\n"
        + "higher_cutoff_freq = 10000\n\n"
        + "[input]\n"
        + "method = pulse\n"
        + "source = auto\n\n"
        + "[output]\n"
        + "method = raw\n"
        + "raw_target = /dev/stdout\n"
        + "data_format = ascii\n"
        + "ascii_max_range = 100\n"
        + "bar_delimiter = 59\n"
        + "frame_delimiter = 10\n"
        + "channels = " + Config.visualizer.channels + "\n"

    onActiveChanged: {
        proc.running = active;
        if (!active) {
            values = [];
            _smooth = [];
        }
    }

    onConfChanged: {
        if (proc.running) {
            proc.running = false;
            proc.running = true;
        }
    }

    function handleFrame(line) {
        const parts = line.split(";");
        const k = Config.visualizer.smoothing;
        const out = [];
        for (let i = 0, j = 0; i < parts.length; i++) {
            if (parts[i] === "")
                continue;
            const v = Math.max(0, Math.min(1, parseInt(parts[i], 10) / 100));
            const prev = j < _smooth.length ? _smooth[j] : 0;
            out.push((1 - k) * v + k * prev);
            j++;
        }
        if (out.length > 0) {
            _smooth = out;
            values = out;
        }
    }

    Process {
        id: proc
        command: ["/bin/sh", "-c",
            "printf '%s' \"$MW_CAVA_CONF\" > \"$MW_CAVA_PATH\" && exec cava -p \"$MW_CAVA_PATH\""]
        environment: ({
            MW_CAVA_CONF: root.conf,
            MW_CAVA_PATH: root.confPath
        })

        stdout: SplitParser {
            onRead: data => root.handleFrame(data)
        }
    }
}
