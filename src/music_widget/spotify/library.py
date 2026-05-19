"""Library views: Liked Songs, Saved Albums, Recently Played."""

LIBRARY_ENTRIES = [
    {"t": "liked", "name": "Liked Songs", "icon": "󰋕"},
    {"t": "albums", "name": "Saved Albums", "icon": "󰀥"},
    {"t": "recent", "name": "Recently Played", "icon": "󰕧"},
]


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
