import Quickshell
import Quickshell.Io
import "modules"

ShellRoot {
    id: root

    MusicWindow {
        id: window
    }

    IpcHandler {
        target: "window"

        function toggle(): void {
            window.visible = !window.visible;
        }

        function show(): void {
            window.visible = true;
        }

        function hide(): void {
            window.visible = false;
        }
    }
}
