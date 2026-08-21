"""Verrou inter-process POSIX (`flock`) partagé — extrait de
`gateway.elicitation` (fiche 0084) pour la fiche 0083.

Réutilisé par `gateway.elicitation.consume_nonce` (anti-rejeu de nonce) et
par `gateway.remote_approval` (anti-clonage passkey, `sign_count`) : les deux
protègent un cycle read-modify-write (reload → check → save) contre une
course TOCTOU entre process concurrents — Touch ID local et approbation
distante passkey empruntent des chemins différents mais le même besoin de
verrou inter-process, POSIX `fcntl.flock` (macOS + Linux).
"""
from __future__ import annotations

import fcntl
import os
from contextlib import contextmanager
from pathlib import Path


@contextmanager
def file_lock(path: Path):
    """Verrou exclusif inter-process sur un lockfile dédié (créé si absent)."""
    path.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(str(path), os.O_CREAT | os.O_RDWR, 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        yield
    finally:
        try:
            fcntl.flock(fd, fcntl.LOCK_UN)
        finally:
            os.close(fd)
