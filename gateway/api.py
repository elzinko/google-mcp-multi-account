"""API publique stable de la gateway (consommée par le serveur MCP)."""
from __future__ import annotations

import json
import os
import tempfile
from collections.abc import Iterator
from contextlib import contextmanager
from pathlib import Path
from typing import Any, Optional

from .config import client_id, profile_dir, upload_spool
from .context import get_git_root, get_session_id
from .errors import GatewayError
from .executor import run_via_broker
from .profiles import is_locked, list_profiles as _list_profiles
from .profiles import require_unlocked, validate_alias
from .project import git_toplevel
from .sessions import is_session_unlocked
from .setup_status import setup_status  # noqa: F401 — re-export pour le dispatch MCP
from .usage import log_usage

# Champs Drive demandés partout : `owners`/`ownedByMe` répondent à « ce
# livrable appartient-il bien au bon compte ? » — la question que le
# multi-comptes pose à chaque dépôt (fiche 0024).
_DRIVE_FILE_FIELDS = (
    "id,name,mimeType,modifiedTime,parents,webViewLink,size,"
    "owners(emailAddress),ownedByMe"
)
_DRIVE_LIST_FIELDS = (
    "files(id,name,mimeType,modifiedTime,parents,"
    "owners(emailAddress),ownedByMe),nextPageToken"
)

# Contenu texte accepté par drive_create. Restreint à ce qui se rédige : Drive
# convertit ces formats vers un type Google, et un paramètre `content` (str)
# n'a de sens que pour du texte.
_CONTENT_TYPES = {
    "text/markdown": ".md",
    "text/plain": ".txt",
    "text/html": ".html",
    "text/csv": ".csv",
}
_GOOGLE_MIME_PREFIX = "application/vnd.google-apps."
_MAX_CONTENT_BYTES = 1_000_000


def profiles_list() -> dict[str, Any]:
    return {"ok": True, "profiles": _list_profiles()}


def _run(alias: str, gws_args: list[str], timeout: int = 60) -> Any:
    sid = get_session_id()
    gro = get_git_root() or git_toplevel()
    try:
        if sid:
            d = profile_dir(alias)
            if not d.is_dir():
                raise GatewayError(
                    f"profil inconnu « {alias} » — le créer avec : gwsa add {alias}",
                    code="not_found",
                )
            if is_locked(d) and not is_session_unlocked(sid, alias):
                raise GatewayError(
                    f"profil « {alias} » verrouillé pour cette session — "
                    f"access_request kind=session_unlock",
                    code="locked",
                )
        else:
            require_unlocked(alias)
    except GatewayError as e:
        if e.code == "locked":
            log_usage(
                alias, gws_args, client_id(), decision="refus", reason="locked",
                session_id=sid, git_root=gro,
            )
        raise
    return run_via_broker(alias, gws_args, timeout=timeout)


def gmail_list(
    alias: str,
    query: str = "",
    max_results: int = 10,
) -> dict[str, Any]:
    validate_alias(alias)
    max_results = max(1, min(int(max_results), 50))
    params: dict[str, Any] = {"userId": "me", "maxResults": max_results}
    if query:
        params["q"] = query
    data = _run(
        alias,
        ["gmail", "users", "messages", "list", "--params", json.dumps(params)],
    )
    return {"ok": True, "alias": alias, "result": data}


def gmail_get(alias: str, message_id: str, format: str = "full") -> dict[str, Any]:
    validate_alias(alias)
    if not message_id or not isinstance(message_id, str):
        raise GatewayError("message_id requis", code="error")
    fmt = format if format in ("full", "metadata", "minimal", "raw") else "full"
    params = {"userId": "me", "id": message_id, "format": fmt}
    data = _run(
        alias,
        ["gmail", "users", "messages", "get", "--params", json.dumps(params)],
    )
    return {"ok": True, "alias": alias, "result": data}


def gmail_create_draft(
    alias: str,
    to: str,
    subject: str,
    body: str,
    cc: str = "",
) -> dict[str, Any]:
    """Crée un brouillon — jamais d'envoi (pas de tool send en v1)."""
    validate_alias(alias)
    if not to or not subject:
        raise GatewayError("to et subject sont requis", code="error")
    # Message RFC 2822 minimal, encodé raw base64url — gws drafts.create attend --json.
    import base64

    headers = [f"To: {to}", f"Subject: {subject}"]
    if cc:
        headers.append(f"Cc: {cc}")
    headers.append("Content-Type: text/plain; charset=utf-8")
    raw = ("\r\n".join(headers) + "\r\n\r\n" + (body or "")).encode("utf-8")
    raw_b64 = base64.urlsafe_b64encode(raw).decode("ascii").rstrip("=")
    payload = {"message": {"raw": raw_b64}}
    # `--json` porte le corps, `--params` le paramètre de CHEMIN userId
    # (gmail/v1/users/{userId}/drafts). Sans lui, gws refuse avant tout appel :
    # « Required path parameter userId is missing » (fiche 0024).
    data = _run(
        alias,
        [
            "gmail", "users", "drafts", "create",
            "--params", json.dumps({"userId": "me"}),
            "--json", json.dumps(payload),
        ],
    )
    return {"ok": True, "alias": alias, "result": data}


