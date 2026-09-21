"""API publique stable de la gateway (consommée par le serveur MCP)."""
from __future__ import annotations

import base64
import hashlib
import json
import mimetypes
import os
import shutil
import tempfile
from collections.abc import Iterator
from contextlib import contextmanager
from pathlib import Path
from typing import Any, Optional

from .config import (
    client_id,
    download_dir,
    env,
    gwsa_root,
    profile_dir,
    upload_roots,
    upload_spool,
)
from .categorize import categorize, consequential_args, norm_service, operand_resource
from .context import get_git_root
from .elicitation import ElicitationError, run_elicitation_gate
from .errors import GatewayError
from .executor import run_via_broker
from .profiles import is_locked, list_profiles as _list_profiles
from .profiles import profile_email, validate_alias
from .project import git_toplevel
from .sessions import (
    is_session_unlocked,
    open_read_lease,
    require_session,
    session_grant_capability_session_lived,
    session_has_capability,
    transactional_enabled,
    transactional_lease_mode,
    try_consume_read_lease,
)
from .setup_status import setup_status  # noqa: F401 — re-export pour le dispatch MCP
from .usage import log_usage

# Borne défensive sur les pièces jointes Gmail : une PJ énorme (ou un
# identifiant malveillant) ne doit pas pouvoir saturer le disque local.
# 25 Mo = limite d'envoi Gmail ; surchargeable via MAG_ATTACHMENT_MAX_MB
# (GWSA_ATTACHMENT_MAX_MB reste accepté en repli).
try:
    _ATTACHMENT_MAX_MB = int(env("ATTACHMENT_MAX_MB", "25"))
except ValueError:
    _ATTACHMENT_MAX_MB = 25
_ATTACHMENT_MAX_BYTES = max(1, _ATTACHMENT_MAX_MB) * 1024 * 1024

# Champs Drive demandés partout : `owners`/`ownedByMe` répondent à « ce
# livrable appartient-il bien au bon compte ? » — la question que le
# multi-comptes pose à chaque dépôt (fiche 0024).
_DRIVE_FILE_FIELDS = (
    "id,name,mimeType,modifiedTime,parents,webViewLink,size,"
    "owners(emailAddress),ownedByMe"
)
_DRIVE_LIST_FIELDS = (
    "files(id,name,mimeType,modifiedTime,parents,"
    "owners(emailAddress),ownedByMe),nextPageToken"
)

# Contenu texte accepté par drive_create. Restreint à ce qui se rédige : Drive
# convertit ces formats vers un type Google, et un paramètre `content` (str)
# n'a de sens que pour du texte.
_CONTENT_TYPES = {
    "text/markdown": ".md",
    "text/plain": ".txt",
    "text/html": ".html",
    "text/csv": ".csv",
}
_GOOGLE_MIME_PREFIX = "application/vnd.google-apps."
_MAX_CONTENT_BYTES = 1_000_000

# Export texte par défaut selon le type Google (drive_read). Markdown pour un
# Doc (structure conservée), CSV pour un Sheet ; sinon texte brut.
_EXPORT_DEFAULTS = {
    "application/vnd.google-apps.document": "text/markdown",
    "application/vnd.google-apps.spreadsheet": "text/csv",
}
# Types non-Google lisibles tels quels (files get alt=media renvoie du texte).
_TEXTY_MIMES = {"application/json", "application/xml"}
_MAX_READ_CHARS = 1_000_000
# Plafond en octets d'un fichier lu par drive_read : le broker bufferise tout
# stdout en mémoire, donc on refuse AVANT de télécharger (quand la taille est
# connue — fichiers non Google). Les exports Google sont bornés par les limites
# d'export de Drive.
_MAX_READ_BYTES = 25_000_000
_MAX_UPLOAD_BYTES = 50_000_000


def profiles_list() -> dict[str, Any]:
    return {"ok": True, "profiles": _list_profiles()}


def _positionals(args: list[str]) -> list[str]:
    """Positionnels de gauche d'un appel gws (`<service> <resource…> <method>`),
    avant tout flag — même règle que `scripts/policy-check.py::positionals_of`
    (ne PAS reprendre après un flag, sinon la valeur d'un flag inconnu se ferait
    passer pour la méthode)."""
    out: list[str] = []
    for a in args:
        if a.startswith("-"):
            break
        out.append(a)
    return out


def _classify_operation(gws_args: list[str]) -> tuple[str, str, str, str, str | None]:
    """Classe un appel gws pour le point de contrôle transactionnel.

    Rend (op_class, resource, op_label, service, category) :
    - op_class ∈ {« lecture », « mutation »} — pilote le gate (bail vs acte signé) ;
    - resource : ressource opérante (prompt/reçu), via `operand_resource` — même
      source de vérité que policy-check ;
    - op_label : `service:ressources:méthode` (ex. « drive:permissions:create »)
      pour l'action SIGNÉE — distingue create de delete (Codex #147, P1) ;
    - service, category : nourrissent la capacité consentie (Zone 1).

    Réutilise `gateway.categorize` (source de vérité partagée avec policy-check et
    l'audit). Fail-closed : appel non classable → mutation (régime le plus strict)."""
    if not gws_args:
        return "mutation", "", "?", "", None
    service = norm_service(gws_args[0])
    pos = _positionals(gws_args[1:])
    if not pos:
        return "mutation", "", service, service, None
    resources, raw_method = pos[:-1], pos[-1]
    category = categorize(service, resources, raw_method)
    resource = operand_resource(service, resources, raw_method, gws_args)
    op_class = "lecture" if category == "read" else "mutation"
    op_label = ":".join([service, *resources, raw_method])
    return op_class, resource, op_label, service, category


def _bound_args(gws_args: list[str]) -> dict[str, Any]:
    """Arguments conséquents de l'acte (ADR-0012, Zone 3), pour le reçu signé et
    le prompt Touch ID — via la table `consequential_args` (même source de vérité
    que policy-check). Dict vide si rien de mappé (l'acte reste lié par op_label
    + target)."""
    if not gws_args:
        return {}
    service = norm_service(gws_args[0])
    pos = _positionals(gws_args[1:])
    if not pos:
        return {}
    resources, raw_method = pos[:-1], pos[-1]
    return consequential_args(service, resources, raw_method, gws_args)


def _consented_cap(service: str, category: str | None) -> dict[str, str]:
    """Capacité consentie qui voyage dans l'appel (ADR-0012, Zone 1).

    SANS ressource à dessein : un cap sans ressource matche tous les chemins de
    `policy-check` (Drive compris, vérifié avec `resource=""`), ce qui évite le
    re-deny du broker (Codex #147, P1). La fidélité fine (destinataire, sujet…)
    vit dans le PAYLOAD SIGNÉ (Zone 3), pas dans le périmètre d'autorisation. Le
    cap autorise `service:catégorie`, borné par policy ∩ manifeste, pour ce seul
    appel (jamais persisté). Catégorie inconnue → opération `*` sur le service
    (l'acte a été approuvé par Touch ID), jamais au-delà de la policy."""
    if not service:
        return {"service": "*", "operation": "*"}
    return {"service": service, "operation": category or "*"}


# Liste blanche d'éligibilité à la grâce « pour la session » (ADR-0013
# §Décision 4) : SEULEMENT read/create/update/delete. `share` et toute
# catégorie inconnue (None) en sont exclus par construction — ni lookup ni
# écriture de grâce, Touch ID par acte toujours (fail-closed par liste
# blanche, jamais par liste noire : une catégorie future non classée reste
# exclue tant qu'elle n'est pas explicitement ajoutée ici).
_GRACE_ELIGIBLE_CATEGORIES = {"read", "create", "update", "delete"}


