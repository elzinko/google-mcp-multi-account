"""Serveur MCP stdio (JSON-RPC newline-delimited, spec MCP) — zéro dépendance PyPI.

Tools curatés Gmail + Drive + profils. Pas d'envoi mail. Pas de gwsa_run générique.
"""
from __future__ import annotations

import json
import sys
import traceback
from typing import Any, Callable

from . import api
from .context import set_git_root, set_session_id
from .errors import GatewayError
from .project import git_toplevel
from .sessions import close_session, create_session
from .version import server_version

SERVER_NAME = "google-mcp-multi-account"
SERVER_VERSION = server_version()
PROTOCOL_VERSION = "2024-11-05"


def _ok_text(payload: Any) -> dict:
    text = payload if isinstance(payload, str) else json.dumps(payload, ensure_ascii=False, indent=2)
    return {"content": [{"type": "text", "text": text}], "isError": False}


def _err_text(exc: BaseException) -> dict:
    if isinstance(exc, GatewayError):
        body = exc.to_dict()
    else:
        body = {"ok": False, "code": "error", "error": str(exc)}
    return {
        "content": [{"type": "text", "text": json.dumps(body, ensure_ascii=False, indent=2)}],
        "isError": True,
    }


def _call(fn: Callable, arguments: dict) -> dict:
    try:
        return _ok_text(fn(**arguments))
    except TypeError as e:
        return _err_text(GatewayError(f"arguments invalides : {e}", code="error"))
    except GatewayError as e:
        return _err_text(e)
    except Exception as e:
        return _err_text(e)


TOOLS: list[dict[str, Any]] = [
    {
        "name": "profiles_list",
        "description": (
            "Liste les profils Google locaux (alias), état connecté/verrouillé, "
            "services couverts par la policy. Appeler en premier pour choisir un alias."
        ),
        "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
    },
    {
        "name": "gmail_list",
        "description": "Liste des messages Gmail du profil alias (lecture). Pas d'envoi.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "alias": {"type": "string", "description": "Profil gwsa (ex. perso)"},
                "query": {"type": "string", "description": "Requête Gmail (ex. is:unread)", "default": ""},
                "max_results": {"type": "integer", "description": "1–50", "default": 10},
            },
            "required": ["alias"],
            "additionalProperties": False,
        },
    },
    {
        "name": "gmail_get",
        "description": "Lit un message Gmail par id (lecture). Pas d'envoi.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "alias": {"type": "string"},
                "message_id": {"type": "string"},
                "format": {
                    "type": "string",
                    "enum": ["full", "metadata", "minimal", "raw"],
                    "default": "full",
                },
            },
            "required": ["alias", "message_id"],
            "additionalProperties": False,
        },
    },
    {
        "name": "gmail_draft_create",
        "description": (
            "Crée un brouillon Gmail (to, subject, body). N'envoie JAMAIS le mail — "
            "l'humain envoie depuis Gmail ou élargit la policy."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "alias": {"type": "string"},
                "to": {"type": "string"},
                "subject": {"type": "string"},
                "body": {"type": "string"},
                "cc": {"type": "string", "default": ""},
            },
            "required": ["alias", "to", "subject", "body"],
            "additionalProperties": False,
        },
    },
    {
        "name": "drive_list",
        "description": (
            "Liste des fichiers Drive (lecture). Filtre optionnel parent / query. "
            "Renvoie `ownership` : le propriétaire de chaque fichier "
            "(owner, owned_by_me) — pour vérifier qu'un livrable est bien sur le "
            "bon compte."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "alias": {"type": "string"},
                "query": {"type": "string", "default": "trashed=false"},
                "page_size": {"type": "integer", "default": 20},
                "parent": {"type": "string", "description": "ID dossier parent optionnel"},
            },
            "required": ["alias"],
            "additionalProperties": False,
        },
    },
    {
        "name": "drive_get",
        "description": (
            "Métadonnées d'un fichier Drive par file_id (lecture), propriétaire "
            "compris : `owner` (email) et `owned_by_me` (null = non renseigné "
            "par Drive, cas des Drive partagés)."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "alias": {"type": "string"},
                "file_id": {"type": "string"},
            },
            "required": ["alias", "file_id"],
            "additionalProperties": False,
        },
    },
    {
        "name": "drive_create",
        "description": (
            "Crée un fichier Drive sous parent_id, avec son contenu si `content` "
            "est fourni : le texte (markdown par défaut) est converti en Google "
            "Doc rédigé — sans `content`, le fichier est créé vide. Renvoie le "
            "propriétaire (`owner`, `owned_by_me`) pour vérifier le dépôt. "
            "Soumis aux zones (policy + grants) ; si refusé : appeler "
            "access_request kind=grant."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "alias": {"type": "string"},
                "name": {"type": "string"},
                "parent_id": {"type": "string", "description": "ID du dossier parent autorisé"},
                "mime_type": {
                    "type": "string",
                    "default": "application/vnd.google-apps.document",
                },
                "content": {
                    "type": "string",
                    "description": (
                        "Contenu texte du document (markdown recommandé : titres, "
                        "listes et gras arrivent rendus). Vide = fichier vide."
                    ),
                },
                "content_type": {
                    "type": "string",
                    "enum": ["text/markdown", "text/plain", "text/html", "text/csv"],
                    "description": (
                        "Format de `content`. Par défaut text/markdown quand la "
                        "cible est un type Google."
                    ),
                },
            },
            "required": ["alias", "name", "parent_id"],
            "additionalProperties": False,
        },
    },
    {
        "name": "setup_status",
        "description": (
            "État agrégé du setup (LECTURE SEULE) : projet GCP, publication, "
            "client_secret, et pour chaque compte connecté son accès IAM "
            "(ok/missing/unknown). Renvoie `next_actions` : les commandes exactes "
            "à faire exécuter par l'utilisateur pour compléter/réparer le setup "
            "(le LLM les propose, ne les lance jamais). À utiliser pour guider "
            "l'onboarding ou diagnostiquer un 403/verrou."
        ),
        "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False},
    },
    {
        "name": "access_request",
        "description": (
            "Demande d'élicitation humaine : kind=unlock (profil verrouillé), "
            "kind=grant (zone Drive temporaire) ou kind=add_account (connecter un "
            "nouveau compte Google — alias inexistant + email requis). N'exécute "
            "RIEN — renvoie la commande exacte à faire exécuter par l'utilisateur."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "alias": {"type": "string"},
                "kind": {"type": "string", "enum": ["unlock", "grant", "add_account", "session_unlock", "session_grant"]},
                "folder": {"type": "string", "description": "Nom ou ID dossier (si grant)"},
                "hours": {"type": "integer", "default": 8, "description": "Durée grant"},
                "minutes": {"type": "integer", "default": 60, "description": "Durée unlock"},
                "email": {"type": "string", "description": "Adresse Gmail à connecter (si add_account)"},
            },
            "required": ["alias", "kind"],
            "additionalProperties": False,
        },
    },
]

