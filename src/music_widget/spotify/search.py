"""Spotify catalog search — tracks/albums/artists/playlists."""


def search(sp, query: str, *, limit: int = 20) -> dict[str, list[dict]]:
    """Return categorized results suitable for click-to-play list rows."""
    if not query.strip():
        return {"tracks": [], "albums": [], "artists": [], "playlists": []}
    res = sp.search(q=query, type="track,album,artist,playlist", limit=limit)

    tracks = []
    for tr in (res.get("tracks") or {}).get("items", []) or []:
        artists = ", ".join(a["name"] for a in tr.get("artists", []))
        tracks.append(
            {
                "t": "track",
                "id": tr["id"],
                "uri": tr["uri"],
                "name": tr["name"],
                "sub": artists,
                "icon": "󰝚",
            }
        )

    albums = []
    for a in (res.get("albums") or {}).get("items", []) or []:
        artists = ", ".join(ar["name"] for ar in a.get("artists", []))
        albums.append(
            {
                "t": "album",
                "id": a["id"],
                "uri": a["uri"],
                "name": a["name"],
                "sub": artists,
                "icon": "󰀥",
            }
        )

    artists_list = []
    for ar in (res.get("artists") or {}).get("items", []) or []:
        artists_list.append(
            {
                "t": "artist",
                "id": ar["id"],
                "uri": ar["uri"],
                "name": ar["name"],
                "sub": "",
                "icon": "󰠃",
            }
        )

    playlists = []
    for pl in (res.get("playlists") or {}).get("items", []) or []:
        # Spotify occasionally returns null entries in playlist search results.
        if not pl:
            continue
        owner = (pl.get("owner") or {}).get("display_name") or ""
        playlists.append(
            {
                "t": "pl",
                "id": pl["id"],
                "uri": pl["uri"],
                "name": pl["name"],
                "sub": owner,
                "icon": "󰲸",
            }
        )

    return {
        "tracks": tracks,
        "albums": albums,
        "artists": artists_list,
        "playlists": playlists,
    }


def fetch_artist_top_tracks(sp, artist_id: str) -> list[dict]:
    """Top tracks for an artist (in the user's market)."""
    res = sp.artist_top_tracks(artist_id)
    items = []
    for tr in res.get("tracks", []):
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
