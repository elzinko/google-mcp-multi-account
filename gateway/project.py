"""Capacités par projet git — lecture `.gwsa/manifest` (fiche 0040 phase B)."""
from __future__ import annotations

import hashlib
import json
import os
import subprocess
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

GWSA_DIR = ".gwsa"
MANIFEST_NAME = "manifest.json"
SIG_NAME = "manifest.sig"


@dataclass
class ProjectContext:
    git_root: str = ""
    project_id: str = ""
    manifest_path: str = ""
    manifest: dict[str, Any] = field(default_factory=dict)
    manifest_valid: bool = False
    verify_error: str = ""


def git_toplevel(start: Path | None = None) -> str:
    cwd = start or Path.cwd()
    try:
        r = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            cwd=str(cwd),
            capture_output=True,
            text=True,
            timeout=5,
        )
        if r.returncode == 0:
            return r.stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        pass
    return ""


def project_id_from_root(root: str) -> str:
    if not root:
        return ""
    try:
        r = subprocess.run(
            ["git", "remote", "get-url", "origin"],
            cwd=root,
            capture_output=True,
            text=True,
            timeout=5,
        )
        if r.returncode == 0 and r.stdout.strip():
            raw = r.stdout.strip()
            return "sha256:" + hashlib.sha256(raw.encode()).hexdigest()[:16]
    except (OSError, subprocess.TimeoutExpired):
        pass
    return "sha256:" + hashlib.sha256(root.encode()).hexdigest()[:16]


def _load_manifest(gwsa_path: Path) -> dict[str, Any]:
    try:
        data = json.loads(gwsa_path.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except (OSError, json.JSONDecodeError):
        return {}


def _verify_signature(manifest_path: Path, sig_path: Path) -> tuple[bool, str]:
    """Vérification minimale : sig non vide + clé publique locale (stub phase B).

    Remplacé par élicitation signée (fiche 0001) en phase C.
    """
    if not manifest_path.is_file():
        return False, "manifeste absent"
    if not sig_path.is_file():
        return False, "signature absente"
    sig = sig_path.read_text(encoding="utf-8").strip()
    if not sig:
        return False, "signature vide"
    # Stub : accepter les sig préfixées « local: » (tests / dev couloir)
    if sig.startswith("local:"):
        return True, ""
    # Production : vérifier avec clé publique hors repo (fiche 0001, phase C)
    return False, "vérification cryptographique non configurée (utiliser local: en dev)"


def resolve_project(start: Path | None = None) -> ProjectContext:
    root = git_toplevel(start)
    if not root:
        return ProjectContext()
    gwsa = Path(root) / GWSA_DIR
    manifest_path = gwsa / MANIFEST_NAME
    sig_path = gwsa / SIG_NAME
    ctx = ProjectContext(
        git_root=root,
        project_id=project_id_from_root(root),
        manifest_path=str(manifest_path) if manifest_path.is_file() else "",
    )
    if not manifest_path.is_file():
        return ctx
    ok, err = _verify_signature(manifest_path, sig_path)
    ctx.manifest = _load_manifest(manifest_path)
    ctx.manifest_valid = ok
    ctx.verify_error = err
    return ctx


def manifest_drive_zones(manifest: dict[str, Any], alias: str) -> set[str]:
    """IDs de dossiers Drive autorisés par le manifeste pour un alias."""
    caps = manifest.get("capabilities") or {}
    if not isinstance(caps, dict):
        return set()
    ac = caps.get(alias) or {}
    if not isinstance(ac, dict):
        return set()
    drive = ac.get("drive") or {}
    if not isinstance(drive, dict):
        return set()
    zones = drive.get("zones") or []
    out: set[str] = set()
    if isinstance(zones, list):
        for z in zones:
            if isinstance(z, dict) and z.get("id"):
                out.add(str(z["id"]))
            elif isinstance(z, str):
                out.add(z)
    return out


def manifest_allows_service(manifest: dict[str, Any], alias: str, service: str, cat: str) -> bool | None:
    """None = pas de contrainte manifeste pour ce service."""
    if not manifest:
        return None
    caps = manifest.get("capabilities") or {}
    if not isinstance(caps, dict):
        return None
    ac = caps.get(alias)
    if not isinstance(ac, dict):
        return None
    svc = ac.get(service)
    if not isinstance(svc, dict):
        return None
    if cat not in svc:
        return None
    return bool(svc.get(cat))
