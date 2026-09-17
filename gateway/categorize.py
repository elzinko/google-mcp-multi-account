"""Catégorisation service-aware des appels gws (méthode + ressource opérante).

Source de vérité partagée par les deux consommateurs qui doivent s'accorder
sur le même triplet service × opération × ressource (fiche 0080, revue Codex
PR #110) :

- `scripts/policy-check.py` l'utilise pour AUTORISER (capacités de session,
  policy par catégorie) ;
- `gateway/usage.py` l'utilise pour AUDITER les appels réussis, afin que le
  journal identifie la même capacité que celle qui a réellement autorisé
  l'appel (`drafts`, `share`, …), pas seulement le nom de méthode.

Aucune des deux fonctions ne lève : une méthode/ressource non reconnue
retourne None / "" — chaque appelant décide de son propre repli (refus côté
policy, best-effort côté audit).
"""
from __future__ import annotations

import base64
import hashlib
import json

READ_METHODS = {
    "list", "get", "export", "download", "search", "query", "getprofile",
    "lookup", "generateids", "instances", "freebusy", "colors", "watch",
    "batchget", "getbatch", "read",
}
CREATE_METHODS = {
    "create", "insert", "copy", "append", "upload", "import", "add",
    "quickadd", "batchcreate", "push", "subscribe",
}
UPDATE_METHODS = {
    "update", "patch", "move", "modify", "batchupdate", "batchmodify",
    "rename", "setdefault", "set", "renew", "untrash",
}
DELETE_METHODS = {
    "delete", "remove", "trash", "batchdelete", "emptytrash", "clear",
    "stop", "revoke",
}
SHARE_RESOURCES = {"permissions", "acl", "members"}


def norm(method: str) -> str:
    return method.lstrip("+").replace("-", "").replace("_", "").lower()


def norm_service(service: str) -> str:
    """Nom de service normalisé : retire un éventuel suffixe de version
    (`calendar:v3` → `calendar`, syntaxe acceptée par gws) et met en
    minuscules — même normalisation que `scripts/policy-check.py` (source de
    vérité pour l'AUTORISATION) avant tout lookup service-aware, pour que
    l'AUDIT (`gateway.usage.infer_call`) catégorise et dérive la ressource
    d'un appel versionné (ex. `calendar:v3`) au lieu de traiter le service
    versionné comme inconnu (fiche 0086)."""
    return service.split(":", 1)[0].strip().lower()


def categorize(service: str, resources: list[str], raw_method: str) -> str | None:
    """Catégorie d'action, ou None si inconnue (l'appelant décide du repli)."""
    m = norm(raw_method)
    res = [r.lower() for r in resources]

    if service == "gmail":
        if m == "send" or m.endswith("send") or m in ("reply", "replyall", "forward"):
            return "send"
        if any("settings" in r for r in res):
            return "settings"
        if "drafts" in res and m in ("create", "update"):
            return "drafts"
        if "labels" in res and m not in READ_METHODS:
            return "labels"
        if m in ("triage", "watch"):
            return "read"

    if res and res[0] in SHARE_RESOURCES and m not in READ_METHODS:
        return "share"
    if m in READ_METHODS:
        return "read"
    if m in CREATE_METHODS:
        return "create"
    if m in UPDATE_METHODS:
        return "update"
    if m in DELETE_METHODS:
        return "delete"
    if raw_method.startswith("+"):
        if m in ("agenda", "standupreport", "meetingprep", "weeklydigest"):
            return "read"
        return None
    return None