def _is_delegated_session(sid: str) -> bool:
    """True si `sid` est une sous-session déléguée (pas la racine).

    Seule la session racine peut écrire une grâce
    (`session_grant_capability_session_lived` refuse sinon avec
    `GatewayError(code="error")`, cf. `_write_session_capability`). Une
    sous-session déléguée ne doit donc jamais être déclarée éligible à la
    grâce « pour la session » (ADR-0013 lot 6, fix P1 latent) — repli
    fail-closed si la session est illisible ici : `require_session` l'a déjà
    validée plus haut dans `_run`."""
    from .sessions import get_session
    state = get_session(sid)
    return bool(state and state.delegated)


def _normalize_grant_scope(raw: str) -> str:
    """Normalise la portée demandée par l'appel (ADR-0013 §Décision 3).

    ``once``/``session`` reconnus tels quels ; tout le reste (absent, vide,
    inconnu) replie sur ``once`` — seul un choix EXPLICITE « session » peut
    desserrer, jamais une valeur par défaut ou mal formée."""
    val = (raw or "").strip().lower()
    return val if val in ("once", "session") else "once"


def _transactional_gate(
    alias: str, gws_args: list[str], sid: str, grant_scope: str = "once",
) -> dict[str, str]:
    """Point de contrôle unique du consentement transactionnel (ADR-0011/0012,
    raffiné ADR-0013), appelé par `_run` quand `transactional_enabled()`. Rend
    la capacité consentie à porter jusqu'au broker (Zone 1).

    En mode ``manuel``, AVANT tout geste : (1) classer l'acte ; (2) garde-fou
    partage — seule une catégorie de la liste blanche est éligible à la
    grâce ; (3) si éligible ET une grâce couvre déjà ce périmètre exact
    (compte × service × catégorie × ressource, `session_has_capability`) :
    AUCUN geste, retour direct de la capacité consentie ; (4) sinon geste
    signé (usage unique, `consume_nonce`) puis, au succès, si la portée
    choisie est ``session`` ET la ressource est dérivable, écriture de la
    grâce (`session_grant_capability_session_lived`) — sans ressource
    dérivable, « session » retombe sur « une fois » (pas de grâce à l'échelle
    du service). Le broker reçoit toujours un `consented_cap` SANS ressource
    (`_consented_cap`) — `handle_exec` est inchangé (ADR-0012 Zone 1).

    En mode ``auto`` : mutation par acte (jamais de grâce, Décision 5) ;
    lecture groupée sous bail (TTL + budget) — inchangé.

    Fail-closed : geste refusé/absent (`ElicitationError`) → refus
    (`GatewayError` code="locked"), jamais un accès."""
    op_class, resource, op_label, service, category = _classify_operation(gws_args)
    # L'email est la vérité « quelle boîte » : le passer pour que le prompt/reçu
    # nomme le compte réel, pas juste l'alias, en multi-comptes (Codex #147, P2).
    email = profile_email(alias)
    mode = transactional_lease_mode()
    scope = _normalize_grant_scope(grant_scope)

    # (2) Garde-fou partage EN PREMIER : seul le mode manuel connaît la grâce
    # « pour la session », et seule une catégorie whitelistée y est éligible.
    # Garde (a) ADR-0013 lot 6, fix P1 : une sous-session déléguée n'est
    # jamais éligible — ni au lookup ni à l'écriture — pour ne jamais tenter
    # une écriture de grâce qu'elle n'a pas le droit de faire.
    grace_eligible = (
        mode == "manuel"
        and category in _GRACE_ELIGIBLE_CATEGORIES
        and not _is_delegated_session(sid)
    )

    # (3) Grâce déjà accordée pour ce périmètre exact → aucun geste.
    if grace_eligible and session_has_capability(sid, alias, service, category, resource):
        return _consented_cap(service, category)

    if op_class == "mutation" or mode == "manuel":
        prefix = "transactional_mutation" if op_class == "mutation" else "transactional_read"
        try:
            run_elicitation_gate(
                {
                    "action": f"{prefix}:{op_label}",
                    "alias": alias,
                    "email": email,
                    "target": resource,
                    "session_id": sid,
                    # Zone 3 : lier les arguments conséquents (qui reçoit quoi) au
                    # reçu signé + au prompt. Vide pour une lecture (mode manuel).
                    "bound_args": _bound_args(gws_args) if op_class == "mutation" else {},
                    # ADR-0013 §Décision 3 : portée signée, threadée depuis l'appel.
                    "grant_scope": scope,
                }
            )
        except ElicitationError as e:
            raise GatewayError(f"acte refusé — {e}", code="locked") from e
        # (4) Au succès : « pour la session » écrit la grâce — seulement si
        # éligible ET ressource dérivable (repli fail-closed sur « une fois »).
        # Garde (b) ADR-0013 lot 6, fix P1 : mémoriser la grâce ne doit JAMAIS
        # faire échouer un acte déjà approuvé (Touch ID déjà consommé) — un
        # échec d'écriture (ex. concurrence, cas non prévu par la garde (a))
        # retombe silencieusement sur « une fois » plutôt que de remonter.
        if grace_eligible and scope == "session" and resource:
            try:
                session_grant_capability_session_lived(sid, alias, service, category, resource)
            except GatewayError:
                pass
        return _consented_cap(service, category)
    # Lecture (mode auto) : consommer un slot de bail ATOMIQUEMENT (check +
    # décrément sous verrou) pour ne pas dépasser le budget signé sous concurrence
    # (Codex #147, P1). Slot indisponible → un geste ouvre un bail frais.
    if not try_consume_read_lease(sid, alias):
        try:
            run_elicitation_gate(
                {
                    "action": "transactional_read_lease",
                    "alias": alias,
                    "email": email,
                    "session_id": sid,
                }
            )
        except ElicitationError as e:
            raise GatewayError(f"bail de lecture refusé — {e}", code="locked") from e
        open_read_lease(sid, alias)
        if not try_consume_read_lease(sid, alias):
            raise GatewayError(
                "bail de lecture indisponible après consentement", code="locked"
            )
    return _consented_cap(service, category)


def _run(
    alias: str,
    gws_args: list[str],
    timeout: int = 60,
    raw_output: bool = False,
    session: str = "",
    grant_scope: str = "once",
) -> Any:
    """Exécute un appel gws via le broker, autorisé par le jeton PORTÉ par cet appel.

    Fail-closed (ADR-0007 §Repli) : jeton absent, inconnu ou expiré → refus,
    quel que soit l'état de verrouillage du profil. Plus de repli sur un état
    global de process — le jeton n'est jamais lu ailleurs que dans `session`,
    le paramètre que l'appelant (gateway.mcp_server) a extrait de CET appel.

    `grant_scope` (ADR-0013 §Décision 3) : indice de portée « une fois »
    (défaut) / « pour la session » threadé au niveau de CET appel jusqu'au
    gate transactionnel — jamais un argument métier par outil (lot 5 câble sa
    source réelle, l'admin/Swift ; ici le défaut `once` préserve bit pour bit
    le comportement des appelants qui ne le passent pas encore).
    """
    sid = (session or "").strip()
    gro = get_git_root() or git_toplevel()
    consented_cap: dict[str, str] | None = None
    try:
        # Guidage adaptatif : en mode « élicitation dans la conversation », pointer
        # le LLM vers les tools MCP (zéro terminal) plutôt que vers « mag … » —
        # sinon le LLM relaie une commande terminale que l'utilisateur refuse.
        from .elicitation import in_conversation_enabled
        inconv = in_conversation_enabled()
        if not sid:
            raise GatewayError(
                (
                    "aucune session pour cette conversation — appeler d'abord le "
                    "tool session_open_in_conversation (popup Touch ID) pour en "
                    "ouvrir une, puis porter le session_id obtenu dans « session »"
                )
                if inconv else
                (
                    "jeton de session requis — paramètre « session » manquant sur "
                    "cet appel (obtenu à l'initialize, ou via access_request)"
                ),
                code="session",
            )
        require_session(sid)  # lève si jeton inconnu ou expiré (TTL)
        d = profile_dir(alias)
        if not d.is_dir():
            raise GatewayError(
                f"profil inconnu « {alias} » — le créer avec : mag add {alias}",
                code="not_found",
            )
        if transactional_enabled():
            # ADR-0011/0012 : le modèle transactionnel REMPLACE la fenêtre minutes.
            # Le gate route lecture/mutation (bail ou acte signé) indépendamment
            # de .locked, et produit la capacité consentie portée au broker (Zone 1).
            consented_cap = _transactional_gate(alias, gws_args, sid, grant_scope=grant_scope)
        elif is_locked(d) and not is_session_unlocked(sid, alias):
            raise GatewayError(
                (
                    f"profil « {alias} » verrouillé — appeler le tool "
                    f"session_unlock_in_conversation sur « {alias} » (popup Touch ID)"
                )
                if inconv else
                (
                    f"profil « {alias} » verrouillé pour cette session — "
                    f"access_request kind=session_unlock"
                ),
                code="locked",
            )
    except GatewayError as e:
        if e.code in ("locked", "session"):
            log_usage(
                alias, gws_args, client_id(), decision="refus", reason=e.code,
                session_id=sid, git_root=gro,
            )
        raise
    return run_via_broker(
        alias, gws_args, timeout=timeout, raw_output=raw_output, session_id=sid,
        consented_cap=consented_cap,
        # Mode porté par la requête (le cap n'est posé QUE par le gate
        # transactionnel) → le broker ne dépend plus de son env de démarrage.
        transactional=consented_cap is not None,
    )


