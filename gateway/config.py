"""Chemins et constantes partagés (alignés sur bin/gwsa)."""
from __future__ import annotations

import os
import re
from pathlib import Path

ALIAS_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_-]*$")
RESERVED = {
    "add", "list", "remove", "status", "help", "lock", "unlock",
    "policy", "grant", "grants", "strongauth", "admin", "broker",
    "session", "vault",
}

# Services gws non soumis à la policy données (auth locale, introspection).
PASSTHROUGH_SERVICES = frozenset({"auth", "schema"})

REPO_DIR = Path(__file__).resolve().parent.parent
POLICY_CHECKER = REPO_DIR / "scripts" / "policy-check.py"
USAGE_LOGGER = REPO_DIR / "scripts" / "log-usage.py"
SYS_PYTHON = "/usr/bin/python3"


def gwsa_root() -> Path:
    return Path(os.environ.get("GWSA_ROOT") or Path.home() / ".config" / "gws-accounts")


def profile_dir(alias: str) -> Path:
    return gwsa_root() / alias


def upload_spool() -> Path:
    """Répertoire de dépôt des médias `--upload` — ET répertoire courant de gws
    côté broker (ADR-0003).

    gws refuse tout `--upload` dont le chemin résolu sort de son cwd : le
    contenu doit donc être écrit ici, et nulle part ailleurs. Le point en tête
    le tient hors des énumérations de profils (`ALIAS_RE`).
    """
    d = gwsa_root() / ".uploads"
    d.mkdir(parents=True, exist_ok=True)
    try:
        os.chmod(d, 0o700)
    except OSError:
        pass
    return d


def client_id() -> str:
    return os.environ.get("GWSA_CLIENT") or "mcp"
