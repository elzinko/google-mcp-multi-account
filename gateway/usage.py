"""Journal d'usage (usage.jsonl) — même trace que bin/gwsa, via scripts/log-usage.py."""
from __future__ import annotations

import os
import subprocess

from .config import SYS_PYTHON, USAGE_LOGGER, gwsa_root

_READ_METHODS = {
    "list", "get", "export", "download", "search", "query", "getprofile",
    "lookup", "generateids", "instances", "freebusy", "colors", "watch",
    "batchget", "getbatch", "read",
}
_CREATE_METHODS = {
    "create", "insert", "copy", "append", "upload", "import", "add",
    "quickadd", "batchcreate", "push", "subscribe",
}
_UPDATE_METHODS = {
    "update", "patch", "move", "modify", "batchupdate", "batchmodify",
    "rename", "setdefault", "set", "renew", "untrash",
}
_DELETE_METHODS = {
    "delete", "remove", "trash", "batchdelete", "emptytrash", "clear",
    "stop", "revoke",
}
_RESOURCE_KEYS = ("fileId", "id", "calendarId", "labelId")


def infer_call(gws_args: list[str]) -> tuple[str, str, str]:
    """(service, operation, resource) best-effort depuis les args gws bruts.

    Sert l'AUDIT (M-08 / ADR-0007 §Décision 5), pas l'autorisation — le grain
    fin utilisé pour AUTORISER reste `scripts/policy-check.py` (source de
    vérité). Ici on veut juste que le journal des appels réussis porte le même
    triplet service × opération × ressource que les capacités de session,
    sans dupliquer toute la logique de policy.
    """
    if not gws_args:
        return "", "", ""
    service = gws_args[0]
    positionals: list[str] = []
    for a in gws_args[1:]:
        if a.startswith("-"):
            break
        positionals.append(a)
    if not positionals:
        return service, "", ""
    method = positionals[-1].lstrip("+").replace("-", "").replace("_", "").lower()
    if method in _READ_METHODS:
        operation = "read"
    elif method in _CREATE_METHODS:
        operation = "create"
    elif method in _UPDATE_METHODS:
        operation = "update"
    elif method in _DELETE_METHODS:
        operation = "delete"
    elif method == "send" or method.endswith("send"):
        operation = "send"
    else:
        operation = method
    resource = ""
    for i, a in enumerate(gws_args):
        if a == "--params" and i + 1 < len(gws_args):
            try:
                import json

                params = json.loads(gws_args[i + 1])
            except Exception:
                params = {}
            if isinstance(params, dict):
                for key in _RESOURCE_KEYS:
                    if params.get(key):
                        resource = str(params[key])
                        break
            break
    return service, operation, resource


def log_usage(
    alias: str,
    gws_args: list[str],
    client: str,
    decision: str = "ok",
    reason: str = "",
    *,
    session_id: str = "",
    git_root: str = "",
) -> None:
    """Best-effort : ne lève jamais, n'empêche jamais la réponse au client."""
    if not USAGE_LOGGER.is_file():
        return
    python = SYS_PYTHON if os.path.isfile(SYS_PYTHON) else "python3"
    env = dict(os.environ)
    env["GWSA_CLIENT"] = client or "broker"
    env["GWSA_LOG_DECISION"] = decision
    env["GWSA_LOG_REASON"] = reason
    if session_id:
        env["GWSA_SESSION_ID"] = session_id
    if git_root:
        env["GWSA_GIT_ROOT"] = git_root
    # Audit du grain service × opération × ressource pour les appels RÉUSSIS
    # (M-08 / ADR-0007 §Décision 5) — pas seulement les refus.
    if decision == "ok":
        service, operation, resource = infer_call(gws_args)
        if service:
            env["GWSA_LOG_SERVICE"] = service
        if operation:
            env["GWSA_LOG_OPERATION"] = operation
        if resource:
            env["GWSA_LOG_RESOURCE"] = resource
    try:
        subprocess.run(
            [python, str(USAGE_LOGGER), str(gwsa_root()), alias, *gws_args],
            capture_output=True,
            env=env,
            timeout=5,
        )
    except Exception:
        pass
