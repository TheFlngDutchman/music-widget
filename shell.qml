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

        // not named "show": that collides with the `qs ipc show` subcommand
        function open(): void {
            window.visible = true;
        }

        function hide(): void {
            window.visible = false;
        }

        // 0 controls, 1 visualizer, 2 playlists, 3 settings
        function tab(index: int): void {
            window.currentTab = index;
            window.visible = true;
        }
    }
}
