"""Controls page — album art, seek bar, transport buttons, volume."""

import threading
import urllib.request

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("GdkPixbuf", "2.0")
gi.require_version("Pango", "1.0")
from gi.repository import Gdk, GdkPixbuf, GLib, Gtk, Pango

from music_widget import player as player_mod
from music_widget.player import sp_ctrl
from music_widget.ui.helpers import ctrl_btn


def _ctrl_async(action: str, **kw) -> None:
    """Dispatch sp_ctrl off the main thread — Spotify Web API calls take
    hundreds of ms and would freeze the UI."""
    threading.Thread(
        target=sp_ctrl, args=(action,), kwargs=kw, daemon=True
    ).start()


class ControlsPage(Gtk.Box):
    def __init__(self):
        super().__init__(orientation=Gtk.Orientation.VERTICAL)
        self._duration = 0
        self._seek_lock = False
        self._art_url = None
        self._vol_timer_id: int | None = None
        self._pending_vol: int = 0

        wrap = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        wrap.set_valign(Gtk.Align.CENTER)
        wrap.set_vexpand(True)
        wrap.set_margin_start(16)
        wrap.set_margin_end(16)
        wrap.set_margin_top(8)
        wrap.set_margin_bottom(4)

        # Art + track info
        info = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)

        self._art_stack = Gtk.Stack()
        self._art_stack.set_size_request(72, 72)
        self._art_stack.set_transition_type(Gtk.StackTransitionType.CROSSFADE)
        self._art_stack.set_transition_duration(200)

        ph = Gtk.Label(label="󰝚")
        ph.add_css_class("mw-art-ph")

        self._art = Gtk.Picture()
        self._art.set_size_request(72, 72)
        self._art.set_content_fit(Gtk.ContentFit.COVER)
        self._art.add_css_class("mw-art")

        self._art_stack.add_named(ph, "ph")
        self._art_stack.add_named(self._art, "art")

        track = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        track.set_hexpand(True)
        track.set_valign(Gtk.Align.CENTER)

        self._title = Gtk.Label(label="Not playing")
        self._title.set_halign(Gtk.Align.START)
        self._title.set_ellipsize(Pango.EllipsizeMode.END)
        self._title.add_css_class("mw-track-title")

        self._artist = Gtk.Label(label="")
        self._artist.set_halign(Gtk.Align.START)
        self._artist.set_ellipsize(Pango.EllipsizeMode.END)
        self._artist.add_css_class("mw-track-artist")

        self._prog = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 0, 1, 0.001)
        self._prog.set_draw_value(False)
        self._prog.set_hexpand(True)
        self._prog.add_css_class("mw-seek")
        self._prog.connect("change-value", self._on_seek)

        self._time_lbl = Gtk.Label(label="0:00 / 0:00")
        self._time_lbl.set_halign(Gtk.Align.END)
        self._time_lbl.add_css_class("mw-time")

        for w in [self._title, self._artist, self._prog, self._time_lbl]:
            track.append(w)

        info.append(self._art_stack)
        info.append(track)
        wrap.append(info)

        # Controls row
        ctrl = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=0)
        ctrl.set_halign(Gtk.Align.CENTER)

        self._sh_btn = ctrl_btn("󰒝", self._on_shuffle, dim=not player_mod.shuffle_on)
        self._play = ctrl_btn("󰐊", self._on_play_pause)
        self._re_btn = ctrl_btn("󰑖", self._on_repeat, dim=not player_mod.repeat_on)

        vol_icon = Gtk.Label(label="󰕾")
        vol_icon.add_css_class("mw-vol-icon")

        self._vol = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 0, 100, 1)
        self._vol.set_value(80)
        self._vol.set_draw_value(False)
        self._vol.set_size_request(96, -1)
        self._vol.add_css_class("mw-vol")
        self._vol.connect("change-value", self._on_volume)

        for w in [
            self._sh_btn,
            ctrl_btn("󰒮", lambda _: _ctrl_async("previous")),
            self._play,
            ctrl_btn("󰒭", lambda _: _ctrl_async("next")),
            self._re_btn,
            vol_icon,
            self._vol,
        ]:
            ctrl.append(w)

        wrap.append(ctrl)
        self.append(wrap)

    def update(self, title, artist, playing, position, duration, art_url):
        self._title.set_text(title or "Not playing")
        self._artist.set_text(artist or "")
        self._duration = duration
        self._play.set_label("󰏤" if playing else "󰐊")

        if duration > 0 and not self._seek_lock:
            self._prog.set_value(position / duration)
            p = f"{int(position // 60)}:{int(position % 60):02d}"
            d = f"{int(duration // 60)}:{int(duration % 60):02d}"
            self._time_lbl.set_text(f"{p} / {d}")
        elif duration == 0:
            self._prog.set_value(0)
            self._time_lbl.set_text("0:00 / 0:00")

        if art_url and art_url != self._art_url:
            self._art_url = art_url
            self._art_stack.set_visible_child_name("ph")
            threading.Thread(target=self._fetch_art, args=(art_url,), daemon=True).start()

    def _fetch_art(self, url: str) -> None:
        try:
            if url.startswith("file://"):
                pb = GdkPixbuf.Pixbuf.new_from_file_at_scale(url[7:], 72, 72, True)
            else:
                data = urllib.request.urlopen(url, timeout=5).read()
                ld = GdkPixbuf.PixbufLoader()
                ld.write(data)
                ld.close()
                pb = ld.get_pixbuf()
                if pb:
                    pb = pb.scale_simple(72, 72, GdkPixbuf.InterpType.BILINEAR)
            if pb:
                fmt = (
                    Gdk.MemoryFormat.R8G8B8A8
                    if pb.get_has_alpha()
                    else Gdk.MemoryFormat.R8G8B8
                )
                tex = Gdk.MemoryTexture.new(
                    pb.get_width(),
                    pb.get_height(),
                    fmt,
                    GLib.Bytes.new(pb.get_pixels()),
                    pb.get_rowstride(),
                )
                GLib.idle_add(self._art.set_paintable, tex)
                GLib.idle_add(self._art_stack.set_visible_child_name, "art")
        except Exception:
            pass

    def _on_seek(self, _, _t, value):
        if self._duration > 0:
            self._seek_lock = True
            _ctrl_async("seek", ms=int(value * self._duration * 1000))
            GLib.timeout_add(1200, lambda: setattr(self, "_seek_lock", False) or False)
        return False

    def _on_play_pause(self, _):
        # Optimistic toggle — the poll loop will reconcile within 500 ms
        # if the API call somehow ends in a different state.
        playing_now = self._play.get_label() == "󰏤"
        self._play.set_label("󰐊" if playing_now else "󰏤")
        _ctrl_async("play-pause")

    def _on_shuffle(self, btn):
        player_mod.shuffle_on = not player_mod.shuffle_on
        btn.set_opacity(1.0 if player_mod.shuffle_on else 0.35)
        _ctrl_async("shuffle", state=player_mod.shuffle_on)

    def _on_repeat(self, btn):
        player_mod.repeat_on = not player_mod.repeat_on
        btn.set_opacity(1.0 if player_mod.repeat_on else 0.35)
        _ctrl_async("repeat", state="track" if player_mod.repeat_on else "off")

    def _on_volume(self, _, _t, v):
        # Debounce: a slider drag fires change-value every few ms; we'd
        # otherwise spray dozens of HTTP requests per drag. Coalesce to
        # one API call ~80 ms after the user stops dragging.
        self._pending_vol = max(0, min(100, int(v)))
        if self._vol_timer_id is not None:
            GLib.source_remove(self._vol_timer_id)
        self._vol_timer_id = GLib.timeout_add(80, self._flush_volume)
        return False

    def _flush_volume(self):
        self._vol_timer_id = None
        _ctrl_async("volume", pct=self._pending_vol)
        return False
