"""Spotify browser — auth onboarding, top-level entries (Liked Songs, Saved
Albums, Recently Played, Your Playlists), nested navigation, and search.

Streams via spotifyd. The widget owns the spotifyd lifecycle; the user never
launches a separate app or service.
"""

import threading

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Pango", "1.0")
from gi.repository import Gdk, GLib, Gtk, Pango

from music_widget import config as cfg_mod
from music_widget import player as player_mod
from music_widget.spotify import api as sp_api
from music_widget.spotify import auth as sp_auth
from music_widget.spotify import library as sp_library
from music_widget.spotify import search as sp_search
from music_widget.spotify import streaming as sp_streaming
from music_widget.ui.helpers import (
    clear_listbox,
    error_row,
    list_row,
    loading_row,
)


class SpotifyBrowser(Gtk.Box):
    """The Spotify tab inside the Playlists page.

    Public API:
    - filter(q)           — apply text filter (or trigger Web search)
    - on_external_query   — settable callable for top-level search routing
    """

    def __init__(self):
        super().__init__(orientation=Gtk.Orientation.VERTICAL)
        self._sp = None
        self._items: list[dict] = []
        self._nav: list[tuple[str, list[dict]]] = []
        self._context_uri: str | None = None  # current playlist/album context for play
        self._port = int(cfg_mod.load()["spotify"]["redirect_port"])
        self._build()
        # Try cached auth shortly after construction so the widget loads fast
        GLib.timeout_add(100, self._try_cached_auth)

    # ── UI build ───────────────────────────────────────────────────────

    def _build(self):
        self._stack = Gtk.Stack()
        self._stack.set_vexpand(True)

        self._stack.add_named(self._build_auth_page(), "auth")
        self._stack.add_named(self._build_waiting_page(), "waiting")
        self._stack.add_named(self._build_browse_page(), "browse")
        self._stack.add_named(self._build_streaming_page(), "streaming-setup")
        self._stack.add_named(self._build_error_page(), "play-error")
        self.append(self._stack)

    def _build_auth_page(self) -> Gtk.Widget:
        page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        page.set_valign(Gtk.Align.CENTER)
        page.set_halign(Gtk.Align.CENTER)
        page.set_margin_start(20)
        page.set_margin_end(20)

        lbl = Gtk.Label(label="󰓇  Connect Spotify")
        lbl.add_css_class("mw-section-lbl")

        step1 = Gtk.Label()
        step1.set_markup(
            "1. Open "
            '<a href="https://developer.spotify.com/dashboard">'
            "developer.spotify.com/dashboard</a>"
        )
        step1.set_halign(Gtk.Align.START)
        step1.add_css_class("mw-note")

        step2 = Gtk.Label(label="2. Edit Settings → Redirect URIs → add this exactly:")
        step2.set_halign(Gtk.Align.START)
        step2.add_css_class("mw-note")

        uri_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        self._uri_display = Gtk.Entry()
        self._uri_display.set_text(sp_auth.redirect_uri(self._port))
        self._uri_display.set_editable(False)
        self._uri_display.set_hexpand(True)
        self._uri_display.add_css_class("mw-uri-display")
        copy_btn = Gtk.Button(label="⧉")
        copy_btn.add_css_class("mw-nav-btn")
        copy_btn.set_tooltip_text("Copy to clipboard")
        copy_btn.connect("clicked", self._copy_uri)
        uri_row.append(self._uri_display)
        uri_row.append(copy_btn)

        step3 = Gtk.Label(label="3. Paste your Client ID:")
        step3.set_halign(Gtk.Align.START)
        step3.add_css_class("mw-note")

        self._cid = Gtk.Entry()
        self._cid.set_placeholder_text("Client ID…")
        self._cid.set_hexpand(True)
        self._cid.connect("activate", lambda _: self._start_auth())

        self._auth_error = Gtk.Label(label="")
        self._auth_error.add_css_class("mw-auth-error")
        self._auth_error.set_visible(False)
        self._auth_error.set_wrap(True)
        self._auth_error.set_max_width_chars(40)
        self._auth_error.set_justify(Gtk.Justification.CENTER)

        conn_btn = Gtk.Button(label="Connect →")
        conn_btn.add_css_class("mw-action-btn")
        conn_btn.connect("clicked", lambda _: self._start_auth())

        note = Gtk.Label(label="⚠  Playback control requires Spotify Premium")
        note.add_css_class("mw-note")

        for w in [
            lbl,
            step1,
            step2,
            uri_row,
            step3,
            self._cid,
            self._auth_error,
            conn_btn,
            note,
        ]:
            page.append(w)
        return page

    def _build_waiting_page(self) -> Gtk.Widget:
        page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        page.set_valign(Gtk.Align.CENTER)
        page.set_halign(Gtk.Align.CENTER)

        spin = Gtk.Spinner()
        spin.set_size_request(28, 28)
        spin.start()
        wait_lbl = Gtk.Label(label="Waiting for browser…")
        wait_lbl.add_css_class("mw-section-lbl")
        wait_note = Gtk.Label(
            label="Complete the login in your browser,\nthen come back here."
        )
        wait_note.add_css_class("mw-note")
        wait_note.set_justify(Gtk.Justification.CENTER)

        cancel = Gtk.Button(label="Cancel")
        cancel.add_css_class("mw-nav-btn")
        cancel.connect(
            "clicked", lambda _: self._stack.set_visible_child_name("auth")
        )

        for w in [spin, wait_lbl, wait_note, cancel]:
            page.append(w)
        return page

    def _build_browse_page(self) -> Gtk.Widget:
        page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)

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
        self._crumb = Gtk.Label(label="Spotify")
        self._crumb.set_halign(Gtk.Align.START)
        self._crumb.set_hexpand(True)
        self._crumb.set_ellipsize(Pango.EllipsizeMode.END)
        self._crumb.add_css_class("mw-crumb")
        nav_inner.append(self._back_arrow)
        nav_inner.append(self._crumb)
        self._nav_btn.set_child(nav_inner)
        page.append(self._nav_btn)

        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroll.set_vexpand(True)

        self._list = Gtk.ListBox()
        self._list.set_selection_mode(Gtk.SelectionMode.SINGLE)
        self._list.add_css_class("mw-list")
        self._list.connect("row-activated", self._activated)
        scroll.set_child(self._list)
        page.append(scroll)
        return page

    def _build_streaming_page(self) -> Gtk.Widget:
        page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        page.set_valign(Gtk.Align.CENTER)
        page.set_halign(Gtk.Align.CENTER)
        page.set_margin_start(14)
        page.set_margin_end(14)

        self._stream_spin = Gtk.Spinner()
        self._stream_spin.set_size_request(28, 28)

        self._stream_lbl = Gtk.Label(label="Connecting…")
        self._stream_lbl.add_css_class("mw-section-lbl")

        cancel = Gtk.Button(label="Cancel")
        cancel.add_css_class("mw-nav-btn")
        cancel.connect("clicked", self._cancel_streaming_setup)

        for w in [self._stream_spin, self._stream_lbl, cancel]:
            page.append(w)
        return page

    def _build_error_page(self) -> Gtk.Widget:
        page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        page.set_valign(Gtk.Align.CENTER)
        page.set_halign(Gtk.Align.CENTER)
        page.set_margin_start(16)
        page.set_margin_end(16)

        self._err_lbl = Gtk.Label(label="")
        self._err_lbl.set_wrap(True)
        self._err_lbl.set_max_width_chars(48)
        self._err_lbl.set_justify(Gtk.Justification.CENTER)
        self._err_lbl.add_css_class("mw-section-lbl")

        self._err_log = Gtk.Label(label="")
        self._err_log.set_wrap(True)
        self._err_log.set_max_width_chars(58)
        self._err_log.set_selectable(True)
        self._err_log.add_css_class("mw-note")
        self._err_log.set_visible(False)

        btn_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        btn_row.set_halign(Gtk.Align.CENTER)
        retry = Gtk.Button(label="Retry")
        retry.add_css_class("mw-action-btn")
        retry.connect("clicked", self._retry_play)
        show_log = Gtk.Button(label="Show spotifyd log")
        show_log.add_css_class("mw-nav-btn")
        show_log.connect("clicked", self._toggle_log)
        back = Gtk.Button(label="Back")
        back.add_css_class("mw-nav-btn")
        back.connect("clicked", lambda _: self._stack.set_visible_child_name("browse"))
        btn_row.append(retry)
        btn_row.append(show_log)
        btn_row.append(back)

        page.append(self._err_lbl)
        page.append(self._err_log)
        page.append(btn_row)
        self._last_play_args: tuple | None = None
        return page

    # ── Auth flow ──────────────────────────────────────────────────────

    def _copy_uri(self, _btn):
        clip = Gdk.Display.get_default().get_clipboard()
        clip.set(sp_auth.redirect_uri(self._port))

    def _try_cached_auth(self):
        cid = sp_auth.saved_client_id()
        if cid:
            GLib.idle_add(self._cid.set_text, cid)
        sp, err = sp_auth.try_cached_session(cid, self._port)
        if sp is not None:
            self._sp = sp
            sp_api.bind(sp)
            self._stack.set_visible_child_name("browse")
            self._show_home()
        else:
            self._stack.set_visible_child_name("auth")
            if err:
                self._auth_error.set_text(err[:140])
                self._auth_error.set_visible(True)
        return False

    def _start_auth(self):
        cid = self._cid.get_text().strip()
        if not cid:
            return
        sp_auth.save_client_id(cid)
        self._auth_error.set_visible(False)

        # Port preflight — the previous code would hang silently here
        if not sp_auth.port_available(self._port):
            self._auth_error.set_text(
                f"Port {self._port} is in use.\n"
                f"Change it in ~/.config/music-widget/config.toml."
            )
            self._auth_error.set_visible(True)
            return

        self._stack.set_visible_child_name("waiting")
        threading.Thread(target=self._auth_thread, args=(cid,), daemon=True).start()

    def _auth_thread(self, cid: str):
        try:
            import spotipy

            auth_mgr = sp_auth.build_auth_manager(cid, self._port, open_browser=True)
            sp = spotipy.Spotify(auth_manager=auth_mgr)
            sp.me()  # blocks until the redirect callback completes
            self._sp = sp
            sp_api.bind(sp)
            GLib.idle_add(self._stack.set_visible_child_name, "browse")
            GLib.idle_add(self._show_home)
        except Exception as e:
            msg = sp_auth.classify_auth_error(str(e), self._port)
            GLib.idle_add(self._show_auth_error, msg)

    def _show_auth_error(self, msg: str):
        self._auth_error.set_text(msg)
        self._auth_error.set_visible(True)
        self._stack.set_visible_child_name("auth")

    # ── Top-level home (library entries + playlists) ───────────────────

    def _show_home(self):
        self._crumb.set_text("Spotify")
        self._nav.clear()
        self._nav_btn.set_sensitive(False)
        self._back_arrow.set_visible(False)
        clear_listbox(self._list)
        self._items = []
        # Library entries appear first
        for entry in sp_library.LIBRARY_ENTRIES:
            row = list_row(entry["icon"], entry["name"])
            row.item = entry
            self._list.append(row)
            self._items.append(entry)
        # Loading placeholder for playlists
        self._list.append(loading_row("Loading playlists…"))
        threading.Thread(target=self._fetch_playlists, daemon=True).start()
        return False

    def _fetch_playlists(self):
        try:
            res = self._sp.current_user_playlists(limit=50)
            playlists = [
                {
                    "t": "pl",
                    "id": p["id"],
                    "uri": p.get("uri", f"spotify:playlist:{p['id']}"),
                    "name": p["name"],
                    "icon": "󰲸",
                }
                for p in res["items"]
                if p
            ]
            GLib.idle_add(self._render_home, playlists)
        except Exception as e:
            GLib.idle_add(self._show_fetch_error, str(e))

    def _render_home(self, playlists):
        clear_listbox(self._list)
        self._items = []
        for entry in sp_library.LIBRARY_ENTRIES:
            row = list_row(entry["icon"], entry["name"])
            row.item = entry
            self._list.append(row)
            self._items.append(entry)
        sep = Gtk.ListBoxRow()
        sep.set_selectable(False)
        sl = Gtk.Label(label="Your Playlists")
        sl.set_halign(Gtk.Align.START)
        sl.add_css_class("mw-note")
        sl.set_margin_top(10)
        sl.set_margin_start(10)
        sl.set_margin_bottom(2)
        sep.set_child(sl)
        self._list.append(sep)
        for pl in playlists:
            row = list_row(pl["icon"], pl["name"])
            row.item = pl
            self._list.append(row)
            self._items.append(pl)
        return False

    # ── Generic list rendering ─────────────────────────────────────────

    def _show_loading(self):
        clear_listbox(self._list)
        self._list.append(loading_row())
        return False

    def _show_fetch_error(self, msg: str):
        clear_listbox(self._list)
        self._list.append(error_row(msg))
        return False

    def _show(self, items: list[dict], label: str):
        self._items = items
        self._crumb.set_text(label)
        clear_listbox(self._list)
        for item in items:
            row = list_row(item["icon"], item["name"], item.get("sub"))
            row.item = item
            self._list.append(row)
        return False

    def _show_grouped(self, groups: list[tuple[str, list[dict]]], label: str):
        self._crumb.set_text(label)
        clear_listbox(self._list)
        flat = []
        for header, items in groups:
            if not items:
                continue
            sep = Gtk.ListBoxRow()
            sep.set_selectable(False)
            lbl = Gtk.Label(label=header)
            lbl.set_halign(Gtk.Align.START)
            lbl.add_css_class("mw-note")
            lbl.set_margin_top(8)
            lbl.set_margin_start(10)
            lbl.set_margin_bottom(2)
            sep.set_child(lbl)
            self._list.append(sep)
            for item in items:
                row = list_row(item["icon"], item["name"], item.get("sub"))
                row.item = item
                self._list.append(row)
                flat.append(item)
        self._items = flat
        return False

    # ── Row activation ─────────────────────────────────────────────────

    def _push_nav(self, label: str):
        self._nav.append((self._crumb.get_text(), self._items[:]))
        self._nav_btn.set_sensitive(True)
        self._back_arrow.set_visible(True)

    def _activated(self, _, row):
        item = getattr(row, "item", None)
        if item is None:
            return
        t = item["t"]
        if t == "pl":
            self._push_nav(item["name"])
            self._context_uri = f"spotify:playlist:{item['id']}"
            threading.Thread(
                target=self._fetch_playlist_tracks, args=(item["id"],), daemon=True
            ).start()
        elif t == "album":
            self._push_nav(item["name"])
            self._context_uri = f"spotify:album:{item['id']}"
            threading.Thread(
                target=self._fetch_album_tracks, args=(item["id"],), daemon=True
            ).start()
        elif t == "artist":
            self._push_nav(item["name"])
            self._context_uri = None
            threading.Thread(
                target=self._fetch_artist_tracks, args=(item["id"],), daemon=True
            ).start()
        elif t == "liked":
            self._push_nav("Liked Songs")
            self._context_uri = None
            threading.Thread(target=self._fetch_liked, daemon=True).start()
        elif t == "albums":
            self._push_nav("Saved Albums")
            self._context_uri = None
            threading.Thread(target=self._fetch_saved_albums, daemon=True).start()
        elif t == "recent":
            self._push_nav("Recently Played")
            self._context_uri = None
            threading.Thread(target=self._fetch_recent, daemon=True).start()
        elif t == "track":
            # If we're inside a playlist/album, pass context_uri so next/prev
            # work natively. Otherwise (Liked Songs, Recently Played, search
            # results) Spotify won't let us use a context_uri — pass the
            # entire visible track list as uris=[...] so a queue exists and
            # the "next" button has somewhere to go.
            if self._context_uri:
                self._play_track_threaded(
                    uri=item["uri"],
                    context_uri=self._context_uri,
                    uri_list=None,
                    position=0,
                )
            else:
                track_uris = [
                    it["uri"] for it in self._items if it.get("t") == "track"
                ]
                try:
                    pos = track_uris.index(item["uri"])
                except ValueError:
                    pos = 0
                self._play_track_threaded(
                    uri=item["uri"],
                    context_uri=None,
                    uri_list=track_uris,
                    position=pos,
                )

    # ── Fetchers (run on background threads) ───────────────────────────

    def _fetch_playlist_tracks(self, pid: str):
        GLib.idle_add(self._show_loading)
        try:
            res = self._sp.playlist_items(pid, limit=100)
            items = []
            for t in res["items"]:
                if not t or not t.get("track"):
                    continue
                tr = t["track"]
                artists = ", ".join(a["name"] for a in tr.get("artists", []))
                items.append(
                    {
                        "t": "track",
                        "id": tr["id"],
                        "uri": tr["uri"],
                        "name": tr["name"],
                        "sub": artists,
                        "icon": "󰝚",
                    }
                )
            GLib.idle_add(self._show, items, "Tracks")
        except Exception as e:
            GLib.idle_add(self._show_fetch_error, str(e))

    def _fetch_album_tracks(self, album_id: str):
        GLib.idle_add(self._show_loading)
        try:
            items = sp_library.fetch_album_tracks(self._sp, album_id)
            GLib.idle_add(self._show, items, "Album")
        except Exception as e:
            GLib.idle_add(self._show_fetch_error, str(e))

    def _fetch_artist_tracks(self, artist_id: str):
        GLib.idle_add(self._show_loading)
        try:
            items = sp_search.fetch_artist_top_tracks(self._sp, artist_id)
            GLib.idle_add(self._show, items, "Top Tracks")
        except Exception as e:
            GLib.idle_add(self._show_fetch_error, str(e))

    def _fetch_liked(self):
        GLib.idle_add(self._show_loading)
        try:
            items = sp_library.fetch_liked(self._sp)
            GLib.idle_add(self._show, items, "Liked Songs")
        except Exception as e:
            GLib.idle_add(self._show_fetch_error, str(e))

    def _fetch_saved_albums(self):
        GLib.idle_add(self._show_loading)
        try:
            items = sp_library.fetch_saved_albums(self._sp)
            GLib.idle_add(self._show, items, "Saved Albums")
        except Exception as e:
            GLib.idle_add(self._show_fetch_error, str(e))

    def _fetch_recent(self):
        GLib.idle_add(self._show_loading)
        try:
            items = sp_library.fetch_recent(self._sp)
            GLib.idle_add(self._show, items, "Recently Played")
        except Exception as e:
            GLib.idle_add(self._show_fetch_error, str(e))

    # ── Search ─────────────────────────────────────────────────────────

    def search_web(self, query: str):
        if self._sp is None:
            return
        # Push current view so back works
        if not self._crumb.get_text().startswith("Search:"):
            self._push_nav(f"Search: {query[:30]}")
        else:
            self._crumb.set_text(f"Search: {query[:30]}")
        threading.Thread(target=self._do_search, args=(query,), daemon=True).start()

    def _do_search(self, query: str):
        GLib.idle_add(self._show_loading)
        try:
            results = sp_search.search(self._sp, query)
            groups = [
                ("Tracks", results["tracks"]),
                ("Albums", results["albums"]),
                ("Artists", results["artists"]),
                ("Playlists", results["playlists"]),
            ]
            GLib.idle_add(self._show_grouped, groups, f"Search: {query[:30]}")
        except Exception as e:
            GLib.idle_add(self._show_fetch_error, str(e))

    def filter(self, q: str):
        """Local in-memory filter; for cross-catalog search use search_web."""
        self._list.set_filter_func(
            (lambda row: q.lower() in getattr(row, "item", {}).get("name", "").lower())
            if q
            else None
        )

    # ── Playback / spotifyd lifecycle ──────────────────────────────────

    def _begin_streaming_setup(self, msg: str):
        self._stream_lbl.set_text(msg)
        self._stream_spin.start()
        self._stack.set_visible_child_name("streaming-setup")
        return False

    def _cancel_streaming_setup(self, _btn):
        sp_streaming.kill_running()
        self._stack.set_visible_child_name("browse")

    def _play_track_threaded(
        self,
        *,
        uri: str,
        context_uri: str | None,
        uri_list: list[str] | None = None,
        position: int = 0,
    ):
        self._last_play_args = (uri, context_uri, uri_list, position)
        threading.Thread(
            target=self._play_track,
            args=(uri, context_uri, uri_list, position),
            daemon=True,
        ).start()

    def _retry_play(self, _btn):
        if self._last_play_args is None:
            self._stack.set_visible_child_name("browse")
            return
        uri, context_uri, uri_list, position = self._last_play_args
        self._play_track_threaded(
            uri=uri,
            context_uri=context_uri,
            uri_list=uri_list,
            position=position,
        )

    def _toggle_log(self, _btn):
        if self._err_log.get_visible():
            self._err_log.set_visible(False)
            return
        log = sp_streaming.tail_log()
        self._err_log.set_text(log or "(no log captured yet)")
        self._err_log.set_visible(True)

    def _show_play_error(self, msg: str):
        self._err_lbl.set_text(msg)
        self._err_log.set_visible(False)
        self._stream_spin.stop()
        self._stack.set_visible_child_name("play-error")
        return False

    def _play_track(
        self,
        uri: str,
        context_uri: str | None,
        uri_list: list[str] | None = None,
        position: int = 0,
    ):
        import shutil as _sh

        if not _sh.which("spotifyd"):
            GLib.idle_add(
                self._show_play_error,
                "spotifyd is not installed.\nRun: omarchy pkg add spotifyd",
            )
            return

        if self._sp is None:
            GLib.idle_add(
                self._show_play_error,
                "Not authenticated with Spotify — complete login first.",
            )
            return

        sp_streaming.ensure_spotifyd_conf()

        # Always re-bootstrap creds so token rotations don't break playback
        if not sp_streaming.bootstrap_credentials(self._sp):
            GLib.idle_add(
                self._show_play_error,
                "Failed to prepare Spotify credentials. "
                "Try reconnecting on the Spotify auth screen.",
            )
            return

        GLib.idle_add(self._begin_streaming_setup, "Starting spotifyd…")

        if not sp_streaming.is_running():
            proc = sp_streaming.spawn()
            if proc is None:
                GLib.idle_add(
                    self._show_play_error, "Could not start spotifyd."
                )
                return

        def progress(msg: str):
            GLib.idle_add(self._begin_streaming_setup, msg)

        device_id = sp_streaming.wait_for_device(
            self._sp, timeout=30.0, progress=progress
        )
        if not device_id:
            GLib.idle_add(
                self._show_play_error,
                f"Spotify Connect device "
                f"'{sp_streaming.device_name()}' did not register within 30s.",
            )
            return

        GLib.idle_add(self._begin_streaming_setup, "Starting playback…")
        try:
            if context_uri:
                self._sp.start_playback(
                    device_id=device_id,
                    context_uri=context_uri,
                    offset={"uri": uri},
                )
            elif uri_list:
                # Liked Songs / Recently Played / search results — no
                # context_uri available, so seed the device queue with
                # the visible list and start at the clicked position.
                self._sp.start_playback(
                    device_id=device_id,
                    uris=uri_list,
                    offset={"position": int(position)},
                )
            else:
                self._sp.start_playback(device_id=device_id, uris=[uri])
        except Exception as e:
            err = str(e)
            low = err.lower()
            if "premium" in low:
                GLib.idle_add(
                    self._show_play_error,
                    "Spotify Premium is required for playback control via the Web API.",
                )
            else:
                GLib.idle_add(self._show_play_error, f"Playback failed: {err[:140]}")
            return

        # Remember the active device for subsequent control calls
        # (shuffle/repeat/seek) and re-assert the user's shuffle/repeat
        # choices — Spotify silently resets both on a context change.
        player_mod.active_device_id = device_id
        try:
            self._sp.shuffle(bool(player_mod.shuffle_on), device_id=device_id)
        except Exception:
            pass
        try:
            self._sp.repeat(
                "track" if player_mod.repeat_on else "off",
                device_id=device_id,
            )
        except Exception:
            pass

        GLib.idle_add(self._stack.set_visible_child_name, "browse")

    # ── Back navigation ────────────────────────────────────────────────

    def _go_back(self, _btn):
        if self._nav:
            lbl, items = self._nav.pop()
            if lbl == "Spotify":
                self._show_home()
            else:
                self._show(items, lbl)
        has_nav = bool(self._nav)
        self._nav_btn.set_sensitive(has_nav)
        self._back_arrow.set_visible(has_nav)