# ---------------------------------------------------------------------------
# Ressource OPÉRANTE (revue adverse post-#110, P0 sécu, fiche 0080)
#
# La ressource qui AUTORISE une capacité scopée doit venir d'un mapping
# EXPLICITE (service, mot-clé de ressource, méthode) → nom du VRAI paramètre
# Google — jamais d'une priorité générique sur les clés d'un --params
# contrôlé par l'appelant. Une priorité générique était attaquable : un `id`
# quelconque (ex. l'id d'un AUTRE objet, choisi par l'appelant) passait avant
# le `labelId`/`calendarId` réel, laissant usurper une ressource accordée par
# un leurre dans les mêmes --params.
#
# Si le triplet (service, ressource, méthode) n'a pas d'entrée ici, ou si le
# paramètre mappé est absent/ambigu (tableau à 0 ou >1 élément), l'opérande
# n'est PAS identifiable de façon univoque : on renvoie "" (aucune ressource
# dérivée). Une capacité SCOPÉE (resource non vide) ne matche alors jamais
# "" (fail-closed) ; une capacité NON scopée (service×opération entier)
# n'est pas affectée, comme aujourd'hui.
_OPERAND_PARAM: dict[tuple[str, str, str], tuple[str, str]] = {
    # Gmail : la capacité scope un LIBELLÉ (labelId) — seules les méthodes où
    # l'API porte réellement cet identifiant sont couvertes. « messages get »/
    # « attachments get » n'y figurent PAS à dessein : le message ciblé ne
    # révèle pas son libellé dans --params, l'opérande n'y est pas fiable.
    # Revue de complétude (Codex PR #118, P2 finding #4) : « messages modify »/
    # « batchModify » portent AUSSI des labelIds (addLabelIds/removeLabelIds,
    # dans le corps --json) mais sont délibérément EXCLUS — deux listes de
    # libellés distinctes dans le même appel (ajout ET retrait) rendent
    # l'opérande ambigu pour une capacité à ressource unique ; fail closed.
    ("gmail", "messages", "list"): ("labelIds", "array"),
    ("gmail", "messages", "watch"): ("labelIds", "array"),
    ("gmail", "labels", "get"): ("id", "scalar"),
    ("gmail", "labels", "update"): ("id", "scalar"),
    ("gmail", "labels", "patch"): ("id", "scalar"),
    ("gmail", "labels", "delete"): ("id", "scalar"),
    # Calendar : la capacité scope un AGENDA (calendarId) — jamais eventId,
    # qui identifie un sous-objet DANS l'agenda, pas l'agenda lui-même.
    # Revue de complétude (Codex PR #118, P2 finding #4) : toutes les
    # méthodes `events` qui portent calendarId de façon NON ambiguë sont
    # listées ici. `move` est délibérément EXCLU : l'API Calendar y porte
    # DEUX agendas (calendarId source ET destination) — mapper l'un des deux
    # laisserait une capacité scopée sur l'agenda source autoriser un
    # déplacement vers n'importe quelle destination (ou l'inverse) ; fail
    # closed le temps d'un mapping à deux ressources (hors périmètre 0080).
    ("calendar", "events", "list"): ("calendarId", "scalar"),
    ("calendar", "events", "get"): ("calendarId", "scalar"),
    ("calendar", "events", "insert"): ("calendarId", "scalar"),
    ("calendar", "events", "import"): ("calendarId", "scalar"),
    ("calendar", "events", "update"): ("calendarId", "scalar"),
    ("calendar", "events", "patch"): ("calendarId", "scalar"),
    ("calendar", "events", "delete"): ("calendarId", "scalar"),
    ("calendar", "events", "instances"): ("calendarId", "scalar"),
    ("calendar", "events", "quickadd"): ("calendarId", "scalar"),
    ("calendar", "events", "watch"): ("calendarId", "scalar"),
    # Drive : audit uniquement (l'autorisation Drive a son propre chemin,
    # `scripts/policy-check.py::check_drive`, qui lit fileId directement —
    # ce mapping ne sert qu'à `gateway/usage.py::infer_call`).
    ("drive", "files", "get"): ("fileId", "scalar"),
    ("drive", "files", "export"): ("fileId", "scalar"),
    ("drive", "files", "download"): ("fileId", "scalar"),
    ("drive", "files", "watch"): ("fileId", "scalar"),
    ("drive", "files", "update"): ("fileId", "scalar"),
    ("drive", "files", "delete"): ("fileId", "scalar"),
    ("drive", "files", "trash"): ("fileId", "scalar"),
    ("drive", "files", "untrash"): ("fileId", "scalar"),
    # `create`/`copy` sont autorisés par `check_drive` contre le PARENT DE
    # DESTINATION (--json.parents), jamais un fileId source (Codex PR #118,
    # P2 finding #1 : l'audit journalisait le fileId source d'un `copy`, pas
    # la ressource qui avait réellement autorisé l'appel) — lu depuis --json,
    # pas --params, avec la même règle "un seul élément" que les tableaux
    # Gmail/Calendar (0/plusieurs parents = ambigu pour un log à une seule
    # ressource → "").
    ("drive", "files", "create"): ("parents", "json-array"),
    ("drive", "files", "copy"): ("parents", "json-array"),
    ("drive", "permissions", "list"): ("fileId", "scalar"),
    ("drive", "permissions", "get"): ("fileId", "scalar"),
    ("drive", "permissions", "create"): ("fileId", "scalar"),
    ("drive", "permissions", "update"): ("fileId", "scalar"),
    ("drive", "permissions", "delete"): ("fileId", "scalar"),
}


def flag_value(args: list[str], flag: str) -> str | None:
    """Valeur brute d'un flag CLI, formes séparée (`--params {...}`) ET
    `--flag=valeur` — les deux sont acceptées par gws/mag. Un helper qui ne
    reconnaît que la forme séparée fait passer à tort une capacité scopée
    pour non couverte dès que l'appelant utilise `--params={...}` (revue
    Codex PR #118, P2 finding #3)."""
    for i, a in enumerate(args):
        if a == flag and i + 1 < len(args):
            return args[i + 1]
        if a.startswith(flag + "="):
            return a.split("=", 1)[1]
    return None


