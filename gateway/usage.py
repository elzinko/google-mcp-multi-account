"""Journal d'usage (usage.jsonl) — même trace que bin/gwsa, via scripts/log-usage.py."""
from __future__ import annotations

import os
import subprocess

from .config import SYS_PYTHON, USAGE_LOGGER, gwsa_root


def log_usage(
    alias: str,
    gws_args: list[str],
    client: str,
    decision: str = "ok",
    reason: str = "",
) -> None:
    """Best-effort : ne lève jamais, n'empêche jamais la réponse au client."""
    if not USAGE_LOGGER.is_file():
        return
    python = SYS_PYTHON if os.path.isfile(SYS_PYTHON) else "python3"
    env = dict(os.environ)
    env["GWSA_CLIENT"] = client or "broker"
    env["GWSA_LOG_DECISION"] = decision
    env["GWSA_LOG_REASON"] = reason
    try:
        subprocess.run(
            [python, str(USAGE_LOGGER), str(gwsa_root()), alias, *gws_args],
            capture_output=True,
            env=env,
            timeout=5,
        )
    except Exception:
        pass
