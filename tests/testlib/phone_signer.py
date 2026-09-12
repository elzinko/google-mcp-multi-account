"""Simulateur de signeur téléphone (P-256, test uniquement) — fiche 0078.

Sert les tests hermétiques de `gateway.remote_approval` : génère une paire de
clés P-256 de test via `openssl` (aucune dépendance Python ajoutée — même
outillage que `gateway.elicitation.verify_p256`), et construit des assertions
WebAuthn-*shaped* qui miment un téléphone signant un défi.

N'est PAS un client WebAuthn réel (pas de CBOR/attestation) — le POC modélise
juste flags (UV/BE) + sign_count + signature P-256 sur `authData||sha256(clientData)`,
conformément à l'ADR-0009 §3 et à la frontière POC/différé.
"""
from __future__ import annotations

import base64
import hashlib
import json
import secrets
import subprocess
import tempfile
from pathlib import Path
from typing import Any


def generate_keypair(tmp_dir: Path) -> tuple[Path, str]:
    """Génère une paire P-256 ; retourne (chemin clé privée PEM, clé publique DER base64).

    Nom de fichier UNIQUE par appel (plusieurs paires peuvent coexister dans le
    même `tmp_dir`, ex. « bonne » clé vs clé d'attaquant dans un même test).
    """
    priv = tmp_dir / f"phone-private-{secrets.token_hex(8)}.pem"
    subprocess.run(
        ["openssl", "ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", str(priv)],
        check=True,
        capture_output=True,
    )
    pub_der = subprocess.run(
        ["openssl", "pkey", "-in", str(priv), "-pubout", "-outform", "DER"],
        check=True,
        capture_output=True,
    ).stdout
    return priv, base64.b64encode(pub_der).decode("ascii")


def _sign_der(priv_pem: Path, message: bytes) -> str:
    with tempfile.NamedTemporaryFile(delete=False) as sf:
        sig_file = sf.name
    try:
        subprocess.run(
            ["openssl", "dgst", "-sha256", "-sign", str(priv_pem), "-out", sig_file],
            input=message,
            check=True,
            capture_output=True,
        )
        return base64.b64encode(Path(sig_file).read_bytes()).decode("ascii")
    finally:
        Path(sig_file).unlink(missing_ok=True)


def _auth_data_bytes(*, uv: bool, be: bool, sign_count: int) -> bytes:
    flags = 0
    if uv:
        flags |= 0x04
    if be:
        flags |= 0x08
    return bytes([flags]) + int(sign_count).to_bytes(4, "big")


def sign_challenge(
    envelope_payload: dict[str, Any],
    priv_pem: Path,
    *,
    credential_id: str,
    sign_count: int,
    uv: bool = True,
    be: bool = False,
    client_data_override: str | None = None,
) -> dict[str, Any]:
    """Construit l'assertion signée que le téléphone renverrait pour ce défi.

    `client_data_override` permet aux tests d'attaque de signer un texte
    différent du payload forgé (substitution WYSIWYS).
    """
    client_data = client_data_override
    if client_data is None:
        client_data = json.dumps(
            envelope_payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False
        )
    auth_bytes = _auth_data_bytes(uv=uv, be=be, sign_count=sign_count)
    client_hash = hashlib.sha256(client_data.encode("utf-8")).digest()
    message = auth_bytes + client_hash
    signature = _sign_der(priv_pem, message)
    return {
        "credential_id": credential_id,
        "client_data": client_data,
        "authenticator_data": {"uv": uv, "be": be, "sign_count": sign_count},
        "signature": signature,
    }
