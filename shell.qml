import QtQuick
import Quickshell
import Quickshell.Io
import "modules"
import "services"

ShellRoot {
    id: root

    // singletons are lazy — touch Spotifyd at startup so the credential
    // seed is refreshed before any spotifyd restart can hit a stale token
    Component.onCompleted: Spotifyd.ensureFreshSeed()

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

        // kick off (re)auth without opening the settings UI
        function spotifyConnect(): void {
            SpotifyAuth.begin();
        }
    }
}
