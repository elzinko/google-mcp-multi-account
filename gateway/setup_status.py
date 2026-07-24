"""setup_status — état agrégé du setup (tool MCP lecture seule + `status --json`).

LIT uniquement : profils connectés (fichiers de profil + métadonnée `.email`,
jamais d'exécution gws — ADR-0002), `provision.env`
(projet + publication), présence du `client_secret.json`, et l'IAM du projet
(`gcloud get-iam-policy`, read-only) quand gcloud est joignable. N'exécute
AUCUNE mutation — déverrouiller / accorder un rôle / connecter un compte reste
un geste humain élicité (ADR-0001). Objectif : donner à un LLM sans shell
(Claude Desktop) la même visibilité que `provision-gcp.sh status`, plus une
liste de commandes prêtes à proposer (`next_actions`).

Dégradation gracieuse : sans gcloud ou sans projet provisionné, l'IAM est
marqué « unknown » et une action « lancer status en terminal » est suggérée —
jamais d'erreur bloquante.
"""
from __future__ import annotations

import shutil
import subprocess
from typing import Any, Optional

from .config import gwsa_root
from .profiles import list_profiles

ROLE_SUC = "roles/serviceusage.serviceUsageConsumer"


def _read_provision_env() -> dict[str, str]:
    out: dict[str, str] = {}
    try:
        text = (gwsa_root() / "provision.env").read_text(encoding="utf-8")
    except OSError:
        return out
    for line in text.splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            out[k.strip()] = v.strip().strip('"')
    return out


def _iam_authorized_emails(project: str) -> Optional[set[str]]:
    """Emails (minuscules) ayant owner/editor/serviceUsageConsumer, ou None si non vérifiable."""
    gcloud = shutil.which("gcloud")
    if not gcloud or not project:
        return None
    try:
        r = subprocess.run(
            [
                gcloud, "projects", "get-iam-policy", project,
                "--flatten=bindings[].members",
                "--filter=bindings.role=roles/owner OR bindings.role=roles/editor "
                f"OR bindings.role={ROLE_SUC}",
                "--format=value(bindings.members)",
            ],
            capture_output=True, text=True, timeout=20,
        )
    except Exception:
        return None
    if r.returncode != 0:
        return None
    return {
        m.split(":", 1)[1].lower()
        for m in r.stdout.split()
        if m.startswith("user:") and ":" in m
    }


def setup_status() -> dict[str, Any]:
    root = gwsa_root()
    state = _read_provision_env()
    project = state.get("PROJECT_ID") or ""
    published = state.get("PUBLISHED") or ""
    client_secret = (root / "client_secret.json").is_file()
    authorized = _iam_authorized_emails(project)  # None => IAM non vérifiable ici

    accounts: list[dict[str, Any]] = []
    for p in list_profiles():
        # Email = métadonnée persistée (.email), fournie par list_profiles même
        # profil verrouillé (ADR-0002) — aucune exécution gws ici.
        email_raw = p.get("email") or ""
        email = email_raw.lower()
        acc: dict[str, Any] = {
            "alias": p["alias"],
            "email": email_raw,
            "connected": p.get("connected", False),
            "locked": p.get("locked", False),
        }
        if authorized is None or not email:
            acc["iam"] = "unknown"
        elif email in authorized:
            acc["iam"] = "ok"
        else:
            acc["iam"] = "missing"
            acc["remediation"] = (
                f"gcloud projects add-iam-policy-binding {project} "
                f"--member=user:{email_raw} --role={ROLE_SUC}"
            )
        accounts.append(acc)

    next_actions: list[str] = []
    if not project:
        next_actions.append("./scripts/provision-gcp.sh   # provisionner le projet GCP (une fois)")
    if not client_secret:
        next_actions.append("client_secret.json absent — voir docs/setup-oauth.md")
    if project and not published:
        next_actions.append("./scripts/provision-gcp.sh   # étape 7 : publier l'app (tokens durables)")
    if not authorized and project:
        next_actions.append("./scripts/provision-gcp.sh status   # (terminal) vérifier l'accès IAM des comptes")
    if any(a["iam"] == "missing" for a in accounts):
        next_actions.append("./scripts/provision-gcp.sh sync-iam   # accorder le rôle IAM manquant")
    if any(a["connected"] and not a["email"] for a in accounts):
        next_actions.append("gwsa list   # renseigner l'email des profils existants (métadonnée .email, une fois)")
    for a in accounts:
        if a["locked"]:
            next_actions.append(f"gwsa unlock {a['alias']} 30   # profil verrouillé (accès sur demande)")
    if not accounts:
        next_actions.append("gwsa add <alias> <email>   # connecter un premier compte")

    return {
        "ok": True,
        "project_id": project or None,
        "published": published or None,
        "client_secret": client_secret,
        "iam_checked": authorized is not None,
        "accounts": accounts,
        "next_actions": next_actions,
        "note": (
            "Lecture seule. Les commandes de next_actions sont à faire exécuter par "
            "l'utilisateur (élicitation) — le LLM ne les lance jamais lui-même."
        ),
    }


if __name__ == "__main__":
    import json
    import sys

    json.dump(setup_status(), sys.stdout, ensure_ascii=False, indent=2)
    sys.stdout.write("\n")
