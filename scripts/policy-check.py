#!/usr/bin/env python3
"""Contrôleur de policy par service pour mag.

Appelé par bin/mag (et la gateway MCP) avant TOUTE commande quand le profil
possède un policy.json. Default-deny : un service absent du policy.json est
refusé (sauf passthrough auth/schema). Un service présent = fail closed :
seules les catégories explicitement autorisées passent.

policy.json (dans ~/.config/gws-accounts/<alias>/) :
{
  "drive":    {"read": true, "create": true, "update": true, "delete": false,
               "share": false, "zonesOnly": true, "writeFolders": ["<folderId>", …],
               "writeFolderNames": {"<folderId>": "Nom"}},
               // ancien schéma {"mode": "open|readonly|restricted"} toujours accepté
  "gmail":    {"read": true, "drafts": true, "send": false, "labels": true,
               "update": false, "delete": false, "settings": false},
  "calendar": {"read": true, "create": false, "update": false, "delete": false, "share": false},
  "keep":     {"read": true, "create": true, "update": false, "delete": false, "share": false},
  "docs":     {"read": true, "create": false, "update": false},
  "sheets":   {"read": true, "create": false, "update": false},
  "tasks":    {"read": true, "create": false, "update": false, "delete": false}
}

Drive, modèle par zones : lecture partout ; en zonesOnly, écritures uniquement
sous les dossiers autorisés (sous-dossiers compris, remontée des parents via
l'API). Zones = writeFolders (permanentes, policy) ∪ session-grants.json
(temporaires, accordées par l'utilisateur via `mag grant`, expiration auto).
Par défaut (zonesOnly sans zones) : aucune écriture possible.

Sortie : exit 0 = autorisé (mag exécute), exit 4 = refusé (message stderr).
Les refus sont journalisés dans ~/.config/gws-accounts/usage.jsonl.
"""
import datetime
import json
import os
import subprocess
import sys
import time

# Catégorisation service-aware (méthode + ressource) partagée avec
# gateway/usage.py — même triplet pour AUTORISER (ici) et AUDITER (fiche 0080).
_REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if _REPO_ROOT not in sys.path:
    sys.path.insert(0, _REPO_ROOT)
from gateway.categorize import (  # noqa: E402
    READ_METHODS,
    SHARE_RESOURCES,
    categorize,
    norm,
    resource_from_params,
)

VALUE_FLAGS = {
    "--params", "--json", "--upload", "--upload-content-type", "--output",
    "--format", "--api-version", "--page-limit", "--page-delay", "--scopes",
    "--services",
}
SERVICE_ALIASES = {"wf": "workflow", "reports": "admin-reports"}
# Introspection / auth locale — pas des APIs données ; hors modèle policy.
PASSTHROUGH_SERVICES = frozenset({"auth", "schema"})

DRIVE_READ_FILES = {"list", "get", "export", "download", "watch", "generateids"}


def now_iso():
    return datetime.datetime.now().astimezone().isoformat(timespec="seconds")


def log_usage(profile_dir, decision, args, reason=""):
    try:
        root = os.path.dirname(os.path.abspath(profile_dir))
        entry = {
            "ts": now_iso(),
            "client": os.environ.get("GWSA_CLIENT", "cli"),
            "alias": os.path.basename(os.path.abspath(profile_dir)),
            "cmd": " ".join(args),
            "decision": decision,
        }
        if reason:
            entry["reason"] = reason
        with open(os.path.join(root, "usage.jsonl"), "a") as f:
            f.write(json.dumps(entry, ensure_ascii=False) + "\n")
    except Exception:
        pass


def deny(profile_dir, args, service, msg):
    alias = os.path.basename(os.path.abspath(profile_dir))
    log_usage(profile_dir, "refus", args, msg)
    sys.stderr.write(
        "mag : ✗ policy %s — %s\n"
        "       Élicitation : demander à l'utilisateur d'élargir la policy\n"
        "       (« mag policy %s show » pour voir, interface admin pour modifier).\n"
        % (service, msg, alias)
    )
    sys.exit(4)


