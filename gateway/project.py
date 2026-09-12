"""Capacités par projet git — lecture `.gwsa/manifest` (fiche 0040 phase B)."""
from __future__ import annotations

import hashlib
import json
import os
import secrets
import subprocess
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

GWSA_DIR = ".gwsa"
MANIFEST_NAME = "manifest.json"
SIG_NAME = "manifest.sig"
LOCAL_SIG_PREFIX = "local:"
CRYPTO_SIG_PREFIX = "p256:"
TRUST_DIR_NAME = ".project-trust"


from .config import gwsa_root


@dataclass
class ProjectContext:
    git_root: str = ""
    project_id: str = ""
    manifest_path: str = ""
    manifest: dict[str, Any] = field(default_factory=dict)
    manifest_valid: bool = False
    verify_error: str = ""
    # Anti-downgrade (ADR-0007 §Décision 3, S-07) : True quand un manifeste
    # DÉJÀ DE CONFIANCE (signature vérifiée au moins une fois) devient
    # invalide, altéré, ou disparaît. Le plafond manifeste ne peut alors JAMAIS
    # être silencieusement omis (ce qui élargirait les droits) : l'appelant
    # doit refuser globalement plutôt que retomber sur policy ∩ session.
    fail_closed: bool = False


def _trust_dir() -> Path:
    d = gwsa_root() / TRUST_DIR_NAME
    d.mkdir(parents=True, exist_ok=True)
    try:
        os.chmod(d, 0o700)
    except OSError:
        pass
    return d


def _trust_path(project_id: str) -> Path:
    safe = project_id.replace("/", "_").replace(":", "_") or "unknown"
    return _trust_dir() / f"{safe}.json"


def _mark_trusted(project_id: str) -> None:
    """Mémorise qu'un manifeste signé valide a été vu pour ce project_id."""
    if not project_id:
        return
    path = _trust_path(project_id)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(
        json.dumps({"project_id": project_id, "trusted_at": time.time()}),
        encoding="utf-8",
    )
    try:
        os.chmod(tmp, 0o600)
    except OSError:
        pass
    tmp.replace(path)


def _was_trusted(project_id: str) -> bool:
    return bool(project_id) and _trust_path(project_id).is_file()


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


def _manifest_hash(manifest_path: Path) -> str:
    return hashlib.sha256(manifest_path.read_bytes()).hexdigest()


def _verify_signature(manifest_path: Path, sig_path: Path) -> tuple[bool, str]:
    """Stub local: (dev) ou reçu JSON élicitation signée (fiche 0001)."""
    if not manifest_path.is_file():
        return False, "manifeste absent"
    if not sig_path.is_file():
        return False, "signature absente"
    raw = sig_path.read_text(encoding="utf-8").strip()
    if not raw:
        return False, "signature vide"
    if raw.startswith(LOCAL_SIG_PREFIX):
        return True, ""
    if raw.startswith("{"):
        try:
            receipt = json.loads(raw)
            if not isinstance(receipt, dict):
                return False, "reçu signature invalide"
            mhash = _manifest_hash(manifest_path)
            if str(receipt.get("manifest_hash") or "") != mhash:
                return False, "manifeste modifié depuis la signature"
            from .elicitation import verify_signature

            payload = receipt.get("payload")
            signature = str(receipt.get("signature") or "")
            if not isinstance(payload, dict) or not signature:
                return False, "reçu signature incomplet"
            if verify_signature(payload, signature):
                return True, ""
            return False, "signature cryptographique invalide"
        except json.JSONDecodeError:
            return False, "reçu signature illisible"
    return False, "format de signature inconnu (local: en dev ou mag project sign)"


def gwsa_dir(root: str | Path) -> Path:
    return Path(root) / GWSA_DIR


def manifest_path_for(root: str | Path) -> Path:
    return gwsa_dir(root) / MANIFEST_NAME


def sig_path_for(root: str | Path) -> Path:
    return gwsa_dir(root) / SIG_NAME


def _default_manifest(project_id: str) -> dict[str, Any]:
    return {
        "schema": 1,
        "project_id": project_id,
        "capabilities": {},
        "expires_at": datetime.fromtimestamp(
            time.time() + 365 * 86400, tz=timezone.utc
        ).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }


def write_manifest(root: str | Path, manifest: dict[str, Any]) -> Path:
    """Écrit manifest.json sous .gwsa/ (mode 600)."""
    path = manifest_path_for(root)
    path.parent.mkdir(parents=True, exist_ok=True)
    try:
        os.chmod(path.parent, 0o700)
    except OSError:
        pass
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    try:
        os.chmod(tmp, 0o600)
    except OSError:
        pass
    tmp.replace(path)
    return path


def init_project(start: Path | None = None) -> dict[str, Any]:
    """Crée un manifeste draft minimal si absent (phase B — sans signature crypto)."""
    root = git_toplevel(start)
    if not root:
        raise ValueError("hors dépôt git — init project impossible")
    path = manifest_path_for(root)
    if path.is_file():
        return {
            "ok": True,
            "created": False,
            "manifest_path": str(path),
            "message": "manifeste déjà présent",
        }
    pid = project_id_from_root(root)
    manifest = _default_manifest(pid)
    write_manifest(root, manifest)
    return {
        "ok": True,
        "created": True,
        "manifest_path": str(path),
        "project_id": pid,
        "message": "manifeste draft créé — éditer capabilities puis « mag project sign » (stub local:)",
    }


