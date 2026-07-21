#!/usr/bin/env python3
"""Journalise une exécution gwsa autorisée dans ~/.config/gws-accounts/usage.jsonl."""
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
        "decision": "ok",
    }
    with open(os.path.join(root, "usage.jsonl"), "a") as f:
        f.write(json.dumps(entry, ensure_ascii=False) + "\n")
except Exception:
    pass
