"""API publique stable de la gateway (consommée par le serveur MCP)."""
from __future__ import annotations

import base64
import hashlib
import json
import mimetypes
import os
import shutil
import tempfile
from collections.abc import Iterator
from contextlib import contextmanager
from pathlib import Path
from typing import Any, Optional

from .config import (
    client_id,
    download_dir,
    gwsa_root,
    profile_dir,
    upload_roots,
    upload_spool,
)
from .context import get_git_root, get_session_id
from .errors import GatewayError
from .executor import run_via_broker
from .profiles import is_locked, list_profiles as _list_profiles
from .profiles import profile_email, require_unlocked, validate_alias
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

# Export texte par défaut selon le type Google (drive_read). Markdown pour un
# Doc (structure conservée), CSV pour un Sheet ; sinon texte brut.
_EXPORT_DEFAULTS = {
    "application/vnd.google-apps.document": "text/markdown",
    "application/vnd.google-apps.spreadsheet": "text/csv",
}
# Types non-Google lisibles tels quels (files get alt=media renvoie du texte).
_TEXTY_MIMES = {"application/json", "application/xml"}
_MAX_READ_CHARS = 1_000_000
# Plafond en octets d'un fichier lu par drive_read : le broker bufferise tout
# stdout en mémoire, donc on refuse AVANT de télécharger (quand la taille est
# connue — fichiers non Google). Les exports Google sont bornés par les limites
# d'export de Drive.
_MAX_READ_BYTES = 25_000_000
_MAX_UPLOAD_BYTES = 50_000_000


def profiles_list() -> dict[str, Any]:
    return {"ok": True, "profiles": _list_profiles()}


def _run(
    alias: str, gws_args: list[str], timeout: int = 60, raw_output: bool = False
) -> Any:
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
    return run_via_broker(alias, gws_args, timeout=timeout, raw_output=raw_output)


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


def _raw_text(data: Any) -> str:
    """Texte verbatim d'une réponse broker `raw_output=True` : le broker garantit
    {"raw": <str>} sans strip ni json.loads — un fichier vide vaut "", un .json
    est rendu tel quel. On ne re-sérialise jamais (ce serait reformater le fichier)."""
    raw = data.get("raw") if isinstance(data, dict) else None
    return raw if isinstance(raw, str) else ""


def _reject_oversize(meta: Any, label: str) -> None:
    """Refuse un fichier trop gros AVANT de le télécharger (le broker bufferise
    tout stdout en mémoire). `size` n'est renseigné que pour les fichiers non
    Google — sans lui, on laisse passer (exports Google bornés par Drive)."""
    size = meta.get("size") if isinstance(meta, dict) else None
    try:
        n = int(size)
    except (TypeError, ValueError):
        return
    if n > _MAX_READ_BYTES:
        raise GatewayError(
            f"« {label} » ({n} octets) dépasse la limite de lecture "
            f"({_MAX_READ_BYTES}) — le récupérer via drive_get / webViewLink",
            code="error",
        )