def gws_json(profile_dir, args):
    """Interroge gws en lecture. Toute défaillance (binaire absent, timeout,
    sortie illisible) renvoie {} : l'appelant conclut alors « parent inconnu »,
    donc refus — fail closed, jamais de crash ni d'autorisation par accident."""
    # Après migration vault (fiche 0040), les creds ne sont plus dans profile_dir :
    # le broker passe le vrai CONFIG_DIR via GWSA_GWS_CONFIG_DIR (revue sécurité F1).
    # Repli sur profile_dir pour un usage direct / legacy non migré.
    cfg = os.environ.get("GWSA_GWS_CONFIG_DIR") or profile_dir
    env = dict(os.environ, GOOGLE_WORKSPACE_CLI_CONFIG_DIR=cfg)
    try:
        r = subprocess.run(["gws"] + args, env=env, capture_output=True,
                           text=True, timeout=20)
        return json.loads(r.stdout)
    except Exception:
        return {}


def flag_value(args, flag):
    for i, a in enumerate(args):
        if a == flag and i + 1 < len(args):
            return args[i + 1]
        if a.startswith(flag + "="):
            return a.split("=", 1)[1]
    return None


def parse_json_flag(args, flag):
    raw = flag_value(args, flag)
    if raw is None:
        return {}
    try:
        d = json.loads(raw)
        return d if isinstance(d, dict) else {}
    except Exception:
        return {}


def positionals_of(args):
    """Positionnels de gauche : `gws <service> <resource> [sous-resource] <method>`.
    La grammaire gws impose que TOUS les positionnels précèdent les flags — on
    s'arrête donc au premier flag `-…`. Ne PAS reprendre après un flag : sinon la
    valeur d'un flag inconnu de VALUE_FLAGS (ex. `--x list`) se ferait passer pour
    la méthode et tromperait la classification (envoi déguisé en lecture).
    Les macros `+triage` etc. sont en position de méthode, donc positionnelles."""
    out = []
    for a in args:
        if a.startswith("-"):
            break
        out.append(a)
    return out


def under_allowed(profile_dir, file_id, allowed, depth=0, seen=None):
    """Vrai si file_id est un dossier autorisé ou un descendant d'un autorisé."""
    seen = seen if seen is not None else set()
    if file_id in allowed:
        return True
    if depth > 20 or file_id in seen:
        return False
    seen.add(file_id)
    data = gws_json(profile_dir, [
        "drive", "files", "get", "--params",
        json.dumps({"fileId": file_id, "fields": "id,parents"}),
    ])
    parents = data.get("parents") or []
    return any(under_allowed(profile_dir, p, allowed, depth + 1, seen) for p in parents)


def normalize_drive(drive):
    """Schéma v2 (booléens + zonesOnly). L'ancien schéma «mode» est traduit.
    Retourne None si le service est libre."""
    if "mode" in drive:
        mode = drive.get("mode", "open")
        if mode == "open":
            return None
        if mode == "readonly":
            return {"read": True, "create": False, "update": False, "delete": False,
                    "share": False, "zonesOnly": False, "writeFolders": []}
        return {"read": True, "create": True, "update": True, "delete": False,
                "share": False, "zonesOnly": True,
                "writeFolders": drive.get("writeFolders") or []}
    base = {"read": True, "create": False, "update": False, "delete": False,
            "share": False, "zonesOnly": True, "writeFolders": []}
    base.update(drive)
    return base


def active_grants(profile_dir):
    """Zones temporaires : session MCP (prioritaire) ou session-grants.json legacy."""
    if os.environ.get("GWSA_USE_SESSION_GRANTS") == "1":
        raw = os.environ.get("GWSA_SESSION_DRIVE_ZONES", "")
        if raw.strip():
            return {z.strip() for z in raw.split(",") if z.strip()}
        return set()
    try:
        with open(os.path.join(profile_dir, "session-grants.json")) as f:
            g = json.load(f)
    except Exception:
        return set()
    now = time.time()
    return {e["id"] for e in g.get("drive", []) if e.get("expiresAt", 0) > now and e.get("id")}


def zone_hint(alias):
    sid = os.environ.get("GWSA_SESSION_ID", "").strip()
    if sid:
        return (
            "aucune zone d'écriture active pour cette session — demander à l'utilisateur "
            "« mag session grant %s %s \"<dossier>\" [heures] » ou access_request "
            "kind=session_grant (zone limitée à cette conversation)"
            % (sid, alias)
        )
    return (
        "aucune zone d'écriture active — demander une autorisation temporaire "
        "(« mag session grant <session_id> %s \"<dossier>\" » via MCP, ou legacy "
        "« mag grant %s \"<dossier>\" » partagé poste entier, déprécié) ou permanente "
        "(« mag policy %s allow <dossier> » / interface admin)"
        % (alias, alias, alias)
    )


