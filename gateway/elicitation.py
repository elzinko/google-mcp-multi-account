"""Élicitation signée v2 — payload canonique, reçu vérifiable, anti-rejeu (fiche 0001).

Sur macOS : signature P-256 Secure Enclave via scripts/elicitation-sign.swift.
En tests / CI (Linux) : GWSA_ELICITATION_MOCK=1 + clé HMAC dans .elicitation/mock.key.
"""
from __future__ import annotations

import base64
import hashlib
import hmac
import json
import os
import secrets
import subprocess
import time
from pathlib import Path
from typing import Any

from ._filelock import file_lock
from .config import PRODUCT_SLUG, REPO_DIR, SYS_PYTHON, gwsa_root

ELICITATION_DIR_NAME = ".elicitation"
PUBLIC_KEY_NAME = "public.der"
PRIVATE_KEY_NAME = "private.p256"  # repli fichier si Keychain/SE inaccessible (-34018)
MOCK_KEY_NAME = "mock.key"
RECEIPTS_NAME = "receipts.jsonl"
NONCES_NAME = "nonces.json"
CHALLENGE_TTL_SEC = 300
MOCK_SIG_PREFIX = "mock:"
P256_SIG_PREFIX = "p256:"

# Le helper d'élicitation signée est compilé en binaire nommé d'après
# PRODUCT_SLUG et exécuté à la place de `swift <script>` : macOS affiche alors ce
# nom (« google-multi-account ») dans le dialogue Touch ID au lieu de
# « swift-frontend » (cf. fiche 0032, étendue ici au chemin d'élicitation signée).
# Artefact de build isolé (gitignoré) : recompilable, non déployé.
SIGN_HELPER_NAME = "elicitation-sign.swift"
SIGN_BUILD_DIR = REPO_DIR / "bin" / ".build"


class ElicitationError(Exception):
    """Échec d'élicitation — fail closed."""


def elicitation_dir() -> Path:
    d = gwsa_root() / ELICITATION_DIR_NAME
    d.mkdir(parents=True, exist_ok=True)
    try:
        os.chmod(d, 0o700)
    except OSError:
        pass
    return d


def public_key_path() -> Path:
    return elicitation_dir() / PUBLIC_KEY_NAME


def private_key_path() -> Path:
    return elicitation_dir() / PRIVATE_KEY_NAME


def mock_key_path() -> Path:
    return elicitation_dir() / MOCK_KEY_NAME


def _swift_env() -> dict[str, str]:
    env = dict(os.environ)
    env["GWSA_ELICITATION_DIR"] = str(elicitation_dir())
    env["GWSA_ROOT"] = str(gwsa_root())
    return env


def receipts_path() -> Path:
    return elicitation_dir() / RECEIPTS_NAME


def nonces_path() -> Path:
    return elicitation_dir() / NONCES_NAME


def nonces_lock_path() -> Path:
    """Lockfile dédié, co-localisé avec le store de nonces (fiche 0084)."""
    return nonces_path().with_suffix(".lock")


_TEST_RACE_DELAY_ENV = "GWSA_ELICITATION_TEST_RACE_DELAY_MS"


def _test_race_delay() -> None:
    """Hook de test (fiche 0084) : injecte un délai déterministe entre la
    vérification et la sauvegarde du nonce, pour rendre une course TOCTOU
    reproductible de façon fiable en test hermétique multi-process. Inactif
    tant que la variable d'env n'est pas positionnée (jamais en production).
    """
    raw = os.environ.get(_TEST_RACE_DELAY_ENV, "").strip()
    if not raw:
        return
    try:
        time.sleep(float(raw) / 1000.0)
    except ValueError:
        pass


def is_mock_mode() -> bool:
    if os.environ.get("GWSA_ELICITATION_MOCK", "").strip() in ("1", "true", "yes"):
        return True
    return mock_key_path().is_file() and not public_key_path().is_file()


def is_enrolled() -> bool:
    if is_mock_mode():
        return mock_key_path().is_file()
    return public_key_path().is_file()


def enroll_mock() -> dict[str, Any]:
    """Enrôlement test : clé HMAC locale (CI / Linux)."""
    d = elicitation_dir()
    key = secrets.token_bytes(32)
    p = mock_key_path()
    p.write_bytes(key)
    try:
        os.chmod(p, 0o600)
    except OSError:
        pass
    return {"ok": True, "mode": "mock", "path": str(p)}


