"""Registre des sessions LLM — capacités éphémères par conversation (fiche 0040).

Chaque session MCP reçoit un identifiant à l'initialize. Les unlock et zones
Drive accordés via « gwsa session … » ne profitent qu'à cette session (et à ses
sous-sessions déclarées), pas aux autres conversations du poste.
"""
from __future__ import annotations

import json
import os
import secrets
import time
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any

from .config import gwsa_root
from .errors import GatewayError

SESSIONS_DIR_NAME = ".sessions"
DEFAULT_SESSION_TTL_SEC = 8 * 3600


def sessions_dir() -> Path:
    d = gwsa_root() / SESSIONS_DIR_NAME
    d.mkdir(parents=True, exist_ok=True)
    try:
        os.chmod(d, 0o700)
    except OSError:
        pass
    return d


def _path(session_id: str) -> Path:
    return sessions_dir() / f"{session_id}.json"


@dataclass
class DriveZone:
    id: str
    name: str = ""
    expires_at: float = 0.0

    def active(self, now: float | None = None) -> bool:
        t = now if now is not None else time.time()
        return bool(self.id) and self.expires_at > t


@dataclass
class SessionState:
    session_id: str
    parent_id: str = ""
    client: str = "mcp"
    created_at: float = 0.0
    last_seen_at: float = 0.0
    # alias → timestamp unix jusqu'auquel le profil est déverrouillé pour CETTE session
    unlocks: dict[str, float] = field(default_factory=dict)
    # alias → zones Drive temporaires
    drive_zones: dict[str, list[DriveZone]] = field(default_factory=dict)
    delegated: bool = False  # True = sous-session (pas d'access_request direct)

    def touch(self) -> None:
        self.last_seen_at = time.time()

    def to_json(self) -> dict[str, Any]:
        return {
            "session_id": self.session_id,
            "parent_id": self.parent_id,
            "client": self.client,
            "created_at": self.created_at,
            "last_seen_at": self.last_seen_at,
            "unlocks": self.unlocks,
            "drive_zones": {
                alias: [asdict(z) for z in zones]
                for alias, zones in self.drive_zones.items()
            },
            "delegated": self.delegated,
        }

    @classmethod
    def from_json(cls, data: dict[str, Any]) -> SessionState:
        dz: dict[str, list[DriveZone]] = {}
        raw = data.get("drive_zones") or {}
        if isinstance(raw, dict):
            for alias, zones in raw.items():
                if not isinstance(zones, list):
                    continue
                dz[str(alias)] = [
                    DriveZone(
                        id=str(z.get("id") or ""),
                        name=str(z.get("name") or ""),
                        expires_at=float(z.get("expires_at") or z.get("expiresAt") or 0),
                    )
                    for z in zones
                    if isinstance(z, dict)
                ]
        unlocks = data.get("unlocks") or {}
        if not isinstance(unlocks, dict):
            unlocks = {}
        return cls(
            session_id=str(data.get("session_id") or ""),
            parent_id=str(data.get("parent_id") or ""),
            client=str(data.get("client") or "mcp"),
            created_at=float(data.get("created_at") or 0),
            last_seen_at=float(data.get("last_seen_at") or 0),
            unlocks={str(k): float(v) for k, v in unlocks.items()},
            drive_zones=dz,
            delegated=bool(data.get("delegated")),
        )


def _save(state: SessionState) -> None:
    path = _path(state.session_id)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(state.to_json(), ensure_ascii=False, indent=2), encoding="utf-8")
    try:
        os.chmod(tmp, 0o600)
    except OSError:
        pass
    tmp.replace(path)


def _load(session_id: str) -> SessionState | None:
    path = _path(session_id)
    if not path.is_file():
        return None
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(data, dict):
            return None
        return SessionState.from_json(data)
    except (OSError, json.JSONDecodeError, TypeError, ValueError):
        return None


def new_session_id() -> str:
    return secrets.token_hex(12)