def gmail_list(
    alias: str,
    query: str = "",
    max_results: int = 10,
    session: str = "",
) -> dict[str, Any]:
    validate_alias(alias)
    max_results = max(1, min(int(max_results), 50))
    params: dict[str, Any] = {"userId": "me", "maxResults": max_results}
    if query:
        params["q"] = query
    data = _run(
        alias,
        ["gmail", "users", "messages", "list", "--params", json.dumps(params)],
        session=session,
    )
    return {"ok": True, "alias": alias, "result": data}


def gmail_get(
    alias: str, message_id: str, format: str = "full", session: str = "",
) -> dict[str, Any]:
    validate_alias(alias)
    if not message_id or not isinstance(message_id, str):
        raise GatewayError("message_id requis", code="error")
    fmt = format if format in ("full", "metadata", "minimal", "raw") else "full"
    params = {"userId": "me", "id": message_id, "format": fmt}
    data = _run(
        alias,
        ["gmail", "users", "messages", "get", "--params", json.dumps(params)],
        session=session,
    )
    return {"ok": True, "alias": alias, "result": data}


def gmail_create_draft(
    alias: str,
    to: str,
    subject: str,
    body: str,
    cc: str = "",
    session: str = "",
) -> dict[str, Any]:
    """Crée un brouillon — jamais d'envoi (pas de tool send en v1).

    Pas de `grant_scope` : un brouillon n'a pas de périmètre-ressource (dossier),
    et sa catégorie ``drafts`` n'est pas éligible à la grâce « pour la session »
    (cf. `_GRACE_ELIGIBLE_CATEGORIES`). Exposer le choix mentirait — il retomberait
    toujours sur « une fois » (Codex #150). Un brouillon reste signé par acte."""
    validate_alias(alias)
    if not to or not subject:
        raise GatewayError("to et subject sont requis", code="error")
    # Anti-injection d'en-têtes (Codex #149) : un CR/LF dans to/cc/subject
    # injecterait des en-têtes arbitraires dans le message RFC (ex. un « Bcc: »
    # caché → destinataire réel mais ABSENT du reçu signé/prompt). Refus net au
    # bord de l'API : le message signé décrit alors exactement ce qui est créé.
    for _label, _val in (("to", to), ("cc", cc), ("subject", subject)):
        if "\r" in _val or "\n" in _val:
            raise GatewayError(
                f"« {_label} » contient un saut de ligne interdit (injection d'en-tête)",
                code="error",
            )
    # Message RFC 2822 minimal, encodé raw base64url — gws drafts.create attend --json.
    headers = [f"To: {to}", f"Subject: {subject}"]
    if cc:
        headers.append(f"Cc: {cc}")
    headers.append("Content-Type: text/plain; charset=utf-8")
    raw = ("\r\n".join(headers) + "\r\n\r\n" + (body or "")).encode("utf-8")
    raw_b64 = base64.urlsafe_b64encode(raw).decode("ascii").rstrip("=")
    payload = {"message": {"raw": raw_b64}}
    # `--json` porte le corps, `--params` le paramètre de CHEMIN userId
    # (gmail/v1/users/{userId}/drafts). Sans lui, gws refuse avant tout appel :
    # « Required path parameter userId is missing » (fiche 0024).
    data = _run(
        alias,
        [
            "gmail", "users", "drafts", "create",
            "--params", json.dumps({"userId": "me"}),
            "--json", json.dumps(payload),
        ],
        session=session,
    )
    return {"ok": True, "alias": alias, "result": data}


def _ownership(f: Any) -> dict[str, Any]:
    """Propriétaire d'un fichier Drive, lisible sans fouiller la réponse brute.

    `owned_by_me` vaut None quand l'API ne renseigne pas `ownedByMe` (cas des
    Drive partagés) : « inconnu » plutôt qu'un « non » inventé.
    """
    if not isinstance(f, dict):
        return {"owner": "", "owned_by_me": None}
    owners = f.get("owners")
    owner = ""
    if isinstance(owners, list) and owners and isinstance(owners[0], dict):
        owner = owners[0].get("emailAddress") or ""
    return {"owner": owner, "owned_by_me": f.get("ownedByMe")}


def drive_list(
    alias: str,
    query: str = "trashed=false",
    page_size: int = 20,
    parent: Optional[str] = None,
    session: str = "",
) -> dict[str, Any]:
    validate_alias(alias)
    page_size = max(1, min(int(page_size), 100))
    q = query or "trashed=false"
    if parent:
        q = f"'{parent}' in parents and ({q})"
    params = {
        "pageSize": page_size,
        "q": q,
        "fields": _DRIVE_LIST_FIELDS,
    }
    data = _run(
        alias,
        ["drive", "files", "list", "--params", json.dumps(params)],
        session=session,
    )
    files = data.get("files") if isinstance(data, dict) else None
    ownership = [
        {"id": f.get("id"), "name": f.get("name"), **_ownership(f)}
        for f in files
        if isinstance(f, dict)
    ] if isinstance(files, list) else []
    return {"ok": True, "alias": alias, "result": data, "ownership": ownership}


def drive_get(alias: str, file_id: str, session: str = "") -> dict[str, Any]:
    validate_alias(alias)
    if not file_id:
        raise GatewayError("file_id requis", code="error")
    params = {
        "fileId": file_id,
        "fields": _DRIVE_FILE_FIELDS,
    }
    data = _run(
        alias,
        ["drive", "files", "get", "--params", json.dumps(params)],
        session=session,
    )
    return {"ok": True, "alias": alias, "result": data, **_ownership(data)}


def _content_type_for(content_type: str, mime_type: str) -> str:
    """Format du texte envoyé, et donc source de conversion côté Drive."""
    ct = (content_type or "").strip().lower()
    if not ct:
        # Cible Google (Doc/Sheet/Slides) : Drive convertit depuis la source.
        # Markdown par défaut — c'est le format dans lequel les agents rédigent,
        # et titres/listes/gras arrivent rendus dans le document.
        # Cible ordinaire : le texte est déposé tel quel.
        ct = "text/markdown" if mime_type.startswith(_GOOGLE_MIME_PREFIX) else mime_type
    if ct not in _CONTENT_TYPES:
        raise GatewayError(
            f"content_type « {ct} » non supporté — formats texte acceptés : "
            f"{', '.join(sorted(_CONTENT_TYPES))}",
            code="error",
        )
    return ct


