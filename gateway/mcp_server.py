"""Serveur MCP stdio (JSON-RPC newline-delimited, spec MCP) — zéro dépendance PyPI.

Tools curatés Gmail + Drive + profils. Pas d'envoi mail. Pas de gwsa_run générique.
"""
from __future__ import annotations

import json
import sys
import traceback
from typing import Any, Callable

from . import api
from .context import set_git_root
from .errors import GatewayError
from .project import git_toplevel
from .sessions import create_session
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


# Jeton de session porté par CHAQUE appel (ADR-0007 §Décision 2) : lu au
# tools/call, jamais posé en global de process. Deux conversations sur une
# même connexion MCP (Claude Desktop) obtiennent chacune leur jeton (renvoyé
# par `initialize`, ou par `access_request`) et restent isolées.
_SESSION_PROPERTY: dict[str, Any] = {
    "type": "string",
    "description": (
        "Jeton de session porté par cet appel (session_id renvoyé par "
        "initialize, ou par access_request). Sans jeton valide : accès refusé."
    ),
}

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
                "session": _SESSION_PROPERTY,
            },
            "required": ["alias", "session"],
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
                "session": _SESSION_PROPERTY,
            },
            "required": ["alias", "message_id", "session"],
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
                "session": _SESSION_PROPERTY,
            },
            "required": ["alias", "to", "subject", "body", "session"],
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
                "session": _SESSION_PROPERTY,
            },
            "required": ["alias", "session"],
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
                "session": _SESSION_PROPERTY,
            },
            "required": ["alias", "file_id", "session"],
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
            "access_request kind=session_grant (ou kind=grant legacy poste entier)."
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
                "session": _SESSION_PROPERTY,
            },
            "required": ["alias", "name", "parent_id", "session"],
            "additionalProperties": False,
        },
    },
    {
        "name": "drive_read",
        "description": (
            "Lit le CONTENU d'un fichier Drive en texte (lecture, sous verrou "
            "comme drive_get). Fichier Google : export texte — markdown par "
            "défaut pour un Doc, CSV pour un Sheet. Fichier ordinaire : renvoyé "
            "tel quel s'il est textuel ; les binaires (PDF, images) ne sont pas "
            "lisibles ici. Sert à relire un document déposé ou un modèle avant "
            "de le copier."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "alias": {"type": "string"},
                "file_id": {"type": "string"},
                "format": {
                    "type": "string",
                    "enum": ["text/markdown", "text/plain", "text/html", "text/csv"],
                    "description": "Format d'export souhaité (fichiers Google seulement)",
                },
                "max_chars": {
                    "type": "integer",
                    "default": 100000,
                    "description": "Troncature du contenu renvoyé (1 000–1 000 000)",
                },
                "session": _SESSION_PROPERTY,
            },
            "required": ["alias", "file_id", "session"],
            "additionalProperties": False,
        },
    },
    {
        "name": "drive_copy",
        "description": (
            "Copie NATIVE d'un fichier Drive (files.copy) vers un dossier de "
            "zone : un Sheet reste un Sheet, un binaire un binaire — pour "
            "dupliquer un modèle vers le dossier client. Soumis aux zones côté "
            "destination (policy + grants) ; si refusé : access_request "
            "kind=session_grant. Renvoie le propriétaire (owner, owned_by_me)."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "alias": {"type": "string"},
                "file_id": {"type": "string", "description": "Fichier source à copier"},
                "parent_id": {"type": "string", "description": "ID du dossier destination autorisé"},
                "name": {"type": "string", "description": "Nom de la copie (défaut : celui de Drive)"},
                "session": _SESSION_PROPERTY,
            },
            "required": ["alias", "file_id", "parent_id", "session"],
            "additionalProperties": False,
        },
    },
    {
        "name": "drive_upload",
        "description": (
            "Téléverse un fichier LOCAL (binaire compris — PDF, image) sous "
            "parent_id, sans conversion : un PDF déposé reste un PDF. Soumis "
            "aux zones (policy + grants) comme drive_create ; si refusé : "
            "access_request kind=session_grant. La SOURCE locale doit être dans "
            ".downloads ou un dossier de la liste blanche (fichier "
            "<GWSA_ROOT>/.upload-roots ou variable GWSA_UPLOAD_ROOTS) — jamais "
            "un chemin arbitraire. Renvoie le propriétaire du fichier créé."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "alias": {"type": "string"},
                "path": {"type": "string", "description": "Chemin local du fichier à téléverser"},
                "parent_id": {"type": "string", "description": "ID du dossier parent autorisé"},
                "name": {"type": "string", "description": "Nom sur Drive (défaut : nom du fichier)"},
                "mime_type": {"type": "string", "description": "Type MIME (défaut : deviné de l'extension)"},
                "session": _SESSION_PROPERTY,
            },
            "required": ["alias", "path", "parent_id", "session"],
            "additionalProperties": False,
        },
    },
    {
        "name": "gmail_attachment_get",
        "description": (
            "Télécharge une pièce jointe d'un message Gmail (lecture, sous "
            "verrou). attachment_id vient de gmail_get (payload.parts[].body."
            "attachmentId). Le fichier est écrit dans le répertoire de "
            "téléchargement local dédié (jamais un chemin arbitraire, jamais "
            "d'écrasement) et son chemin est renvoyé."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "alias": {"type": "string"},
                "message_id": {"type": "string"},
                "attachment_id": {"type": "string"},
                "filename": {"type": "string", "description": "Nom de fichier souhaité (assaini, unifié)"},
                "session": _SESSION_PROPERTY,
            },
            "required": ["alias", "message_id", "attachment_id", "session"],
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
        "name": "drive_update",
        "description": (
            "Met à jour un fichier Drive (renommage et/ou contenu texte). "
            "Soumis aux zones (policy + grants). Au moins un de name ou content "
            "est requis. Si refusé : access_request kind=session_grant."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "alias": {"type": "string"},
                "file_id": {"type": "string"},
                "name": {"type": "string", "description": "Nouveau nom (optionnel)"},
                "content": {
                    "type": "string",
                    "description": "Nouveau contenu texte (optionnel, upload multipart)",
                },
                "content_type": {
                    "type": "string",
                    "enum": ["text/markdown", "text/plain", "text/html", "text/csv"],
                },
                "mime_type": {
                    "type": "string",
                    "description": "Type MIME cible si content fourni",
                },
                "session": _SESSION_PROPERTY,
            },
            "required": ["alias", "file_id", "session"],
            "additionalProperties": False,
        },
    },
    {
        "name": "drive_permissions_list",
        "description": (
            "Liste les permissions (partages) d'un fichier Drive (lecture). "
            "Utile avant/après partage ou transfert de propriété."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "alias": {"type": "string"},
                "file_id": {"type": "string"},
                "page_size": {"type": "integer", "default": 100},
                "page_token": {
                    "type": "string",
                    "description": "Jeton de page suivante (nextPageToken du résultat précédent) — au-delà de 100 permissions",
                },
                "session": _SESSION_PROPERTY,
            },
            "required": ["alias", "file_id", "session"],
            "additionalProperties": False,
        },
    },
    {
        "name": "drive_permissions_create",
        "description": (
            "Partage un fichier avec un utilisateur (reader/commenter/writer). "
            "Nécessite drive.share:true dans la policy. Action visible — confirmer "
            "avec l'humain avant d'appeler. (Transfert de propriété : hors de cette "
            "version, PR dédiée non prête.)"
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "alias": {"type": "string", "description": "Profil propriétaire"},
                "file_id": {"type": "string"},
                "email": {"type": "string", "description": "Destinataire du partage"},
                "role": {
                    "type": "string",
                    "enum": ["reader", "commenter", "writer"],
                    "default": "reader",
                },
                "send_notification": {
                    "type": "boolean",
                    "default": False,
                    "description": "Envoyer un email de notification au destinataire",
                },
                "session": _SESSION_PROPERTY,
            },
            "required": ["alias", "file_id", "email", "session"],
            "additionalProperties": False,
        },
    },
    {
        "name": "drive_permissions_delete",
        "description": (
            "Révoque une permission sur un fichier (policy share requise). "
            "permission_id vient de drive_permissions_list."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "alias": {"type": "string"},
                "file_id": {"type": "string"},
                "permission_id": {"type": "string"},
                "session": _SESSION_PROPERTY,
            },
            "required": ["alias", "file_id", "permission_id", "session"],
            "additionalProperties": False,
        },
    },
    {
        "name": "access_request",
        "description": (
            "Demande d'élicitation humaine : kind=session_unlock / session_grant / "
            "project_grant (cette conversation MCP ; project_grant vérifie le plafond "
            ".gwsa/), kind=unlock / kind=grant (legacy poste entier, déprécié), ou "
            "kind=add_account (nouveau compte — alias inexistant + email). "
            "N'exécute RIEN — renvoie la commande exacte à faire exécuter par l'utilisateur."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "alias": {"type": "string"},
                "kind": {
                    "type": "string",
                    "enum": [
                        "unlock", "grant", "add_account",
                        "session_unlock", "session_grant", "project_grant",
                    ],
                },
                "folder": {"type": "string", "description": "Nom ou ID dossier (si grant)"},
                "hours": {"type": "integer", "default": 8, "description": "Durée grant"},
                "minutes": {"type": "integer", "default": 60, "description": "Durée unlock"},
                "email": {"type": "string", "description": "Adresse Gmail à connecter (si add_account)"},
                "session": {
                    "type": "string",
                    "description": (
                        "Jeton de session (requis pour kind=session_unlock / "
                        "session_grant / project_grant — inutile pour les kinds "
                        "legacy poste entier ou add_account)."
                    ),
                },
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
        session=kw.get("session") or "",
    ),
    "gmail_get": lambda **kw: api.gmail_get(
        alias=kw["alias"],
        message_id=kw["message_id"],
        format=kw.get("format") or "full",
        session=kw.get("session") or "",
    ),
    "gmail_draft_create": lambda **kw: api.gmail_create_draft(
        alias=kw["alias"],
        to=kw["to"],
        subject=kw["subject"],
        body=kw.get("body") or "",
        cc=kw.get("cc") or "",
        session=kw.get("session") or "",
    ),
    "drive_list": lambda **kw: api.drive_list(
        alias=kw["alias"],
        query=kw.get("query") or "trashed=false",
        page_size=int(kw.get("page_size") or 20),
        parent=kw.get("parent") or None,
        session=kw.get("session") or "",
    ),
    "drive_get": lambda **kw: api.drive_get(
        alias=kw["alias"], file_id=kw["file_id"], session=kw.get("session") or "",
    ),
    "drive_read": lambda **kw: api.drive_read(
        alias=kw["alias"],
        file_id=kw["file_id"],
        format=kw.get("format") or "",
        max_chars=int(kw.get("max_chars") or 100_000),
        session=kw.get("session") or "",
    ),
    "drive_copy": lambda **kw: api.drive_copy(
        alias=kw["alias"],
        file_id=kw["file_id"],
        parent_id=kw["parent_id"],
        name=kw.get("name") or "",
        session=kw.get("session") or "",
    ),
    "drive_upload": lambda **kw: api.drive_upload(
        alias=kw["alias"],
        path=kw["path"],
        parent_id=kw["parent_id"],
        name=kw.get("name") or "",
        mime_type=kw.get("mime_type") or "",
        session=kw.get("session") or "",
    ),
    "gmail_attachment_get": lambda **kw: api.gmail_attachment_get(
        alias=kw["alias"],
        message_id=kw["message_id"],
        attachment_id=kw["attachment_id"],
        filename=kw.get("filename") or "",
        session=kw.get("session") or "",
    ),
    "drive_create": lambda **kw: api.drive_create(
        alias=kw["alias"],
        name=kw["name"],
        parent_id=kw["parent_id"],
        mime_type=kw.get("mime_type") or "application/vnd.google-apps.document",
        content=kw.get("content") or "",
        content_type=kw.get("content_type") or "",
        session=kw.get("session") or "",
    ),
    "drive_update": lambda **kw: api.drive_update(
        alias=kw["alias"],
        file_id=kw["file_id"],
        name=kw.get("name") or "",
        # Distinguer absent (None) de "" (vider le fichier) — ne pas faire `or ""`.
        content=kw["content"] if "content" in kw else None,
        content_type=kw.get("content_type") or "",
        mime_type=kw.get("mime_type") or "",
        session=kw.get("session") or "",
    ),
    "drive_permissions_list": lambda **kw: api.drive_permissions_list(
        alias=kw["alias"],
        file_id=kw["file_id"],
        page_size=int(kw.get("page_size") or 100),
        page_token=kw.get("page_token") or "",
        session=kw.get("session") or "",
    ),
    "drive_permissions_create": lambda **kw: api.drive_permissions_create(
        alias=kw["alias"],
        file_id=kw["file_id"],
        email=kw["email"],
        role=kw.get("role") or "reader",
        # Valeur BRUTE (pas de bool() permissif) : l'API rejette tout non-booléen.
        send_notification=kw.get("send_notification", False),
        session=kw.get("session") or "",
    ),
    "drive_permissions_delete": lambda **kw: api.drive_permissions_delete(
        alias=kw["alias"],
        file_id=kw["file_id"],
        permission_id=kw["permission_id"],
        session=kw.get("session") or "",
    ),
    "access_request": lambda **kw: api.access_request(
        alias=kw["alias"],
        kind=kw["kind"],
        folder=kw.get("folder") or "",
        hours=int(kw.get("hours") or 8),
        minutes=int(kw.get("minutes") or 60),
        email=kw.get("email") or "",
        session=kw.get("session") or "",
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
    # stderr pour logs — stdout réservé au JSON-RPC.
    #
    # Cycle de vie découplé de la connexion (ADR-0007 §Décision 5) : la
    # déconnexion stdio n'est PAS un signal de cycle de vie — les jetons sont
    # au porteur et le protocole MCP ne transmet aucun identifiant de
    # conversation, donc le serveur ne peut pas savoir à la déconnexion quels
    # jetons appartiennent à quelle conversation. Aucune purge ici : fin de vie
    # = TTL (gateway.sessions.purge_expired, câblée au broker) ou révocation
    # explicite (`gma session close` / `revoke-descendants`).
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            sys.stderr.write("gateway-mcp : JSON invalide ignoré\n")
            continue
        try:
            if isinstance(msg, dict) and msg.get("method") == "initialize":
                mid = msg.get("id")
                # `create_session` amorce une session par défaut pour cette
                # connexion (compat) ; le jeton n'est PLUS posé en global — le
                # client doit le PORTER dans chaque tools/call (paramètre
                # `session`). Le bootstrap sans jeton (élicitation de création)
                # relève d'un lot ultérieur (fiche 0076, hors périmètre ici).
                state = create_session(client=SERVER_NAME)
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
                continue
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