def create_session(
    *,
    parent_id: str = "",
    client: str = "mcp",
    delegated: bool = False,
) -> SessionState:
    purge_expired()
    if parent_id:
        parent = get_session(parent_id)
        if parent is None:
            raise GatewayError(f"session parente inconnue « {parent_id} »", code="error")
        delegated = True
    now = time.time()
    state = SessionState(
        session_id=new_session_id(),
        parent_id=parent_id,
        client=client or "mcp",
        created_at=now,
        last_seen_at=now,
        delegated=delegated,
    )
    _save(state)
    return state


def get_session(session_id: str) -> SessionState | None:
    if not session_id:
        return None
    state = _load(session_id)
    if state is None:
        return None
    state.touch()
    _save(state)
    return state


def require_session(session_id: str) -> SessionState:
    state = get_session(session_id)
    if state is None:
        raise GatewayError(f"session inconnue ou expirée « {session_id} »", code="error")
    return state


def _root_session(state: SessionState) -> SessionState:
    cur = state
    seen = {cur.session_id}
    while cur.parent_id:
        if cur.parent_id in seen:
            break
        parent = _load(cur.parent_id)
        if parent is None:
            break
        seen.add(parent.session_id)
        cur = parent
    return cur


def session_unlock(session_id: str, alias: str, minutes: int) -> SessionState:
    state = require_session(session_id)
    root = _root_session(state)
    if state.delegated and state.session_id != root.session_id:
        raise GatewayError(
            "seule la session racine (ou l'humain) peut déverrouiller un profil",
            code="error",
        )
    mins = max(1, min(int(minutes), 1440))
    state.unlocks[alias] = time.time() + mins * 60
    _save(state)
    return state


def session_grant_drive(
    session_id: str,
    alias: str,
    folder_id: str,
    folder_name: str = "",
    hours: int = 8,
) -> SessionState:
    state = require_session(session_id)
    root = _root_session(state)
    if state.delegated and state.session_id != root.session_id:
        raise GatewayError(
            "seule la session racine (ou l'humain) peut accorder une zone Drive",
            code="error",
        )
    h = max(1, min(int(hours), 168))
    expires = time.time() + h * 3600
    fid = folder_id.strip()
    if not fid:
        raise GatewayError("folder_id requis", code="error")
    git_root = os.environ.get("GWSA_GIT_ROOT", "").strip()
    if git_root:
        from .project import grant_allowed_by_manifest, resolve_project

        proj = resolve_project(Path(git_root))
        if proj.manifest_valid and proj.manifest:
            if not grant_allowed_by_manifest(proj.manifest, alias, fid):
                raise GatewayError(
                    f"zone « {fid} » hors périmètre manifeste projet (.gwsa/manifest.json)",
                    code="policy",
                )
    zones = [z for z in state.drive_zones.get(alias, []) if z.id != fid]
    zones.append(DriveZone(id=fid, name=folder_name or fid, expires_at=expires))
    state.drive_zones[alias] = zones
    _save(state)
    return state


def active_drive_zones(session_id: str, alias: str) -> set[str]:
    """Zones Drive actives pour (session, alias), avec héritage parent."""
    state = get_session(session_id)
    if state is None:
        return set()
    now = time.time()
    out: set[str] = set()
    chain: list[SessionState] = []
    cur: SessionState | None = state
    seen: set[str] = set()
    while cur and cur.session_id not in seen:
        seen.add(cur.session_id)
        chain.append(cur)
        if not cur.parent_id:
            break
        cur = _load(cur.parent_id)
    for s in chain:
        for z in s.drive_zones.get(alias, []):
            if z.active(now):
                out.add(z.id)
    return out