@contextmanager
def _spooled_content(content: str, content_type: str) -> Iterator[Path]:
    """Écrit le contenu dans le répertoire de dépôt du broker, le temps d'un appel.

    gws n'accepte un média que par chemin de fichier (`--upload`), et refuse
    tout chemin hors de son répertoire courant — qui est précisément ce
    répertoire de dépôt (ADR-0003). Fichier en 0600, effacé quoi qu'il arrive.
    """
    raw = content.encode("utf-8")
    if len(raw) > _MAX_CONTENT_BYTES:
        raise GatewayError(
            f"contenu trop volumineux ({len(raw)} octets, maximum "
            f"{_MAX_CONTENT_BYTES}) — déposer un fichier plus court",
            code="error",
        )
    fd, tmp = tempfile.mkstemp(
        dir=str(upload_spool()),
        prefix="content-",
        suffix=_CONTENT_TYPES[content_type],
    )
    path = Path(tmp)
    try:
        with os.fdopen(fd, "wb") as fh:
            fh.write(raw)
        yield path
    finally:
        try:
            path.unlink()
        except OSError:
            pass


def drive_create(
    alias: str,
    name: str,
    parent_id: str,
    mime_type: str = "application/vnd.google-apps.document",
    content: str = "",
    content_type: str = "",
    session: str = "",
    grant_scope: str = "once",
) -> dict[str, Any]:
    """Crée un fichier sous parent_id — soumis aux zones Drive (policy + grants).

    Avec `content`, le texte part en upload multipart dans la même requête et
    Drive le convertit vers `mime_type` : un Google Doc rédigé, pas une coquille
    vide. Sans `content`, le fichier est créé vide (comportement historique).
    """
    validate_alias(alias)
    if not name or not parent_id:
        raise GatewayError("name et parent_id sont requis", code="error")
    body = {
        "name": name,
        "mimeType": mime_type,
        # `parents` doit rester dans --json : c'est le seul endroit que
        # scripts/policy-check.py lit pour vérifier la zone d'écriture.
        "parents": [parent_id],
    }
    args = [
        "drive", "files", "create",
        "--params", json.dumps({"fields": _DRIVE_FILE_FIELDS}),
        "--json", json.dumps(body),
    ]
    if not content:
        data = _run(alias, args, session=session, grant_scope=grant_scope)
        return {"ok": True, "alias": alias, "result": data, **_ownership(data)}
    ctype = _content_type_for(content_type, mime_type)
    with _spooled_content(content, ctype) as path:
        data = _run(
            alias,
            [*args, "--upload", str(path), "--upload-content-type", ctype],
            session=session,
            grant_scope=grant_scope,
        )
    return {"ok": True, "alias": alias, "result": data, **_ownership(data)}


def _raw_text(data: Any) -> str:
    """Texte verbatim d'une réponse broker `raw_output=True` : le broker garantit
    {"raw": <str>} sans strip ni json.loads — un fichier vide vaut "", un .json
    est rendu tel quel. On ne re-sérialise jamais (ce serait reformater le fichier)."""
    raw = data.get("raw") if isinstance(data, dict) else None
    return raw if isinstance(raw, str) else ""


def _reject_oversize(meta: Any, label: str) -> None:
    """Refuse un fichier trop gros AVANT de le télécharger (le broker bufferise
    tout stdout en mémoire). `size` n'est renseigné que pour les fichiers non
    Google — sans lui, on laisse passer (exports Google bornés par Drive)."""
    size = meta.get("size") if isinstance(meta, dict) else None
    try:
        n = int(size)
    except (TypeError, ValueError):
        return
    if n > _MAX_READ_BYTES:
        raise GatewayError(
            f"« {label} » ({n} octets) dépasse la limite de lecture "
            f"({_MAX_READ_BYTES}) — le récupérer via drive_get / webViewLink",
            code="error",
        )


def drive_read(
    alias: str,
    file_id: str,
    format: str = "",
    max_chars: int = 100_000,
    session: str = "",
) -> dict[str, Any]:
    """Lit le CONTENU d'un fichier Drive en texte (lecture, sous verrou).

    Fichier Google (Doc/Sheet/…) : export vers un format texte — markdown par
    défaut pour un Doc, CSV pour un Sheet. Fichier ordinaire : téléchargé tel
    quel s'il est textuel. Les binaires (PDF, images) ne sont pas lisibles ici.
    """
    validate_alias(alias)
    if not file_id:
        raise GatewayError("file_id requis", code="error")
    fmt = (format or "").strip().lower()
    if fmt and fmt not in _CONTENT_TYPES:
        raise GatewayError(
            f"format « {fmt} » non supporté — formats texte acceptés : "
            f"{', '.join(sorted(_CONTENT_TYPES))}",
            code="error",
        )
    max_chars = max(1_000, min(int(max_chars), _MAX_READ_CHARS))
    meta = _run(
        alias,
        ["drive", "files", "get", "--params",
         json.dumps({"fileId": file_id, "fields": "id,name,mimeType,size"})],
        session=session,
    )
    mime = (meta.get("mimeType") or "") if isinstance(meta, dict) else ""
    name = (meta.get("name") or "") if isinstance(meta, dict) else ""
    # raw_output=True : le broker renvoie stdout VERBATIM ({"raw": <texte>}),
    # sans strip ni json.loads — sinon une fin de ligne saute, un fichier vide
    # devient "{}", et un .json est reparsé/reformaté (clés dédupliquées).
    if mime.startswith(_GOOGLE_MIME_PREFIX):
        export_mime = fmt or _EXPORT_DEFAULTS.get(mime, "text/plain")
        data = _run(
            alias,
            ["drive", "files", "export", "--params",
             json.dumps({"fileId": file_id, "mimeType": export_mime})],
            raw_output=True,
            session=session,
        )
    elif mime.startswith("text/") or mime in _TEXTY_MIMES:
        _reject_oversize(meta, name or file_id)  # taille connue hors Google
        export_mime = mime
        data = _run(
            alias,
            ["drive", "files", "get", "--params",
             json.dumps({"fileId": file_id, "alt": "media"})],
            raw_output=True,
            session=session,
        )
    else:
        raise GatewayError(
            f"« {name or file_id} » ({mime or 'type inconnu'}) n'est pas lisible "
            f"en texte — drive_read couvre les fichiers Google (export) et les "
            f"fichiers texte",
            code="error",
        )
    content = _raw_text(data)
    truncated = len(content) > max_chars
    return {
        "ok": True,
        "alias": alias,
        "file_id": file_id,
        "name": name,
        "mime_type": mime,
        "export_mime_type": export_mime,
        "content": content[:max_chars],
        "truncated": truncated,
    }


def drive_copy(
    alias: str,
    file_id: str,
    parent_id: str,
    name: str = "",
    session: str = "",
    grant_scope: str = "once",
) -> dict[str, Any]:
    """Copie un fichier Drive vers parent_id — soumis aux zones côté destination.

    Copie native (files.copy) : un Sheet reste un Sheet, un binaire un binaire —
    le cas « dupliquer un modèle vers le dossier client » sans passer par un
    export/recréation.
    """
    validate_alias(alias)
    if not file_id or not parent_id:
        raise GatewayError("file_id et parent_id sont requis", code="error")
    # `parents` dans --json : seul endroit que scripts/policy-check.py lit pour
    # vérifier la zone d'écriture (même règle que drive_create).
    body: dict[str, Any] = {"parents": [parent_id]}
    if name:
        body["name"] = name
    data = _run(
        alias,
        [
            "drive", "files", "copy",
            "--params", json.dumps({"fileId": file_id, "fields": _DRIVE_FILE_FIELDS}),
            "--json", json.dumps(body),
        ],
        session=session,
        grant_scope=grant_scope,
    )
    return {"ok": True, "alias": alias, "result": data, **_ownership(data)}


