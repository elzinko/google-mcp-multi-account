"""Registre des sessions LLM — capacités éphémères par conversation (fiche 0040).

Chaque session MCP reçoit un identifiant à l'initialize. Les unlock et zones
Drive accordés via « mag session … » ne profitent qu'à cette session (et à ses
sous-sessions déclarées), pas aux autres conversations du poste.
"""
from __future__ import annotations

import json
import os
import secrets
import time
from dataclasses import asdict, dataclass, field, replace
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
class Capability:
    """Capacité fine (compte, service, opération, ressource?) avec expiry.

    Généralise `unlocks` / `drive_zones` (conservés pour compat) au grain
    service × opération × ressource (ADR-0007 §Décision 3). Une ressource
    ABSENTE signifie « périmètre du service borné par la policy compte »,
    jamais un wildcard au-delà : Drive exige une ressource en écriture ; Gmail
    (libellé) et Calendar (agenda) la laissent optionnelle.
    """

    account: str
    service: str
    operation: str
    resource: str = ""
    expires_at: float = 0.0

    def active(self, now: float | None = None) -> bool:
        t = now if now is not None else time.time()
        return (
            bool(self.account) and bool(self.service) and bool(self.operation)
            and self.expires_at > t
        )


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
    # capacités fines (compte, service, opération, ressource?) — cf. Capability
    capabilities: list[Capability] = field(default_factory=list)
    delegated: bool = False  # True = sous-session (pas d'access_request direct)
    # True dès qu'une session est créée/enregistrée par la révision 0080 (ou
    # plus récente) : `capabilities` porte déjà l'état résolu (racine : le
    # sien ; enfant : figé à la création). False = fichier écrit AVANT 0080
    # (upgrade in-place, session encore active) — `capabilities` n'y
    # contenait alors QUE les octrois directs, la résolution passait par
    # `_ancestor_chain` ; `_capabilities_resolution_chain` bascule sur ce
    # repli legacy tant que ce marqueur est absent (Codex PR #118, P2 finding
    # #2). NE COUVRE QUE les capacités fines — cf. `grants_snapshot` pour
    # unlock + zones Drive.
    capabilities_snapshot: bool = True
    # True dès qu'une session est créée/enregistrée par la révision 0085 (ou
    # plus récente) : `unlocks` et `drive_zones` portent déjà l'état résolu.
    # False = fichier écrit AVANT 0085 (upgrade in-place) — que le fichier
    # date de 0080 (capabilities_snapshot=True mais unlock/zones ENCORE
    # hérités en direct à l'époque) ou d'avant, `unlocks`/`drive_zones` n'y
    # contiennent QUE les octrois directs et doivent rester résolus en LIVE
    # via `_ancestor_chain` (`_grants_resolution_chain`) — marqueur DISTINCT
    # de `capabilities_snapshot` à dessein : les deux grains n'ont pas été
    # figés à la même révision, un même marqueur pour les deux aurait fait
    # perdre son unlock/accès Drive à toute session écrite par 0080 dès la
    # mise à jour vers 0085 (revue Codex PR #119, finding P1).
    grants_snapshot: bool = True

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
            "capabilities": [asdict(c) for c in self.capabilities],
            "delegated": self.delegated,
            "capabilities_snapshot": self.capabilities_snapshot,
            "grants_snapshot": self.grants_snapshot,
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
        caps_raw = data.get("capabilities") or []
        capabilities: list[Capability] = []
        if isinstance(caps_raw, list):
            for c in caps_raw:
                if not isinstance(c, dict):
                    continue
                capabilities.append(
                    Capability(
                        account=str(c.get("account") or ""),
                        service=str(c.get("service") or ""),
                        operation=str(c.get("operation") or ""),
                        resource=str(c.get("resource") or ""),
                        expires_at=float(c.get("expires_at") or 0),
                    )
                )
        return cls(
            session_id=str(data.get("session_id") or ""),
            parent_id=str(data.get("parent_id") or ""),
            client=str(data.get("client") or "mcp"),
            created_at=float(data.get("created_at") or 0),
            last_seen_at=float(data.get("last_seen_at") or 0),
            unlocks={str(k): float(v) for k, v in unlocks.items()},
            drive_zones=dz,
            capabilities=capabilities,
            delegated=bool(data.get("delegated")),
            # Absent (fichier écrit avant la fiche 0080) → False : repli
            # legacy `_ancestor_chain` dans `active_capabilities` tant que la
            # session n'a pas été recréée (Codex PR #118, P2 finding #2).
            capabilities_snapshot=bool(data.get("capabilities_snapshot", False)),
            # Absent (fichier écrit avant la fiche 0085 — y compris un fichier
            # 0080 dont `capabilities_snapshot` vaut déjà True) → False :
            # repli legacy sur `_ancestor_chain` pour unlock/zones Drive
            # (Codex PR #119, finding P1 — marqueur distinct de
            # `capabilities_snapshot`, cf. commentaire du champ).
            grants_snapshot=bool(data.get("grants_snapshot", False)),
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


def session_ttl_sec() -> int:
    """TTL effectif d'une session (secondes), surchargeable pour les tests."""
    try:
        return int(os.environ.get("GWSA_SESSION_TTL_SEC", str(DEFAULT_SESSION_TTL_SEC)))
    except ValueError:
        return DEFAULT_SESSION_TTL_SEC


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
    """Charge une session active ; None si absente OU expirée (TTL, fail-closed).

    L'expiration est vérifiée à CHAQUE accès (pas seulement au GC périodique) :
    une session dont le TTL est dépassé ne doit jamais être considérée valide,
    même si `purge_expired` n'est pas encore passée dessus. Ne délègue pas à
    `close_session` (récursion : close_session → revoke_descendants →
    require_session → get_session).
    """
    if not session_id:
        return None
    state = _load(session_id)
    if state is None:
        return None
    now = time.time()
    last_activity = state.last_seen_at or state.created_at
    if last_activity and now - last_activity > session_ttl_sec():
        _path(session_id).unlink(missing_ok=True)
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
        if proj.fail_closed:
            raise GatewayError(
                "manifeste projet invalide/altéré/supprimé après confiance — "
                "refus (anti-downgrade, ADR-0007 §Décision 3)",
                code="policy",
            )
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


def _ancestor_chain(state: SessionState) -> list[SessionState]:
    """Session + ses ancêtres (parent_id …), sans boucle infinie sur un cycle."""
    chain: list[SessionState] = []
    cur: SessionState | None = state
    seen: set[str] = set()
    while cur and cur.session_id not in seen:
        seen.add(cur.session_id)
        chain.append(cur)
        if not cur.parent_id:
            break
        cur = _load(cur.parent_id)
    return chain


def _capabilities_resolution_chain(state: SessionState) -> list[SessionState]:
    """Chaîne de sessions à consulter pour résoudre les CAPACITÉS FINES
    héritées d'une session (grain versionné par `capabilities_snapshot`,
    fiche 0080).

    Une session non déléguée (racine), ou déléguée et marquée
    `capabilities_snapshot`, porte déjà l'état résolu dans ses propres champs
    locaux — figé au moment de sa création par `create_child_session` — donc
    UNIQUEMENT elle-même. Une sous-session déléguée NON marquée (fichier
    écrit par une révision antérieure à 0080, upgrade in-place, encore
    active) retombe sur le repli legacy : remonter la chaîne d'ancêtres en
    direct, comme avant la fiche 0080."""
    return (
        _ancestor_chain(state)
        if state.delegated and not state.capabilities_snapshot
        else [state]
    )


def _grants_resolution_chain(state: SessionState) -> list[SessionState]:
    """Chaîne de sessions à consulter pour résoudre UNLOCK + ZONES DRIVE
    hérités d'une session (grain versionné par `grants_snapshot`, fiche
    0085 — DISTINCT de `capabilities_snapshot` : un fichier écrit par la
    révision 0080 a `capabilities_snapshot=True` mais `grants_snapshot=False`,
    unlock/zones y étaient encore résolus en live, cf. commentaire du champ
    sur `SessionState`, Codex PR #119 finding P1).

    Une session non déléguée (racine), ou déléguée et marquée
    `grants_snapshot`, porte déjà l'état résolu localement — figé à la
    création par `create_child_session` — donc UNIQUEMENT elle-même. Une
    sous-session déléguée NON marquée (fichier écrit avant 0085, qu'il date
    de 0080 ou d'avant) retombe sur le repli legacy : remonter la chaîne
    d'ancêtres en direct."""
    return (
        _ancestor_chain(state)
        if state.delegated and not state.grants_snapshot
        else [state]
    )


def _effective_capabilities(state: SessionState) -> list[Capability]:
    """Capacités fines résolues d'une session (toutes, non filtrées par
    compte/service/expiry) — chaîne de résolution legacy comprise. Sert de
    base à `active_capabilities` et au snapshot pris par
    `create_child_session` : un enfant doit hériter de l'état EFFECTIF de son
    parent, pas de sa seule liste locale brute (sinon un petit-enfant d'un
    parent legacy perd tout — Codex PR #118, P2 finding #2)."""
    return [cap for s in _capabilities_resolution_chain(state) for cap in s.capabilities]


def _effective_unlocks(state: SessionState) -> dict[str, float]:
    """Unlocks résolus d'une session (alias → timestamp d'expiration), même
    principe que `_effective_capabilities` mais versionnés par
    `grants_snapshot` (fiche 0085, Codex PR #119 finding P1)."""
    out: dict[str, float] = {}
    for s in _grants_resolution_chain(state):
        for alias, until in s.unlocks.items():
            out[alias] = max(out.get(alias, 0.0), until)
    return out


def _effective_drive_zones(state: SessionState) -> dict[str, list[DriveZone]]:
    """Zones Drive résolues d'une session (alias → zones), même principe que
    `_effective_unlocks` (grain `grants_snapshot`, fiche 0085)."""
    out: dict[str, list[DriveZone]] = {}
    for s in _grants_resolution_chain(state):
        for alias, zones in s.drive_zones.items():
            out.setdefault(alias, []).extend(zones)
    return out


def active_drive_zones(session_id: str, alias: str) -> set[str]:
    """Zones Drive actives pour (session, alias).

    Une sous-session marquée `grants_snapshot` (snapshot pris à la création
    par `create_child_session`, fiche 0085) ne consulte QUE son propre état :
    une zone accordée au parent après coup ne s'expose plus passivement à
    l'enfant déjà créé. Une session non déléguée, ou une sous-session non
    marquée `grants_snapshot` (fichier 0080 ou pré-0080), retombe sur la
    résolution live via `_grants_resolution_chain`."""
    state = get_session(session_id)
    if state is None:
        return set()
    now = time.time()
    return {z.id for z in _effective_drive_zones(state).get(alias, []) if z.active(now)}


def is_session_unlocked(session_id: str, alias: str) -> bool:
    """Déverrouillage actif pour (session, alias) — même figement à la
    création qu'`active_drive_zones` (fiche 0085) : un `session unlock`
    accordé au parent après coup ne s'expose plus passivement à un enfant
    marqué déjà créé."""
    state = get_session(session_id)
    if state is None:
        return False
    now = time.time()
    return _effective_unlocks(state).get(alias, 0.0) > now


def session_grant_capability(
    session_id: str,
    account: str,
    service: str,
    operation: str,
    resource: str = "",
    hours: int = 8,
) -> SessionState:
    """Octroie une capacité fine (compte, service, opération, ressource?) à une session.

    Réservé à la session racine — une sous-session déléguée ne peut pas
    s'élargir elle-même (même règle que `session_unlock` / `session_grant_drive`).
    """
    state = require_session(session_id)
    root = _root_session(state)
    if state.delegated and state.session_id != root.session_id:
        raise GatewayError(
            "seule la session racine (ou l'humain) peut accorder une capacité",
            code="error",
        )
    account = account.strip()
    service = service.strip().lower()
    operation = operation.strip().lower()
    resource = resource.strip()
    if not account or not service or not operation:
        raise GatewayError("account/service/operation requis", code="error")
    h = max(1, min(int(hours), 168))
    expires = time.time() + h * 3600
    caps = [
        c
        for c in state.capabilities
        if not (
            c.account == account
            and c.service == service
            and c.operation == operation
            and c.resource == resource
        )
    ]
    caps.append(
        Capability(
            account=account, service=service, operation=operation,
            resource=resource, expires_at=expires,
        )
    )
    state.capabilities = caps
    _save(state)
    return state


def active_capabilities(session_id: str, account: str, service: str = "") -> list[Capability]:
    """Capacités actives pour (session, compte[, service]).

    Ne consulte QUE les capacités propres à `session_id` — jamais celles,
    live, d'un ancêtre. Une session racine ne porte que les siennes (aucun
    parent). Une sous-session déléguée reçoit un INSTANTANÉ des capacités
    actives de son parent au moment de sa création (`create_child_session`) ;
    elle ne peut plus en recevoir directement ensuite (`session_grant_capability`
    le refuse). Sa propre liste EST donc déjà l'héritage résolu — la parcourir
    en direct (au lieu de remonter la chaîne à chaque appel) fige les
    capacités déléguées à la création : un octroi accordé au parent APRÈS coup
    ne s'expose plus passivement à un enfant déjà créé (fiche 0080, revue
    Codex PR #110 raffinement #2).

    Repli LEGACY (Codex PR #118, P2 finding #2) : une sous-session ÉCRITE
    AVANT la fiche 0080 (upgrade in-place, encore active) n'a pas
    `capabilities_snapshot` — son `capabilities` local ne contenait alors QUE
    ses octrois directs (elle n'en reçoit jamais), pas l'héritage. Pour ne
    pas la priver d'un coup de ses capacités parent au redémarrage du broker,
    elle retombe sur l'ancienne résolution par chaîne d'ancêtres tant qu'elle
    n'a pas été recréée (une nouvelle sous-session porte toujours le
    marqueur, donc ce repli ne s'applique jamais à une session neuve)."""
    state = get_session(session_id)
    if state is None:
        return []
    now = time.time()
    out: list[Capability] = []
    for cap in _effective_capabilities(state):
        if cap.account != account:
            continue
        if service and cap.service != service:
            continue
        if cap.active(now):
            out.append(cap)
    return out


def session_has_capability(
    session_id: str, account: str, service: str, operation: str, resource: str = "",
) -> bool:
    """True si la session (ou un ancêtre) porte une capacité active couvrant l'appel.

    Une capacité SANS ressource couvre tout appel de ce service × opération
    (le périmètre reste borné ailleurs par la policy compte) ; une capacité
    AVEC ressource ne couvre que cette ressource exacte (ex. zone Drive).
    """
    for cap in active_capabilities(session_id, account, service):
        if cap.operation != operation:
            continue
        if not cap.resource or cap.resource == resource:
            return True
    return False


def create_child_session(parent_id: str, client: str = "mcp") -> SessionState:
    """Crée une sous-session ; l'état hérité du parent — CAPACITÉS FINES
    (`Capability`, service × opération × ressource), UNLOCK et ZONES DRIVE —
    est FIGÉ au moment T (snapshot), par valeur (copie via `replace`, zéro
    aliasing d'objet mutable).

    Le payload signé qui enrôle une sous-session ne nomme que le parent, pas
    ses octrois futurs — copier l'état actif du parent une bonne fois ici
    (plutôt que de le résoudre en direct à chaque appel) évite qu'un octroi
    accordé au parent APRÈS cette création ne s'expose passivement à
    l'enfant : capacités fines (fiche 0080, revue Codex PR #110 raffinement
    #2), étendu à unlock + zones Drive par la fiche 0085 (même trou, révélé
    par la revue de 0080).

    Snapshote depuis l'état EFFECTIF résolu du parent (`_effective_*`, qui
    retombe sur le repli legacy si le parent lui-même est une sous-session
    pré-snapshot), pas sa seule liste locale brute — sinon un petit-enfant
    d'un parent legacy perdrait tout l'héritage (Codex PR #118, P2 finding
    #2)."""
    parent = require_session(parent_id)
    child = create_session(parent_id=parent_id, client=client, delegated=True)
    now = time.time()
    child.capabilities = [replace(c) for c in _effective_capabilities(parent) if c.active(now)]
    child.unlocks = {
        alias: until for alias, until in _effective_unlocks(parent).items() if until > now
    }
    child.drive_zones = {
        alias: zones_active
        for alias, zones in _effective_drive_zones(parent).items()
        if (zones_active := [replace(z) for z in zones if z.active(now)])
    }
    _save(child)
    return child


def revoke_descendants(session_id: str) -> int:
    """Supprime toutes les sous-sessions directes/indirectes ; retourne le nombre purgé.

    N'exige PAS que `session_id` existe encore (révocation en cascade appelée
    depuis `close_session`, y compris sur une session déjà expirée côté GC) —
    l'id sert de racine de comparaison, pas d'un `require_session`.

    Construit d'abord la carte sid → parent_id de TOUS les fichiers présents
    (une seule passe de lecture), avant de supprimer quoi que ce soit : sur une
    chaîne à plusieurs niveaux (petit-enfant → enfant → racine), supprimer
    l'enfant AVANT d'avoir résolu le petit-enfant casserait la remontée de la
    chaîne (son parent deviendrait introuvable en cours de route).
    """
    root_id = session_id
    parent_of: dict[str, str] = {}
    paths: dict[str, Path] = {}
    for path in sessions_dir().glob("*.json"):
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            if not isinstance(data, dict):
                continue
            sid = str(data.get("session_id") or "")
            if not sid:
                continue
            parent_of[sid] = str(data.get("parent_id") or "")
            paths[sid] = path
        except (OSError, json.JSONDecodeError):
            continue

    purged = 0
    for sid, path in paths.items():
        if sid == root_id:
            continue
        cur = parent_of.get(sid, "")
        seen: set[str] = set()
        is_desc = False
        while cur and cur not in seen:
            if cur == root_id:
                is_desc = True
                break
            seen.add(cur)
            cur = parent_of.get(cur, "")
        if is_desc:
            path.unlink(missing_ok=True)
            purged += 1
    return purged


def close_session(session_id: str) -> None:
    """Révocation explicite : purge la session et ses descendants (cycle de vie
    découplé de la connexion MCP — ADR-0007 §Décision 5)."""
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
        caps_live: list[dict[str, Any]] = []
        for cap in state.capabilities:
            if cap.active(now):
                caps_live.append(
                    {
                        "account": cap.account,
                        "service": cap.service,
                        "operation": cap.operation,
                        "resource": cap.resource,
                        "expires_at": cap.expires_at,
                        "minutes_left": max(0, int((cap.expires_at - now) / 60)),
                    }
                )
        children = 0
        for other in sessions_dir().glob("*.json"):
            try:
                data = json.loads(other.read_text(encoding="utf-8"))
                if isinstance(data, dict) and str(data.get("parent_id") or "") == state.session_id:
                    children += 1
            except (OSError, json.JSONDecodeError):
                continue
        last_activity = state.last_seen_at or state.created_at
        ttl_left = max(0, int(session_ttl_sec() - (now - last_activity))) if last_activity else session_ttl_sec()
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
                "capabilities": caps_live,
                "ttl_seconds_left": ttl_left,
                "child_count": children,
            }
        )
    out.sort(key=lambda s: float(s.get("last_seen_at") or 0), reverse=True)
    return out


def purge_expired(max_age_sec: int | None = None) -> int:
    """GC : purge les sessions sans activité depuis max_age_sec (TTL).

    Câblée au balayage/accès (broker `handle_exec`, `create_session`,
    `list_sessions`) — le cycle de vie d'une session ne dépend jamais de la
    déconnexion MCP (ADR-0007 §Décision 5). Lit les fichiers directement (pas
    `get_session`) pour éviter toute récursion avec `close_session`.
    """
    limit = max_age_sec if max_age_sec is not None else session_ttl_sec()
    now = time.time()
    n = 0
    for path in sessions_dir().glob("*.json"):
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            last = float(data.get("last_seen_at") or data.get("created_at") or 0)
            if last and now - last > limit:
                sid = str(data.get("session_id") or path.stem)
                close_session(sid)
                n += 1
        except (OSError, json.JSONDecodeError):
            continue
    return n