def _manifest_drive_cap(alias):
    """Plafond zones Drive du manifeste projet, ou None si pas de contrainte."""
    git_root = os.environ.get("GWSA_GIT_ROOT", "").strip()
    if not git_root:
        return None
    try:
        repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        if repo not in sys.path:
            sys.path.insert(0, repo)
        from gateway.project import manifest_drive_zones, resolve_project
        from pathlib import Path

        proj = resolve_project(Path(git_root))
        if not proj.manifest_valid or not proj.manifest:
            return None
        zones = manifest_drive_zones(proj.manifest, alias)
        return zones if zones else None
    except Exception:
        return None


def _apply_manifest_cap(alias, zones):
    cap = _manifest_drive_cap(alias)
    if cap is None:
        return zones
    return zones & cap


def check_drive(profile_dir, drive_raw, args, pos):
    drive = normalize_drive(drive_raw)
    if drive is None:
        # Policy « open » : aucune restriction de compte. Mais si la session porte des
        # capacités fines, l'op Drive doit y être couverte (intersection fail-closed,
        # ADR-0007 §Décision 3) — sinon une session limitée écrirait partout.
        if _session_caps_from_env() is not None:
            _gate_drive_session(profile_dir, args, pos)
        return
    alias = os.path.basename(os.path.abspath(profile_dir))
    resource, method = pos[0], norm(pos[-1])

    if resource == "files" and method in DRIVE_READ_FILES:
        check_session_caps(profile_dir, args, "drive", "read")
        return
    if resource in SHARE_RESOURCES and method in ("list", "get"):
        check_session_caps(profile_dir, args, "drive", "read")
        return
    if resource not in ("files",) and resource not in SHARE_RESOURCES \
            and method in READ_METHODS:
        check_session_caps(profile_dir, args, "drive", "read")
        return

    if method == "emptytrash":
        deny(profile_dir, args, "drive", "emptyTrash interdit (suppression définitive)")

    if resource in SHARE_RESOURCES:
        if not drive.get("share"):
            deny(profile_dir, args, "drive",
                 "partage refusé par la policy (« %s %s »)" % (resource, pos[-1]))
        check_session_caps(profile_dir, args, "drive", "share")
        return

    if pos[-1].startswith("+") or resource != "files":
        cat = categorize("drive", [resource], pos[-1]) or "update"
        allowed_flag = drive.get(cat, False)
        if not allowed_flag:
            deny(profile_dir, args, "drive",
                 "%s refusé·e par la policy (« %s %s »)"
                 % (LABELS_FR.get(cat, cat), resource, pos[-1]))
        if drive.get("zonesOnly"):
            deny(profile_dir, args, "drive",
                 "« %s %s » non vérifiable par zones — utiliser files create/update "
                 "avec un parent autorisé" % (resource, pos[-1]))
        check_session_caps(profile_dir, args, "drive", cat)
        return

    if method in ("create", "copy"):
        cat = "create"
    elif method in ("delete", "trash", "batchdelete"):
        cat = "delete"
    elif method in ("update", "patch", "modify", "untrash", "upload"):
        cat = "update"
    else:
        deny(profile_dir, args, "drive",
             "méthode files « %s » non classifiable — refusée par prudence" % pos[-1])
    # Option A (fiche 0037) : mettre à la corbeille EST une suppression, même quand
    # l'API le fait via « files update {"trashed": true} » (classé « update » sur le
    # seul nom de méthode). On regarde le corps : trashed=true → catégorie delete,
    # donc refusé sous delete:false (défaut). « trashed:false » (restauration) reste
    # une modification.
    if cat == "update":
        _tbody = parse_json_flag(args, "--json")
        _tparams = parse_json_flag(args, "--params")
        if _tbody.get("trashed") is True or _tparams.get("trashed") is True:
            cat = "delete"
    if not drive.get(cat, False):
        deny(profile_dir, args, "drive",
             "%s refusé·e par la policy (« files %s »)" % (LABELS_FR.get(cat, cat), pos[-1]))

    if not drive.get("zonesOnly"):
        # Policy sans zones : la policy autorise l'écriture partout, mais une session
        # à capacités fines reste bornée (intersection fail-closed, ADR-0007 §3).
        if _session_caps_from_env() is not None:
            _gate_drive_session(profile_dir, args, pos)
        return

    zones = set(drive.get("writeFolders") or []) | active_grants(profile_dir)
    zones = _apply_manifest_cap(alias, zones)
    if not zones:
        deny(profile_dir, args, "drive", zone_hint(alias))

    params = parse_json_flag(args, "--params")
    body = parse_json_flag(args, "--json")

    if cat == "create":
        # Pour create/copy, gws met `parents` dans le CORPS (--json), pas dans la
        # query (--params). Ne lire QUE le corps : un parent glissé dans --params
        # serait validé ici mais ignoré par l'API → fichier créé à la racine, hors
        # zone. Sans parent dans le corps, l'API écrit à la racine → refus.
        parents = body.get("parents") or []
        if not parents:
            deny(profile_dir, args, "drive",
                 "files %s sans parent dans --json — préciser \"parents\": "
                 "[<dossier autorisé>] (zones actives : mag grants %s)" % (pos[-1], alias))
        for p in parents:
            if not _session_drive_ok(profile_dir, p, cat):
                deny(profile_dir, args, "drive",
                     "« drive:%s » vers %s hors capacités/zones de session — "
                     "mag session grant-capability" % (cat, p))
            if not under_allowed(profile_dir, p, zones):
                deny(profile_dir, args, "drive",
                     "parent/destination %s hors zone d'écriture autorisée" % p)
        return

    fid = params.get("fileId")
    if not fid:
        deny(profile_dir, args, "drive",
             "files %s sans fileId identifiable — refusé par prudence" % pos[-1])
    # Option B (fiche 0037) : la RACINE d'une zone est une frontière immuable —
    # jamais corbeillée / renommée / déplacée, même sous delete:true. Seul son
    # CONTENU (les descendants) est modifiable. « Retirer une zone » est un geste
    # de config (« mag grant revoke »), pas une opération Drive.
    if fid in zones:
        deny(profile_dir, args, "drive",
             "cible %s = racine d'une zone (frontière immuable) — créer/modifier "
             "seulement DEDANS ; retirer la zone via « mag grant revoke »" % fid)
    if not _session_drive_ok(profile_dir, fid, cat):
        deny(profile_dir, args, "drive",
             "« drive:%s » vers %s hors capacités/zones de session — "
             "mag session grant-capability" % (cat, fid))
    if not under_allowed(profile_dir, fid, zones):
        deny(profile_dir, args, "drive", "cible %s hors zone d'écriture autorisée" % fid)
    # Un déplacement (addParents/removeParents, dans --params OU --json) peut faire
    # SORTIR un fichier de sa zone. Toute destination ajoutée doit rester en zone ;
    # un retrait de parent sans réancrage explicite en zone est refusé (le fichier
    # pourrait se retrouver hors de tout dossier contrôlé).
    add_parents = params.get("addParents") or body.get("addParents")
    if add_parents:
        for p in str(add_parents).split(","):
            if not under_allowed(profile_dir, p, zones):
                deny(profile_dir, args, "drive", "addParents %s hors zone autorisée" % p)
    remove_parents = params.get("removeParents") or body.get("removeParents")
    if remove_parents and not add_parents:
        deny(profile_dir, args, "drive",
             "removeParents sans addParents en zone — un retrait de parent peut "
             "sortir le fichier de sa zone ; réancrer explicitement via addParents")


