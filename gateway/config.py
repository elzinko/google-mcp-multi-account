"""Chemins et constantes partagés (alignés sur bin/gwsa)."""
from __future__ import annotations

import os
import re
from pathlib import Path

ALIAS_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_-]*$")
RESERVED = {
    "add", "list", "remove", "status", "help", "lock", "unlock",
    "policy", "grant", "grants", "strongauth", "admin",
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


def client_id() -> str:
    return os.environ.get("GWSA_CLIENT") or "mcp"