def drive_read(
    alias: str,
    file_id: str,
    format: str = "",
    max_chars: int = 100_000,
) -> dict[str, Any]:
    """Lit le CONTENU d'un fichier Drive en texte (lecture, sous verrou).

    Fichier Google (Doc/Sheet/…) : export vers un format texte — markdown par
    défaut pour un Doc, CSV pour un Sheet. Fichier ordinaire : téléchargé tel
    quel s'il est textuel. Les binaires (PDF, images) ne sont pas lisibles ici.
    """
    validate_alias(alias)
    if not file_id:
        raise GatewayError("file_id requis", code="error")
    fmt = (format or "").strip().lower()
    if fmt and fmt not in _CONTENT_TYPES:
        raise GatewayError(
            f"format « {fmt} » non supporté — formats texte acceptés : "
            f"{', '.join(sorted(_CONTENT_TYPES))}",
            code="error",
        )
    max_chars = max(1_000, min(int(max_chars), _MAX_READ_CHARS))
    meta = _run(
        alias,
        ["drive", "files", "get", "--params",
         json.dumps({"fileId": file_id, "fields": "id,name,mimeType,size"})],
    )
    mime = (meta.get("mimeType") or "") if isinstance(meta, dict) else ""
    name = (meta.get("name") or "") if isinstance(meta, dict) else ""
    # raw_output=True : le broker renvoie stdout VERBATIM ({"raw": <texte>}),
    # sans strip ni json.loads — sinon une fin de ligne saute, un fichier vide
    # devient "{}", et un .json est reparsé/reformaté (clés dédupliquées).
    if mime.startswith(_GOOGLE_MIME_PREFIX):
        export_mime = fmt or _EXPORT_DEFAULTS.get(mime, "text/plain")
        data = _run(
            alias,
            ["drive", "files", "export", "--params",
             json.dumps({"fileId": file_id, "mimeType": export_mime})],
            raw_output=True,
        )
    elif mime.startswith("text/") or mime in _TEXTY_MIMES:
        _reject_oversize(meta, name or file_id)  # taille connue hors Google
        export_mime = mime
        data = _run(
            alias,
            ["drive", "files", "get", "--params",
             json.dumps({"fileId": file_id, "alt": "media"})],
            raw_output=True,
        )
    else:
        raise GatewayError(
            f"« {name or file_id} » ({mime or 'type inconnu'}) n'est pas lisible "
            f"en texte — drive_read couvre les fichiers Google (export) et les "
            f"fichiers texte",
            code="error",
        )
    content = _raw_text(data)
    truncated = len(content) > max_chars
    return {
        "ok": True,
        "alias": alias,
        "file_id": file_id,
        "name": name,
        "mime_type": mime,
        "export_mime_type": export_mime,
        "content": content[:max_chars],
        "truncated": truncated,
    }


def drive_copy(
    alias: str,
    file_id: str,
    parent_id: str,
    name: str = "",
) -> dict[str, Any]:
    """Copie un fichier Drive vers parent_id — soumis aux zones côté destination.

    Copie native (files.copy) : un Sheet reste un Sheet, un binaire un binaire —
    le cas « dupliquer un modèle vers le dossier client » sans passer par un
    export/recréation.
    """
    validate_alias(alias)
    if not file_id or not parent_id:
        raise GatewayError("file_id et parent_id sont requis", code="error")
    # `parents` dans --json : seul endroit que scripts/policy-check.py lit pour
    # vérifier la zone d'écriture (même règle que drive_create).
    body: dict[str, Any] = {"parents": [parent_id]}
    if name:
        body["name"] = name
    data = _run(
        alias,
        [
            "drive", "files", "copy",
            "--params", json.dumps({"fileId": file_id, "fields": _DRIVE_FILE_FIELDS}),
            "--json", json.dumps(body),
        ],
    )
    return {"ok": True, "alias": alias, "result": data, **_ownership(data)}