def sign_manifest_local(start: Path | None = None) -> dict[str, Any]:
    """Signature dev stub « local:… » (sans strongauth / tests)."""
    root = git_toplevel(start)
    if not root:
        raise ValueError("hors dépôt git")
    mpath = manifest_path_for(root)
    if not mpath.is_file():
        raise ValueError("manifeste absent — « mag project init » d'abord")
    spath = sig_path_for(root)
    token = secrets.token_hex(8)
    sig = f"{LOCAL_SIG_PREFIX}{token}"
    spath.parent.mkdir(parents=True, exist_ok=True)
    spath.write_text(sig + "\n", encoding="utf-8")
    try:
        os.chmod(spath, 0o600)
    except OSError:
        pass
    ok, err = _verify_signature(mpath, spath)
    return {
        "ok": ok,
        "manifest_path": str(mpath),
        "sig_path": str(spath),
        "verify_error": err,
        "message": "signature locale (dev) — pas de garantie cryptographique",
    }


def sign_manifest(start: Path | None = None) -> dict[str, Any]:
    """Signe le manifeste : stub local: ou élicitation signée si strongauth."""
    root = git_toplevel(start)
    if not root:
        raise ValueError("hors dépôt git")
    mpath = manifest_path_for(root)
    if not mpath.is_file():
        raise ValueError("manifeste absent — « mag project init » d'abord")
    strong = (gwsa_root() / ".strong-auth").is_file()
    if not strong:
        return sign_manifest_local(start)
    from .elicitation import (
        ElicitationError,
        build_payload,
        consume_nonce,
        is_enrolled,
        log_receipt,
        obtain_signature,
        verify_signature,
    )

    if not is_enrolled():
        raise ValueError(
            "élicitation signée requise — exécuter : mag elicitation enroll"
        )
    mhash = _manifest_hash(mpath)
    payload = build_payload("project_sign", target=mhash[:32])
    try:
        signature = obtain_signature(payload)
        if not verify_signature(payload, signature):
            raise ElicitationError("signature manifeste invalide")
        consume_nonce(str(payload["nonce"]), expires_at=int(payload["expires_at"]))
        log_receipt(payload, signature)
    except ElicitationError as e:
        raise ValueError(str(e)) from e
    receipt = {
        "v": 1,
        "manifest_hash": mhash,
        "payload": payload,
        "signature": signature,
    }
    spath = sig_path_for(root)
    spath.parent.mkdir(parents=True, exist_ok=True)
    spath.write_text(json.dumps(receipt, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    try:
        os.chmod(spath, 0o600)
    except OSError:
        pass
    ok, err = _verify_signature(mpath, spath)
    return {
        "ok": ok,
        "manifest_path": str(mpath),
        "sig_path": str(spath),
        "verify_error": err,
        "message": "manifeste signé (élicitation biométrique)",
    }


def manifest_cap_for_alias(
    manifest: dict[str, Any],
    alias: str,
) -> dict[str, Any] | None:
    """Capacités manifeste pour un alias, ou None si pas de contrainte projet."""
    if not manifest:
        return None
    caps = manifest.get("capabilities") or {}
    if not isinstance(caps, dict):
        return None
    ac = caps.get(alias)
    if not isinstance(ac, dict):
        return None
    return ac


def grant_allowed_by_manifest(
    manifest: dict[str, Any],
    alias: str,
    folder_id: str,
) -> bool:
    """True si le grant session est dans le plafond manifeste (ou pas de plafond drive).

    Absence de `drive` / de clé `zones` = pas de plafond (True).
    Liste explicite `zones: []` = plafond vide → aucun grant Drive.
    """
    ac = manifest_cap_for_alias(manifest, alias)
    if ac is None:
        return True
    drive = ac.get("drive")
    if not isinstance(drive, dict):
        return True
    if "zones" not in drive:
        return True
    zones = drive.get("zones")
    if not isinstance(zones, list):
        return True
    allowed = manifest_drive_zones(manifest, alias)
    return folder_id.strip() in allowed


def resolve_project(start: Path | None = None) -> ProjectContext:
    root = git_toplevel(start)
    if not root:
        return ProjectContext()
    mag = Path(root) / GWSA_DIR
    manifest_path = mag / MANIFEST_NAME
    sig_path = mag / SIG_NAME
    pid = project_id_from_root(root)
    ctx = ProjectContext(
        git_root=root,
        project_id=pid,
        manifest_path=str(manifest_path) if manifest_path.is_file() else "",
    )
    if not manifest_path.is_file():
        # Manifeste absent : downgrade silencieux vers policy ∩ session accepté
        # SEULEMENT si ce projet n'a jamais été de confiance (contexte jamais
        # configuré). Une suppression APRÈS confiance est un downgrade — refus.
        if _was_trusted(pid):
            ctx.fail_closed = True
        return ctx
    ok, err = _verify_signature(manifest_path, sig_path)
    ctx.manifest = _load_manifest(manifest_path)
    ctx.manifest_valid = ok
    ctx.verify_error = err
    if ok:
        _mark_trusted(pid)
    elif _was_trusted(pid):
        # Manifeste présent mais invalide/altéré, sur un projet déjà de
        # confiance : jamais un downgrade silencieux vers « pas de plafond ».
        ctx.fail_closed = True
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