LABELS_FR = {
    "read": "lecture", "create": "création", "update": "modification",
    "delete": "suppression", "send": "envoi", "drafts": "brouillons",
    "labels": "libellés", "share": "partage", "settings": "réglages",
}


def _project_fail_closed():
    """True si le manifeste projet (GWSA_GIT_ROOT) est en anti-downgrade
    (invalide/altéré/supprimé après avoir été de confiance) — ADR-0007 §3,
    défend S-07. Aucun contrainte GWSA_GIT_ROOT = pas de projet git → False."""
    git_root = os.environ.get("GWSA_GIT_ROOT", "").strip()
    if not git_root:
        return False
    try:
        repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        if repo not in sys.path:
            sys.path.insert(0, repo)
        from gateway.project import resolve_project
        from pathlib import Path

        proj = resolve_project(Path(git_root))
        return bool(proj.fail_closed)
    except Exception:
        return False


def _session_caps_from_env():
    """Capacités de session (opt-in, GWSA_SESSION_CAPS) : liste de
    {"service":…, "operation":…, "resource":…(optionnel)}. Absent/illisible
    → None (pas de contrainte — compat tests/appelants legacy)."""
    raw = os.environ.get("GWSA_SESSION_CAPS", "").strip()
    if not raw:
        return None
    try:
        caps = json.loads(raw)
    except Exception:
        return None
    return caps if isinstance(caps, list) else None


