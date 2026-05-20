"""spotifyd lifecycle: authenticate, spawn, device discovery, log capture."""

import asyncio
import json
import os
import shutil
import socket as _socket
import subprocess
import tempfile
import threading
import time
from contextlib import contextmanager
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
    lines = [
        "[global]",
        f'device_name = "{DEFAULT_DEVICE_NAME}"',
        'device_type = "computer"',
        "use_mpris = true",
        f'cache_path = "{SPOTIFYD_CACHE}"',
    ]
    SPOTIFYD_CONF.write_text("\n".join(lines) + "\n")


def _ensure_conf_key(key: str, value: str) -> None:
    try:
        text = SPOTIFYD_CONF.read_text()
        if key not in text:
            with open(SPOTIFYD_CONF, "a") as f:
                f.write(f'{key} = "{value}"\n')
    except OSError:
        pass


def clear_stale_credentials() -> None:
    """Remove auth_type=3 credentials.json if present.

    spotifyd 0.4+ / librespot 0.5+ no longer accepts injected Web API access
    tokens (auth_type=3) for AP authentication. Removing them forces spotifyd
    to use its own built-in OAuth flow via `spotifyd authenticate`.
    """
    creds_path = SPOTIFYD_CACHE / "oauth" / "credentials.json"
    if not creds_path.exists():
        return
    try:
        with open(creds_path) as f:
            data = json.load(f)
        if data.get("auth_type") == 3:
            creds_path.unlink()
    except (OSError, ValueError):
        pass


def has_stored_credentials() -> bool:
    """Return True if spotifyd has persistent auth_type=1 credentials."""
    creds_path = SPOTIFYD_CACHE / "oauth" / "credentials.json"
    try:
        with open(creds_path) as f:
            data = json.load(f)
        return data.get("auth_type") == 1
    except (OSError, ValueError):
        return False


async def _http_connect_handler(reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
    """HTTP CONNECT proxy: refuse port 4070 instantly, tunnel everything else."""
    try:
        # Read the CONNECT request line and headers
        lines: list[bytes] = []
        while True:
            line = await asyncio.wait_for(reader.readline(), timeout=5)
            lines.append(line)
            if line in (b"\r\n", b"\n", b""):
                break

        if not lines:
            return
        first = lines[0].decode(errors="replace")
        # CONNECT host:port HTTP/1.x
        parts = first.split()
        if len(parts) < 2 or parts[0].upper() != "CONNECT":
            writer.write(b"HTTP/1.1 400 Bad Request\r\n\r\n")
            await writer.drain()
            return

        host_port = parts[1]
        host, _, port_str = host_port.rpartition(":")
        port = int(port_str) if port_str.isdigit() else 443

        if port == 4070:
            writer.write(b"HTTP/1.1 502 Bad Gateway\r\n\r\n")
            await writer.drain()
            return

        try:
            rr, rw = await asyncio.wait_for(
                asyncio.open_connection(host, port), timeout=15
            )
        except Exception:
            writer.write(b"HTTP/1.1 502 Bad Gateway\r\n\r\n")
            await writer.drain()
            return

        writer.write(b"HTTP/1.1 200 Connection Established\r\n\r\n")
        await writer.drain()

        async def _pipe(src: asyncio.StreamReader, dst: asyncio.StreamWriter) -> None:
            try:
                while chunk := await src.read(65536):
                    dst.write(chunk)
                    await dst.drain()
            except Exception:
                pass
            finally:
                try:
                    dst.close()
                except Exception:
                    pass

        await asyncio.gather(_pipe(reader, rw), _pipe(rr, writer))
    except Exception:
        pass
    finally:
        try:
            writer.close()
        except Exception:
            pass


@contextmanager
def _no_port_4070():
    """HTTP CONNECT proxy that instantly refuses port-4070 connections.

    Yields the proxy port.  Spotifyd falls back to port 443 in milliseconds
    instead of waiting for the ~136 s TCP SYN timeout.
    """
    with _socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        proxy_port = s.getsockname()[1]

    loop = asyncio.new_event_loop()

    async def _start() -> None:
        srv = await asyncio.start_server(_http_connect_handler, "127.0.0.1", proxy_port)
        await srv.start_serving()

    loop.run_until_complete(_start())
    t = threading.Thread(target=loop.run_forever, daemon=True)
    t.start()
    try:
        yield proxy_port
    finally:
        loop.call_soon_threadsafe(loop.stop)
        t.join(timeout=2)
        try:
            loop.close()
        except Exception:
            pass


def run_oauth(
    oauth_port: int,
    log_path: Path = SPOTIFYD_LOG,
    timeout: float = 120.0,
) -> bool:
    """Run `spotifyd authenticate` via a local SOCKS5 proxy that blocks port 4070.

    Port 4070 is Spotify's preferred AP port but is slow/blocked on many
    networks.  Routing through the proxy causes an immediate refusal so
    spotifyd falls back to port 443 in under a second.

    Uses a temporary spotifyd.conf so the main conf is never modified.
    Uses the same oauth_port as spotipy's redirect URI — no extra redirect URI
    needs to be registered in the Spotify Developer app.
    """
    if not shutil.which("spotifyd"):
        return False
    log_path.parent.mkdir(parents=True, exist_ok=True)

    with _no_port_4070() as proxy_port:
        with tempfile.NamedTemporaryFile(
            mode="w", suffix=".conf", delete=False
        ) as tmp:
            tmp.write("[global]\n")
            tmp.write(f'cache_path = "{SPOTIFYD_CACHE}"\n')
            tmp.write(f'proxy = "http://127.0.0.1:{proxy_port}"\n')
            tmp_path = tmp.name

        try:
            with open(log_path, "ab", buffering=0) as log_fp:
                proc = subprocess.Popen(
                    [
                        "spotifyd",
                        "authenticate",
                        "--config-path", tmp_path,
                        "--cache-path", str(SPOTIFYD_CACHE),
                        "--oauth-port", str(oauth_port),
                    ],
                    stdout=log_fp,
                    stderr=log_fp,
                )
                deadline = time.time() + timeout
                while time.time() < deadline:
                    if proc.poll() is not None:
                        return has_stored_credentials()
                    if has_stored_credentials():
                        proc.kill()
                        return True
                    time.sleep(1.0)
                proc.kill()
                return has_stored_credentials()
        except Exception:
            return False
        finally:
            Path(tmp_path).unlink(missing_ok=True)


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
