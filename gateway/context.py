"""Contexte MCP courant — session_id propagé aux appels broker."""
from __future__ import annotations

_session_id: str = ""
_git_root: str = ""


def set_session_id(session_id: str) -> None:
    global _session_id
    _session_id = session_id or ""


def get_session_id() -> str:
    return _session_id


def set_git_root(git_root: str) -> None:
    global _git_root
    _git_root = git_root or ""


def get_git_root() -> str:
    return _git_root
