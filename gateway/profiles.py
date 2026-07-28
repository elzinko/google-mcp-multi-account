"""Résolution des profils, verrous, validation d'alias."""
from __future__ import annotations

import json
import re
import time
from pathlib import Path
from typing import Any

from .config import ALIAS_RE, RESERVED, gwsa_root, profile_dir
from .errors import GatewayError
from .vault import has_credentials


def validate_alias(alias: str) -> str:
    if not alias or not ALIAS_RE.match(alias):
        raise GatewayError(
            f"alias invalide « {alias} » (lettres, chiffres, - et _ uniquement)",
            code="alias",
        )
    if alias in RESERVED:
        raise GatewayError(f"« {alias} » est un mot réservé", code="alias")
    return alias


def is_locked(dir_path: Path) -> bool:
    if not (dir_path / ".locked").is_file():
        return False
    try:
        until = int((dir_path / ".unlock-until").read_text().strip() or "0")
    except (OSError, ValueError):
        until = 0
    return time.time() >= until


def require_unlocked(alias: str) -> Path:
    validate_alias(alias)
    d = profile_dir(alias)
    if not d.is_dir():
        raise GatewayError(
            f"profil inconnu « {alias} » — le créer avec : gwsa add {alias}",
            code="not_found",
        )
    if is_locked(d):
        raise GatewayError(
            f"profil « {alias} » verrouillé — accès sur demande. "
            f"Demander à l'utilisateur d'exécuter « gwsa unlock {alias} [minutes] » "
            f"ou via l'interface admin (http://127.0.0.1:4877 — démarrer : « gwsa admin »). "
            f"Ne pas tenter de contourner (gws nu / édition de fichiers).",
            code="locked",
        )
    return d


_EMAIL_RE = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]+")


def _profile_email(dir_path: Path) -> str:
    """Email du compte : métadonnée `.email` écrite par gwsa add/list (ADR-0002).

    Jamais d'exécution gws ici — le broker est le seul exécuteur côté gateway.
    Fichier absent (profil d'avant la fiche 0014) ou contenu non-email : chaîne
    vide ; un passage humain `gwsa list` le renseigne.
    """
    try:
        text = (dir_path / ".email").read_text(encoding="utf-8").strip()
    except (OSError, UnicodeDecodeError):
        # Fichier absent/illisible OU octets non-UTF-8 (métadonnée corrompue) :
        # traiter comme absent/invalide, jamais crasher (retour Codex, PR #18).
        return ""
    first = text.splitlines()[0].strip() if text else ""
    return first if _EMAIL_RE.fullmatch(first) else ""


def list_profiles() -> list[dict[str, Any]]:
    root = gwsa_root()
    if not root.is_dir():
        return []
    out: list[dict[str, Any]] = []
    for entry in sorted(root.iterdir()):
        if not entry.is_dir():
            continue
        alias = entry.name
        if not ALIAS_RE.match(alias) or alias in RESERVED:
            continue
        connected = has_credentials(alias)
        has_lock = (entry / ".locked").is_file()
        unlocked_for_min = 0
        if has_lock:
            try:
                until = int((entry / ".unlock-until").read_text().strip() or "0")
            except (OSError, ValueError):
                until = 0
            unlocked_for_min = max(0, int((until - time.time()) / 60))
        policy = None
        try:
            policy = json.loads((entry / "policy.json").read_text(encoding="utf-8"))
        except Exception:
            policy = None
        # Email lisible même verrouillé : métadonnée d'identité, pas une donnée
        # (SECURITY.md, ADR-0002) — simple lecture de fichier, pas de gws.
        email = _profile_email(entry) if connected else ""
        out.append({
            "alias": alias,
            "connected": connected,
            "email": email,
            "locked": has_lock and is_locked(entry),
            "lock_file": has_lock,
            "unlocked_for_min": unlocked_for_min,
            "has_policy": policy is not None,
            "policy_services": sorted(policy.keys()) if isinstance(policy, dict) else [],
        })
    return out