def drive_upload(
    alias: str,
    path: str,
    parent_id: str,
    name: str = "",
    mime_type: str = "",
    session: str = "",
    grant_scope: str = "once",
) -> dict[str, Any]:
    """Téléverse un fichier local (binaire compris) — soumis aux zones Drive.

    Le média transite par le répertoire de dépôt du broker (ADR-0003), sans
    conversion : un PDF déposé reste un PDF. Jamais de lecture sous GWSA_ROOT
    (tokens/credentials) — seule exception, le répertoire de téléchargement
    .downloads (re-téléverser une pièce jointe reçue est un cas légitime).
    """
    validate_alias(alias)
    if not path or not parent_id:
        raise GatewayError("path et parent_id sont requis", code="error")
    src = Path(path).expanduser()
    if not src.is_file():
        raise GatewayError(f"fichier introuvable : {src}", code="error")
    resolved = src.resolve()
    root = gwsa_root().resolve()
    dl = download_dir().resolve()
    under_dl = resolved == dl or dl in resolved.parents
    under_root = resolved == root or root in resolved.parents
    # Garde 1 (dur) : jamais les tokens/credentials, même si GWSA_UPLOAD_ROOTS
    # était mal configuré pour englober GWSA_ROOT. Seul .downloads y échappe.
    if under_root and not under_dl:
        raise GatewayError(
            "lecture refusée sous le répertoire des comptes (tokens/credentials) "
            "— seul son sous-répertoire .downloads est re-téléversable",
            code="error",
        )
    # Garde 2 (liste blanche, défaut-deny) : la source doit être .downloads ou
    # un dossier explicitement ouvert dans GWSA_UPLOAD_ROOTS. Sinon le LLM
    # pourrait lire un chemin arbitraire (ex. ~/.ssh/id_rsa) et l'exfiltrer vers
    # une zone Drive active — atteignable par le seul MCP, sans shell (ADR-0006).
    allowed = [dl, *upload_roots()]
    if not any(resolved == a or a in resolved.parents for a in allowed):
        raise GatewayError(
            f"source « {src} » hors des dossiers autorisés au téléversement — "
            f"déposer le fichier dans .downloads, ou déclarer son dossier dans "
            f"<GWSA_ROOT>/.upload-roots (un chemin absolu par ligne) ou la "
            f"variable GWSA_UPLOAD_ROOTS",
            code="error",
        )
    size = src.stat().st_size
    if size > _MAX_UPLOAD_BYTES:
        raise GatewayError(
            f"fichier trop volumineux ({size} octets, maximum {_MAX_UPLOAD_BYTES})",
            code="error",
        )
    mime = mime_type or mimetypes.guess_type(src.name)[0] or "application/octet-stream"
    body = {
        "name": name or src.name,
        # Pas de mimeType dans le corps : aucune conversion, le fichier garde
        # le type du média téléversé.
        "parents": [parent_id],
    }
    args = [
        "drive", "files", "create",
        "--params", json.dumps({"fields": _DRIVE_FILE_FIELDS}),
        "--json", json.dumps(body),
    ]
    # Même contrainte que _spooled_content : gws n'accepte un média que par un
    # chemin sous son cwd = le répertoire de dépôt (ADR-0003).
    fd, tmp = tempfile.mkstemp(
        dir=str(upload_spool()), prefix="upload-", suffix=src.suffix[:16],
    )
    spool = Path(tmp)
    try:
        with os.fdopen(fd, "wb") as out, open(src, "rb") as inp:
            shutil.copyfileobj(inp, out)
        data = _run(
            alias,
            [*args, "--upload", str(spool), "--upload-content-type", mime],
            session=session,
            grant_scope=grant_scope,
        )
    finally:
        try:
            spool.unlink()
        except OSError:
            pass
    return {
        "ok": True,
        "alias": alias,
        "result": data,
        **_ownership(data),
        "size": size,
        "mime_type": mime,
    }


def _safe_filename(filename: str) -> str:
    """Nom de fichier inoffensif : nom de base seul, jamais caché, jamais vide."""
    base = os.path.basename((filename or "").replace("\\", "/"))
    # Filtrer séparateurs / deux-points / non-imprimables AVANT de retirer les
    # points de tête : sinon un caractère-écran (« :.env », « \x00.bashrc »)
    # masque un point que le filtre promeut ensuite en tête → fichier caché.
    base = "".join(c for c in base if c.isprintable() and c not in '/\\:')
    base = base.strip().lstrip(". ")[:120]
    return base or "piece-jointe.bin"



def drive_update(
    alias: str,
    file_id: str,
    name: str = "",
    content: Optional[str] = None,
    content_type: str = "",
    mime_type: str = "",
    session: str = "",
    grant_scope: str = "once",
) -> dict[str, Any]:
    """Met à jour un fichier Drive (nom et/ou contenu) — soumis aux zones.

    `file_id` doit être sous une zone autorisée. `content=None` = pas de
    changement de contenu ; `content=""` = payload vide (vider le fichier).

    ⚠ Avec un `content`, c'est un **remplacement INTÉGRAL** du contenu (media
    upload), pas une édition partielle. Réservé aux fichiers **non-natifs** :
    un fichier Google natif (Doc/Sheet/Slide) ne s'édite pas par media upload
    (API Docs/Sheets non implémentée) → refus explicite (revue F5).
    """
    validate_alias(alias)
    if not file_id:
        raise GatewayError("file_id requis", code="error")
    if not name and content is None:
        raise GatewayError(
            "au moins un de name ou content est requis", code="error",
        )
    body: dict[str, Any] = {}
    if name:
        body["name"] = name
    if mime_type:
        body["mimeType"] = mime_type
    args = [
        "drive", "files", "update",
        "--params", json.dumps({"fileId": file_id, "fields": _DRIVE_FILE_FIELDS}),
        "--json", json.dumps(body),
    ]
    if content is None:
        data = _run(alias, args, session=session, grant_scope=grant_scope)
        return {"ok": True, "alias": alias, "result": data, **_ownership(data)}
    # content = remplacement INTÉGRAL (media upload). On lit d'abord le vrai
    # mimeType : un fichier Google natif ne s'édite pas ainsi (média ≠ contenu
    # structuré) → refus plutôt qu'échec silencieux / corruption d'un binaire
    # (revue F5 / Codex P1). « content » réservé aux fichiers non-natifs.
    # (lecture incidente, PAS la mutation choisie par l'appelant : la portée
    # demandée ne s'applique qu'à l'acte d'écriture ci-dessous)
    current = _run(
        alias,
        ["drive", "files", "get", "--params",
         json.dumps({"fileId": file_id, "fields": "mimeType"})],
        session=session,
    )
    current_mime = current.get("mimeType", "") if isinstance(current, dict) else ""
    if current_mime.startswith("application/vnd.google-apps."):
        raise GatewayError(
            f"drive_update ne peut pas remplacer le contenu d'un fichier Google "
            f"natif ({current_mime}) — édition via l'API Docs/Sheets non "
            f"implémentée ; « content » n'est supporté que sur un fichier non-natif",
            code="error",
        )
    target_mime = mime_type or current_mime or "text/plain"
    ctype = _content_type_for(content_type, target_mime)
    with _spooled_content(content, ctype) as path:
        data = _run(
            alias,
            [*args, "--upload", str(path), "--upload-content-type", ctype],
            session=session,
            grant_scope=grant_scope,
        )
    return {"ok": True, "alias": alias, "result": data, **_ownership(data)}


_PERMISSION_FIELDS = (
    "id,type,role,emailAddress,displayName,deleted,permissionDetails"
)