def is_session_unlocked(session_id: str, alias: str) -> bool:
    state = get_session(session_id)
    if state is None:
        return False
    now = time.time()
    chain: list[SessionState] = []
    cur: SessionState | None = state
    seen: set[str] = set()
    while cur and cur.session_id not in seen:
        seen.add(cur.session_id)
        chain.append(cur)
        if not cur.parent_id:
            break
        cur = _load(cur.parent_id)
    for s in chain:
        until = s.unlocks.get(alias, 0)
        if until > now:
            return True
    return False


def create_child_session(parent_id: str, client: str = "mcp") -> SessionState:
    return create_session(parent_id=parent_id, client=client, delegated=True)


def revoke_descendants(session_id: str) -> int:
    """Supprime toutes les sous-sessions directes/indirectes ; retourne le nombre purgé."""
    root = require_session(session_id)
    purged = 0
    for path in sessions_dir().glob("*.json"):
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            if not isinstance(data, dict):
                continue
            sid = str(data.get("session_id") or "")
            pid = str(data.get("parent_id") or "")
            if not sid or sid == root.session_id:
                continue
            # descendant si parent_id chain mène à root
            cur = pid
            seen: set[str] = set()
            is_desc = False
            while cur and cur not in seen:
                if cur == root.session_id:
                    is_desc = True
                    break
                seen.add(cur)
                parent = _load(cur)
                cur = parent.parent_id if parent else ""
            if is_desc:
                path.unlink(missing_ok=True)
                purged += 1
        except (OSError, json.JSONDecodeError):
            continue
    return purged


def close_session(session_id: str) -> None:
    revoke_descendants(session_id)
    _path(session_id).unlink(missing_ok=True)


def list_sessions(*, include_expired_zones: bool = False) -> list[dict[str, Any]]:
    """Résumé des sessions actives pour CLI / admin (purge TTL d'abord)."""
    purge_expired()
    now = time.time()
    out: list[dict[str, Any]] = []
    for path in sorted(sessions_dir().glob("*.json"), key=lambda p: p.name):
        state = _load(path.stem)
        if state is None or not state.session_id:
            continue
        unlocks_live: dict[str, dict[str, Any]] = {}
        for alias, until in state.unlocks.items():
            until_f = float(until)
            if until_f > now:
                unlocks_live[alias] = {
                    "until": until_f,
                    "minutes_left": max(0, int((until_f - now) / 60)),
                }
        zones_live: dict[str, list[dict[str, Any]]] = {}
        for alias, zones in state.drive_zones.items():
            active = []
            for z in zones:
                if z.active(now) or include_expired_zones:
                    active.append(
                        {
                            "id": z.id,
                            "name": z.name,
                            "expires_at": z.expires_at,
                            "minutes_left": max(0, int((z.expires_at - now) / 60)),
                        }
                    )
            if active:
                zones_live[alias] = active
        children = 0
        for other in sessions_dir().glob("*.json"):
            try:
                data = json.loads(other.read_text(encoding="utf-8"))
                if isinstance(data, dict) and str(data.get("parent_id") or "") == state.session_id:
                    children += 1
            except (OSError, json.JSONDecodeError):
                continue
        out.append(
            {
                "session_id": state.session_id,
                "parent_id": state.parent_id or None,
                "client": state.client,
                "delegated": state.delegated,
                "created_at": state.created_at,
                "last_seen_at": state.last_seen_at,
                "unlocks": unlocks_live,
                "drive_zones": zones_live,
                "child_count": children,
            }
        )
    out.sort(key=lambda s: float(s.get("last_seen_at") or 0), reverse=True)
    return out


def purge_expired(max_age_sec: int = DEFAULT_SESSION_TTL_SEC) -> int:
    """Purge les sessions sans activité depuis max_age_sec."""
    now = time.time()
    n = 0
    for path in sessions_dir().glob("*.json"):
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            last = float(data.get("last_seen_at") or data.get("created_at") or 0)
            if last and now - last > max_age_sec:
                sid = str(data.get("session_id") or path.stem)
                close_session(sid)
                n += 1
        except (OSError, json.JSONDecodeError):
            continue
    return n
