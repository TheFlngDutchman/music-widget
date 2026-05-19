"""Local / MPD browser — path navigation + playback via the MPD client."""

import os
import subprocess
import threading

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Pango", "1.0")
from gi.repository import GLib, Gtk, Pango

from music_widget.ui.helpers import (
    clear_listbox,
    error_row,
    list_row,
    loading_row,
)


def _read_music_dir() -> str:
    try:
        with open(os.path.expanduser("~/.config/mpd/mpd.conf")) as f:
            for line in f:
                line = line.strip()
                if line.startswith("music_directory"):
                    val = line.split(None, 1)[1].strip().strip('"\'')
                    return os.path.expanduser(val)
    except Exception:
        pass
    return os.path.expanduser("~/Music")


class LocalBrowser(Gtk.Box):
    def __init__(self):
        super().__init__(orientation=Gtk.Orientation.VERTICAL)
        self._mpd = None
        self._nav: list[str] = []
        self._path = ""
        self._music_dir = _read_music_dir()
        self._build()
        GLib.timeout_add(200, self._init_mpd)

    def _build(self):
        self._stack = Gtk.Stack()
        self._stack.set_vexpand(True)

        # No-MPD page
        nomp = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        nomp.set_valign(Gtk.Align.CENTER)
        nomp.set_halign(Gtk.Align.CENTER)
        lbl = Gtk.Label(label="MPD not running")
        lbl.add_css_class("mw-section-lbl")
        btn = Gtk.Button(label="󰐊  Start MPD")
        btn.add_css_class("mw-action-btn")
        btn.connect("clicked", self._start_mpd)
        note = Gtk.Label(label="Add music to ~/Music, then run: mpc update")
        note.add_css_class("mw-note")
        for w in [lbl, btn, note]:
            nomp.append(w)

        # Browse page
        browse = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        home = os.path.expanduser("~")
        default_display = (
            self._music_dir.replace(home, "~", 1)
            if self._music_dir.startswith(home)
            else self._music_dir
        )
        self._path_entry = Gtk.Entry()
        self._path_entry.set_text(default_display)
        self._path_entry.set_hexpand(True)
        self._path_entry.add_css_class("mw-path-entry")
        self._path_entry.set_margin_start(8)
        self._path_entry.set_margin_end(8)
        self._path_entry.set_margin_top(6)
        self._path_entry.set_margin_bottom(2)
        self._path_entry.connect("activate", self._on_path_entered)
        browse.append(self._path_entry)

        self._nav_btn = Gtk.Button()
        self._nav_btn.add_css_class("mw-nav-row")
        self._nav_btn.set_hexpand(True)
        self._nav_btn.set_sensitive(False)
        self._nav_btn.connect("clicked", self._go_back)
        nav_inner = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        nav_inner.set_margin_start(8)
        nav_inner.set_margin_end(8)
        nav_inner.set_margin_top(5)
        nav_inner.set_margin_bottom(5)
        self._back_arrow = Gtk.Label(label="←")
        self._back_arrow.add_css_class("mw-nav-arrow")
        self._back_arrow.set_visible(False)
        self._crumb = Gtk.Label(label="Music Library")
        self._crumb.set_halign(Gtk.Align.START)
        self._crumb.set_hexpand(True)
        self._crumb.set_ellipsize(Pango.EllipsizeMode.END)
        self._crumb.add_css_class("mw-crumb")
        nav_inner.append(self._back_arrow)
        nav_inner.append(self._crumb)
        self._nav_btn.set_child(nav_inner)
        browse.append(self._nav_btn)

        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroll.set_vexpand(True)
        self._list = Gtk.ListBox()
        self._list.set_selection_mode(Gtk.SelectionMode.SINGLE)
        self._list.add_css_class("mw-list")
        self._list.connect("row-activated", self._activated)
        scroll.set_child(self._list)
        browse.append(scroll)

        self._stack.add_named(nomp, "nomp")
        self._stack.add_named(browse, "browse")
        self.append(self._stack)

    def _init_mpd(self):
        try:
            from mpd import MPDClient

            self._mpd = MPDClient()
            self._mpd.connect("127.0.0.1", 6600)
            self._stack.set_visible_child_name("browse")
            self._browse("")
        except Exception:
            self._stack.set_visible_child_name("nomp")
        return False

    def _start_mpd(self, _btn):
        subprocess.Popen(
            ["systemctl", "--user", "start", "mpd"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        GLib.timeout_add(1800, self._init_mpd)

    def _show_loading(self):
        clear_listbox(self._list)
        self._list.append(loading_row())
        return False

    def _show_fetch_error(self, msg: str):
        clear_listbox(self._list)
        self._list.append(error_row(msg))
        return False

    def _browse(self, path: str):
        self._path = path
        threading.Thread(target=self._fetch_dir, args=(path,), daemon=True).start()

    def _fetch_dir(self, path: str):
        GLib.idle_add(self._show_loading)
        try:
            raw = self._mpd.lsinfo(path) if path else self._mpd.lsinfo()
            items = []
            for e in raw:
                if "directory" in e:
                    name = e["directory"].rstrip("/").split("/")[-1]
                    items.append(
                        {
                            "t": "dir",
                            "path": e["directory"],
                            "name": name,
                            "icon": "󰉋",
                        }
                    )
                elif "file" in e:
                    name = e.get("title") or e["file"].split("/")[-1]
                    artist = e.get("artist", "")
                    items.append(
                        {
                            "t": "file",
                            "path": e["file"],
                            "name": name,
                            "sub": artist,
                            "icon": "󰝚",
                        }
                    )
            label = path.rstrip("/").split("/")[-1] if path else "Music Library"
            GLib.idle_add(self._show, items, label)
        except Exception as e:
            GLib.idle_add(self._show_fetch_error, str(e))

    def _show(self, items: list[dict], label: str):
        self._crumb.set_text(label)
        home = os.path.expanduser("~")
        abs_path = (
            os.path.join(self._music_dir, self._path) if self._path else self._music_dir
        )
        display = (
            abs_path.replace(home, "~", 1) if abs_path.startswith(home) else abs_path
        )
        self._path_entry.set_text(display)
        clear_listbox(self._list)
        for item in items:
            row = list_row(item["icon"], item["name"], item.get("sub"))
            row.item = item
            self._list.append(row)
        return False

    def _on_path_entered(self, entry):
        text = os.path.expanduser(entry.get_text().strip())
        if text.startswith(self._music_dir + os.sep):
            rel = text[len(self._music_dir) + 1 :]
        elif text == self._music_dir:
            rel = ""
        else:
            rel = text  # treat as MPD-relative path
        self._nav.clear()
        self._nav_btn.set_sensitive(False)
        self._back_arrow.set_visible(False)
        self._browse(rel)

    def _activated(self, _, row):
        item = getattr(row, "item", None)
        if item is None:
            return
        if item["t"] == "dir":
            self._nav.append(self._path)
            self._nav_btn.set_sensitive(True)
            self._back_arrow.set_visible(True)
            self._browse(item["path"])
        else:
            try:
                self._mpd.clear()
                self._mpd.add(item["path"])
                self._mpd.play(0)
            except Exception:
                for cmd in [
                    ["mpc", "clear"],
                    ["mpc", "add", item["path"]],
                    ["mpc", "play"],
                ]:
                    subprocess.Popen(
                        cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
                    )

    def _go_back(self, _btn):
        if self._nav:
            self._browse(self._nav.pop())
        has_nav = bool(self._nav)
        self._nav_btn.set_sensitive(has_nav)
        self._back_arrow.set_visible(has_nav)

    def filter(self, q: str):
        self._list.set_filter_func(
            (lambda row: q.lower() in getattr(row, "item", {}).get("name", "").lower())
            if q
            else None
        )
