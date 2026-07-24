#!/usr/bin/env python3
"""Journalise une exécution gwsa dans ~/.config/gws-accounts/usage.jsonl.

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
    reason = os.environ.get("GWSA_LOG_REASON", "")
    if reason:
        entry["reason"] = reason
    with open(os.path.join(root, "usage.jsonl"), "a") as f:
        f.write(json.dumps(entry, ensure_ascii=False) + "\n")
except Exception:
    pass
