"""Music Widget — Hyprland/Waybar popup. Entry point: main()."""

import os
import sys
import threading
from pathlib import Path

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Pango", "1.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, Gdk, Gio, GLib, Gtk, Pango

from music_widget import player as player_mod
from music_widget import theme as theme_mod
from music_widget.controls.page import ControlsPage
from music_widget.local.browser import LocalBrowser
from music_widget.spotify.browser import SpotifyBrowser
from music_widget.ui.helpers import page_tab
from music_widget.visualizer.page import VisualizerPage

THEME_CSS = Path(os.path.expanduser("~/.config/omarchy/current/theme/gtk.css"))


def _resolve_data(name: str) -> Path | None:
    """Locate a shared data file (CSS, etc.) installed via hatch shared-data."""
    candidates = []
    # Editable / dev: data/ next to the package
    here = Path(__file__).resolve()
    candidates.append(here.parent.parent.parent / "data" / name)
    # Installed: <venv>/share/music-widget/<name>
    venv_root = Path(sys.prefix)
    candidates.append(venv_root / "share" / "music-widget" / name)
    # System install
    candidates.append(Path("/usr/share/music-widget") / name)
    for c in candidates:
        if c.exists():
            return c
    return None


# ── Playlists page (Spotify + Local) ─────────────────────────────────


class PlaylistsPage(Gtk.Box):
    def __init__(self):
        super().__init__(orientation=Gtk.Orientation.VERTICAL)

        top = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        top.set_margin_start(10)
        top.set_margin_end(10)
        top.set_margin_top(8)
        top.set_margin_bottom(6)

        self._sp_tab = Gtk.ToggleButton(label="󰓇  Spotify")
        self._sp_tab.add_css_class("mw-tab")
        self._sp_tab.set_active(True)

        self._lo_tab = Gtk.ToggleButton(label="󰉋  Local")
        self._lo_tab.add_css_class("mw-tab")
        self._lo_tab.set_group(self._sp_tab)

        self._search = Gtk.SearchEntry()
        self._search.set_placeholder_text("Search…")
        self._search.set_hexpand(True)
        self._search.add_css_class("mw-search")
        self._search.connect("search-changed", self._on_search_changed)
        self._search.connect("activate", self._on_search_activate)

        for w in [self._sp_tab, self._lo_tab, self._search]:
            top.append(w)
        self.append(top)
        self.append(Gtk.Separator(orientation=Gtk.Orientation.HORIZONTAL))

        self._bstack = Gtk.Stack()
        self._bstack.set_vexpand(True)
        self._sp_browser = SpotifyBrowser()
        self._lo_browser = LocalBrowser()
        self._bstack.add_named(self._sp_browser, "spotify")
        self._bstack.add_named(self._lo_browser, "local")
        self.append(self._bstack)

        self._sp_tab.connect("toggled", lambda _: self._switch())
        self._lo_tab.connect("toggled", lambda _: self._switch())

    def _switch(self):
        self._bstack.set_visible_child_name(
            "spotify" if self._sp_tab.get_active() else "local"
        )

    def _on_search_changed(self, entry):
        q = entry.get_text()
        # In-memory filter of currently shown items
        active = (
            self._sp_browser if self._sp_tab.get_active() else self._lo_browser
        )
        active.filter(q)

    def _on_search_activate(self, entry):
        """Pressing Enter on the Spotify tab promotes the query to a Web search."""
        if not self._sp_tab.get_active():
            return
        q = entry.get_text().strip()
        if q:
            self._sp_browser.search_web(q)


# ── Main window ──────────────────────────────────────────────────────


