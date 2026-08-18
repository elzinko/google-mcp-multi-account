"""Journal d'usage (usage.jsonl) — même trace que bin/mag, via scripts/log-usage.py."""
from __future__ import annotations

import os
import subprocess

from .categorize import (
    CREATE_METHODS,
    DELETE_METHODS,
    READ_METHODS,
    categorize,
    drive_files_trash_override,
    norm,
    operand_resource,
)
from .config import SYS_PYTHON, USAGE_LOGGER, gwsa_root


def _fallback_operation(method: str) -> str:
    """Repli quand `categorize` ne reconnaît pas la méthode (best-effort audit,
    jamais un refus — contrairement à policy-check.py, l'audit ne bloque rien)."""
    if method in READ_METHODS:
        return "read"
    if method in CREATE_METHODS:
        return "create"
    if method in DELETE_METHODS:
        return "delete"
    if method == "send" or method.endswith("send"):
        return "send"
    return method


def infer_call(gws_args: list[str]) -> tuple[str, str, str]:
    """(service, operation, resource) best-effort depuis les args gws bruts.

    Sert l'AUDIT (M-08 / ADR-0007 §Décision 5), pas l'autorisation — le grain
    fin utilisé pour AUTORISER reste `scripts/policy-check.py` (source de
    vérité). L'opération réutilise la MÊME catégorisation service-aware que le
    contrôleur de policy (`gateway.categorize.categorize` : `drafts`, `share`,
    …) — pas seulement le nom de méthode —, y compris le reclassement
    « update » → « delete » d'un `drive files update {trashed:true}` (Option A,
    fiche 0037), pour que le triplet journalisé identifie la capacité qui a
    réellement autorisé l'appel (fiche 0080, revue Codex PR #110
    raffinement #3 + revue adverse P2). La ressource vient du même mapping
    explicite (service, ressource, méthode) → paramètre que `policy-check.py`
    (raffinement #1 / P0) — jamais d'une priorité générique.
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
    resources, raw_method = positionals[:-1], positionals[-1]
    operation = categorize(service, resources, raw_method) or _fallback_operation(norm(raw_method))
    operation = drive_files_trash_override(resources, raw_method, operation, gws_args)
    resource = operand_resource(service, resources, raw_method, gws_args)
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