def canonical_json(payload: dict[str, Any]) -> str:
    return json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def payload_hash(payload: dict[str, Any]) -> str:
    return hashlib.sha256(canonical_json(payload).encode("utf-8")).hexdigest()


def prompt_from_payload(payload: dict[str, Any]) -> str:
    """Texte Touch ID — doit rester aligné avec elicitation-sign.swift."""
    action = str(payload.get("action") or "")
    alias = str(payload.get("alias") or "")
    email = str(payload.get("email") or "")
    target = str(payload.get("target") or "")
    sid = str(payload.get("session_id") or "")
    minutes = int(payload.get("minutes") or 0)
    hours = int(payload.get("hours") or 0)
    # Nommer le compte à l'instant d'autoriser (fiche 0047) : l'email est la
    # vérité terrain « quelle boîte Gmail ». Repli sur l'alias seul si inconnu.
    who = f"« {alias} » ({email})" if email else f"« {alias} »"
    acct = f"{alias} · {email}" if email else alias
    if action == "session_unlock":
        return f"mag : déverrouiller {who} pour la session {sid} ({minutes} min)"
    if action == "unlock":
        if target == "off":
            return f"mag : retirer le verrou permanent sur {who}"
        return f"mag : déverrouiller {who} ({minutes or target} min, poste entier)"
    if action == "session_grant":
        return f"mag : zone session {sid} — « {target} » ({acct}, {hours} h)"
    if action == "session_grant_capability":
        return f"mag : capacité session {sid} — « {target} » ({acct}, {hours} h)"
    if action == "grant":
        return f"mag : autoriser l'écriture Drive « {target} » ({acct}, {hours} h)"
    if action == "project_sign":
        return f"mag : signer le manifeste projet (.gwsa/)"
    if action == "add_account":
        return f"mag : connecter le compte Google « {alias} » ({target})"
    if action == "revoke_descendants":
        return f"mag : révoquer les sous-sessions de {sid or target}"
    if action == "strongauth_off":
        return "mag : désactiver l'authentification forte"
    return f"mag : {action} — {alias} {target}".strip()


def build_payload(
    action: str,
    *,
    alias: str = "",
    target: str = "",
    session_id: str = "",
    minutes: int = 0,
    hours: int = 0,
    email: str = "",
) -> dict[str, Any]:
    now = int(time.time())
    return {
        "v": 1,
        "action": action,
        "alias": alias,
        "email": email,
        "target": target,
        "session_id": session_id,
        "minutes": int(minutes or 0),
        "hours": int(hours or 0),
        "nonce": secrets.token_hex(16),
        "issued_at": now,
        "expires_at": now + CHALLENGE_TTL_SEC,
    }


def _load_nonces() -> dict[str, float]:
    path = nonces_path()
    if not path.is_file():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        if isinstance(data, dict):
            return {str(k): float(v) for k, v in data.items()}
    except (OSError, json.JSONDecodeError, TypeError, ValueError):
        pass
    return {}


def _save_nonces(nonces: dict[str, float]) -> None:
    now = time.time()
    pruned = {k: v for k, v in nonces.items() if v > now - 86400}
    path = nonces_path()
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(pruned), encoding="utf-8")
    try:
        os.chmod(tmp, 0o600)
    except OSError:
        pass
    tmp.replace(path)


def consume_nonce(nonce: str, *, expires_at: int) -> None:
    if not nonce:
        raise ElicitationError("nonce manquant")
    if int(time.time()) > int(expires_at):
        raise ElicitationError("défi expiré — relancer la commande")
    # Verrou inter-process (fiche 0084) : reload → check → save doivent être
    # atomiques face à deux process concurrents (Touch ID local + approbation
    # passkey distante brûlent leur nonce par ce même chemin). Le rechargement
    # DOIT se faire sous le verrou — jamais réutiliser un état chargé avant
    # l'acquisition, sous peine de revalider la course qu'on cherche à fermer.
    with file_lock(nonces_lock_path()):
        # Ré-vérifier l'expiration SOUS le verrou (revue Codex PR #125) : l'attente
        # d'acquisition du verrou peut franchir expires_at ; sans ce re-check, un
        # défi expiré PENDANT l'attente serait consommé. Temps frais, sous le verrou.
        if int(time.time()) > int(expires_at):
            raise ElicitationError("défi expiré — relancer la commande")
        nonces = _load_nonces()
        if nonce in nonces:
            raise ElicitationError("rejeu refusé (nonce déjà consommé)")
        _test_race_delay()
        nonces[nonce] = float(expires_at)
        _save_nonces(nonces)