def _ownership(f: Any) -> dict[str, Any]:
    """Propriétaire d'un fichier Drive, lisible sans fouiller la réponse brute.

    `owned_by_me` vaut None quand l'API ne renseigne pas `ownedByMe` (cas des
    Drive partagés) : « inconnu » plutôt qu'un « non » inventé.
    """
    if not isinstance(f, dict):
        return {"owner": "", "owned_by_me": None}
    owners = f.get("owners")
    owner = ""
    if isinstance(owners, list) and owners and isinstance(owners[0], dict):
        owner = owners[0].get("emailAddress") or ""
    return {"owner": owner, "owned_by_me": f.get("ownedByMe")}


def drive_list(
    alias: str,
    query: str = "trashed=false",
    page_size: int = 20,
    parent: Optional[str] = None,
) -> dict[str, Any]:
    validate_alias(alias)
    page_size = max(1, min(int(page_size), 100))
    q = query or "trashed=false"
    if parent:
        q = f"'{parent}' in parents and ({q})"
    params = {
        "pageSize": page_size,
        "q": q,
        "fields": _DRIVE_LIST_FIELDS,
    }
    data = _run(
        alias,
        ["drive", "files", "list", "--params", json.dumps(params)],
    )
    files = data.get("files") if isinstance(data, dict) else None
    ownership = [
        {"id": f.get("id"), "name": f.get("name"), **_ownership(f)}
        for f in files
        if isinstance(f, dict)
    ] if isinstance(files, list) else []
    return {"ok": True, "alias": alias, "result": data, "ownership": ownership}


def drive_get(alias: str, file_id: str) -> dict[str, Any]:
    validate_alias(alias)
    if not file_id:
        raise GatewayError("file_id requis", code="error")
    params = {
        "fileId": file_id,
        "fields": _DRIVE_FILE_FIELDS,
    }
    data = _run(
        alias,
        ["drive", "files", "get", "--params", json.dumps(params)],
    )
    return {"ok": True, "alias": alias, "result": data, **_ownership(data)}


def _content_type_for(content_type: str, mime_type: str) -> str:
    """Format du texte envoyé, et donc source de conversion côté Drive."""
    ct = (content_type or "").strip().lower()
    if not ct:
        # Cible Google (Doc/Sheet/Slides) : Drive convertit depuis la source.
        # Markdown par défaut — c'est le format dans lequel les agents rédigent,
        # et titres/listes/gras arrivent rendus dans le document.
        # Cible ordinaire : le texte est déposé tel quel.
        ct = "text/markdown" if mime_type.startswith(_GOOGLE_MIME_PREFIX) else mime_type
    if ct not in _CONTENT_TYPES:
        raise GatewayError(
            f"content_type « {ct} » non supporté — formats texte acceptés : "
            f"{', '.join(sorted(_CONTENT_TYPES))}",
            code="error",
        )
    return ct


@contextmanager
def _spooled_content(content: str, content_type: str) -> Iterator[Path]:
    """Écrit le contenu dans le répertoire de dépôt du broker, le temps d'un appel.

    gws n'accepte un média que par chemin de fichier (`--upload`), et refuse
    tout chemin hors de son répertoire courant — qui est précisément ce
    répertoire de dépôt (ADR-0003). Fichier en 0600, effacé quoi qu'il arrive.
    """
    raw = content.encode("utf-8")
    if len(raw) > _MAX_CONTENT_BYTES:
        raise GatewayError(
            f"contenu trop volumineux ({len(raw)} octets, maximum "
            f"{_MAX_CONTENT_BYTES}) — déposer un fichier plus court",
            code="error",
        )
    fd, tmp = tempfile.mkstemp(
        dir=str(upload_spool()),
        prefix="content-",
        suffix=_CONTENT_TYPES[content_type],
    )
    path = Path(tmp)
    try:
        with os.fdopen(fd, "wb") as fh:
            fh.write(raw)
        yield path
    finally:
        try:
            path.unlink()
        except OSError:
            pass