def _session_cap_allows(caps, service, operation, resource=""):
    for c in caps:
        if not isinstance(c, dict):
            continue
        c_service = c.get("service")
        c_operation = c.get("operation")
        # Capacité joker (service="*"/operation="*") : matérialise un
        # « session unlock <alias> » — compte entier, borné ensuite par la
        # policy du compte comme n'importe quel autre appel (ADR-0007 §3).
        if not (c_service in ("*", service) and c_operation in ("*", operation)):
            continue
        cap_res = c.get("resource") or ""
        # Ressource absente sur la capacité = service×opération entier
        # (borné par la policy compte, jamais un wildcard au-delà). Ressource
        # présente = seulement cette ressource exacte (ex. zone Drive).
        if not cap_res or cap_res == resource:
            return True
    return False


def check_session_caps(profile_dir, args, service, operation, resource=""):
    """Si GWSA_SESSION_CAPS est présent (un appel porte un session_id), l'appel
    doit être couvert par une capacité de session — sinon refus (deny-all sur
    ensemble vide, ADR-0007 §3, revue Codex P1 sur PR #110). Le broker pose
    toujours la variable dès qu'une session existe, y compris vide ; une
    capacité joker service=*/opération=* matérialise un `session unlock`.
    Sans GWSA_SESSION_CAPS (appel legacy sans session_id) : pas de contrainte
    (unlock/zones legacy restent le seul mécanisme, tests existants inchangés)."""
    caps = _session_caps_from_env()
    if caps is None:
        return
    if not _session_cap_allows(caps, service, operation, resource):
        deny(
            profile_dir, args, service,
            "%s « %s » hors capacités de session%s — access_request "
            "kind=session_grant_capability"
            % (
                LABELS_FR.get(operation, operation), service,
                (" (%s:%s)" % (service, resource)) if resource else " (%s:%s)" % (service, operation),
            ),
        )


def _session_drive_ok(profile_dir, parent, cat):
    """La SESSION autorise-t-elle l'écriture drive:<cat> vers `parent` ?
    Sans GWSA_SESSION_CAPS (appel legacy sans session_id) → True (zones/unlock
    legacy seuls). Sinon (y compris ensemble vide → False, deny-all) :
    couvert par une capacité fine `drive:<cat>` (globale ou sur `parent`), OU `parent`
    sous une zone Drive accordée à la SESSION (une zone de session EST une capacité)."""
    caps = _session_caps_from_env()
    if caps is None:
        return True
    if _session_cap_allows(caps, "drive", cat, parent or ""):
        return True
    if parent and os.environ.get("GWSA_USE_SESSION_GRANTS") == "1":
        raw = os.environ.get("GWSA_SESSION_DRIVE_ZONES", "")
        sz = {z.strip() for z in raw.split(",") if z.strip()}
        if sz and under_allowed(profile_dir, parent, sz):
            return True
    return False


def _drive_target_id(args):
    p = parse_json_flag(args, "--params")
    return p.get("fileId") or p.get("id") or ""


def _gate_drive_session(profile_dir, args, pos):
    """Intersection fail-closed des capacités de session sur une op Drive quand la
    policy compte est permissive (« open » ou non-`zonesOnly`). Appelée UNIQUEMENT
    si GWSA_SESSION_CAPS est présent — sinon le comportement legacy est inchangé."""
    resource, method = pos[0], norm(pos[-1])
    if (resource == "files" and method in DRIVE_READ_FILES) \
            or (resource in SHARE_RESOURCES and method in ("list", "get")) \
            or (resource not in ("files",) and resource not in SHARE_RESOURCES
                and method in READ_METHODS):
        check_session_caps(profile_dir, args, "drive", "read")
        return
    if resource in SHARE_RESOURCES:
        check_session_caps(profile_dir, args, "drive", "share")
        return
    if method in ("create", "copy"):
        cat = "create"
    elif method in ("delete", "trash", "batchdelete"):
        cat = "delete"
    elif method in ("update", "patch", "modify", "untrash", "upload"):
        cat = "update"
    else:
        cat = "update"
    parents = parse_json_flag(args, "--json").get("parents") or []
    targets = parents if (cat == "create" and parents) else [_drive_target_id(args)]
    for t in targets:
        if not _session_drive_ok(profile_dir, t, cat):
            deny(profile_dir, args, "drive",
                 "« drive:%s »%s hors capacités/zones de session — access_request "
                 "kind=session_grant_capability" % (cat, (" %s" % t) if t else ""))


