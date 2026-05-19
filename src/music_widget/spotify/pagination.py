"""Pagination helpers for Spotify list views.

A PageContext wraps a paginated spotipy call so the browser can:
- fetch the first page,
- detect when more results exist,
- fetch the next page when the user scrolls to the bottom.

`fetch_fn(offset, limit)` must return `(items, has_more)`. For spotipy
endpoints that use cursor-based pagination (e.g. recently played) the
fetcher hides the cursor inside its closure.
"""

from typing import Callable


class PageContext:
    def __init__(self, fetch_fn: Callable[[int, int], tuple[list[dict], bool]], *, limit: int = 50):
        self._fetch_fn = fetch_fn
        self._limit = limit
        self.offset = 0
        self.has_more = True
        self.loading = False

    def reset(self) -> None:
        self.offset = 0
        self.has_more = True
        self.loading = False

    def fetch_first(self) -> list[dict]:
        self.reset()
        self.loading = True
        try:
            items, has_more = self._fetch_fn(0, self._limit)
        finally:
            self.loading = False
        self.offset = len(items)
        self.has_more = has_more
        return items

    def fetch_next(self) -> list[dict]:
        if not self.has_more or self.loading:
            return []
        self.loading = True
        try:
            items, has_more = self._fetch_fn(self.offset, self._limit)
        finally:
            self.loading = False
        self.offset += len(items)
        self.has_more = has_more
        return items


# ── Paginated fetchers ─────────────────────────────────────────────────


def playlists_page(sp):
    """User's playlists, limit 50/page."""
    def fetch(offset, limit):
        res = sp.current_user_playlists(limit=limit, offset=offset)
        items = [
            {
                "t": "pl",
                "id": p["id"],
                "uri": p.get("uri", f"spotify:playlist:{p['id']}"),
                "name": p["name"],
                "icon": "󰲸",
            }
            for p in res.get("items", [])
            if p
        ]
        has_more = bool(res.get("next"))
        return items, has_more
    return PageContext(fetch, limit=50)


def liked_page(sp):
    def fetch(offset, limit):
        res = sp.current_user_saved_tracks(limit=limit, offset=offset)
        items = []
        for t in res.get("items", []):
            tr = t.get("track")
            if not tr:
                continue
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
        return items, bool(res.get("next"))
    return PageContext(fetch, limit=50)


def saved_albums_page(sp):
    def fetch(offset, limit):
        res = sp.current_user_saved_albums(limit=limit, offset=offset)
        items = []
        for entry in res.get("items", []):
            a = entry.get("album")
            if not a:
                continue
            artists = ", ".join(ar["name"] for ar in a.get("artists", []))
            items.append(
                {
                    "t": "album",
                    "id": a["id"],
                    "uri": a["uri"],
                    "name": a["name"],
                    "sub": artists,
                    "icon": "󰀥",
                }
            )
        return items, bool(res.get("next"))
    return PageContext(fetch, limit=50)


def recently_played_page(sp):
    """Recently played uses cursor pagination — track the cursor in closure."""
    state = {"after": None, "exhausted": False}

    def fetch(offset, limit):
        if state["exhausted"]:
            return [], False
        kwargs = {"limit": limit}
        if state["after"]:
            kwargs["before"] = state["after"]
        res = sp.current_user_recently_played(**kwargs)
        items = []
        for t in res.get("items", []):
            tr = t.get("track")
            if not tr:
                continue
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
        cursors = res.get("cursors") or {}
        state["after"] = cursors.get("before")  # for the *next* "before"
        has_more = bool(state["after"]) and bool(items)
        if not has_more:
            state["exhausted"] = True
        return items, has_more
    return PageContext(fetch, limit=50)


def playlist_tracks_page(sp, playlist_id: str):
    def fetch(offset, limit):
        res = sp.playlist_items(playlist_id, limit=limit, offset=offset)
        items = []
        for t in res.get("items", []):
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
        return items, bool(res.get("next"))
    return PageContext(fetch, limit=100)
