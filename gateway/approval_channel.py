"""Interface de canal d'approbation distante (fiche 0078, ADR-0009 §4).

Le domaine (`remote_approval.py`) dépend de l'ABSTRACTION `ApprovalChannel`,
jamais d'un transport concret (DIP). `InMemoryChannel` est le seul canal du
POC : le simulateur de signeur téléphone (tests) dépose sa réponse en process,
aucun vrai réseau. Le futur relais aveugle chiffré E2E (épic 0077) sera une
seconde implémentation de la même interface.
"""
from __future__ import annotations

import secrets
from typing import Any, Protocol


class ApprovalChannel(Protocol):
    """Transport entre le Mac (holder) et le téléphone (signeur)."""

    def send_challenge(self, envelope: dict[str, Any]) -> str:
        """Envoie le défi (non secret) ; retourne un request_id pour await_response()."""
        ...

    def await_response(self, request_id: str, timeout: int = 120) -> dict[str, Any] | None:
        """Attend l'assertion signée ; None si timeout/refus/erreur (fail-closed)."""
        ...


class InMemoryChannel:
    """Canal POC — le simulateur de signeur téléphone répond en process."""

    def __init__(self) -> None:
        self._envelopes: dict[str, dict[str, Any]] = {}
        self._responses: dict[str, dict[str, Any] | None] = {}

    def send_challenge(self, envelope: dict[str, Any]) -> str:
        request_id = secrets.token_hex(8)
        self._envelopes[request_id] = envelope
        return request_id

    def envelope_for(self, request_id: str) -> dict[str, Any] | None:
        """Lu par le simulateur de signeur téléphone (tests) pour construire l'assertion."""
        return self._envelopes.get(request_id)

    def respond(self, request_id: str, assertion: dict[str, Any] | None) -> None:
        """Déposé par le simulateur de signeur téléphone (tests) — None = refus/absence."""
        self._responses[request_id] = assertion

    def await_response(self, request_id: str, timeout: int = 120) -> dict[str, Any] | None:
        # POC : réponse déjà déposée en process — aucune attente réseau réelle.
        return self._responses.get(request_id)