def parse_json_flag(args: list[str], flag: str) -> dict:
    raw = flag_value(args, flag)
    if raw is None:
        return {}
    try:
        parsed = json.loads(raw)
    except Exception:
        return {}
    return parsed if isinstance(parsed, dict) else {}


def _operand_entry(service: str, resources: list[str], raw_method: str):
    method = norm(raw_method)
    for keyword in resources:
        entry = _OPERAND_PARAM.get((service, keyword.lower(), method))
        if entry:
            return entry
    return None


def operand_resource(
    service: str, resources: list[str], raw_method: str, args: list[str],
) -> str:
    """Ressource opérante réelle pour (service, resources, méthode), dérivée
    du paramètre EXPLICITEMENT mappé à ce triplet — jamais d'une priorité
    générique. "" si non mappé, absent, ou ambigu (fail-closed pour une
    capacité scopée sur une ressource — cf. `_OPERAND_PARAM` ci-dessus).

    `mode` : "scalar"/"array" lisent --params (Gmail/Calendar) ; "json-array"
    lit --json (Drive `files create`/`copy`, dont la seule ressource qui
    AUTORISE est le parent de destination dans le corps de la requête, pas
    --params)."""
    entry = _operand_entry(service, resources, raw_method)
    if entry is None:
        return ""
    key, mode = entry
    if mode == "json-array":
        val = parse_json_flag(args, "--json").get(key)
        if isinstance(val, list) and len(val) == 1 and val[0]:
            return str(val[0])
        return ""
    params = parse_json_flag(args, "--params")
    val = params.get(key)
    if mode == "array":
        if isinstance(val, list) and len(val) == 1 and val[0]:
            return str(val[0])
        return ""
    if isinstance(val, (str, int)) and str(val):
        return str(val)
    return ""


def drive_files_trash_override(
    resources: list[str], raw_method: str, operation: str, args: list[str],
) -> str:
    """Reclasse « update » en « delete » pour `drive files update
    {"trashed": true}` (Option A, fiche 0037) — même règle que
    `scripts/policy-check.py::check_drive`, pour que l'audit (`infer_call`)
    suive la même catégorie que l'autorisation (fiche 0080, raffinement P2)."""
    if operation != "update":
        return operation
    if not resources or resources[-1].lower() != "files":
        return operation
    if norm(raw_method) not in UPDATE_METHODS:
        return operation
    body = parse_json_flag(args, "--json")
    params = parse_json_flag(args, "--params")
    if body.get("trashed") is True or params.get("trashed") is True:
        return "delete"
    return operation


# ---------------------------------------------------------------------------
# Arguments CONSÉQUENTS liés au reçu signé (ADR-0012, Zone 3)
#
# Le payload signé (ADR-0005) portait service:ressources:méthode + une ressource
# unique. Deux « drive permissions create » sur le même fichier (destinataire ou
# rôle différent) signaient pareil ; une suppression de permission omettait
# `permissionId` ; un brouillon Gmail omettait destinataire/sujet (Codex #147,
# P1). `consequential_args` extrait, des MÊMES flags parsés, les arguments qui
# changent la CONSÉQUENCE de l'acte — normalisés et canoniques (listes triées,
# clés triées à la sérialisation) — pour les mettre dans le reçu SIGNÉ et le
# prompt Touch ID. L'humain approuve alors QUI reçoit QUOI, pas juste la méthode.
#
# Best-effort : dict vide si l'acte n'a pas d'arguments conséquents mappés — il
# reste lié par op_label + target dans le payload (jamais un blanc). Les actes
# SENSIBLES (partage Drive, destinataires Gmail) sont mappés explicitement : y
# confondre deux actes serait grave.


def _gmail_message_headers(args: list[str]) -> dict:
    """to/cc/subject d'un brouillon Gmail — décodés du message RFC-2822 encodé
    base64url dans `--json {"message":{"raw":…}}` (c'est ainsi que gmail_create_draft
    transporte le message). Corps NON lié (décision produit : to/cc/subject, pas
    le corps — volumineux, volatil, aucun tool n'envoie)."""
    body = parse_json_flag(args, "--json")
    msg = body.get("message") if isinstance(body, dict) else None
    raw = msg.get("raw") if isinstance(msg, dict) else None
    if not isinstance(raw, str) or not raw:
        return {}
    try:
        decoded = base64.urlsafe_b64decode(raw + "=" * (-len(raw) % 4)).decode("utf-8", "replace")
    except (ValueError, TypeError):
        return {}
    to: list[str] = []
    cc: list[str] = []
    subject = ""
    for line in decoded.replace("\r\n", "\n").split("\n"):
        if line == "":
            break  # fin des en-têtes
        low = line.lower()
        if low.startswith("to:"):
            to = [a.strip() for a in line[3:].split(",") if a.strip()]
        elif low.startswith("cc:"):
            cc = [a.strip() for a in line[3:].split(",") if a.strip()]
        elif low.startswith("subject:"):
            subject = line[8:].strip()
    out: dict = {}
    if to:
        out["to"] = sorted(to)
    if cc:
        out["cc"] = sorted(cc)
    if subject:
        out["subject"] = subject
    return out