def sign_mock(payload: dict[str, Any]) -> str:
    key = mock_key_path().read_bytes()
    digest = canonical_json(payload).encode("utf-8")
    sig = hmac.new(key, digest, hashlib.sha256).digest()
    return MOCK_SIG_PREFIX + base64.b64encode(sig).decode("ascii")


def verify_mock(payload: dict[str, Any], signature: str) -> bool:
    if not signature.startswith(MOCK_SIG_PREFIX):
        return False
    try:
        got = base64.b64decode(signature[len(MOCK_SIG_PREFIX) :], validate=True)
    except Exception:
        return False
    key = mock_key_path().read_bytes()
    expected = hmac.new(key, canonical_json(payload).encode("utf-8"), hashlib.sha256).digest()
    return hmac.compare_digest(got, expected)


def _sign_helper_cmd() -> list[str]:
    """Préfixe de commande du helper d'élicitation signée.

    Préfère le binaire produit compilé (dialogue Touch ID nommé d'après
    PRODUCT_SLUG, cf. fiche 0032) s'il est présent et exécutable ; à défaut,
    `swift <script>` (dialogue système « swift-frontend »). GWSA_SIGN_BIN suit le
    même modèle de confiance que GWSA_SYS_SWIFT : fixé par le wrapper, chemin dur
    (REPO_DIR) par défaut.
    """
    binp = os.environ.get("GWSA_SIGN_BIN") or str(SIGN_BUILD_DIR / PRODUCT_SLUG)
    if binp and os.access(binp, os.X_OK):
        return [binp]
    swift = os.environ.get("GWSA_SYS_SWIFT", "/usr/bin/swift")
    script = REPO_DIR / "scripts" / SIGN_HELPER_NAME
    if not Path(swift).is_file():
        raise ElicitationError(f"Swift introuvable ({swift}) — xcode-select --install")
    if not script.is_file():
        raise ElicitationError(f"helper de signature absent ({script})")
    return [swift, str(script)]


def _swift_sign(payload: dict[str, Any]) -> str:
    proc = subprocess.run(
        [*_sign_helper_cmd(), "sign", canonical_json(payload)],
        capture_output=True,
        text=True,
        timeout=120,
        env=_swift_env(),
    )
    if proc.returncode == 2:
        raise ElicitationError(
            "biométrie indisponible — pas d'accord silencieux "
            "(capot fermé, pas de Touch ID, ou clé non enrôlée : mag elicitation enroll)"
        )
    if proc.returncode != 0:
        detail = (proc.stderr or proc.stdout or "").strip()
        raise ElicitationError(detail or "signature refusée")
    try:
        receipt = json.loads(proc.stdout.strip())
    except json.JSONDecodeError as e:
        raise ElicitationError(f"réponse helper invalide : {e}") from e
    sig = str(receipt.get("signature") or "")
    if not sig:
        raise ElicitationError("signature absente dans le reçu")
    return sig


def verify_p256(payload: dict[str, Any], signature: str) -> bool:
    if not signature.startswith(P256_SIG_PREFIX):
        return False
    pub = public_key_path()
    if not pub.is_file():
        return False
    try:
        sig_bytes = base64.b64decode(signature[len(P256_SIG_PREFIX) :], validate=True)
    except Exception:
        return False
    msg = canonical_json(payload).encode("utf-8")
    import tempfile

    pem_file = sig_file = None
    try:
        # openssl dgst -verify attend du PEM, pas du SPKI DER brut
        conv = subprocess.run(
            ["openssl", "pkey", "-pubin", "-inform", "DER", "-in", str(pub)],
            capture_output=True,
            timeout=10,
        )
        if conv.returncode != 0 or not conv.stdout:
            return False
        with tempfile.NamedTemporaryFile(delete=False, suffix=".pem") as pf:
            pf.write(conv.stdout)
            pem_file = pf.name
        with tempfile.NamedTemporaryFile(delete=False) as sf:
            sf.write(sig_bytes)
            sig_file = sf.name
        proc = subprocess.run(
            [
                "openssl", "dgst", "-sha256",
                "-verify", pem_file,
                "-signature", sig_file,
            ],
            input=msg,
            capture_output=True,
            timeout=10,
        )
        return proc.returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False
    finally:
        for path in (pem_file, sig_file):
            if path:
                try:
                    os.unlink(path)
                except OSError:
                    pass


