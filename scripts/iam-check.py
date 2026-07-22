#!/usr/bin/env python3
"""Détecte le 403 « quota project » de gws et produit la commande de remédiation IAM.

`gws` attache le projet GCP du `client_secret.json` comme *quota project* à
chaque appel API. Google exige alors que le **compte appelant** ait le rôle
`roles/serviceusage.serviceUsageConsumer` (ou owner/editor) sur ce projet ;
sinon tout appel renvoie « Caller does not have required permission to use
project <id> » — même avec un token parfaitement valide (cf. docs/setup-oauth.md
§7, fiche backlog 0005).

Usage :
  gws … 2>&1 | scripts/iam-check.py detect <email>
      Lit la sortie de gws sur stdin. Si l'erreur « use project <id> » est
      présente, écrit un message de remédiation (dont la commande gcloud
      exacte) sur stdout et sort 0. Sinon : rien sur stdout, sort 1.

Hermétique : aucune I/O réseau, aucune dépendance gcloud. La détection est
purement textuelle et l'id du projet est extrait de l'erreur elle-même —
c'est ce qui rend le comportement testable sans compte réel (scripts/test.sh).

Le message est indicatif : cet outil n'exécute JAMAIS la commande gcloud —
accorder un rôle IAM est un geste admin humain (même logique que unlock/grant).
"""
from __future__ import annotations

import re
import sys
from typing import Optional

ROLE = "roles/serviceusage.serviceUsageConsumer"
# Id de projet GCP : minuscule initiale, 6–30 car. [a-z0-9-], pas de tiret final.
_PROJECT_RE = re.compile(r"use project ([a-z][-a-z0-9]{4,28}[a-z0-9])")


def remediation(project: str, email: str) -> str:
    cmd = (
        f"gcloud projects add-iam-policy-binding {project} "
        f"--member=user:{email} --role={ROLE}"
    )
    return (
        f"⚠ Le compte {email} n'a pas accès au projet GCP « {project} » "
        f"(quota project de l'app OAuth).\n"
        f"  Tant que le rôle serviceUsageConsumer n'est pas accordé, chaque "
        f"appel API renverra 403.\n"
        f"  À faire exécuter par le propriétaire du projet (geste admin — le "
        f"LLM ne l'exécute jamais) :\n"
        f"    {cmd}\n"
        f"  Propagation ~2 min. Détail : docs/setup-oauth.md §7."
    )


def detect(email: str, text: str) -> Optional[str]:
    """Renvoie le message de remédiation si le texte contient le 403-projet, sinon None."""
    m = _PROJECT_RE.search(text)
    if not m:
        return None
    return remediation(m.group(1), email)


def main(argv: list[str]) -> int:
    if len(argv) < 2 or argv[0] != "detect" or not argv[1]:
        sys.stderr.write("usage : gws … 2>&1 | iam-check.py detect <email>\n")
        return 2
    msg = detect(argv[1], sys.stdin.read())
    if msg is None:
        return 1
    print(msg)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
