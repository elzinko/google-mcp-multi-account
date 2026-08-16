#!/usr/bin/env python3
"""CLI approbation distante par passkey téléphone — enroll, gate (fiche 0078).

Gabarit : scripts/elicitation-cli.py. Le canal réel (relais aveugle E2E) est
différé (épic 0077) : le POC n'a que `InMemoryChannel`. `gate` accepte
`--response` (fichier JSON de l'assertion déjà signée par le téléphone —
déposée par un simulateur en tests, ou par un futur pont réel) ; sans
`--response`, aucune réponse n'arrive jamais et le gate refuse (fail-closed,
transport non branché).
"""
from __future__ import annotations

import argparse
import json
import os
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, REPO)

from gateway.approval_channel import InMemoryChannel  # noqa: E402
from gateway.remote_approval import (  # noqa: E402
    RemoteApprovalError,
    enroll_phone,
    run_remote_approval_gate,
)


def _channel_with_response(assertion: dict | None) -> InMemoryChannel:
    channel = InMemoryChannel()
    if assertion is None:
        return channel
    original_send = channel.send_challenge

    def send_and_respond(envelope: dict) -> str:
        request_id = original_send(envelope)
        channel.respond(request_id, assertion)
        return request_id

    channel.send_challenge = send_and_respond  # type: ignore[method-assign]
    return channel


def main() -> int:
    p = argparse.ArgumentParser(description="gma approbation distante par passkey")
    sub = p.add_subparsers(dest="cmd", required=True)

    e = sub.add_parser("enroll")
    e.add_argument("--json", required=True, help="registration (credential_id, public_key, uv, be, …)")

    g = sub.add_parser("gate")
    g.add_argument("--json", required=True, help="champs payload (action, alias, session_id, …)")
    g.add_argument("--response", help="fichier JSON : assertion signée par le téléphone (POC)")
    g.add_argument("--timeout", type=int, default=120)

    args = p.parse_args()
    try:
        if args.cmd == "enroll":
            registration = json.loads(args.json)
            enrollment = enroll_phone(registration)
            print(json.dumps(enrollment.to_json(), indent=2, ensure_ascii=False))
            return 0
        if args.cmd == "gate":
            fields = json.loads(args.json)
            assertion = None
            if args.response:
                with open(args.response, encoding="utf-8") as f:
                    assertion = json.load(f)
            channel = _channel_with_response(assertion)
            payload = run_remote_approval_gate(fields, channel, timeout=args.timeout)
            print(json.dumps(payload, ensure_ascii=False))
            return 0
    except RemoteApprovalError as e:
        print(f"approbation distante : {e}", file=sys.stderr)
        return 1
    except json.JSONDecodeError as e:
        print(f"approbation distante : JSON invalide — {e}", file=sys.stderr)
        return 1
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
