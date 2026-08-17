"""Approbation distante par passkey téléphone (fiche 0078, ADR-0009).

Signeur FRÈRE du Touch ID : réutilise le socle d'élicitation signée ADR-0005
(`build_payload`, `canonical_json`, `consume_nonce`, `log_receipt`,
`prompt_from_payload`) — `gateway.elicitation.run_elicitation_gate` n'est PAS
modifié. Le téléphone ne détient aucun jeton Google ; le Mac ne persiste que
sa clé publique. Fail-closed partout : un seul écart ⇒ aucune exécution.
"""
from __future__ import annotations

import base64
import hashlib
import json
import os
import re
import secrets
import subprocess
import tempfile
import time
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any

from .approval_channel import ApprovalChannel
from .config import gwsa_root
from .elicitation import (
    build_payload,
    canonical_json,
    consume_nonce,
    log_receipt,
    prompt_from_payload,
)

REMOTE_APPROVAL_DIR_NAME = ".remote-approval"
ENROLLMENT_NAME = "phone.json"
PENDING_DIR_NAME = "pending"


class RemoteApprovalError(Exception):
    """Échec d'approbation distante — fail closed."""


def remote_approval_dir() -> Path:
    d = gwsa_root() / REMOTE_APPROVAL_DIR_NAME
    d.mkdir(parents=True, exist_ok=True)
    try:
        os.chmod(d, 0o700)
    except OSError:
        pass
    return d


def enrollment_path() -> Path:
    return remote_approval_dir() / ENROLLMENT_NAME


def pending_dir() -> Path:
    """Défis publiés, en attente de la réponse du téléphone (échange en deux
    temps, fix Codex P1 : le défi doit exister AVANT que quiconque puisse
    présenter une réponse — sinon aucun téléphone hors-process ne peut jamais
    voir le nonce qu'il doit signer)."""
    d = remote_approval_dir() / PENDING_DIR_NAME
    d.mkdir(parents=True, exist_ok=True)
    try:
        os.chmod(d, 0o700)
    except OSError:
        pass
    return d


_CHALLENGE_ID_RE = re.compile(r"^[0-9a-f]{1,64}$")


def _pending_path(challenge_id: str) -> Path:
    # Anti-traversée (Codex P2, PR #113) : `challenge_id` vient du CLI
    # (`verify --challenge-id`). Seul un jeton hexadécimal (cf. `secrets.token_hex`)
    # est accepté — un id contenant « / », « .. » ou un chemin absolu est refusé
    # AVANT toute construction de chemin (fail-closed).
    if not _CHALLENGE_ID_RE.match(challenge_id or ""):
        raise RemoteApprovalError("challenge_id invalide — jeton hexadécimal requis")
    return pending_dir() / f"{challenge_id}.json"


@dataclass
class ChallengeEnvelope:
    """Défi transporté vers le téléphone — non secret (ADR-0009 §2 : la sûreté
    vient de WYSIWYS + vérification de signature côté Mac, pas du secret)."""

    payload: dict[str, Any]
    prompt: str

    def to_json(self) -> dict[str, Any]:
        return {"payload": self.payload, "prompt": self.prompt}


@dataclass
class PhoneEnrollment:
    credential_id: str
    aaguid: str
    public_key: str  # base64 SPKI DER — SEUL secret Google absent, seule la clé publique
    sign_count: int = 0

    def to_json(self) -> dict[str, Any]:
        return asdict(self)

    @classmethod
    def from_json(cls, data: dict[str, Any]) -> PhoneEnrollment:
        return cls(
            credential_id=str(data.get("credential_id") or ""),
            aaguid=str(data.get("aaguid") or ""),
            public_key=str(data.get("public_key") or ""),
            sign_count=int(data.get("sign_count") or 0),
        )


def forge_challenge(fields: dict[str, Any]) -> ChallengeEnvelope:
    """Forge le défi — réutilise le payload canonique ADR-0005, lié à `session_id`."""
    action = str(fields.get("action") or "")
    if not action:
        raise RemoteApprovalError("action manquante")
    payload = build_payload(
        action,
        alias=str(fields.get("alias") or ""),
        email=str(fields.get("email") or ""),
        target=str(fields.get("target") or ""),
        session_id=str(fields.get("session_id") or ""),
        minutes=int(fields.get("minutes") or 0),
        hours=int(fields.get("hours") or 0),
    )
    return ChallengeEnvelope(payload=payload, prompt=prompt_from_payload(payload))


