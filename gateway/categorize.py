"""Catégorisation service-aware des appels gws (méthode + ressource opérante).

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


# ---------------------------------------------------------------------------
# Ressource OPÉRANTE (revue adverse post-#110, P0 sécu, fiche 0080)
#
# La ressource qui AUTORISE une capacité scopée doit venir d'un mapping
# EXPLICITE (service, mot-clé de ressource, méthode) → nom du VRAI paramètre
# Google — jamais d'une priorité générique sur les clés d'un --params
# contrôlé par l'appelant. Une priorité générique était attaquable : un `id`
# quelconque (ex. l'id d'un AUTRE objet, choisi par l'appelant) passait avant
# le `labelId`/`calendarId` réel, laissant usurper une ressource accordée par
# un leurre dans les mêmes --params.
#
# Si le triplet (service, ressource, méthode) n'a pas d'entrée ici, ou si le
# paramètre mappé est absent/ambigu (tableau à 0 ou >1 élément), l'opérande
# n'est PAS identifiable de façon univoque : on renvoie "" (aucune ressource
# dérivée). Une capacité SCOPÉE (resource non vide) ne matche alors jamais
# "" (fail-closed) ; une capacité NON scopée (service×opération entier)
# n'est pas affectée, comme aujourd'hui.
_OPERAND_PARAM: dict[tuple[str, str, str], tuple[str, str]] = {
    # Gmail : la capacité scope un LIBELLÉ (labelId) — seules les méthodes où
    # l'API porte réellement cet identifiant sont couvertes. « messages get »/
    # « attachments get » n'y figurent PAS à dessein : le message ciblé ne
    # révèle pas son libellé dans --params, l'opérande n'y est pas fiable.
    ("gmail", "messages", "list"): ("labelIds", "array"),
    ("gmail", "messages", "watch"): ("labelIds", "array"),
    ("gmail", "labels", "get"): ("id", "scalar"),
    ("gmail", "labels", "update"): ("id", "scalar"),
    ("gmail", "labels", "patch"): ("id", "scalar"),
    ("gmail", "labels", "delete"): ("id", "scalar"),
    # Calendar : la capacité scope un AGENDA (calendarId) — jamais eventId,
    # qui identifie un sous-objet DANS l'agenda, pas l'agenda lui-même.
    ("calendar", "events", "list"): ("calendarId", "scalar"),
    ("calendar", "events", "get"): ("calendarId", "scalar"),
    ("calendar", "events", "insert"): ("calendarId", "scalar"),
    ("calendar", "events", "update"): ("calendarId", "scalar"),
    ("calendar", "events", "patch"): ("calendarId", "scalar"),
    ("calendar", "events", "delete"): ("calendarId", "scalar"),
    ("calendar", "events", "instances"): ("calendarId", "scalar"),
    ("calendar", "events", "quickadd"): ("calendarId", "scalar"),
    # Drive : audit uniquement (l'autorisation Drive a son propre chemin,
    # `scripts/policy-check.py::check_drive`, qui lit fileId directement —
    # ce mapping ne sert qu'à `gateway/usage.py::infer_call`).
    ("drive", "files", "get"): ("fileId", "scalar"),
    ("drive", "files", "export"): ("fileId", "scalar"),
    ("drive", "files", "download"): ("fileId", "scalar"),
    ("drive", "files", "watch"): ("fileId", "scalar"),
    ("drive", "files", "copy"): ("fileId", "scalar"),
    ("drive", "files", "update"): ("fileId", "scalar"),
    ("drive", "files", "delete"): ("fileId", "scalar"),
    ("drive", "files", "trash"): ("fileId", "scalar"),
    ("drive", "files", "untrash"): ("fileId", "scalar"),
    ("drive", "permissions", "list"): ("fileId", "scalar"),
    ("drive", "permissions", "get"): ("fileId", "scalar"),
    ("drive", "permissions", "create"): ("fileId", "scalar"),
    ("drive", "permissions", "update"): ("fileId", "scalar"),
    ("drive", "permissions", "delete"): ("fileId", "scalar"),
}


def _params_from_args(args: list[str], flag: str) -> dict:
    for i, a in enumerate(args):
        if a == flag and i + 1 < len(args):
            try:
                parsed = json.loads(args[i + 1])
            except Exception:
                return {}
            return parsed if isinstance(parsed, dict) else {}
    return {}


def _operand_entry(service: str, resources: list[str], raw_method: str):
    method = norm(raw_method)
    for keyword in resources:
        entry = _OPERAND_PARAM.get((service, keyword.lower(), method))
        if entry:
            return entry
    return None


def operand_resource(
    service: str, resources: list[str], raw_method: str, args: list[str],
) -> str:
    """Ressource opérante réelle pour (service, resources, méthode), dérivée
    du paramètre EXPLICITEMENT mappé à ce triplet — jamais d'une priorité
    générique. "" si non mappé, absent, ou ambigu (fail-closed pour une
    capacité scopée sur une ressource — cf. `_OPERAND_PARAM` ci-dessus)."""
    entry = _operand_entry(service, resources, raw_method)
    if entry is None:
        return ""
    key, mode = entry
    params = _params_from_args(args, "--params")
    val = params.get(key)
    if mode == "array":
        if isinstance(val, list) and len(val) == 1 and val[0]:
            return str(val[0])
        return ""
    if isinstance(val, (str, int)) and str(val):
        return str(val)
    return ""


def drive_files_trash_override(
    resources: list[str], raw_method: str, operation: str, args: list[str],
) -> str:
    """Reclasse « update » en « delete » pour `drive files update
    {"trashed": true}` (Option A, fiche 0037) — même règle que
    `scripts/policy-check.py::check_drive`, pour que l'audit (`infer_call`)
    suive la même catégorie que l'autorisation (fiche 0080, raffinement P2)."""
    if operation != "update":
        return operation
    if not resources or resources[-1].lower() != "files":
        return operation
    if norm(raw_method) not in UPDATE_METHODS:
        return operation
    body = _params_from_args(args, "--json")
    params = _params_from_args(args, "--params")
    if body.get("trashed") is True or params.get("trashed") is True:
        return "delete"
    return operation
