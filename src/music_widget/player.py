"""Player control — playerctl bridge with optional spotipy override."""

import subprocess

_PLAYERS = "spotifyd,spotify,mpd"

# Shared mutable reference for the active spotipy client. The Spotify auth
# flow assigns into _sp_ref[0]; control calls below prefer it when set so
# the same widget instance can drive Spotify Web API and fall back to
# playerctl/MPD when no Spotify session is authenticated.
_sp_ref: list = [None]

# Active spotifyd device id, set by the browser once playback starts.
# Without an explicit device_id, sp.shuffle() / sp.volume() operate on
# whatever Spotify thinks is "active" — which is fragile right after a
# start_playback because the device list takes a moment to settle.
active_device_id: str | None = None

# UI shuffle/repeat state, lifted out of ControlsPage so the browser can
# re-assert it after each start_playback (Spotify resets these on a
# context change).
shuffle_on: bool = False
repeat_on: bool = False


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
            # Pass our spotifyd device id when we know it, so calls work
            # even if Spotify briefly thinks another device is "active".
            dev = active_device_id
            if action == "next":
                sp.next_track(device_id=dev)
            elif action == "previous":
                sp.previous_track(device_id=dev)
            elif action == "play-pause":
                pb = sp.current_playback()
                if pb and pb.get("is_playing"):
                    sp.pause_playback(device_id=dev)
                else:
                    sp.start_playback(device_id=dev)
            elif action == "seek":
                sp.seek_track(int(kw["ms"]), device_id=dev)
            elif action == "shuffle":
                sp.shuffle(bool(kw["state"]), device_id=dev)
            elif action == "repeat":
                sp.repeat(kw["state"], device_id=dev)
            elif action == "volume":
                sp.volume(int(kw["pct"]), device_id=dev)
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
