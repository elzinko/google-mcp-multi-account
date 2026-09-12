"""Contexte MCP courant — git_root propagé aux appels broker.

Le jeton de session n'est PLUS un global de process (ADR-0007 §Décision 2) :
il est porté par chaque appel (paramètre `session` des tools MCP), lu au
`tools/call` et transmis explicitement à travers gateway.api → gateway.executor
→ le broker. Un global partagerait le même jeton entre toutes les conversations
d'une connexion MCP partagée (Claude Desktop) — exactement le bug que la fiche
0076 corrige. `git_root` reste un global : il ne porte pas de droit, seulement
le contexte de dépôt courant du process (hors périmètre de cette fiche).
"""
from __future__ import annotations

_git_root: str = ""


def set_git_root(git_root: str) -> None:
    global _git_root
    _git_root = git_root or ""


def get_git_root() -> str:
    return _git_root
