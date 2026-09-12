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

try:
    root, alias, args = sys.argv[1], sys.argv[2], sys.argv[3:]
    entry = {
        "ts": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
        "client": os.environ.get("GWSA_CLIENT", "cli"),
        "alias": alias,
        "cmd": " ".join(args),
        "decision": os.environ.get("GWSA_LOG_DECISION", "ok"),
    }
    sid = os.environ.get("GWSA_SESSION_ID", "")
    if sid:
        entry["session_id"] = sid
    gro = os.environ.get("GWSA_GIT_ROOT", "")
    if gro:
        entry["git_root"] = gro
    reason = os.environ.get("GWSA_LOG_REASON", "")
    if reason:
        entry["reason"] = reason
    # Audit du grain service × opération × ressource (fiche 0076 lot 3, M-08) :
    # posé par gateway.usage.log_usage pour les appels réussis seulement —
    # champs optionnels, un lecteur existant du journal les ignore sans casser.
    service = os.environ.get("GWSA_LOG_SERVICE", "")
    if service:
        entry["service"] = service
    operation = os.environ.get("GWSA_LOG_OPERATION", "")
    if operation:
        entry["operation"] = operation
    resource = os.environ.get("GWSA_LOG_RESOURCE", "")
    if resource:
        entry["resource"] = resource
    with open(os.path.join(root, "usage.jsonl"), "a") as f:
        f.write(json.dumps(entry, ensure_ascii=False) + "\n")
except Exception:
    pass