def drive_upload(
    alias: str,
    path: str,
    parent_id: str,
    name: str = "",
    mime_type: str = "",
) -> dict[str, Any]:
    """Téléverse un fichier local (binaire compris) — soumis aux zones Drive.

    Le média transite par le répertoire de dépôt du broker (ADR-0003), sans
    conversion : un PDF déposé reste un PDF. Jamais de lecture sous GWSA_ROOT
    (tokens/credentials) — seule exception, le répertoire de téléchargement
    .downloads (re-téléverser une pièce jointe reçue est un cas légitime).
    """
    validate_alias(alias)
    if not path or not parent_id:
        raise GatewayError("path et parent_id sont requis", code="error")
    src = Path(path).expanduser()
    if not src.is_file():
        raise GatewayError(f"fichier introuvable : {src}", code="error")
    resolved = src.resolve()
    root = gwsa_root().resolve()
    dl = download_dir().resolve()
    under_dl = resolved == dl or dl in resolved.parents
    under_root = resolved == root or root in resolved.parents
    # Garde 1 (dur) : jamais les tokens/credentials, même si GWSA_UPLOAD_ROOTS
    # était mal configuré pour englober GWSA_ROOT. Seul .downloads y échappe.
    if under_root and not under_dl:
        raise GatewayError(
            "lecture refusée sous le répertoire des comptes (tokens/credentials) "
            "— seul son sous-répertoire .downloads est re-téléversable",
            code="error",
        )
    # Garde 2 (liste blanche, défaut-deny) : la source doit être .downloads ou
    # un dossier explicitement ouvert dans GWSA_UPLOAD_ROOTS. Sinon le LLM
    # pourrait lire un chemin arbitraire (ex. ~/.ssh/id_rsa) et l'exfiltrer vers
    # une zone Drive active — atteignable par le seul MCP, sans shell (ADR-0006).
    allowed = [dl, *upload_roots()]
    if not any(resolved == a or a in resolved.parents for a in allowed):
        raise GatewayError(
            f"source « {src} » hors des dossiers autorisés au téléversement — "
            f"déposer le fichier dans .downloads, ou déclarer son dossier dans "
            f"<GWSA_ROOT>/.upload-roots (un chemin absolu par ligne) ou la "
            f"variable GWSA_UPLOAD_ROOTS",
            code="error",
        )
    size = src.stat().st_size
    if size > _MAX_UPLOAD_BYTES:
        raise GatewayError(
            f"fichier trop volumineux ({size} octets, maximum {_MAX_UPLOAD_BYTES})",
            code="error",
        )
    mime = mime_type or mimetypes.guess_type(src.name)[0] or "application/octet-stream"
    body = {
        "name": name or src.name,
        # Pas de mimeType dans le corps : aucune conversion, le fichier garde
        # le type du média téléversé.
        "parents": [parent_id],
    }
    args = [
        "drive", "files", "create",
        "--params", json.dumps({"fields": _DRIVE_FILE_FIELDS}),
        "--json", json.dumps(body),
    ]
    # Même contrainte que _spooled_content : gws n'accepte un média que par un
    # chemin sous son cwd = le répertoire de dépôt (ADR-0003).
    fd, tmp = tempfile.mkstemp(
        dir=str(upload_spool()), prefix="upload-", suffix=src.suffix[:16],
    )
    spool = Path(tmp)
    try:
        with os.fdopen(fd, "wb") as out, open(src, "rb") as inp:
            shutil.copyfileobj(inp, out)
        data = _run(
            alias,
            [*args, "--upload", str(spool), "--upload-content-type", mime],
        )
    finally:
        try:
            spool.unlink()
        except OSError:
            pass
    return {
        "ok": True,
        "alias": alias,
        "result": data,
        **_ownership(data),
        "size": size,
        "mime_type": mime,
    }


def _safe_filename(filename: str) -> str:
    """Nom de fichier inoffensif : nom de base seul, jamais caché, jamais vide."""
    base = os.path.basename((filename or "").replace("\\", "/"))
    # Filtrer séparateurs / deux-points / non-imprimables AVANT de retirer les
    # points de tête : sinon un caractère-écran (« :.env », « \x00.bashrc »)
    # masque un point que le filtre promeut ensuite en tête → fichier caché.
    base = "".join(c for c in base if c.isprintable() and c not in '/\\:')
    base = base.strip().lstrip(". ")[:120]
    return base or "piece-jointe.bin"