def drive_permissions_list(
    alias: str,
    file_id: str,
    page_size: int = 100,
    page_token: str = "",
    session: str = "",
) -> dict[str, Any]:
    """Liste les permissions d'un fichier (lecture).

    Au-delà de 100 permissions, le résultat porte `nextPageToken` : le rappeler
    via `page_token` pour la page suivante — sinon les permissions au-delà de la
    1ʳᵉ page seraient omises et `drive_permissions_delete` inopérant dessus (F6).
    """
    validate_alias(alias)
    if not file_id:
        raise GatewayError("file_id requis", code="error")
    page_size = max(1, min(int(page_size), 100))
    params = {
        "fileId": file_id,
        "pageSize": page_size,
        "fields": f"permissions({_PERMISSION_FIELDS}),nextPageToken",
    }
    if page_token:
        params["pageToken"] = page_token
    data = _run(
        alias,
        ["drive", "permissions", "list", "--params", json.dumps(params)],
        session=session,
    )
    return {"ok": True, "alias": alias, "result": data}


def drive_permissions_create(
    alias: str,
    file_id: str,
    email: str,
    role: str = "reader",
    transfer_ownership: bool = False,
    send_notification: bool = False,
    session: str = "",
) -> dict[str, Any]:
    """Partage un fichier avec un utilisateur (reader/commenter/writer).

    Nécessite `drive.share:true` dans la policy. Action visible — confirmer avec
    l'humain avant d'appeler. Le transfert de propriété (`transfer_ownership`) est
    déplacé dans une PR dédiée (non prête) et refusé ici.
    """
    validate_alias(alias)
    # Booléens STRICTS : « transfer_ownership » est destructif (don de propriété).
    # Le dispatch MCP ne valide pas le schéma → une chaîne "false" ne doit jamais
    # être coercée en vrai (revue Codex). On refuse tout non-booléen.
    if not isinstance(transfer_ownership, bool):
        raise GatewayError("transfer_ownership doit être un booléen (true/false)", code="error")
    if not isinstance(send_notification, bool):
        raise GatewayError("send_notification doit être un booléen (true/false)", code="error")
    if not file_id or not email:
        raise GatewayError("file_id et email sont requis", code="error")
    if "@" not in email:
        raise GatewayError("email invalide", code="error")
    role = (role or "reader").lower().strip()
    # Transfert de propriété RETIRÉ de cette version : destructif, garde de sécurité
    # à concevoir (zones / grant de session / Touch ID) et à valider sur de vrais
    # comptes @gmail.com → déplacé dans une PR dédiée, non prête. Ici : partage
    # lecture/écriture seulement.
    if transfer_ownership:
        raise GatewayError(
            "transfert de propriété non disponible dans cette version "
            "(fonction déplacée dans une PR dédiée, non prête)",
            code="error",
        )
    allowed_roles = {"reader", "commenter", "writer"}
    if role not in allowed_roles:
        raise GatewayError(
            f"role « {role} » invalide — valeurs : {', '.join(sorted(allowed_roles))}",
            code="error",
        )
    params: dict[str, Any] = {
        "fileId": file_id,
        "fields": _PERMISSION_FIELDS,
        "sendNotificationEmail": bool(send_notification),
    }
    body: dict[str, Any] = {
        "type": "user",
        "role": role,
        "emailAddress": email,
    }
    data = _run(
        alias,
        [
            "drive", "permissions", "create",
            "--params", json.dumps(params),
            "--json", json.dumps(body),
        ],
        session=session,
    )
    return {
        "ok": True,
        "alias": alias,
        "result": data,
        "transfer_ownership": transfer_ownership,
    }


def drive_permissions_delete(
    alias: str,
    file_id: str,
    permission_id: str,
    session: str = "",
) -> dict[str, Any]:
    """Révoque une permission (policy share requise)."""
    validate_alias(alias)
    if not file_id or not permission_id:
        raise GatewayError("file_id et permission_id sont requis", code="error")
    params = {"fileId": file_id, "permissionId": permission_id}
    _run(
        alias,
        ["drive", "permissions", "delete", "--params", json.dumps(params)],
        session=session,
    )
    return {"ok": True, "alias": alias, "deleted": permission_id}

