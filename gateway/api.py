"""API publique stable de la gateway (consommée par le serveur MCP)."""
from __future__ import annotations

import json
from typing import Any, Optional

from .errors import GatewayError
from .executor import run_gws
from .policy import check_policy, log_ok
from .profiles import list_profiles as _list_profiles
from .profiles import require_unlocked, validate_alias


def profiles_list() -> dict[str, Any]:
    return {"ok": True, "profiles": _list_profiles()}


def _run(alias: str, gws_args: list[str], timeout: int = 60) -> Any:
    d = require_unlocked(alias)
    check_policy(d, gws_args)
    result = run_gws(str(d), gws_args, timeout=timeout)
    log_ok(alias, gws_args)
    return result


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
    data = _run(
        alias,
        ["gmail", "users", "drafts", "create", "--json", json.dumps(payload)],
    )
    return {"ok": True, "alias": alias, "result": data}


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
        "fields": "files(id,name,mimeType,modifiedTime,parents),nextPageToken",
    }
    data = _run(
        alias,
        ["drive", "files", "list", "--params", json.dumps(params)],
    )
    return {"ok": True, "alias": alias, "result": data}


def drive_get(alias: str, file_id: str) -> dict[str, Any]:
    validate_alias(alias)
    if not file_id:
        raise GatewayError("file_id requis", code="error")
    params = {
        "fileId": file_id,
        "fields": "id,name,mimeType,modifiedTime,parents,webViewLink,size",
    }
    data = _run(
        alias,
        ["drive", "files", "get", "--params", json.dumps(params)],
    )
    return {"ok": True, "alias": alias, "result": data}


def drive_create(
    alias: str,
    name: str,
    parent_id: str,
    mime_type: str = "application/vnd.google-apps.document",
) -> dict[str, Any]:
    """Crée un fichier sous parent_id — soumis aux zones Drive (policy + grants)."""
    validate_alias(alias)
    if not name or not parent_id:
        raise GatewayError("name et parent_id sont requis", code="error")
    body = {
        "name": name,
        "mimeType": mime_type,
        "parents": [parent_id],
    }
    data = _run(
        alias,
        ["drive", "files", "create", "--json", json.dumps(body)],
    )
    return {"ok": True, "alias": alias, "result": data}


def access_request(
    alias: str,
    kind: str,
    folder: str = "",
    hours: int = 8,
    minutes: int = 60,
) -> dict[str, Any]:
    """Produit un message d'élicitation — n'exécute jamais unlock/grant."""
    validate_alias(alias)
    kind = (kind or "").lower().strip()
    if kind == "unlock":
        mins = max(1, min(int(minutes), 1440))
        return {
            "ok": True,
            "elicitation": True,
            "kind": "unlock",
            "alias": alias,
            "message": (
                f"Le profil « {alias} » est verrouillé (accès sur demande). "
                f"Pour autoriser l'accès pendant {mins} min, l'utilisateur doit exécuter :\n"
                f"  gwsa unlock {alias} {mins}\n"
                f"ou utiliser l'interface admin http://127.0.0.1:4877 "
                f"(Touch ID si strongauth est activé). "
                f"Le LLM ne doit PAS exécuter cette commande ni contourner le verrou."
            ),
            "suggested_command": f"gwsa unlock {alias} {mins}",
        }
    if kind == "grant":
        if not folder:
            raise GatewayError(
                "kind=grant nécessite folder (nom ou ID du dossier Drive)",
                code="error",
            )
        h = max(1, min(int(hours), 168))
        return {
            "ok": True,
            "elicitation": True,
            "kind": "grant",
            "alias": alias,
            "folder": folder,
            "message": (
                f"Écriture Drive sous « {folder} » refusée sans zone active. "
                f"Pour une autorisation temporaire ({h} h), l'utilisateur doit exécuter :\n"
                f"  gwsa grant {alias} \"{folder}\" {h}\n"
                f"ou via l'admin http://127.0.0.1:4877. Expiration automatique — "
                f"redemander à chaque session est normal."
            ),
            "suggested_command": f'gwsa grant {alias} "{folder}" {h}',
        }
    raise GatewayError(
        "kind invalide — utiliser « unlock » ou « grant »",
        code="error",
    )