def verify_signature(payload: dict[str, Any], signature: str) -> bool:
    if signature.startswith(MOCK_SIG_PREFIX):
        return verify_mock(payload, signature)
    if signature.startswith(P256_SIG_PREFIX):
        return verify_p256(payload, signature)
    return False


def log_receipt(payload: dict[str, Any], signature: str) -> None:
    entry = {
        "ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "payload": payload,
        "payload_hash": payload_hash(payload),
        "signature": signature,
        "prompt": prompt_from_payload(payload),
    }
    path = receipts_path()
    with path.open("a", encoding="utf-8") as f:
        f.write(json.dumps(entry, ensure_ascii=False) + "\n")
    # Miroir dans usage.jsonl pour audit unifié
    logger = REPO_DIR / "scripts" / "log-usage.py"
    python = SYS_PYTHON if os.path.isfile(SYS_PYTHON) else "python3"
    env = dict(os.environ)
    env["GWSA_LOG_DECISION"] = "elicitation"
    env["GWSA_LOG_REASON"] = f"{payload.get('action')}:{payload_hash(payload)[:16]}"
    alias = str(payload.get("alias") or "_")
    sid = str(payload.get("session_id") or "")
    if sid:
        env["GWSA_SESSION_ID"] = sid
    try:
        subprocess.run(
            [python, str(logger), str(gwsa_root()), alias, "elicitation", canonical_json(payload)],
            capture_output=True,
            env=env,
            timeout=5,
        )
    except Exception:
        pass


def obtain_signature(payload: dict[str, Any]) -> str:
    if is_mock_mode():
        return sign_mock(payload)
    return _swift_sign(payload)


def run_elicitation_gate(fields: dict[str, Any]) -> None:
    """Point d'entrée : construit le payload, obtient signature, vérifie, journalise."""
    if not is_enrolled():
        raise ElicitationError(
            "élicitation signée requise mais non enrôlée — exécuter : mag elicitation enroll"
        )
    action = str(fields.get("action") or "")
    if not action:
        raise ElicitationError("action manquante")
    payload = build_payload(
        action,
        alias=str(fields.get("alias") or ""),
        email=str(fields.get("email") or ""),
        target=str(fields.get("target") or ""),
        session_id=str(fields.get("session_id") or ""),
        minutes=int(fields.get("minutes") or 0),
        hours=int(fields.get("hours") or 0),
    )
    signature = obtain_signature(payload)
    if not verify_signature(payload, signature):
        raise ElicitationError("signature invalide — action refusée")
    consume_nonce(str(payload["nonce"]), expires_at=int(payload["expires_at"]))
    log_receipt(payload, signature)


def enroll_secure() -> dict[str, Any]:
    """Enrôlement macOS — SE / Keychain, sinon fichier private.p256 + Touch ID."""
    if is_mock_mode() and os.environ.get("GWSA_ELICITATION_MOCK"):
        return enroll_mock()
    pub = public_key_path()
    proc = subprocess.run(
        [*_sign_helper_cmd(), "enroll", str(pub)],
        capture_output=True,
        text=True,
        timeout=60,
        env=_swift_env(),
    )
    if proc.returncode != 0:
        detail = (proc.stderr or proc.stdout or "").strip()
        raise ElicitationError(detail or "échec enrôlement")
    meta: dict[str, Any] = {"ok": True, "mode": "p256", "public_key": str(pub)}
    try:
        meta.update(json.loads((proc.stdout or "").strip().splitlines()[-1]))
    except (json.JSONDecodeError, IndexError):
        pass
    priv = private_key_path()
    if priv.is_file():
        try:
            os.chmod(priv, 0o600)
        except OSError:
            pass
        meta["private_key"] = str(priv)
    return meta


def status() -> dict[str, Any]:
    storage = ""
    if is_mock_mode() and mock_key_path().is_file():
        storage = "mock"
    elif private_key_path().is_file():
        storage = "file"
    elif public_key_path().is_file():
        storage = "keychain_or_se"
    return {
        "enrolled": is_enrolled(),
        "mock": is_mock_mode(),
        "storage": storage,
        "public_key": str(public_key_path()) if public_key_path().is_file() else "",
        "receipts": str(receipts_path()) if receipts_path().is_file() else "",
    }
