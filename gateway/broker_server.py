"""Broker Phase 2 A — seul process qui exécute gws (loopback TCP).

Protocole : une ligne JSON par requête / réponse (newline-delimited).

Requête :
  {"token":"…","cmd":"exec","alias":"perso","args":["gmail",…],"client":"mcp"}
  {"token":"…","cmd":"ping"}

Réponse :
  {"ok":true,"result":{…}}
  {"ok":false,"code":"locked|policy|…","error":"…"}
"""
from __future__ import annotations

import json
import os
import secrets
import shutil
import socketserver
import subprocess
import sys
from pathlib import Path
from typing import Any

# Réutiliser la logique gateway (lock, policy, config)
from .config import SYS_PYTHON, POLICY_CHECKER, gwsa_root, upload_spool
from .errors import GatewayError
from .profiles import require_unlocked
from .usage import log_usage

DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 4878
TOKEN_FILE_NAME = ".broker-token"
# Pidfile : rend le broker pilotable (« gwsa broker status|stop »). Il vit dans
# GWSA_ROOT, donc chaque couloir (stable / dev) a le sien — fiche 0023.
PID_FILE_NAME = ".broker.pid"


def broker_host() -> str:
    return os.environ.get("GWSA_BROKER_HOST", DEFAULT_HOST)


def broker_port() -> int:
    return int(os.environ.get("GWSA_BROKER_PORT", str(DEFAULT_PORT)))


def token_path() -> Path:
    return gwsa_root() / TOKEN_FILE_NAME


def pid_path() -> Path:
    return gwsa_root() / PID_FILE_NAME


def ensure_token() -> str:
    root = gwsa_root()
    root.mkdir(parents=True, exist_ok=True)
    path = token_path()
    if path.is_file():
        return path.read_text(encoding="utf-8").strip()
    tok = secrets.token_hex(16)
    path.write_text(tok + "\n", encoding="utf-8")
    try:
        os.chmod(path, 0o600)
    except OSError:
        pass
    return tok


def _gws_bin() -> str:
    path = shutil.which("gws")
    if not path:
        raise GatewayError(
            "binaire gws introuvable dans le PATH — installer : brew install googleworkspace-cli",
            code="exec",
        )
    return path


def run_gws_local(profile_path: Path, args: list[str], timeout: int = 60) -> Any:
    env = dict(os.environ)
    env["GOOGLE_WORKSPACE_CLI_CONFIG_DIR"] = str(profile_path)
    try:
        r = subprocess.run(
            [_gws_bin(), *args],
            env=env,
            # cwd = répertoire de dépôt (ADR-0003) : c'est le bac à sable
            # fichiers de gws (il refuse tout `--upload` hors de son cwd). Le
            # fixer ici sert les uploads ET rétrécit ce bac à sable pour toutes
            # les commandes — sinon gws s'exécute dans le dépôt git.
            cwd=str(upload_spool()),
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired as e:
        raise GatewayError(f"gws timeout après {timeout}s", code="exec") from e
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


def check_policy(profile_path: Path, gws_args: list[str], client: str) -> None:
    if not (profile_path / "policy.json").is_file():
        return
    if not POLICY_CHECKER.is_file():
        raise GatewayError(f"contrôleur policy absent ({POLICY_CHECKER})", code="error")
    python = SYS_PYTHON if os.path.isfile(SYS_PYTHON) else "python3"
    env = dict(os.environ)
    env["GWSA_CLIENT"] = client or "broker"
    r = subprocess.run(
        [python, str(POLICY_CHECKER), str(profile_path), *gws_args],
        capture_output=True,
        text=True,
        env=env,
    )
    if r.returncode != 0:
        msg = (r.stderr or r.stdout or "").strip() or "policy refus"
        raise GatewayError(msg, code="policy")


def handle_exec(alias: str, args: list[str], client: str) -> Any:
    if not isinstance(args, list) or not all(isinstance(a, str) for a in args):
        raise GatewayError("args doit être une liste de chaînes", code="error")
    if not args:
        raise GatewayError("args vide", code="error")
    try:
        d = require_unlocked(alias)
    except GatewayError as e:
        # Refus de verrou tracé comme un refus de policy — sinon usage.jsonl
        # ne voit jamais les tentatives sur profil verrouillé.
        if e.code == "locked":
            log_usage(alias, args, client, decision="refus", reason="locked")
        raise
    check_policy(d, args, client)
    result = run_gws_local(d, args)
    log_usage(alias, args, client)
    return result


class BrokerHandler(socketserver.StreamRequestHandler):
    expected_token: str = ""

    def handle(self) -> None:
        try:
            line = self.rfile.readline()
            if not line:
                return
            req = json.loads(line.decode("utf-8"))
        except Exception as e:
            self._reply({"ok": False, "code": "error", "error": f"requête invalide : {e}"})
            return

        if req.get("token") != self.expected_token:
            self._reply({"ok": False, "code": "auth", "error": "token broker invalide"})
            return

        cmd = req.get("cmd") or "exec"
        try:
            if cmd == "ping":
                self._reply({"ok": True, "result": {"pong": True}})
                return
            if cmd == "exec":
                alias = req.get("alias") or ""
                args = req.get("args") or []
                client = req.get("client") or "broker"
                result = handle_exec(alias, args, client)
                self._reply({"ok": True, "result": result})
                return
            self._reply({"ok": False, "code": "error", "error": f"cmd inconnue : {cmd}"})
        except GatewayError as e:
            self._reply(e.to_dict())
        except Exception as e:
            self._reply({"ok": False, "code": "error", "error": str(e)})

    def _reply(self, obj: dict) -> None:
        self.wfile.write((json.dumps(obj, ensure_ascii=False) + "\n").encode("utf-8"))


class ThreadedTCPServer(socketserver.ThreadingMixIn, socketserver.TCPServer):
    allow_reuse_address = True
    daemon_threads = True


def serve(host: str | None = None, port: int | None = None) -> None:
    host = host or broker_host()
    port = port if port is not None else broker_port()
    token = ensure_token()
    BrokerHandler.expected_token = token
    with ThreadedTCPServer((host, port), BrokerHandler) as server:
        _write_pid()
        sys.stderr.write(f"google-broker : écoute {host}:{port} (token {token_path()})\n")
        sys.stderr.flush()
        try:
            server.serve_forever()
        finally:
            _clear_pid()


def _write_pid() -> None:
    path = pid_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(f"{os.getpid()}\n", encoding="utf-8")


def _clear_pid() -> None:
    """N'efface le pidfile que s'il est le nôtre — sinon on effacerait celui d'un
    broker qui nous a succédé sur le même GWSA_ROOT."""
    path = pid_path()
    try:
        if path.read_text(encoding="utf-8").strip() == str(os.getpid()):
            path.unlink()
    except OSError:
        pass


def main() -> None:
    serve()


if __name__ == "__main__":
    main()
