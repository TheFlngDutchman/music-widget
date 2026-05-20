"""Library views: Liked Songs, Saved Albums, Recently Played, Queue."""

LIBRARY_ENTRIES = [
    {"t": "queue", "name": "Queue", "icon": "≡"},
    {"t": "liked", "name": "Liked Songs", "icon": "󰋕"},
    {"t": "albums", "name": "Saved Albums", "icon": "󰀥"},
    {"t": "recent", "name": "Recently Played", "icon": "󰕧"},
]


def _track_item(tr: dict) -> dict:
    artists = ", ".join(a["name"] for a in tr.get("artists", []))
    return {
        "t": "track",
        "id": tr["id"],
        "uri": tr["uri"],
        "name": tr["name"],
        "sub": artists,
        "icon": "󰝚",
    }


def fetch_queue(sp) -> tuple[dict | None, list[dict]]:
    """Return (currently_playing, upcoming_queue). Either may be empty."""
    data = sp.queue() or {}
    cp_raw = data.get("currently_playing")
    cp = _track_item(cp_raw) if cp_raw and cp_raw.get("type") == "track" else None
    upcoming = [
        _track_item(tr) for tr in (data.get("queue") or [])
        if tr and tr.get("type") == "track"
    ]
    return cp, upcoming


def fetch_liked(sp, limit: int = 50) -> list[dict]:
    res = sp.current_user_saved_tracks(limit=limit)
    items = []
    for t in res["items"]:
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
    return items


def fetch_saved_albums(sp, limit: int = 50) -> list[dict]:
    res = sp.current_user_saved_albums(limit=limit)
    items = []
    for entry in res["items"]:
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
    return items


def fetch_recent(sp, limit: int = 50) -> list[dict]:
    res = sp.current_user_recently_played(limit=limit)
    items = []
    for t in res["items"]:
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
    return items


def fetch_album_tracks(sp, album_id: str) -> list[dict]:
    res = sp.album_tracks(album_id, limit=50)
    items = []
    for tr in res["items"]:
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
    return items
