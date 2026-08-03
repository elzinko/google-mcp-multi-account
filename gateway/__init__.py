"""Gateway locale unique — porte d'entrée broker-ready vers les comptes Google.

Phase 2 A : toute exécution gws passe par le broker loopback
(gateway.executor → broker_server) — jamais de subprocess gws ailleurs dans
ce package (ADR-0002). L'API publique et les tools MCP restent stables.
"""
from .api import (
    access_request,
    drive_copy,
    drive_create,
    drive_get,
    drive_list,
    drive_permissions_create,
    drive_permissions_delete,
    drive_permissions_list,
    drive_read,
    drive_update,
    drive_upload,
    gmail_attachment_get,
    gmail_create_draft,
    gmail_get,
    gmail_list,
    profiles_list,
)
from .errors import GatewayError

__all__ = [
    "GatewayError",
    "access_request",
    "drive_copy",
    "drive_create",
    "drive_get",
    "drive_list",
    "drive_permissions_create",
    "drive_permissions_delete",
    "drive_permissions_list",
    "drive_read",
    "drive_update",
    "drive_upload",
    "gmail_attachment_get",
    "gmail_create_draft",
    "gmail_get",
    "gmail_list",
    "profiles_list",
]