def drive_update(
    alias: str,
    file_id: str,
    name: str = "",
    content: Optional[str] = None,
    content_type: str = "",
    mime_type: str = "",
) -> dict[str, Any]:
    """Met à jour un fichier Drive (nom et/ou contenu) — soumis aux zones.

    `file_id` doit être sous une zone autorisée. `content=None` = pas de
    changement de contenu ; `content=""` = payload vide (vider le fichier).

    ⚠ Avec un `content`, c'est un **remplacement INTÉGRAL** du contenu (media
    upload), pas une édition partielle. Réservé aux fichiers **non-natifs** :
    un fichier Google natif (Doc/Sheet/Slide) ne s'édite pas par media upload
    (API Docs/Sheets non implémentée) → refus explicite (revue F5).
    """
    validate_alias(alias)
    if not file_id:
        raise GatewayError("file_id requis", code="error")
    if not name and content is None:
        raise GatewayError(
            "au moins un de name ou content est requis", code="error",
        )
    body: dict[str, Any] = {}
    if name:
        body["name"] = name
    if mime_type:
        body["mimeType"] = mime_type
    args = [
        "drive", "files", "update",
        "--params", json.dumps({"fileId": file_id, "fields": _DRIVE_FILE_FIELDS}),
        "--json", json.dumps(body),
    ]
    if content is None:
        data = _run(alias, args)
        return {"ok": True, "alias": alias, "result": data, **_ownership(data)}
    # content = remplacement INTÉGRAL (media upload). On lit d'abord le vrai
    # mimeType : un fichier Google natif ne s'édite pas ainsi (média ≠ contenu
    # structuré) → refus plutôt qu'échec silencieux / corruption d'un binaire
    # (revue F5 / Codex P1). « content » réservé aux fichiers non-natifs.
    current = _run(
        alias,
        ["drive", "files", "get", "--params",
         json.dumps({"fileId": file_id, "fields": "mimeType"})],
    )
    current_mime = current.get("mimeType", "") if isinstance(current, dict) else ""
    if current_mime.startswith("application/vnd.google-apps."):
        raise GatewayError(
            f"drive_update ne peut pas remplacer le contenu d'un fichier Google "
            f"natif ({current_mime}) — édition via l'API Docs/Sheets non "
            f"implémentée ; « content » n'est supporté que sur un fichier non-natif",
            code="error",
        )
    target_mime = mime_type or current_mime or "text/plain"
    ctype = _content_type_for(content_type, target_mime)
    with _spooled_content(content, ctype) as path:
        data = _run(
            alias,
            [*args, "--upload", str(path), "--upload-content-type", ctype],
        )
    return {"ok": True, "alias": alias, "result": data, **_ownership(data)}


_PERMISSION_FIELDS = (
    "id,type,role,emailAddress,displayName,deleted,permissionDetails"
)


def drive_permissions_list(
    alias: str,
    file_id: str,
    page_size: int = 100,
    page_token: str = "",
) -> dict[str, Any]:
    """Liste les permissions d'un fichier (lecture).

    Au-delà de 100 permissions, le résultat porte `nextPageToken` : le rappeler
    via `page_token` pour la page suivante — sinon les permissions au-delà de la
    1ʳᵉ page seraient omises et `drive_permissions_delete` inopérant dessus (F6).
    """
    validate_alias(alias)
    if not file_id:
        raise GatewayError("file_id requis", code="error")
    page_size = max(1, min(int(page_size), 100))
    params = {
        "fileId": file_id,
        "pageSize": page_size,
        "fields": f"permissions({_PERMISSION_FIELDS}),nextPageToken",
    }
    if page_token:
        params["pageToken"] = page_token
    data = _run(
        alias,
        ["drive", "permissions", "list", "--params", json.dumps(params)],
    )
    return {"ok": True, "alias": alias, "result": data}


def drive_permissions_create(
    alias: str,
    file_id: str,
    email: str,
    role: str = "reader",
    transfer_ownership: bool = False,
    send_notification: bool = False,
) -> dict[str, Any]:
    """Partage un fichier ou transfère la propriété (policy share requise).

    `transfer_ownership=true` : le compte courant devient writer, `email` devient
    propriétaire. Action visible — confirmer avec l'humain avant d'appeler.
    """
    validate_alias(alias)
    if not file_id or not email:
        raise GatewayError("file_id et email sont requis", code="error")
    if "@" not in email:
        raise GatewayError("email invalide", code="error")
    role = (role or "reader").lower().strip()
    allowed_roles = {"reader", "commenter", "writer", "owner"}
    if role not in allowed_roles:
        raise GatewayError(
            f"role « {role} » invalide — valeurs : {', '.join(sorted(allowed_roles))}",
            code="error",
        )
    if transfer_ownership:
        if role != "owner":
            raise GatewayError(
                "transfer_ownership exige role=owner", code="error",
            )
    elif role == "owner":
        raise GatewayError(
            "role=owner sans transfer_ownership — utiliser transfer_ownership=true "
            "pour un transfert de propriété explicite",
            code="error",
        )
    params: dict[str, Any] = {
        "fileId": file_id,
        "fields": _PERMISSION_FIELDS,
        "sendNotificationEmail": bool(send_notification),
    }
    if transfer_ownership:
        params["transferOwnership"] = True
        # Google exige une notification pour les transferts de propriété.
        params["sendNotificationEmail"] = True
    body = {
        "type": "user",
        "role": role,
        "emailAddress": email,
    }
    data = _run(
        alias,
        [
            "drive", "permissions", "create",
            "--params", json.dumps(params),
            "--json", json.dumps(body),
        ],
    )
    return {
        "ok": True,
        "alias": alias,
        "result": data,
        "transfer_ownership": transfer_ownership,
    }


