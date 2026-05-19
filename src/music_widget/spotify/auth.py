"""Spotify PKCE OAuth — port preflight, clear error surfacing, cached-token reuse.

The widget runs spotipy's PKCE flow which spins up a local callback HTTP server
on `redirect_port`. The current widget's flakiness mostly comes from that port
being silently occupied, so we preflight here.
"""

import os
import socket
from pathlib import Path

from music_widget.config import CONFIG_DIR

CLIENT_ID_FILE = CONFIG_DIR / "config.json"  # kept for backward compat
SP_CACHE = CONFIG_DIR / ".spotify_cache"
SP_SCOPES = (
    "user-read-playback-state user-modify-playback-state "
    "user-read-currently-playing playlist-read-private "
    "playlist-read-collaborative user-library-read user-read-recently-played"
)


def redirect_uri(port: int) -> str:
    return f"http://127.0.0.1:{port}/login"


def port_available(port: int) -> bool:
    """Best-effort check that nothing else is bound to 127.0.0.1:<port>."""
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(0.3)
    try:
        # If we can bind, the port is free.
        s.bind(("127.0.0.1", port))
        s.close()
        return True
    except OSError:
        return False


def saved_client_id() -> str:
    """Read the client_id we wrote on the last successful onboarding."""
    if not CLIENT_ID_FILE.exists():
        return ""
    try:
        import json
        with open(CLIENT_ID_FILE) as f:
            return json.load(f).get("client_id", "")
    except Exception:
        return ""


def save_client_id(cid: str) -> None:
    import json
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    with open(CLIENT_ID_FILE, "w") as f:
        json.dump({"client_id": cid}, f)


def build_auth_manager(client_id: str, port: int, *, open_browser: bool):
    """Construct a spotipy SpotifyPKCE auth manager pointed at our cache.

    Imported lazily so the rest of the package can load without spotipy.
    """
    from spotipy.oauth2 import SpotifyPKCE

    return SpotifyPKCE(
        client_id=client_id,
        redirect_uri=redirect_uri(port),
        scope=SP_SCOPES,
        cache_path=str(SP_CACHE),
        open_browser=open_browser,
    )


def try_cached_session(client_id: str, port: int):
    """Return (spotipy.Spotify | None, error message | None) using only cached token.

    Never blocks on the network beyond a token refresh; never opens a browser.
    """
    if not client_id:
        return None, None
    try:
        import spotipy
    except ImportError as e:
        return None, f"spotipy not installed: {e}"
    try:
        auth = build_auth_manager(client_id, port, open_browser=False)
        if auth.get_cached_token():
            return spotipy.Spotify(auth_manager=auth), None
    except Exception as e:  # noqa: BLE001
        return None, str(e)
    return None, None


def classify_auth_error(err: str, port: int) -> str:
    """Turn an opaque spotipy error into something actionable in the UI."""
    low = err.lower()
    if "redirect" in low or "uri" in low:
        return (
            "Redirect URI mismatch.\n"
            f"Add exactly this to your Spotify app:\n{redirect_uri(port)}"
        )
    if "invalid_client" in low or "client" in low:
        return "Invalid Client ID — double-check your Spotify app."
    return f"Auth failed: {err[:120]}"
