"""Application de la policy (délègue à scripts/policy-check.py)."""
from __future__ import annotations

import os
import subprocess
from pathlib import Path

from .config import POLICY_CHECKER, SYS_PYTHON, USAGE_LOGGER, client_id, gwsa_root
from .errors import GatewayError


def check_policy(profile_path: Path, gws_args: list[str]) -> None:
    """Refuse (GatewayError code=policy|locked) si policy-check exit ≠ 0.

    Absent de policy.json : le checker est no-op (comportement historique gwsa) ;
    les profils créés via gwsa add ont désormais une policy prudente.
    """
    policy_file = profile_path / "policy.json"
    if not policy_file.is_file():
        return
    if not POLICY_CHECKER.is_file():
        raise GatewayError(
            f"policy.json présent mais contrôleur absent ({POLICY_CHECKER})",
            code="error",
        )
    python = SYS_PYTHON if os.path.isfile(SYS_PYTHON) else "python3"
    env = dict(os.environ)
    env["GWSA_CLIENT"] = client_id()
    r = subprocess.run(
        [python, str(POLICY_CHECKER), str(profile_path), *gws_args],
        capture_output=True,
        text=True,
        env=env,
    )
    if r.returncode == 0:
        return
    msg = (r.stderr or r.stdout or "").strip() or f"policy refus (exit {r.returncode})"
    raise GatewayError(msg, code="policy")


def log_ok(alias: str, gws_args: list[str]) -> None:
    if not USAGE_LOGGER.is_file():
        return
    python = SYS_PYTHON if os.path.isfile(SYS_PYTHON) else "python3"
    env = dict(os.environ)
    env["GWSA_CLIENT"] = client_id()
    try:
        subprocess.run(
            [python, str(USAGE_LOGGER), str(gwsa_root()), alias, *gws_args],
            capture_output=True,
            env=env,
            timeout=5,
        )
    except Exception:
        pass
