"""Executor v2 (Phase 2 A) — client RPC vers le broker local ; plus d'appel gws ici."""
from __future__ import annotations

import json
import os
import socket
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

from .broker_server import broker_host, broker_port, ensure_token, token_path
from .config import REPO_DIR, SYS_PYTHON, client_id
from .context import get_git_root, get_session_id
from .errors import GatewayError

_CONNECT_TIMEOUT = 2.0
_READ_TIMEOUT = 90.0


def _request(payload: dict, timeout: float = _READ_TIMEOUT) -> dict:
    host, port = broker_host(), broker_port()
    data = (json.dumps(payload, ensure_ascii=False) + "\n").encode("utf-8")
    with socket.create_connection((host, port), timeout=_CONNECT_TIMEOUT) as sock:
        sock.settimeout(timeout)
        sock.sendall(data)
        buf = b""
        while b"\n" not in buf:
            chunk = sock.recv(65536)
            if not chunk:
                break
            buf += chunk
    if not buf:
        raise GatewayError("broker : réponse vide", code="exec")
    try:
        return json.loads(buf.split(b"\n", 1)[0].decode("utf-8"))
    except json.JSONDecodeError as e:
        raise GatewayError(f"broker : JSON invalide ({e})", code="exec") from e


def _broker_alive() -> bool:
    try:
        tok = token_path().read_text(encoding="utf-8").strip() if token_path().is_file() else ""
        if not tok:
            return False
        r = _request({"token": tok, "cmd": "ping"}, timeout=2.0)
        return bool(r.get("ok"))
    except Exception:
        return False


def ensure_broker_running() -> None:
    """Démarre le broker en arrière-plan s'il n'écoute pas encore."""
    if _broker_alive():
        return
    ensure_token()
    python = SYS_PYTHON if os.path.isfile(SYS_PYTHON) else sys.executable
    env = dict(os.environ)
    env["PYTHONPATH"] = str(REPO_DIR) + (os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")
    log_path = Path(os.environ.get("GWSA_ROOT") or Path.home() / ".config" / "gws-accounts") / ".broker.log"
    log_path.parent.mkdir(parents=True, exist_ok=True)
    logf = open(log_path, "a", encoding="utf-8")  # noqa: SIM115 — vit avec le daemon
    subprocess.Popen(
        [python, "-m", "gateway.broker_server"],
        cwd=str(REPO_DIR),
        env=env,
        stdin=subprocess.DEVNULL,
        stdout=logf,
        stderr=logf,
        start_new_session=True,
    )
    for _ in range(25):
        time.sleep(0.1)
        if _broker_alive():
            return
    raise GatewayError(
        f"impossible de démarrer le broker (voir {log_path})",
        code="exec",
    )


def run_gws(profile_dir: str, args: list[str], timeout: int = 60) -> Any:
    """Compat API v1 : profile_dir est ignoré pour l'auth (le broker résout l'alias).

    Conservé pour ne pas casser les appelants ; l'alias est dérivé du basename.
    Préférer `run_via_broker(alias, args)`.
    """
    alias = Path(profile_dir).name
    return run_via_broker(alias, args, timeout=timeout)


def run_via_broker(alias: str, args: list[str], timeout: int = 60) -> Any:
    ensure_broker_running()
    tok = ensure_token()
    payload: dict[str, Any] = {
        "token": tok,
        "cmd": "exec",
        "alias": alias,
        "args": args,
        "client": client_id(),
    }
    sid = get_session_id()
    if sid:
        payload["session_id"] = sid
    gro = get_git_root()
    if gro:
        payload["git_root"] = gro
    resp = _request(payload, timeout=float(timeout) + 5)
    if not resp.get("ok"):
        raise GatewayError(
            resp.get("error") or "refus broker",
            code=resp.get("code") or "exec",
        )
    return resp.get("result")
