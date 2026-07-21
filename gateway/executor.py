"""Executor v1 — invoque gws avec le config dir du profil.

Point de remplacement Phase 2 (broker) : seule cette couche doit parler à Google.
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
from typing import Any

from .errors import GatewayError


def _gws_bin() -> str:
    path = shutil.which("gws")
    if not path:
        raise GatewayError(
            "binaire gws introuvable dans le PATH — installer : brew install googleworkspace-cli",
            code="exec",
        )
    return path


def run_gws(profile_dir: str, args: list[str], timeout: int = 60) -> Any:
    """Exécute `gws <args…>` et parse la sortie JSON. Échec → GatewayError."""
    env = dict(os.environ)
    env["GOOGLE_WORKSPACE_CLI_CONFIG_DIR"] = profile_dir
    try:
        r = subprocess.run(
            [_gws_bin(), *args],
            env=env,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired as e:
        raise GatewayError(f"gws timeout après {timeout}s : {' '.join(args)}", code="exec") from e
    except FileNotFoundError as e:
        raise GatewayError("binaire gws introuvable", code="exec") from e

    if r.returncode != 0:
        err = (r.stderr or r.stdout or "").strip() or f"exit {r.returncode}"
        raise GatewayError(f"gws a échoué : {err}", code="exec")

    out = (r.stdout or "").strip()
    if not out:
        return {}
    try:
        return json.loads(out)
    except json.JSONDecodeError:
        return {"raw": out}