def _manifest_service_cap(alias, service, cat):
    """None = pas de contrainte ; True/False = plafond manifeste."""
    git_root = os.environ.get("GWSA_GIT_ROOT", "").strip()
    if not git_root:
        return None
    try:
        repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        if repo not in sys.path:
            sys.path.insert(0, repo)
        from gateway.project import manifest_allows_service, resolve_project
        from pathlib import Path

        proj = resolve_project(Path(git_root))
        if not proj.manifest_valid or not proj.manifest:
            return None
        return manifest_allows_service(proj.manifest, alias, service, cat)
    except Exception:
        return None


def main():
    if len(sys.argv) < 3:
        return
    profile_dir, args = sys.argv[1], sys.argv[2:]
    policy_path = os.path.join(profile_dir, "policy.json")
    # Absence de policy = le checker n'est pas appelé par mag (profil legacy).
    # Les profils créés via `mag add` reçoivent une policy prudente automatiquement.
    # Un policy.json PRÉSENT et illisible doit refuser — fail closed.
    if not os.path.exists(policy_path):
        return
    try:
        with open(policy_path) as f:
            pol = json.load(f)
    except Exception:
        log_usage(profile_dir, "refus", args, "policy.json illisible/corrompu")
        sys.stderr.write(
            "mag : ✗ policy — policy.json présent mais illisible (corrompu) : "
            "refus par sécurité. Corriger ou recréer la policy du profil.\n"
        )
        sys.exit(4)

    # Normaliser le service AVANT le lookup policy : retirer un éventuel suffixe
    # de version (`gmail:v1`, `drive:v3` — syntaxe acceptée par gws) et la casse,
    # sinon `pol.get("gmail:v1")` = None ferait tout passer hors policy.
    raw_service = args[0].split(":", 1)[0].lower()
    service = SERVICE_ALIASES.get(raw_service, raw_service)
    if service in PASSTHROUGH_SERVICES:
        return

    # Anti-downgrade (ADR-0007 §3, S-07) : un manifeste projet déjà de
    # confiance qui devient invalide/altéré/supprimé ne doit JAMAIS retomber
    # silencieusement sur policy ∩ session — refus global, avant tout calcul
    # de catégorie (fail-closed, prime sur toute autre autorisation).
    if _project_fail_closed():
        deny(
            profile_dir, args, service,
            "manifeste projet invalide/altéré/supprimé après confiance — refus "
            "(anti-downgrade) — reconstituer/signer .gwsa/manifest.json "
            "(« mag project sign »)",
        )

    pos = positionals_of(args[1:])
    if not pos:
        return

    svc_pol = pol.get(service)
    if not isinstance(svc_pol, dict):
        # Default-deny : service non déclaré = refus (chat, meet, people, …).
        deny(
            profile_dir, args, service,
            "service « %s » non déclaré dans la policy — refus (default-deny). "
            "Élicitation : demander à l'utilisateur d'ajouter ce service via "
            "l'interface admin ou policy.json" % service,
        )

    if service == "drive":
        check_drive(profile_dir, svc_pol, args, pos)
        return

    resources, raw_method = pos[:-1], pos[-1]
    cat = categorize(service, resources, raw_method)
    if cat is None:
        deny(profile_dir, args, service,
             "méthode « %s » non classifiable — refusée par prudence" % raw_method)
    # Pas de défaut « read libre » : seule une clé explicite True autorise.
    if not svc_pol.get(cat, False):
        deny(profile_dir, args, service,
             "%s refusé·e par la policy (« %s %s »)"
             % (LABELS_FR.get(cat, cat), " ".join(resources) or service, raw_method))
    # Intersection couche projet (.gwsa) : plafond services si déclaré
    alias = os.path.basename(os.path.abspath(profile_dir))
    mcap = _manifest_service_cap(alias, service, cat)
    if mcap is False:
        deny(
            profile_dir, args, service,
            "%s « %s » hors périmètre manifeste projet (.gwsa/manifest.json) — "
            "éditer le manifeste puis « mag project sign », ou access_request "
            "kind=project_grant"
            % (LABELS_FR.get(cat, cat), service),
        )
    # Ressource propre au service (Gmail labelId, Calendar calendarId, …) —
    # sans elle, la granularité ressource des capacités de session ne
    # fonctionnait que sur Drive (fiche 0080, raffinement #1).
    check_session_caps(profile_dir, args, service, cat, resource_from_params(args))


if __name__ == "__main__":
    main()