class MusicWindow(Gtk.ApplicationWindow):
    def __init__(self, app, colors):
        super().__init__(application=app, title="Music")
        self.set_default_size(560, 240)
        self.set_resizable(False)
        self.set_decorated(False)

        self._running = True
        self._last_title = ""
        self._last_artist = ""

        self._load_css()
        self._build(colors)
        GLib.timeout_add(500, self._poll)
        self.connect("destroy", self._on_destroy)

    def _build(self, colors):
        root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        root.add_css_class("mw-root")
        self.set_child(root)

        # Header
        hdr = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        hdr.set_margin_start(14)
        hdr.set_margin_end(8)
        hdr.set_margin_top(4)
        hdr.set_margin_bottom(2)

        lbl = Gtk.Label(label="󰝚  MUSIC")
        lbl.set_hexpand(True)
        lbl.set_halign(Gtk.Align.START)
        lbl.add_css_class("mw-hdr-lbl")

        close = Gtk.Button(label="󰅖")
        close.add_css_class("mw-close-btn")
        close.connect("clicked", lambda _: self.close())

        hdr.append(lbl)
        hdr.append(close)
        root.append(hdr)

        # Tab row
        tab_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=0)
        tab_row.set_margin_start(10)
        tab_row.set_margin_end(10)

        self._ctrl_tab = page_tab("⏯  Controls", active=True)
        self._vis_tab = page_tab("󰕾  Visualizer", group=self._ctrl_tab)
        self._list_tab = page_tab("󰲸  Playlists", group=self._ctrl_tab)

        for t in [self._ctrl_tab, self._vis_tab, self._list_tab]:
            t.set_hexpand(True)
            tab_row.append(t)
        root.append(tab_row)
        root.append(Gtk.Separator(orientation=Gtk.Orientation.HORIZONTAL))

        self._stack = Gtk.Stack()
        self._stack.set_vexpand(True)
        self._stack.set_hhomogeneous(True)
        self._stack.set_vhomogeneous(False)
        self._stack.set_transition_type(Gtk.StackTransitionType.SLIDE_LEFT_RIGHT)
        self._stack.set_transition_duration(120)

        self._ctrl_page = ControlsPage()
        self._vis_page = VisualizerPage(colors)
        self._pl_page = PlaylistsPage()

        self._stack.add_named(self._ctrl_page, "controls")
        self._stack.add_named(self._vis_page, "vis")
        self._stack.add_named(self._pl_page, "playlists")
        root.append(self._stack)

        self._ctrl_tab.connect("toggled", self._tab, "controls")
        self._vis_tab.connect("toggled", self._tab, "vis")
        self._list_tab.connect("toggled", self._tab, "playlists")

    def _tab(self, btn, name):
        if btn.get_active():
            self._stack.set_visible_child_name(name)

    def _poll(self):
        if not self._running:
            return False
        threading.Thread(target=self._fetch_state, daemon=True).start()
        return True

    def _fetch_state(self):
        st = player_mod.fetch_state()
        GLib.idle_add(
            self._ctrl_page.update,
            st["title"] or None,
            st["artist"] or None,
            st["playing"],
            st["position"],
            st["duration"],
            st["art_url"] or None,
        )
        GLib.idle_add(
            self._vis_page.update_track,
            st["title"] or None,
            st["artist"] or None,
        )

    def _load_css(self):
        display = Gdk.Display.get_default()
        prio = Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION

        # 1. Omarchy theme colors (@-variables)
        if THEME_CSS.exists():
            p = Gtk.CssProvider()
            p.load_from_path(str(THEME_CSS))
            Gtk.StyleContext.add_provider_for_display(display, p, prio - 1)

        # 2. Widget CSS, loaded from shared-data (or dev path)
        css_path = _resolve_data("style.css")
        if css_path is not None:
            p2 = Gtk.CssProvider()
            p2.load_from_path(str(css_path))
            Gtk.StyleContext.add_provider_for_display(display, p2, prio)

    def _on_destroy(self, _):
        self._running = False
        try:
            self._vis_page.shutdown()
        except Exception:
            pass


# ── Application ──────────────────────────────────────────────────────


class MusicApp(Adw.Application):
    def __init__(self):
        super().__init__(
            application_id="com.music.widget",
            flags=Gio.ApplicationFlags.FLAGS_NONE,
        )
        self._colors = theme_mod.cairo_colors()
        self.connect("activate", self._activate)

    def _activate(self, app):
        Adw.StyleManager.get_default().set_color_scheme(Adw.ColorScheme.PREFER_DARK)
        wins = self.get_windows()
        if wins:
            wins[0].close()
        else:
            MusicWindow(app, self._colors).present()


def main() -> int:
    return MusicApp().run(sys.argv)
