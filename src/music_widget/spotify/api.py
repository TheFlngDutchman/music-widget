"""Small wrapper that binds the active spotipy client into player._sp_ref.

Keeps Spotify-specific imports lazy and centralizes the place where we set
the player module's shared reference so controls fall back correctly.
"""

from music_widget import player as _player


def bind(sp) -> None:
    _player._sp_ref[0] = sp


def unbind() -> None:
    _player._sp_ref[0] = None


def active():
    return _player._sp_ref[0]
