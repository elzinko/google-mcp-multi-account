"""Gateway locale unique — porte d'entrée broker-ready vers les comptes Google.

Phase 1 : délègue à gws via GOOGLE_WORKSPACE_CLI_CONFIG_DIR (executor v1).
Phase 2 (hors scope) : remplacer gateway.executor par un broker de tokens ;
les tools MCP et l'API publique de ce package restent stables.
"""
from .api import (
    access_request,
    drive_create,
    drive_get,
    drive_list,
    gmail_create_draft,
    gmail_get,
    gmail_list,
    profiles_list,
)
from .errors import GatewayError

__all__ = [
    "GatewayError",
    "access_request",
    "drive_create",
    "drive_get",
    "drive_list",
    "gmail_create_draft",
    "gmail_get",
    "gmail_list",
    "profiles_list",
]