def gmail_attachment_get(
    alias: str,
    message_id: str,
    attachment_id: str,
    filename: str = "",
    session: str = "",
) -> dict[str, Any]:
    """Télécharge une pièce jointe (lecture, sous verrou) vers .downloads.

    La destination n'est JAMAIS choisie par l'appelant (ADR-0006) : une pièce
    jointe est un contenu tiers, l'écrire sur un chemin arbitraire serait un
    vecteur d'attaque. Noms uniques — jamais d'écrasement.
    """
    validate_alias(alias)
    if not message_id or not attachment_id:
        raise GatewayError("message_id et attachment_id sont requis", code="error")
    params = {"userId": "me", "messageId": message_id, "id": attachment_id}
    data = _run(
        alias,
        ["gmail", "users", "messages", "attachments", "get",
         "--params", json.dumps(params)],
        session=session,
    )
    b64 = data.get("data") if isinstance(data, dict) else None
    if not isinstance(b64, str):
        raise GatewayError(
            "réponse sans données de pièce jointe (message_id / attachment_id "
            "à vérifier via gmail_get)",
            code="exec",
        )
    # b64 == "" est une pièce jointe légitimement vide (0 octet) : on écrit un
    # fichier vide plutôt que d'accuser à tort les identifiants.
    raw = base64.urlsafe_b64decode(b64 + "=" * (-len(b64) % 4))
    if len(raw) > _ATTACHMENT_MAX_BYTES:
        raise GatewayError(
            f"pièce jointe trop volumineuse : {len(raw)} octets > "
            f"{_ATTACHMENT_MAX_BYTES} (borne GWSA_ATTACHMENT_MAX_MB)",
            code="error",
        )
    base = Path(_safe_filename(filename))
    dest_dir = download_dir()
    for i in range(1000):
        suffix = "" if i == 0 else f"-{i}"
        dest = dest_dir / f"{base.stem}{suffix}{base.suffix}"
        try:
            fd = os.open(dest, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
            break
        except FileExistsError:
            continue
    else:
        raise GatewayError("impossible de créer un nom de fichier unique", code="error")
    with os.fdopen(fd, "wb") as fh:
        fh.write(raw)
    return {
        "ok": True,
        "alias": alias,
        "path": str(dest),
        "filename": dest.name,
        "size": len(raw),
        "sha256": hashlib.sha256(raw).hexdigest(),
    }


def _bootstrap_no_session(kind: str) -> dict[str, Any]:
    """Bootstrap SANS jeton (ADR-0007 §Repli) : le seul chemin qu'un appel sans

    jeton peut emprunter est l'élicitation de CRÉATION de session — jamais un
    accès données. `access_request` reste utilisable sans jeton (ce n'est pas
    un tool de données), mais un kind qui exige une session en pointe ici vers
    `mag session open`, plutôt que d'échouer sans piste.
    """
    from .elicitation import in_conversation_enabled
    if in_conversation_enabled():
        return {
            "ok": True,
            "elicitation": True,
            "kind": "session_open",
            "requested_kind": kind,
            "message": (
                f"« {kind} » nécessite une session active, et aucune n'est ouverte "
                f"pour cette conversation. Appeler le tool "
                f"session_open_in_conversation (popup Touch ID) pour en ouvrir une, "
                f"puis porter le session_id obtenu — aucun terminal requis."
            ),
            "suggested_tool": "session_open_in_conversation",
        }
    return {
        "ok": True,
        "elicitation": True,
        "kind": "session_open",
        "requested_kind": kind,
        "message": (
            f"« {kind} » nécessite une session MCP active (jeton). Aucune session "
            f"n'est ouverte pour cette conversation. L'utilisateur doit exécuter :\n"
            f"  mag session open\n"
            f"(geste signé — Touch ID/biométrie ; enrôlement requis) puis relancer "
            f"la demande avec le jeton (session_id) obtenu."
        ),
        "suggested_command": "mag session open",
    }


def _reject_if_delegated(sid: str, kind: str) -> None:
    """Une sous-session déléguée ne peut PAS demander d'élargissement (fiche 0045 /
    ADR-0007 §Décision 1) : pas d'`access_request` élargissant depuis un enfant."""
    from .sessions import get_session

    state = get_session(sid)
    if state is not None and state.delegated:
        raise GatewayError(
            f"sous-session déléguée « {sid} » : « {kind} » (élargissement) refusé — "
            f"seule la session racine (ou l'humain) peut demander plus de droits",
            code="delegated",
        )


def access_request(
    alias: str,
    kind: str,
    folder: str = "",
    hours: int = 8,
    minutes: int = 60,
    email: str = "",
    session: str = "",
) -> dict[str, Any]:
    """Produit un message d'élicitation — n'exécute jamais unlock/grant/add."""
    validate_alias(alias)
    kind = (kind or "").lower().strip()
    if kind == "add_account":
        # Connexion d'un NOUVEAU compte : l'alias n'existe pas encore (validé
        # en format seulement). Le LLM propose ; l'humain exécute mag add
        # (consentement OAuth navigateur + Touch ID si strongauth).
        if not email or "@" not in email:
            raise GatewayError(
                "kind=add_account nécessite email (l'adresse Gmail à connecter)",
                code="error",
            )
        return {
            "ok": True,
            "elicitation": True,
            "kind": "add_account",
            "alias": alias,
            "email": email,
            "message": (
                f"Connexion d'un nouveau compte demandée : « {alias} » ({email}). "
                f"L'utilisateur doit exécuter lui-même :\n"
                f"  mag add {alias} {email}\n"
                f"(navigateur → choisir {email} → accepter ; Touch ID d'abord si "
                f"strongauth est activé). Prérequis côté projet GCP : l'adresse doit "
                f"être test user si l'app est en Testing, et recevoir le rôle IAM "
                f"serviceUsageConsumer — vérifier/réparer avec "
                f"« ./scripts/provision-gcp.sh status » puis « sync-iam » "
                f"(docs/setup-oauth.md §7). Le LLM ne doit RIEN exécuter de tout ça."
            ),
            "suggested_command": f"mag add {alias} {email}",
        }
    # Nommer le compte au moment d'autoriser (fiche 0047) : « alias » (email).
    # L'email (.email, ADR-0002) est lisible même verrouillé ; repli alias seul
    # si inconnu. La commande suggérée garde l'alias nu (c'est la clé).
    acct_email = profile_email(alias)
    who = f"« {alias} » ({acct_email})" if acct_email else f"« {alias} »"
    if kind in ("session_unlock", "unlock"):
        mins = max(1, min(int(minutes), 1440))
        sid = (session or "").strip()
        if sid or kind == "session_unlock":
            if not sid:
                # Bootstrap sans jeton (ADR-0007 §Repli) : pas d'accès données,
                # juste la piste de création de session.
                return _bootstrap_no_session(kind)
            _reject_if_delegated(sid, kind)
            return {
                "ok": True,
                "elicitation": True,
                "kind": "session_unlock",
                "alias": alias,
                "session_id": sid,
                "message": (
                    f"Le profil {who} est verrouillé pour cette session. "
                    f"L'utilisateur doit exécuter :\n"
                    f"  mag session unlock {sid} {alias} {mins}\n"
                    f"(déverrouillage limité à cette conversation — {mins} min). "
                    f"À distance (loin du Mac), la même commande + « --remote » "
                    f"bascule l'approbation sur la passkey du téléphone (fiche 0078) "
                    f"— nécessite un enrôlement préalable côté humain."
                ),
                "suggested_command": f"mag session unlock {sid} {alias} {mins}",
            }
        return {
            "ok": True,
            "elicitation": True,
            "kind": "unlock",
            "alias": alias,
            "deprecated": True,
            "message": (
                f"Le profil {who} est verrouillé (accès sur demande). "
                f"Depuis une conversation MCP, préférer access_request kind=session_unlock "
                f"(déverrouillage limité à cette session). Sans session MCP active, legacy poste entier :\n"
                f"  mag unlock {alias} {mins}\n"
                f"(déprécié — partagé entre toutes les sessions ; admin http://127.0.0.1:4877). "
                f"Le LLM ne doit PAS exécuter cette commande ni contourner le verrou."
            ),
            "suggested_command": f"mag unlock {alias} {mins}",
        }
    if kind in ("session_grant", "grant", "project_grant"):
        if not folder:
            raise GatewayError(
                "kind=grant nécessite folder (nom ou ID du dossier Drive)",
                code="error",
            )
        h = max(1, min(int(hours), 168))
        sid = (session or "").strip()

        if kind == "project_grant":
            if not sid:
                return _bootstrap_no_session(kind)
            _reject_if_delegated(sid, kind)
            from .project import grant_allowed_by_manifest, resolve_project
            from pathlib import Path

            git_root = (get_git_root() or env("GIT_ROOT") or "").strip()
            start = Path(git_root) if git_root else None
            proj = resolve_project(start)
            if not proj.manifest_path:
                return {
                    "ok": True,
                    "elicitation": True,
                    "kind": "project_grant",
                    "alias": alias,
                    "folder": folder,
                    "session_id": sid,
                    "message": (
                        f"Aucun manifeste projet (.gwsa/manifest.json). "
                        f"L'utilisateur doit d'abord :\n"
                        f"  mag project init\n"
                        f"  # éditer capabilities.{alias}.drive.zones\n"
                        f"  mag project sign\n"
                        f"puis access_request kind=project_grant à nouveau."
                    ),
                    "suggested_command": "mag project init",
                }
            if not proj.manifest_valid:
                return {
                    "ok": True,
                    "elicitation": True,
                    "kind": "project_grant",
                    "alias": alias,
                    "folder": folder,
                    "session_id": sid,
                    "message": (
                        f"Manifeste projet présent mais signature invalide "
                        f"({proj.verify_error or 'non signé'}). "
                        f"Exécuter : mag project sign"
                    ),
                    "suggested_command": "mag project sign",
                }
            # folder peut être un nom — on ne résout pas Drive ici ; on teste si
            # ça ressemble à un id déjà dans le manifeste, sinon on guide quand même
            # vers session grant en rappelant le plafond.
            in_ceiling = grant_allowed_by_manifest(proj.manifest, alias, folder)
            if not in_ceiling:
                return {
                    "ok": True,
                    "elicitation": True,
                    "kind": "project_grant",
                    "alias": alias,
                    "folder": folder,
                    "session_id": sid,
                    "blocked_by_manifest": True,
                    "message": (
                        f"« {folder} » n'est pas dans le plafond manifeste projet "
                        f"pour {who} (.gwsa/manifest.json). "
                        f"L'humain doit éditer capabilities puis « mag project sign », "
                        f"ou choisir une zone déjà déclarée. "
                        f"Session grant hors manifeste serait refusé."
                    ),
                    "suggested_command": "mag project show",
                }
            return {
                "ok": True,
                "elicitation": True,
                "kind": "project_grant",
                "alias": alias,
                "folder": folder,
                "session_id": sid,
                "message": (
                    f"Zone projet « {folder} » dans le plafond .gwsa/ pour {who}. "
                    f"Pour l'activer sur cette conversation :\n"
                    f'  mag session grant {sid} {alias} "{folder}" {h}\n'
                    f"(intersection policy ∩ manifeste ∩ session — {h} h)."
                ),
                "suggested_command": f'mag session grant {sid} {alias} "{folder}" {h}',
            }

        if sid or kind == "session_grant":
            if not sid:
                return _bootstrap_no_session(kind)
            _reject_if_delegated(sid, kind)
            return {
                "ok": True,
                "elicitation": True,
                "kind": "session_grant",
                "alias": alias,
                "session_id": sid,
                "folder": folder,
                "message": (
                    f"Écriture Drive sous « {folder} » refusée pour cette session "
                    f"(compte {who}). "
                    f"L'utilisateur doit exécuter :\n"
                    f'  mag session grant {sid} {alias} "{folder}" {h}\n'
                    f"(zone valable pour cette conversation seulement — {h} h). "
                    f"Si le dépôt a un .gwsa/ signé, préférer kind=project_grant "
                    f"(vérifie le plafond manifeste). À distance, ajouter « --remote » "
                    f"pour approuver depuis la passkey du téléphone (fiche 0078)."
                ),
                "suggested_command": f'mag session grant {sid} {alias} "{folder}" {h}',
            }
        return {
            "ok": True,
            "elicitation": True,
            "kind": "grant",
            "alias": alias,
            "folder": folder,
            "deprecated": True,
            "message": (
                f"Écriture Drive sous « {folder} » refusée sans zone active "
                f"(compte {who}). "
                f"Depuis une conversation MCP, préférer access_request kind=session_grant "
                f"ou kind=project_grant (zone limitée à cette session + plafond .gwsa/). "
                f"Sans session MCP active, legacy poste entier :\n"
                f"  mag grant {alias} \"{folder}\" {h}\n"
                f"(déprécié — partagé entre toutes les sessions ; admin http://127.0.0.1:4877). "
                f"Expiration automatique — redemander est normal."
            ),
            "suggested_command": f'mag grant {alias} "{folder}" {h}',
        }
    raise GatewayError(
        "kind invalide — utiliser « unlock », « grant », « session_unlock », "
        "« session_grant », « project_grant » ou « add_account »",
        code="error",
    )


def session_unlock_in_conversation(
    alias: str,
    minutes: int | None = 60,
    session: str = "",
    confirm: bool = False,
) -> dict[str, Any]:
    """Mode opt-in — élicitation dans la conversation (mag elicitation in-conversation).

    Protocole en DEUX temps (décision ferme, ne pas ré-arbitrer) :
      - 1er appel (confirm=False) : AUCUN popup. Renvoie juste le texte de
        l'action à annoncer dans le chat, à charge pour le LLM d'attendre le
        « ok » humain avant de rappeler avec confirm=True.
      - 2e appel (confirm=True) : déclenche l'élicitation signée (Touch ID ou
        mock en test), puis déverrouille la session si la signature est valide.

    La confirmation chat est un verrou SOUPLE (coopération du LLM) — le vrai
    filet de sécurité reste la signature Touch ID (fail-closed en cas de refus).
    """
    from .elicitation import (
        ElicitationError,
        check_inconv_throttle,
        in_conversation_enabled,
        inconv_inflight_guard,
        run_elicitation_gate,
    )
    from .sessions import session_unlock

    if not in_conversation_enabled():
        raise GatewayError(
            "élicitation dans la conversation désactivée — "
            "l'utilisateur doit exécuter : mag elicitation in-conversation on",
            code="error",
        )
    validate_alias(alias)
    sid = (session or "").strip()
    if not sid:
        raise GatewayError("session requise (jeton de conversation)", code="error")
    require_session(sid)
    _reject_if_delegated(sid, "session_unlock_in_conversation")
    # Rejeter tout `confirm` non booléen (revue Codex #142) : un client peut
    # envoyer une valeur schéma-invalide mais plausible (« "confirm": "false" »)
    # que le dispatch transmet brute — sans ce garde, elle serait vue comme un
    # accord et déclencherait le popup dès le 1er appel.
    if not isinstance(confirm, bool):
        raise GatewayError(
            "paramètre « confirm » invalide — un booléen JSON est requis "
            "(1er appel sans confirm = annonce ; confirm=true = déclenche Touch ID)",
            code="error",
        )
    # Profil inconnu → refus AVANT toute confirmation ou signature (revue Codex
    # #142) : sinon un alias fabriqué passe Touch ID, « déverrouille » dans le
    # vide, et créer cet alias avant l'expiration rendrait le grant effectif.
    if not profile_dir(alias).is_dir():
        raise GatewayError(
            f"profil inconnu « {alias} » — le créer avec : mag add {alias}",
            code="not_found",
        )
    # None (absent) → 60 par défaut ; un 0 explicite est borné à 1 par max(1, …),
    # pas transformé en 60 (ne pas confondre « absent » et « zéro », Codex #142).
    mins = 60 if minutes is None else int(minutes)
    mins = max(1, min(mins, 1440))
    acct_email = profile_email(alias)
    who = f"« {alias} » ({acct_email})" if acct_email else f"« {alias} »"

    if not confirm:
        return {
            "ok": True,
            "confirmation_required": True,
            "alias": alias,
            "session_id": sid,
            "minutes": mins,
            "message": (
                f"Déverrouillage demandé pour {who}, session {sid}, {mins} min. "
                f"AUCUN popup n'a été déclenché — annoncer cette action dans le "
                f"chat et attendre l'accord explicite de l'utilisateur avant de "
                f"rappeler ce tool avec confirm=true (cela déclenchera Touch ID)."
            ),
        }

    try:
        check_inconv_throttle(sid)
        # Verrou GLOBAL « une élicitation en conversation à la fois », tenu
        # pendant tout le popup (revue Codex #142) : le throttle par session ne
        # suffit pas — deux conversations (deux session_id) pourraient déclencher
        # deux Touch ID concurrents. Toute autre demande en vol est refusée ici.
        with inconv_inflight_guard():
            run_elicitation_gate({
                "action": "session_unlock",
                "alias": alias,
                "email": acct_email,
                "session_id": sid,
                "minutes": mins,
            })
    except ElicitationError as e:
        raise GatewayError(str(e), code="error") from e

    session_unlock(sid, alias, mins)
    return {
        "ok": True,
        "unlocked": True,
        "alias": alias,
        "session_id": sid,
        "minutes": mins,
        "message": f"{who} déverrouillé pour la session {sid} ({mins} min).",
    }


def session_open_in_conversation(confirm: bool = False) -> dict[str, Any]:
    """Mode opt-in — OUVRIR une session depuis la conversation (zéro terminal).

    Pendant MCP du geste terminal `mag session open`, mais déclenché par le LLM à
    la demande de l'humain : le popup Touch ID est levé par le serveur MCP, une
    session vide (zéro droit) est créée, et son `session_id` est RENDU au LLM pour
    qu'il le porte ensuite (déverrouillage, lectures…). C'est le maillon qui rend
    le mode utilisable sans terminal préalable (fiche 20260910194019668).

    Réservé au mode opt-in (`mag elicitation in-conversation on`) : que le LLM
    déclenche l'élicitation est un choix de sécurité assumé ; le filet reste le
    popup Touch ID (fail-closed). Protocole en deux temps comme
    session_unlock_in_conversation.
    """
    from .elicitation import (
        ElicitationError,
        in_conversation_enabled,
        inconv_inflight_guard,
        run_elicitation_gate,
    )
    from .sessions import create_session

    if not in_conversation_enabled():
        raise GatewayError(
            "élicitation dans la conversation désactivée — "
            "l'utilisateur doit exécuter : mag elicitation in-conversation on",
            code="error",
        )
    if not isinstance(confirm, bool):
        raise GatewayError(
            "paramètre « confirm » invalide — un booléen JSON est requis "
            "(1er appel sans confirm = annonce ; confirm=true = déclenche Touch ID)",
            code="error",
        )

    if not confirm:
        return {
            "ok": True,
            "confirmation_required": True,
            "message": (
                "Ouverture d'une session pour cette conversation demandée. AUCUN "
                "popup n'a été déclenché — annoncer cette action dans le chat et "
                "attendre l'accord explicite de l'utilisateur avant de rappeler ce "
                "tool avec confirm=true (cela déclenchera Touch ID)."
            ),
        }

    try:
        with inconv_inflight_guard():
            run_elicitation_gate({"action": "session_open"})
    except ElicitationError as e:
        raise GatewayError(str(e), code="error") from e

    state = create_session(client="mcp-in-conversation")
    return {
        "ok": True,
        "opened": True,
        "session": state.session_id,
        "message": (
            f"Session ouverte : {state.session_id}. Porter ce session_id dans le "
            f"paramètre « session » des prochains appels (déverrouillage, lecture…)."
        ),
    }
