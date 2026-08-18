"""Catégorisation service-aware des appels gws (méthode + ressource ciblée).

Source de vérité partagée par les deux consommateurs qui doivent s'accorder
sur le même triplet service × opération × ressource (fiche 0080, revue Codex
PR #110) :

- `scripts/policy-check.py` l'utilise pour AUTORISER (capacités de session,
  policy par catégorie) ;
- `gateway/usage.py` l'utilise pour AUDITER les appels réussis, afin que le
  journal identifie la même capacité que celle qui a réellement autorisé
  l'appel (`drafts`, `share`, …), pas seulement le nom de méthode.

Aucune des deux fonctions ne lève : une méthode/ressource non reconnue
retourne None / "" — chaque appelant décide de son propre repli (refus côté
policy, best-effort côté audit).
"""
from __future__ import annotations

import json

READ_METHODS = {
    "list", "get", "export", "download", "search", "query", "getprofile",
    "lookup", "generateids", "instances", "freebusy", "colors", "watch",
    "batchget", "getbatch", "read",
}
CREATE_METHODS = {
    "create", "insert", "copy", "append", "upload", "import", "add",
    "quickadd", "batchcreate", "push", "subscribe",
}
UPDATE_METHODS = {
    "update", "patch", "move", "modify", "batchupdate", "batchmodify",
    "rename", "setdefault", "set", "renew", "untrash",
}
DELETE_METHODS = {
    "delete", "remove", "trash", "batchdelete", "emptytrash", "clear",
    "stop", "revoke",
}
SHARE_RESOURCES = {"permissions", "acl", "members"}

# Ordre de priorité pour dériver la ressource ciblée depuis --params (Drive
# fileId, Calendar calendarId, Gmail labelId — ID générique en repli).
RESOURCE_PARAM_KEYS = ("fileId", "id", "calendarId", "labelId")


def norm(method: str) -> str:
    return method.lstrip("+").replace("-", "").replace("_", "").lower()


def categorize(service: str, resources: list[str], raw_method: str) -> str | None:
    """Catégorie d'action, ou None si inconnue (l'appelant décide du repli)."""
    m = norm(raw_method)
    res = [r.lower() for r in resources]

    if service == "gmail":
        if m == "send" or m.endswith("send") or m in ("reply", "replyall", "forward"):
            return "send"
        if any("settings" in r for r in res):
            return "settings"
        if "drafts" in res and m in ("create", "update"):
            return "drafts"
        if "labels" in res and m not in READ_METHODS:
            return "labels"
        if m in ("triage", "watch"):
            return "read"

    if res and res[0] in SHARE_RESOURCES and m not in READ_METHODS:
        return "share"
    if m in READ_METHODS:
        return "read"
    if m in CREATE_METHODS:
        return "create"
    if m in UPDATE_METHODS:
        return "update"
    if m in DELETE_METHODS:
        return "delete"
    if raw_method.startswith("+"):
        if m in ("agenda", "standupreport", "meetingprep", "weeklydigest"):
            return "read"
        return None
    return None


def resource_from_params(args: list[str], flag: str = "--params") -> str:
    """Ressource ciblée par l'appel, dérivée du flag --params (fileId, id,
    calendarId, labelId…). Best-effort : flag absent/JSON invalide → ""."""
    for i, a in enumerate(args):
        if a == flag and i + 1 < len(args):
            try:
                params = json.loads(args[i + 1])
            except Exception:
                params = {}
            if isinstance(params, dict):
                for key in RESOURCE_PARAM_KEYS:
                    if params.get(key):
                        return str(params[key])
            break
    return ""
