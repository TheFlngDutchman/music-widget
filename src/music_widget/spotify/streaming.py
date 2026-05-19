"""spotifyd lifecycle: spawn, credential bootstrap, device discovery, log capture.

Hardening over the previous implementation:
- device_name is read from spotifyd.conf instead of hard-coded "Music Widget";
  if the user changed it for some reason, we still discover the right device.
- 30s discovery window with caller-visible progress stages.
- Captures stderr into a temp log so the UI can surface what went wrong.
- Refreshes the auth_type=3 credential bridge every play call (the original
  code already did this — we keep it because it's the right behavior).
"""

import base64
import json
import os
import shutil
import subprocess
import time
from pathlib import Path
from typing import Callable, Optional

SPOTIFYD_CONF = Path(os.path.expanduser("~/.config/spotifyd/spotifyd.conf"))
SPOTIFYD_CACHE = Path(os.path.expanduser("~/.cache/spotifyd"))
SPOTIFYD_LOG = Path(os.path.expanduser("~/.cache/music-widget/spotifyd.log"))
DEFAULT_DEVICE_NAME = "Music Widget"


def is_running() -> bool:
    return (
        subprocess.run(["pgrep", "-x", "spotifyd"], capture_output=True).returncode
        == 0
    )


def kill_running() -> None:
    subprocess.Popen(
        ["pkill", "-x", "spotifyd"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def device_name() -> str:
    """Read device_name from spotifyd.conf; fall back to DEFAULT_DEVICE_NAME."""
    try:
        with open(SPOTIFYD_CONF) as f:
            for line in f:
                line = line.strip()
                if line.startswith("device_name"):
                    val = line.split("=", 1)[1].strip().strip('"').strip("'")
                    if val:
                        return val
    except OSError:
        pass
    return DEFAULT_DEVICE_NAME


def ensure_spotifyd_conf() -> None:
    """Write a sane default spotifyd.conf if none exists."""
    SPOTIFYD_CONF.parent.mkdir(parents=True, exist_ok=True)
    SPOTIFYD_CACHE.mkdir(parents=True, exist_ok=True)
    if SPOTIFYD_CONF.exists():
        return
    SPOTIFYD_CONF.write_text(
        "[global]\n"
        f'device_name = "{DEFAULT_DEVICE_NAME}"\n'
        'device_type = "computer"\n'
        "use_mpris = true\n"
        f'cache_path = "{SPOTIFYD_CACHE}"\n'
    )


def bootstrap_credentials(sp) -> bool:
    """Write spotipy's OAuth token into spotifyd's credentials.json.

    librespot exchanges AUTHENTICATION_SPOTIFY_TOKEN (auth_type=3) for stored
    credentials on first AP connection — no separate browser login needed.

    Returns True on success, False otherwise (caller surfaces the error).
    """
    try:
        token_info = sp.auth_manager.get_cached_token()
        if not token_info:
            return False
        access_token = token_info["access_token"]
        username = sp.me()["id"]
        creds = {
            "username": username,
            "auth_type": 3,
            "auth_data": base64.b64encode(access_token.encode("utf-8")).decode(
                "ascii"
            ),
        }
        creds_path = SPOTIFYD_CACHE / "oauth" / "credentials.json"
        creds_path.parent.mkdir(parents=True, exist_ok=True)
        with open(creds_path, "w") as f:
            json.dump(creds, f)
        return True
    except Exception:
        return False


def spawn(log_path: Path = SPOTIFYD_LOG) -> Optional[subprocess.Popen]:
    """Start `spotifyd --no-daemon` in the background, capturing stderr.

    Caller is responsible for waiting for the device to register via
    `wait_for_device`.
    """
    if not shutil.which("spotifyd"):
        return None
    log_path.parent.mkdir(parents=True, exist_ok=True)
    log_fp = open(log_path, "ab", buffering=0)
    return subprocess.Popen(
        [
            "spotifyd",
            "--no-daemon",
            "--cache-path",
            str(SPOTIFYD_CACHE),
            "--use-mpris=true",
        ],
        stdout=log_fp,
        stderr=log_fp,
    )


def wait_for_device(
    sp,
    *,
    name: Optional[str] = None,
    timeout: float = 30.0,
    progress: Callable[[str], None] = lambda s: None,
) -> Optional[str]:
    """Poll Spotify's device list until our device appears, return its ID.

    Calls progress() at well-defined stages so the UI can show what's happening.
    """
    if name is None:
        name = device_name()
    progress("Looking for Spotify Connect device…")
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            devices = sp.devices().get("devices", [])
            for d in devices:
                if d["name"] == name:
                    progress("Device registered.")
                    return d["id"]
        except Exception:
            pass
        time.sleep(0.5)
    return None


def tail_log(n_lines: int = 40) -> str:
    """Return last `n_lines` of the spotifyd log for diagnostics in the UI."""
    if not SPOTIFYD_LOG.exists():
        return ""
    try:
        with open(SPOTIFYD_LOG, "rb") as f:
            data = f.read().decode(errors="ignore")
        lines = data.splitlines()[-n_lines:]
        return "\n".join(lines)
    except OSError:
        return ""
