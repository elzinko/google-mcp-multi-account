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
from .config import SYS_PYTHON, POLICY_CHECKER, gwsa_root, profile_dir, upload_spool
from .errors import GatewayError
from .profiles import is_locked, require_unlocked
from .sessions import active_drive_zones, is_session_unlocked
from .usage import log_usage
from .vault import gws_config_dir, migrate_all

DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 4878
# Jeton et pidfile sont nommés d'après le PORT, pas seulement d'après GWSA_ROOT
# (fiche 0025). Deux versions branchées en même temps partagent les comptes mais
# ont chacune leur broker : sans le port dans le nom, le second écrase le
# pidfile du premier et « gwsa broker stop » arrête le mauvais process.
TOKEN_FILE_TPL = ".broker-{port}-token"
PID_FILE_TPL = ".broker-{port}.pid"


def broker_host() -> str:
    return os.environ.get("GWSA_BROKER_HOST", DEFAULT_HOST)


def broker_port() -> int:
    return int(os.environ.get("GWSA_BROKER_PORT", str(DEFAULT_PORT)))


def token_path(port: int | None = None) -> Path:
    return gwsa_root() / TOKEN_FILE_TPL.format(port=port if port is not None else broker_port())


def pid_path(port: int | None = None) -> Path:
    return gwsa_root() / PID_FILE_TPL.format(port=port if port is not None else broker_port())


def ensure_token(port: int | None = None) -> str:
    root = gwsa_root()
    root.mkdir(parents=True, exist_ok=True)
    path = token_path(port)
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


def run_gws_local(
    alias: str, args: list[str], timeout: int = 60, raw_output: bool = False
) -> Any:
    env = dict(os.environ)
    env["GOOGLE_WORKSPACE_CLI_CONFIG_DIR"] = str(gws_config_dir(alias))
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
            # Mode raw (drive_read) : stdout capturé en octets, décodé tolérant
            # plus bas — un fichier texte non-UTF-8 (CSV latin-1) ne doit pas
            # faire planter le broker. Mode normal : gws imprime du JSON, text=True.
            text=not raw_output,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired as e:
        raise GatewayError(f"gws timeout après {timeout}s", code="exec") from e
    except FileNotFoundError as e:
        raise GatewayError("binaire gws introuvable", code="exec") from e
    if raw_output:
        # Contenu VERBATIM : ni `.strip()` (une fin de ligne fait partie du
        # fichier), ni `json.loads` (un .json ne doit pas être reparsé/reformaté
        # ni ses clés dédupliquées). L'appelant reçoit toujours {"raw": <texte>},
        # même pour un fichier vide (→ "").
        def _text(b: Any) -> str:
            return b if isinstance(b, str) else (b or b"").decode("utf-8", "replace")
        stdout, stderr = _text(r.stdout), _text(r.stderr)
        if r.returncode != 0:
            err = (stderr or stdout).strip() or f"exit {r.returncode}"
            raise GatewayError(f"gws a échoué : {err}", code="exec")
        return {"raw": stdout}
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


def check_policy(
    profile_path: Path,
    gws_args: list[str],
    client: str,
    *,
    session_id: str = "",
    git_root: str = "",
    session_drive_zones: set[str] | None = None,
    use_session_grants: bool = False,
) -> None:
    if not (profile_path / "policy.json").is_file():
        return
    if not POLICY_CHECKER.is_file():
        raise GatewayError(f"contrôleur policy absent ({POLICY_CHECKER})", code="error")
    python = SYS_PYTHON if os.path.isfile(SYS_PYTHON) else "python3"
    env = dict(os.environ)
    # CONFIG_DIR du vault pour les lectures gws de policy-check (under_allowed) :
    # après la migration vault (fiche 0040), les creds ne sont plus dans
    # profile_path ; sans ça, la remontée des parents échoue → tout drive_update /
    # copie / création en sous-dossier est refusé à tort (revue sécurité F1).
    env["GWSA_GWS_CONFIG_DIR"] = str(gws_config_dir(profile_path.name))
    env["GWSA_CLIENT"] = client or "broker"
    if session_id:
        env["GWSA_SESSION_ID"] = session_id
    if git_root:
        env["GWSA_GIT_ROOT"] = git_root
    if use_session_grants and session_drive_zones is not None:
        env["GWSA_SESSION_DRIVE_ZONES"] = ",".join(sorted(session_drive_zones))
        env["GWSA_USE_SESSION_GRANTS"] = "1"
    r = subprocess.run(
        [python, str(POLICY_CHECKER), str(profile_path), *gws_args],
        capture_output=True,
        text=True,
        env=env,
    )
    if r.returncode != 0:
        msg = (r.stderr or r.stdout or "").strip() or "policy refus"
        raise GatewayError(msg, code="policy")


