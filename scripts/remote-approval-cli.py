#!/usr/bin/env python3
"""CLI approbation distante par passkey téléphone — enroll, challenge, verify
(fiche 0078 ; échange en deux temps, fix Codex P1 sur PR #113).

Gabarit : scripts/elicitation-cli.py. Le canal réel (relais aveugle E2E) est
différé (épic 0077) : le POC transporte le défi et la réponse via des
fichiers, en deux invocations SÉPARÉES et hors-process :

  1. `challenge --json <fields>` forge le défi et le PERSISTE (fichier 0600)
     AVANT que quiconque puisse y répondre, puis imprime `{challenge_id,
     envelope}` — c'est cet envelope qu'on publie tel quel au téléphone.
  2. `verify --challenge-id <id> --response <fichier>` charge (et consomme,
     one-shot) le défi publié, vérifie l'assertion signée par le téléphone,
     et imprime le payload SIGNÉ si tout concorde.

L'ancien sous-commande `gate` chargeait la réponse AVANT de forger le défi :
son `client_data` ne pouvait par construction jamais correspondre au nonce
fraîchement généré, donc un vrai téléphone hors-process ne pouvait jamais
produire une réponse valide — seul un canal in-process (`InMemoryChannel`
signant après coup) réussissait. `challenge`/`verify` corrige l'ordre.
"""
from __future__ import annotations

import argparse
import json
import os
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, REPO)

from gateway.remote_approval import (  # noqa: E402
    RemoteApprovalError,
    close_remote_challenge,
    enroll_phone,
    open_remote_challenge,
)


def main() -> int:
    p = argparse.ArgumentParser(description="gma approbation distante par passkey")
    sub = p.add_subparsers(dest="cmd", required=True)

    e = sub.add_parser("enroll")
    e.add_argument("--json", required=True, help="registration (credential_id, public_key, uv, be, …)")

    c = sub.add_parser("challenge")
    c.add_argument("--json", required=True, help="champs payload (action, alias, session_id, …)")

    v = sub.add_parser("verify")
    v.add_argument("--challenge-id", required=True, help="identifiant retourné par `challenge`")
    v.add_argument("--response", required=True, help="fichier JSON : assertion signée par le téléphone")

    args = p.parse_args()
    try:
        if args.cmd == "enroll":
            registration = json.loads(args.json)
            enrollment = enroll_phone(registration)
            print(json.dumps(enrollment.to_json(), indent=2, ensure_ascii=False))
            return 0
        if args.cmd == "challenge":
            fields = json.loads(args.json)
            envelope, challenge_id = open_remote_challenge(fields)
            print(json.dumps(
                {"challenge_id": challenge_id, "envelope": envelope.to_json()},
                ensure_ascii=False,
            ))
            return 0
        if args.cmd == "verify":
            with open(args.response, encoding="utf-8") as f:
                assertion = json.load(f)
            payload = close_remote_challenge(args.challenge_id, assertion)
            print(json.dumps(payload, ensure_ascii=False))
            return 0
    except RemoteApprovalError as e:
        print(f"approbation distante : {e}", file=sys.stderr)
        return 1
    except json.JSONDecodeError as e:
        print(f"approbation distante : JSON invalide — {e}", file=sys.stderr)
        return 1
    except OSError as e:
        print(f"approbation distante : {e}", file=sys.stderr)
        return 1
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
