"""Player control — playerctl bridge with optional spotipy override."""

import subprocess

_PLAYERS = "spotifyd,spotify,mpd"

# Shared mutable reference for the active spotipy client. The Spotify auth
# flow assigns into _sp_ref[0]; control calls below prefer it when set so
# the same widget instance can drive Spotify Web API and fall back to
# playerctl/MPD when no Spotify session is authenticated.
_sp_ref: list = [None]


def _pc(*args, timeout: float = 1.0) -> str:
    """Run playerctl scoped to our preferred players. Returns stdout stripped."""
    try:
        return subprocess.run(
            ["playerctl", f"--player={_PLAYERS}", *args],
            capture_output=True,
            text=True,
            timeout=timeout,
        ).stdout.strip()
    except Exception:
        return ""


def sp_ctrl(action: str, **kw) -> None:
    """Playback control. Uses spotipy when authenticated; else playerctl."""
    sp = _sp_ref[0]
    if sp is not None:
        try:
            if action == "next":
                sp.next_track()
            elif action == "previous":
                sp.previous_track()
            elif action == "play-pause":
                pb = sp.current_playback()
                if pb and pb.get("is_playing"):
                    sp.pause_playback()
                else:
                    sp.start_playback()
            elif action == "seek":
                sp.seek_track(int(kw["ms"]))
            elif action == "shuffle":
                sp.shuffle(kw["state"])
            elif action == "repeat":
                sp.repeat(kw["state"])  # "track", "context", or "off"
            elif action == "volume":
                sp.volume(int(kw["pct"]))
            return
        except Exception:
            pass
    # Fallback: playerctl
    if action == "next":
        _pc("next")
    elif action == "previous":
        _pc("previous")
    elif action == "play-pause":
        _pc("play-pause")
    elif action == "seek":
        _pc("position", str(kw.get("ms", 0) / 1000))
    elif action == "shuffle":
        _pc("shuffle", "Toggle")
    elif action == "repeat":
        _pc("loop", "Track" if kw.get("state") == "track" else "None")
    elif action == "volume":
        _pc("volume", str(kw.get("pct", 50) / 100))


def fetch_state() -> dict:
    """Return current player state. Empty title means no player.

    Keys: title, artist, art_url, position (s), duration (s), playing (bool)
    """
    status = _pc("status")
    if not status or "No players" in status:
        return {
            "title": "",
            "artist": "",
            "art_url": "",
            "position": 0,
            "duration": 0,
            "playing": False,
        }

    raw = _pc(
        "metadata",
        "--format",
        "{{title}}\n{{artist}}\n{{mpris:artUrl}}\n"
        "{{duration(position)}}\n{{duration(mpris:length)}}",
    ).split("\n")

    return {
        "title": raw[0] if len(raw) > 0 else "",
        "artist": raw[1] if len(raw) > 1 else "",
        "art_url": raw[2] if len(raw) > 2 else "",
        "position": _parse_time(raw[3] if len(raw) > 3 else ""),
        "duration": _parse_time(raw[4] if len(raw) > 4 else ""),
        "playing": status == "Playing",
    }


def _parse_time(s: str) -> float:
    try:
        p = s.strip().split(":")
        if len(p) == 2:
            return int(p[0]) * 60 + float(p[1])
        if len(p) == 3:
            return int(p[0]) * 3600 + int(p[1]) * 60 + float(p[2])
    except Exception:
        pass
    return 0
