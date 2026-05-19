"""Cava subprocess lifecycle.

Cava re-reads config on SIGUSR1 only for a subset of options, and `bars` /
`channels` changes typically need a full restart. We just terminate and
respawn — it's quick enough.
"""

import os
import shutil
import signal
import subprocess
import threading
from pathlib import Path

from music_widget.config import CAVA_CONF, CONFIG_DIR


def write_cava_conf(*, bars: int, sensitivity: int, channels: str) -> Path:
    """Write the live cava.conf, returning its path. Idempotent."""
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    text = (
        "[general]\n"
        f"bars = {int(bars)}\n"
        "framerate = 60\n"
        f"sensitivity = {int(sensitivity)}\n"
        "lower_cutoff_freq = 50\n"
        "higher_cutoff_freq = 10000\n"
        "\n"
        "[input]\n"
        "method = pulse\n"
        "source = auto\n"
        "\n"
        "[output]\n"
        "method = raw\n"
        "raw_target = /dev/stdout\n"
        "data_format = ascii\n"
        "ascii_max_range = 100\n"
        "bar_delimiter = 59\n"
        "frame_delimiter = 10\n"
        f"channels = {channels}\n"
    )
    CAVA_CONF.write_text(text)
    return CAVA_CONF


class CavaRunner:
    """Owns the cava subprocess; reads bar frames on a background thread.

    on_bars(list[int]) is called from the reader thread for each frame.
    Callers should marshal back onto the GTK thread via GLib.idle_add.
    """

    def __init__(self, on_bars):
        self._on_bars = on_bars
        self._proc: subprocess.Popen | None = None
        self._running = True
        self._lock = threading.Lock()

    def start(self) -> bool:
        if not shutil.which("cava"):
            return False
        if not CAVA_CONF.exists():
            return False
        with self._lock:
            self._spawn()
        return self._proc is not None

    def restart(self) -> None:
        with self._lock:
            self._terminate()
            self._spawn()

    def stop(self) -> None:
        self._running = False
        with self._lock:
            self._terminate()

    def _spawn(self) -> None:
        try:
            self._proc = subprocess.Popen(
                ["cava", "-p", str(CAVA_CONF)],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
            )
            t = threading.Thread(target=self._reader, args=(self._proc,), daemon=True)
            t.start()
        except Exception:
            self._proc = None

    def _terminate(self) -> None:
        if self._proc is None:
            return
        try:
            self._proc.terminate()
            try:
                self._proc.wait(timeout=1.0)
            except subprocess.TimeoutExpired:
                self._proc.kill()
        except Exception:
            pass
        self._proc = None

    def _reader(self, proc: subprocess.Popen) -> None:
        try:
            for line in proc.stdout:  # type: ignore[union-attr]
                if not self._running:
                    break
                raw = line.decode(errors="ignore").strip()
                if not raw:
                    continue
                try:
                    bars = [int(x) for x in raw.split(";") if x]
                    if bars:
                        self._on_bars(bars)
                except ValueError:
                    pass
        except Exception:
            pass