def drive_permissions_delete(
    alias: str,
    file_id: str,
    permission_id: str,
) -> dict[str, Any]:
    """Révoque une permission (policy share requise)."""
    validate_alias(alias)
    if not file_id or not permission_id:
        raise GatewayError("file_id et permission_id sont requis", code="error")
    params = {"fileId": file_id, "permissionId": permission_id}
    _run(
        alias,
        ["drive", "permissions", "delete", "--params", json.dumps(params)],
    )
    return {"ok": True, "alias": alias, "deleted": permission_id}

def gmail_attachment_get(
    alias: str,
    message_id: str,
    attachment_id: str,
    filename: str = "",
) -> dict[str, Any]:
    """Télécharge une pièce jointe (lecture, sous verrou) vers .downloads.

    La destination n'est JAMAIS choisie par l'appelant (ADR-0006) : une pièce
    jointe est un contenu tiers, l'écrire sur un chemin arbitraire serait un
    vecteur d'attaque. Noms uniques — jamais d'écrasement.
    """
    validate_alias(alias)
    if not message_id or not attachment_id:
        raise GatewayError("message_id et attachment_id sont requis", code="error")
    params = {"userId": "me", "messageId": message_id, "id": attachment_id}
    data = _run(
        alias,
        ["gmail", "users", "messages", "attachments", "get",
         "--params", json.dumps(params)],
    )
    b64 = data.get("data") if isinstance(data, dict) else None
    if not isinstance(b64, str):
        raise GatewayError(
            "réponse sans données de pièce jointe (message_id / attachment_id "
            "à vérifier via gmail_get)",
            code="exec",
        )
    # b64 == "" est une pièce jointe légitimement vide (0 octet) : on écrit un
    # fichier vide plutôt que d'accuser à tort les identifiants.
    raw = base64.urlsafe_b64decode(b64 + "=" * (-len(b64) % 4))
    base = Path(_safe_filename(filename))
    dest_dir = download_dir()
    for i in range(1000):
        suffix = "" if i == 0 else f"-{i}"
        dest = dest_dir / f"{base.stem}{suffix}{base.suffix}"
        try:
            fd = os.open(dest, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
            break
        except FileExistsError:
            continue
    else:
        raise GatewayError("impossible de créer un nom de fichier unique", code="error")
    with os.fdopen(fd, "wb") as fh:
        fh.write(raw)
    return {
        "ok": True,
        "alias": alias,
        "path": str(dest),
        "filename": dest.name,
        "size": len(raw),
        "sha256": hashlib.sha256(raw).hexdigest(),
    }


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
    # Nommer le compte au moment d'autoriser (fiche 0047) : « alias » (email).
    # L'email (.email, ADR-0002) est lisible même verrouillé ; repli alias seul
    # si inconnu. La commande suggérée garde l'alias nu (c'est la clé).
    acct_email = profile_email(alias)
    who = f"« {alias} » ({acct_email})" if acct_email else f"« {alias} »"
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
                    f"Le profil {who} est verrouillé pour cette session. "
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
                f"Le profil {who} est verrouillé (accès sur demande). "
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
                        f"pour {who} (.gwsa/manifest.json). "
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
                    f"Zone projet « {folder} » dans le plafond .gwsa/ pour {who}. "
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
                    f"Écriture Drive sous « {folder} » refusée pour cette session "
                    f"(compte {who}). "
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
                f"Écriture Drive sous « {folder} » refusée sans zone active "
                f"(compte {who}). "
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