def drive_create(
    alias: str,
    name: str,
    parent_id: str,
    mime_type: str = "application/vnd.google-apps.document",
    content: str = "",
    content_type: str = "",
) -> dict[str, Any]:
    """Crée un fichier sous parent_id — soumis aux zones Drive (policy + grants).

    Avec `content`, le texte part en upload multipart dans la même requête et
    Drive le convertit vers `mime_type` : un Google Doc rédigé, pas une coquille
    vide. Sans `content`, le fichier est créé vide (comportement historique).
    """
    validate_alias(alias)
    if not name or not parent_id:
        raise GatewayError("name et parent_id sont requis", code="error")
    body = {
        "name": name,
        "mimeType": mime_type,
        # `parents` doit rester dans --json : c'est le seul endroit que
        # scripts/policy-check.py lit pour vérifier la zone d'écriture.
        "parents": [parent_id],
    }
    args = [
        "drive", "files", "create",
        "--params", json.dumps({"fields": _DRIVE_FILE_FIELDS}),
        "--json", json.dumps(body),
    ]
    if not content:
        data = _run(alias, args)
        return {"ok": True, "alias": alias, "result": data, **_ownership(data)}
    ctype = _content_type_for(content_type, mime_type)
    with _spooled_content(content, ctype) as path:
        data = _run(
            alias,
            [*args, "--upload", str(path), "--upload-content-type", ctype],
        )
    return {"ok": True, "alias": alias, "result": data, **_ownership(data)}