def _require_access(alias: str, session_id: str) -> Path:
    d = profile_dir(alias)
    if not d.is_dir():
        raise GatewayError(
            f"profil inconnu « {alias} » — le créer avec : gwsa add {alias}",
            code="not_found",
        )
    if session_id:
        if is_locked(d) and not is_session_unlocked(session_id, alias):
            raise GatewayError(
                f"profil « {alias} » verrouillé pour cette session — "
                f"demander : gwsa session unlock {session_id} {alias} [minutes]",
                code="locked",
            )
        return d
    return require_unlocked(alias)


def handle_exec(
    alias: str,
    args: list[str],
    client: str,
    *,
    session_id: str = "",
    git_root: str = "",
    raw_output: bool = False,
) -> Any:
    if not isinstance(args, list) or not all(isinstance(a, str) for a in args):
        raise GatewayError("args doit être une liste de chaînes", code="error")
    if not args:
        raise GatewayError("args vide", code="error")
    try:
        d = _require_access(alias, session_id)
    except GatewayError as e:
        if e.code == "locked":
            log_usage(
                alias, args, client, decision="refus", reason="locked",
                session_id=session_id, git_root=git_root,
            )
        raise

    session_zones: set[str] | None = None
    use_session = bool(session_id)
    if use_session:
        session_zones = active_drive_zones(session_id, alias)
        # Plafond manifeste appliqué dans policy-check via GWSA_GIT_ROOT (intersection)

    check_policy(
        d, args, client,
        session_id=session_id,
        git_root=git_root,
        session_drive_zones=session_zones,
        use_session_grants=use_session,
    )
    result = run_gws_local(alias, args, raw_output=raw_output)
    log_usage(alias, args, client, session_id=session_id, git_root=git_root)
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
                session_id = str(req.get("session_id") or "")
                git_root = str(req.get("git_root") or "")
                result = handle_exec(
                    alias, args, client,
                    session_id=session_id,
                    git_root=git_root,
                    raw_output=bool(req.get("raw_output")),
                )
                self._reply({"ok": True, "result": result})
                return
            if cmd == "session_create":
                from .sessions import create_child_session, create_session
                parent = str(req.get("parent_id") or "")
                client = str(req.get("client") or "broker")
                if parent:
                    st = create_child_session(parent, client=client)
                else:
                    st = create_session(client=client)
                self._reply({"ok": True, "result": st.to_json()})
                return
            if cmd == "session_revoke_descendants":
                from .sessions import revoke_descendants
                sid = str(req.get("session_id") or "")
                n = revoke_descendants(sid)
                self._reply({"ok": True, "result": {"revoked": n}})
                return
            if cmd == "migrate_vault":
                moved = migrate_all()
                self._reply({"ok": True, "result": {"migrated": moved}})
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
    migrate_all()
    host = host or broker_host()
    port = port if port is not None else broker_port()
    # Le port EFFECTIF nomme le jeton et le pidfile — pas celui de
    # l'environnement, qui peut différer si serve() a reçu un port explicite.
    token = ensure_token(port)
    BrokerHandler.expected_token = token
    with ThreadedTCPServer((host, port), BrokerHandler) as server:
        _write_pid(port)
        sys.stderr.write(f"google-broker : écoute {host}:{port} (token {token_path(port)})\n")
        sys.stderr.flush()
        try:
            server.serve_forever()
        finally:
            _clear_pid(port)


def _write_pid(port: int | None = None) -> None:
    path = pid_path(port)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(f"{os.getpid()}\n", encoding="utf-8")


def _clear_pid(port: int | None = None) -> None:
    """N'efface le pidfile que s'il est le nôtre — sinon on effacerait celui d'un
    broker qui nous a succédé sur le même port."""
    path = pid_path(port)
    try:
        if path.read_text(encoding="utf-8").strip() == str(os.getpid()):
            path.unlink()
    except OSError:
        pass


def main() -> None:
    serve()


if __name__ == "__main__":
    main()