DISPATCH: dict[str, Callable] = {
    "profiles_list": lambda **_: api.profiles_list(),
    "setup_status": lambda **_: api.setup_status(),
    "gmail_list": lambda **kw: api.gmail_list(
        alias=kw["alias"],
        query=kw.get("query") or "",
        max_results=int(kw.get("max_results") or 10),
    ),
    "gmail_get": lambda **kw: api.gmail_get(
        alias=kw["alias"],
        message_id=kw["message_id"],
        format=kw.get("format") or "full",
    ),
    "gmail_draft_create": lambda **kw: api.gmail_create_draft(
        alias=kw["alias"],
        to=kw["to"],
        subject=kw["subject"],
        body=kw.get("body") or "",
        cc=kw.get("cc") or "",
    ),
    "drive_list": lambda **kw: api.drive_list(
        alias=kw["alias"],
        query=kw.get("query") or "trashed=false",
        page_size=int(kw.get("page_size") or 20),
        parent=kw.get("parent") or None,
    ),
    "drive_get": lambda **kw: api.drive_get(alias=kw["alias"], file_id=kw["file_id"]),
    "drive_create": lambda **kw: api.drive_create(
        alias=kw["alias"],
        name=kw["name"],
        parent_id=kw["parent_id"],
        mime_type=kw.get("mime_type") or "application/vnd.google-apps.document",
        content=kw.get("content") or "",
        content_type=kw.get("content_type") or "",
    ),
    "access_request": lambda **kw: api.access_request(
        alias=kw["alias"],
        kind=kw["kind"],
        folder=kw.get("folder") or "",
        hours=int(kw.get("hours") or 8),
        minutes=int(kw.get("minutes") or 60),
        email=kw.get("email") or "",
    ),
}


def _write(msg: dict) -> None:
    sys.stdout.write(json.dumps(msg, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def _handle(msg: dict) -> None:
    mid = msg.get("id")
    method = msg.get("method")
    params = msg.get("params") or {}

    # Notifications (pas de réponse)
    if mid is None and method:
        return

    if method == "initialize":
        state = create_session(client=SERVER_NAME)
        set_session_id(state.session_id)
        root = git_toplevel()
        if root:
            set_git_root(root)
        _write({
            "jsonrpc": "2.0",
            "id": mid,
            "result": {
                "protocolVersion": PROTOCOL_VERSION,
                "capabilities": {"tools": {"listChanged": False}},
                "serverInfo": {
                    "name": SERVER_NAME,
                    "version": SERVER_VERSION,
                    "session_id": state.session_id,
                },
            },
        })
        return

    if method == "ping":
        _write({"jsonrpc": "2.0", "id": mid, "result": {}})
        return

    if method == "tools/list":
        _write({"jsonrpc": "2.0", "id": mid, "result": {"tools": TOOLS}})
        return

    if method == "tools/call":
        name = params.get("name") or ""
        arguments = params.get("arguments") or {}
        if not isinstance(arguments, dict):
            arguments = {}
        fn = DISPATCH.get(name)
        if not fn:
            _write({
                "jsonrpc": "2.0",
                "id": mid,
                "result": _err_text(GatewayError(f"tool inconnu : {name}", code="error")),
            })
            return
        _write({"jsonrpc": "2.0", "id": mid, "result": _call(fn, arguments)})
        return

    if method == "resources/list":
        _write({"jsonrpc": "2.0", "id": mid, "result": {"resources": []}})
        return

    if method == "prompts/list":
        _write({"jsonrpc": "2.0", "id": mid, "result": {"prompts": []}})
        return

    _write({
        "jsonrpc": "2.0",
        "id": mid,
        "error": {"code": -32601, "message": f"Method not found: {method}"},
    })


def main() -> None:
    # stderr pour logs — stdout réservé au JSON-RPC
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            sys.stderr.write(f"gateway-mcp : JSON invalide ignoré\n")
            continue
        try:
            _handle(msg)
        except Exception:
            traceback.print_exc(file=sys.stderr)
            mid = msg.get("id") if isinstance(msg, dict) else None
            if mid is not None:
                _write({
                    "jsonrpc": "2.0",
                    "id": mid,
                    "error": {"code": -32603, "message": "internal error"},
                })


if __name__ == "__main__":
    main()
