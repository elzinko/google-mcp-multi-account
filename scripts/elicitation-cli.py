#!/usr/bin/env python3
"""CLI élicitation signée — enroll, status, gate (appelé par bin/gwsa)."""
from __future__ import annotations

import argparse
import json
import os
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, REPO)

from gateway.elicitation import (  # noqa: E402
    ElicitationError,
    enroll_mock,
    enroll_secure,
    run_elicitation_gate,
    status,
)


def main() -> int:
    p = argparse.ArgumentParser(description="gwsa élicitation signée")
    sub = p.add_subparsers(dest="cmd", required=True)

    sub.add_parser("status")
    e = sub.add_parser("enroll")
    e.add_argument("--mock", action="store_true", help="clé HMAC test (CI/Linux)")

    g = sub.add_parser("gate")
    g.add_argument("--json", required=True, help="champs payload (action, alias, …)")

    args = p.parse_args()
    try:
        if args.cmd == "status":
            print(json.dumps(status(), indent=2, ensure_ascii=False))
            return 0
        if args.cmd == "enroll":
            if args.mock or os.environ.get("GWSA_ELICITATION_MOCK"):
                print(json.dumps(enroll_mock(), indent=2))
            else:
                print(json.dumps(enroll_secure(), indent=2))
            return 0
        if args.cmd == "gate":
            fields = json.loads(args.json)
            run_elicitation_gate(fields)
            return 0
    except ElicitationError as e:
        print(f"elicitation : {e}", file=sys.stderr)
        return 1
    except json.JSONDecodeError as e:
        print(f"elicitation : JSON invalide — {e}", file=sys.stderr)
        return 1
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