def access_request(
    alias: str,
    kind: str,
    folder: str = "",
    hours: int = 8,
    minutes: int = 60,
    email: str = "",
) -> dict[str, Any]:
    """Produit un message d'élicitation — n'exécute jamais unlock/grant/add."""
    validate_alias(alias)
    kind = (kind or "").lower().strip()
    if kind == "add_account":
        # Connexion d'un NOUVEAU compte : l'alias n'existe pas encore (validé
        # en format seulement). Le LLM propose ; l'humain exécute gwsa add
        # (consentement OAuth navigateur + Touch ID si strongauth).
        if not email or "@" not in email:
            raise GatewayError(
                "kind=add_account nécessite email (l'adresse Gmail à connecter)",
                code="error",
            )
        return {
            "ok": True,
            "elicitation": True,
            "kind": "add_account",
            "alias": alias,
            "email": email,
            "message": (
                f"Connexion d'un nouveau compte demandée : « {alias} » ({email}). "
                f"L'utilisateur doit exécuter lui-même :\n"
                f"  gwsa add {alias} {email}\n"
                f"(navigateur → choisir {email} → accepter ; Touch ID d'abord si "
                f"strongauth est activé). Prérequis côté projet GCP : l'adresse doit "
                f"être test user si l'app est en Testing, et recevoir le rôle IAM "
                f"serviceUsageConsumer — vérifier/réparer avec "
                f"« ./scripts/provision-gcp.sh status » puis « sync-iam » "
                f"(docs/setup-oauth.md §7). Le LLM ne doit RIEN exécuter de tout ça."
            ),
            "suggested_command": f"gwsa add {alias} {email}",
        }
    if kind in ("session_unlock", "unlock"):
        mins = max(1, min(int(minutes), 1440))
        sid = get_session_id()
        if sid or kind == "session_unlock":
            if not sid:
                raise GatewayError("session_unlock nécessite une session MCP active", code="error")
            return {
                "ok": True,
                "elicitation": True,
                "kind": "session_unlock",
                "alias": alias,
                "session_id": sid,
                "message": (
                    f"Le profil « {alias} » est verrouillé pour cette session. "
                    f"L'utilisateur doit exécuter :\n"
                    f"  gwsa session unlock {sid} {alias} {mins}\n"
                    f"(déverrouillage limité à cette conversation — {mins} min)."
                ),
                "suggested_command": f"gwsa session unlock {sid} {alias} {mins}",
            }
        return {
            "ok": True,
            "elicitation": True,
            "kind": "unlock",
            "alias": alias,
            "deprecated": True,
            "message": (
                f"Le profil « {alias} » est verrouillé (accès sur demande). "
                f"Depuis une conversation MCP, préférer access_request kind=session_unlock "
                f"(déverrouillage limité à cette session). Sans session MCP active, legacy poste entier :\n"
                f"  gwsa unlock {alias} {mins}\n"
                f"(déprécié — partagé entre toutes les sessions ; admin http://127.0.0.1:4877). "
                f"Le LLM ne doit PAS exécuter cette commande ni contourner le verrou."
            ),
            "suggested_command": f"gwsa unlock {alias} {mins}",
        }
    if kind in ("session_grant", "grant", "project_grant"):
        if not folder:
            raise GatewayError(
                "kind=grant nécessite folder (nom ou ID du dossier Drive)",
                code="error",
            )
        h = max(1, min(int(hours), 168))
        sid = get_session_id()

        if kind == "project_grant":
            if not sid:
                raise GatewayError("project_grant nécessite une session MCP active", code="error")
            from .project import grant_allowed_by_manifest, resolve_project
            from pathlib import Path

            git_root = (get_git_root() or os.environ.get("GWSA_GIT_ROOT", "") or "").strip()
            start = Path(git_root) if git_root else None
            proj = resolve_project(start)
            if not proj.manifest_path:
                return {
                    "ok": True,
                    "elicitation": True,
                    "kind": "project_grant",
                    "alias": alias,
                    "folder": folder,
                    "session_id": sid,
                    "message": (
                        f"Aucun manifeste projet (.gwsa/manifest.json). "
                        f"L'utilisateur doit d'abord :\n"
                        f"  gwsa project init\n"
                        f"  # éditer capabilities.{alias}.drive.zones\n"
                        f"  gwsa project sign\n"
                        f"puis access_request kind=project_grant à nouveau."
                    ),
                    "suggested_command": "gwsa project init",
                }
            if not proj.manifest_valid:
                return {
                    "ok": True,
                    "elicitation": True,
                    "kind": "project_grant",
                    "alias": alias,
                    "folder": folder,
                    "session_id": sid,
                    "message": (
                        f"Manifeste projet présent mais signature invalide "
                        f"({proj.verify_error or 'non signé'}). "
                        f"Exécuter : gwsa project sign"
                    ),
                    "suggested_command": "gwsa project sign",
                }
            # folder peut être un nom — on ne résout pas Drive ici ; on teste si
            # ça ressemble à un id déjà dans le manifeste, sinon on guide quand même
            # vers session grant en rappelant le plafond.
            in_ceiling = grant_allowed_by_manifest(proj.manifest, alias, folder)
            if not in_ceiling:
                return {
                    "ok": True,
                    "elicitation": True,
                    "kind": "project_grant",
                    "alias": alias,
                    "folder": folder,
                    "session_id": sid,
                    "blocked_by_manifest": True,
                    "message": (
                        f"« {folder} » n'est pas dans le plafond manifeste projet "
                        f"pour « {alias} » (.gwsa/manifest.json). "
                        f"L'humain doit éditer capabilities puis « gwsa project sign », "
                        f"ou choisir une zone déjà déclarée. "
                        f"Session grant hors manifeste serait refusé."
                    ),
                    "suggested_command": "gwsa project show",
                }
            return {
                "ok": True,
                "elicitation": True,
                "kind": "project_grant",
                "alias": alias,
                "folder": folder,
                "session_id": sid,
                "message": (
                    f"Zone projet « {folder} » dans le plafond .gwsa/ pour « {alias} ». "
                    f"Pour l'activer sur cette conversation :\n"
                    f'  gwsa session grant {sid} {alias} "{folder}" {h}\n'
                    f"(intersection policy ∩ manifeste ∩ session — {h} h)."
                ),
                "suggested_command": f'gwsa session grant {sid} {alias} "{folder}" {h}',
            }

        if sid or kind == "session_grant":
            if not sid:
                raise GatewayError("session_grant nécessite une session MCP active", code="error")
            return {
                "ok": True,
                "elicitation": True,
                "kind": "session_grant",
                "alias": alias,
                "session_id": sid,
                "folder": folder,
                "message": (
                    f"Écriture Drive sous « {folder} » refusée pour cette session. "
                    f"L'utilisateur doit exécuter :\n"
                    f'  gwsa session grant {sid} {alias} "{folder}" {h}\n'
                    f"(zone valable pour cette conversation seulement — {h} h). "
                    f"Si le dépôt a un .gwsa/ signé, préférer kind=project_grant "
                    f"(vérifie le plafond manifeste)."
                ),
                "suggested_command": f'gwsa session grant {sid} {alias} "{folder}" {h}',
            }
        return {
            "ok": True,
            "elicitation": True,
            "kind": "grant",
            "alias": alias,
            "folder": folder,
            "deprecated": True,
            "message": (
                f"Écriture Drive sous « {folder} » refusée sans zone active. "
                f"Depuis une conversation MCP, préférer access_request kind=session_grant "
                f"ou kind=project_grant (zone limitée à cette session + plafond .gwsa/). "
                f"Sans session MCP active, legacy poste entier :\n"
                f"  gwsa grant {alias} \"{folder}\" {h}\n"
                f"(déprécié — partagé entre toutes les sessions ; admin http://127.0.0.1:4877). "
                f"Expiration automatique — redemander est normal."
            ),
            "suggested_command": f'gwsa grant {alias} "{folder}" {h}',
        }
    raise GatewayError(
        "kind invalide — utiliser « unlock », « grant », « session_unlock », "
        "« session_grant », « project_grant » ou « add_account »",
        code="error",
    )