def _upload_digest(path: str) -> str:
    """Empreinte courte du contenu média remplacé (ADR-0012 Zone 3, Codex #149) :
    deux remplacements différents ne doivent pas signer pareil. Rend
    ``media:sha256:<16 hex>`` ou ``media:?`` si illisible."""
    try:
        h = hashlib.sha256()
        with open(path, "rb") as f:
            for chunk in iter(lambda: f.read(65536), b""):
                h.update(chunk)
        return "media:sha256:" + h.hexdigest()[:16]
    except OSError:
        return "media:?"


def consequential_args(
    service: str, resources: list[str], raw_method: str, args: list[str],
) -> dict:
    """Arguments conséquents (canoniques) d'un acte mutant, à lier au reçu signé
    et au prompt Touch ID (ADR-0012, Zone 3). Voir le commentaire ci-dessus.

    Rend TOUJOURS un dict (vide = pas d'arguments fins mappés) : la
    non-régression fonctionnelle prime — un acte non mappé reste signé via
    op_label + target, jamais un blanc."""
    service = norm_service(service)
    method = norm(raw_method)
    res = [r.lower() for r in resources]

    if service == "gmail" and "drafts" in res and method in ("create", "update"):
        return _gmail_message_headers(args)

    if service == "drive" and "permissions" in res:
        params = parse_json_flag(args, "--params")
        req = parse_json_flag(args, "--json")
        if method == "create":
            out: dict = {}
            if params.get("fileId"):
                out["fileId"] = str(params.get("fileId"))
            if req.get("type"):
                out["type"] = str(req.get("type"))
            if req.get("role"):
                out["role"] = str(req.get("role"))
            grantee = req.get("emailAddress") or req.get("domain") or ""
            if grantee:
                out["grantee"] = str(grantee)
            # Notification par email = acte VISIBLE de l'extérieur : le lier pour
            # que l'humain le voie (un partage notifié ≠ un partage silencieux,
            # Codex #149 P2). Le flag est dans --params. Stocké en CHAÎNE
            # "true"/"false" : rendu identique Python↔Swift (un bool JSON se
            # rendrait « True » d'un côté, « 1 » de l'autre).
            if "sendNotificationEmail" in params:
                out["sendNotificationEmail"] = "true" if params.get("sendNotificationEmail") else "false"
            return out
        if method == "delete":
            out = {}
            if params.get("fileId"):
                out["fileId"] = str(params.get("fileId"))
            if params.get("permissionId"):
                out["permissionId"] = str(params.get("permissionId"))
            return out

    if service == "drive" and "files" in res:
        params = parse_json_flag(args, "--params")
        req = parse_json_flag(args, "--json")
        fid = str(params.get("fileId") or "")
        if method in ("delete", "trash", "batchdelete"):
            return {"fileId": fid} if fid else {}
        if method in ("update", "patch", "modify", "untrash"):
            out = {}
            if fid:
                out["fileId"] = fid
            # Lier les VALEURS, pas seulement les noms de champs (Codex #149 P2) :
            # deux renommages différents doivent signer différemment.
            if isinstance(req, dict):
                if req.get("name") is not None:
                    out["name"] = str(req.get("name"))
                if req.get("mimeType"):
                    out["mimeType"] = str(req.get("mimeType"))
                extra = sorted(k for k in req if k not in ("name", "mimeType"))
                if extra:
                    out["fields"] = extra
            # Remplacement de contenu (media upload) : lier une empreinte, sinon
            # deux contenus différents signeraient pareil (Codex #149 P2).
            up = flag_value(args, "--upload")
            if up:
                out["content"] = _upload_digest(up)
            return out
        if method in ("create", "copy"):
            out = {}
            if fid:
                out["fileId"] = fid  # source d'une copie
            if isinstance(req, dict):
                if req.get("name"):
                    out["name"] = str(req.get("name"))
                parents = req.get("parents")
                if isinstance(parents, list) and parents:
                    out["parents"] = sorted(str(p) for p in parents if p)
            return out

    return {}