def open_remote_challenge(fields: dict[str, Any]) -> tuple[ChallengeEnvelope, str]:
    """Publie un défi — PREMIER temps de l'échange (fix Codex P1, PR #113).

    L'ancien CLI chargeait `--response` avant de forger le défi, donc son
    `client_data` (lié au `nonce` frais) ne pouvait par construction jamais
    correspondre à une assertion produite hors-process. Ici le défi est forgé
    et PERSISTÉ (fichier 0600) avant que quiconque puisse y répondre — c'est
    cet envelope qu'on publie tel quel au téléphone (§2 : non secret).
    """
    if load_enrollment() is None:
        raise RemoteApprovalError(
            "aucune passkey téléphone enrôlée — exécuter : "
            "scripts/remote-approval-cli.py enroll"
        )
    envelope = forge_challenge(fields)
    challenge_id = secrets.token_hex(16)
    path = _pending_path(challenge_id)
    path.write_text(canonical_json(envelope.payload), encoding="utf-8")
    try:
        os.chmod(path, 0o600)
    except OSError:
        pass
    return envelope, challenge_id


def close_remote_challenge(challenge_id: str, assertion: dict[str, Any]) -> dict[str, Any]:
    """Clôt un défi publié — SECOND temps de l'échange (fix Codex P1).

    One-shot : le pending est chargé PUIS supprimé (pop) avant même la
    vérification de signature, donc un 2ᵉ `close_remote_challenge` sur le même
    `challenge_id` échoue systématiquement (anti-rejeu, en plus du registre de
    nonce partagé avec le Touch ID).
    """
    enrollment = load_enrollment()
    if enrollment is None:
        raise RemoteApprovalError(
            "aucune passkey téléphone enrôlée — exécuter : "
            "scripts/remote-approval-cli.py enroll"
        )
    path = _pending_path(challenge_id)
    try:
        raw = path.read_text(encoding="utf-8")
    except OSError:
        raise RemoteApprovalError(
            "défi distant introuvable ou déjà consommé — action refusée"
        ) from None
    try:
        path.unlink()
    except OSError:
        pass
    try:
        payload = json.loads(raw)
    except ValueError:
        raise RemoteApprovalError("défi distant corrompu — action refusée") from None
    envelope = ChallengeEnvelope(payload=payload, prompt=prompt_from_payload(payload))
    if not verify_assertion(envelope, assertion, enrollment):
        raise RemoteApprovalError("assertion distante invalide — action refusée")
    consume_nonce(str(envelope.payload["nonce"]), expires_at=int(envelope.payload["expires_at"]))
    log_receipt(envelope.payload, f"remote-passkey:{enrollment.credential_id}")
    return envelope.payload


def enroll_phone(registration: dict[str, Any]) -> PhoneEnrollment:
    """Enrôle la clé publique d'une passkey device-bound.

    Refuse à l'enrôlement (pas seulement à la vérification, ADR-0009 §3) :
    - une passkey *backup-eligible* (`be` armé) — synchronisable, pas liée à
      cet appareil ;
    - toute vérification autre que biométrique (`uv != "biometric"`, ex. PIN).
    """
    if registration.get("be"):
        raise RemoteApprovalError(
            "passkey synchronisable (backup-eligible) refusée — "
            "exiger un authentificateur device-bound"
        )
    if str(registration.get("uv") or "") != "biometric":
        raise RemoteApprovalError(
            "vérification biométrique requise à l'enrôlement — PIN/autre refusé"
        )
    credential_id = str(registration.get("credential_id") or "")
    public_key = str(registration.get("public_key") or "")
    if not credential_id or not public_key:
        raise RemoteApprovalError("credential_id / public_key requis à l'enrôlement")
    enrollment = PhoneEnrollment(
        credential_id=credential_id,
        aaguid=str(registration.get("aaguid") or ""),
        public_key=public_key,
        sign_count=int(registration.get("sign_count") or 0),
    )
    _save_enrollment(enrollment)
    return enrollment


def _save_enrollment(enrollment: PhoneEnrollment) -> None:
    path = enrollment_path()
    tmp = path.with_suffix(".tmp")
    tmp.write_text(canonical_json(enrollment.to_json()), encoding="utf-8")
    try:
        os.chmod(tmp, 0o600)
    except OSError:
        pass
    tmp.replace(path)
    try:
        os.chmod(path, 0o600)
    except OSError:
        pass


def load_enrollment() -> PhoneEnrollment | None:
    path = enrollment_path()
    if not path.is_file():
        return None
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        if isinstance(data, dict):
            return PhoneEnrollment.from_json(data)
    except (OSError, ValueError):
        pass
    return None


def _auth_data_bytes(*, uv: bool, be: bool, sign_count: int) -> bytes:
    """Octets `authenticatorData` minimaux (flags + sign_count) — WebAuthn-*shaped*,
    sans dépendance CBOR (POC, cf. ADR-0009, frontière POC/différé)."""
    flags = 0
    if uv:
        flags |= 0x04
    if be:
        flags |= 0x08
    return bytes([flags]) + int(sign_count).to_bytes(4, "big")


