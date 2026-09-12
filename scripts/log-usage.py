#!/usr/bin/env python3
"""Journalise une exécution mag dans ~/.config/gws-accounts/usage.jsonl.

Décision « ok » par défaut. Un refus amont (verrou) se journalise en passant
GWSA_LOG_DECISION=refus et GWSA_LOG_REASON=locked dans l'environnement —
même format que les refus écrits par policy-check.py.
"""
import datetime
import json
import os
import sys


def _env(name, default=None):
    """Lecture bi-nom MAG_/GWSA_ (fiche 20260912000249823) — copie locale minimale
    de gateway.config.env(). Ce script feuille reste sans dépendance pour ne jamais
    planter à l'import ; garder aligné avec gateway/config.py:env()."""
    return os.environ.get("MAG_" + name) or os.environ.get("GWSA_" + name) or default


try:
    root, alias, args = sys.argv[1], sys.argv[2], sys.argv[3:]
    entry = {
        "ts": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
        "client": _env("CLIENT", "cli"),
        "alias": alias,
        "cmd": " ".join(args),
        "decision": _env("LOG_DECISION", "ok"),
    }
    sid = _env("SESSION_ID", "")
    if sid:
        entry["session_id"] = sid
    gro = _env("GIT_ROOT", "")
    if gro:
        entry["git_root"] = gro
    reason = _env("LOG_REASON", "")
    if reason:
        entry["reason"] = reason
    # Audit du grain service × opération × ressource (fiche 0076 lot 3, M-08) :
    # posé par gateway.usage.log_usage pour les appels réussis seulement —
    # champs optionnels, un lecteur existant du journal les ignore sans casser.
    service = _env("LOG_SERVICE", "")
    if service:
        entry["service"] = service
    operation = _env("LOG_OPERATION", "")
    if operation:
        entry["operation"] = operation
    resource = _env("LOG_RESOURCE", "")
    if resource:
        entry["resource"] = resource
    with open(os.path.join(root, "usage.jsonl"), "a") as f:
        f.write(json.dumps(entry, ensure_ascii=False) + "\n")
except Exception:
    pass