def _verify_p256_der(public_key_b64: str, message: bytes, signature_b64: str) -> bool:
    """Vérifie une signature P-256 (DER) via `openssl` — même approche que
    `gateway.elicitation.verify_p256` (pas de nouvelle dépendance lourde)."""
    try:
        pub_der = base64.b64decode(public_key_b64, validate=True)
        sig = base64.b64decode(signature_b64, validate=True)
    except Exception:
        return False
    pem_file = sig_file = der_file = None
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=".der") as df:
            df.write(pub_der)
            der_file = df.name
        conv = subprocess.run(
            ["openssl", "pkey", "-pubin", "-inform", "DER", "-in", der_file],
            capture_output=True,
            timeout=10,
        )
        if conv.returncode != 0 or not conv.stdout:
            return False
        with tempfile.NamedTemporaryFile(delete=False, suffix=".pem") as pf:
            pf.write(conv.stdout)
            pem_file = pf.name
        with tempfile.NamedTemporaryFile(delete=False) as sf:
            sf.write(sig)
            sig_file = sf.name
        proc = subprocess.run(
            ["openssl", "dgst", "-sha256", "-verify", pem_file, "-signature", sig_file],
            input=message,
            capture_output=True,
            timeout=10,
        )
        return proc.returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False
    finally:
        for p in (pem_file, sig_file, der_file):
            if p:
                try:
                    os.unlink(p)
                except OSError:
                    pass


def verify_assertion(
    envelope: ChallengeEnvelope, assertion: dict[str, Any], enrollment: PhoneEnrollment
) -> bool:
    """Vérifie l'assertion device-bound — un seul écart ⇒ refus total (ADR-0009 §3).

    Persiste `sign_count` (anti-clonage) SEULEMENT en cas de succès complet.
    """
    if not assertion:
        return False
    if str(assertion.get("credential_id") or "") != enrollment.credential_id:
        return False
    client_data = str(assertion.get("client_data") or "")
    if client_data != canonical_json(envelope.payload):
        return False  # défi != payload forgé — substitution (autre action/session) refusée
    auth = assertion.get("authenticator_data") or {}
    if not isinstance(auth, dict):
        return False
    if not auth.get("uv"):
        return False  # vérification utilisateur non armée
    if auth.get("be"):
        return False  # backup-eligible armé — passkey synced, refus
    try:
        sign_count = int(auth.get("sign_count"))
    except (TypeError, ValueError):
        return False
    if sign_count <= enrollment.sign_count:
        return False  # anti-clonage : sign_count doit strictement croître
    if int(time.time()) > int(envelope.payload.get("expires_at") or 0):
        return False  # défi expiré
    auth_bytes = _auth_data_bytes(uv=True, be=False, sign_count=sign_count)
    client_hash = hashlib.sha256(client_data.encode("utf-8")).digest()
    message = auth_bytes + client_hash
    signature = str(assertion.get("signature") or "")
    if not _verify_p256_der(enrollment.public_key, message, signature):
        return False
    enrollment.sign_count = sign_count
    _save_enrollment(enrollment)
    return True


def run_remote_approval_gate(
    fields: dict[str, Any], channel: ApprovalChannel, *, timeout: int = 120
) -> dict[str, Any]:
    """forge → send → await → verify → consume_nonce → log_receipt → payload signé.

    Retourne le payload SIGNÉ (porteur du `session_id` réel) — l'appelant DOIT
    exécuter avec cette valeur, jamais avec la `session_id` annoncée dans
    `fields` (ADR-0009 §5 / CA7 : interdit le rejeu cross-session).
    """
    enrollment = load_enrollment()
    if enrollment is None:
        raise RemoteApprovalError(
            "aucune passkey téléphone enrôlée — exécuter : "
            "scripts/remote-approval-cli.py enroll"
        )
    envelope = forge_challenge(fields)
    request_id = channel.send_challenge(envelope.to_json())
    assertion = channel.await_response(request_id, timeout=timeout)
    if not assertion:
        raise RemoteApprovalError(
            "aucune réponse du téléphone (refus, timeout ou canal indisponible) — action refusée"
        )
    if not verify_assertion(envelope, assertion, enrollment):
        raise RemoteApprovalError("assertion distante invalide — action refusée")
    consume_nonce(str(envelope.payload["nonce"]), expires_at=int(envelope.payload["expires_at"]))
    log_receipt(envelope.payload, f"remote-passkey:{enrollment.credential_id}")
    return envelope.payload
