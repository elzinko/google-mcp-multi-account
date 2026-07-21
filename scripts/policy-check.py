#!/usr/bin/env python3
"""Contrôleur de policy par service pour gwsa.

Appelé par bin/gwsa (et la gateway MCP) avant TOUTE commande quand le profil
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
(temporaires, accordées par l'utilisateur via `gwsa grant`, expiration auto).
Par défaut (zonesOnly sans zones) : aucune écriture possible.

Sortie : exit 0 = autorisé (gwsa exécute), exit 4 = refusé (message stderr).
Les refus sont journalisés dans ~/.config/gws-accounts/usage.jsonl.
"""
import datetime
import json
import os
import subprocess
import sys
import time

VALUE_FLAGS = {
    "--params", "--json", "--upload", "--upload-content-type", "--output",
    "--format", "--api-version", "--page-limit", "--page-delay", "--scopes",
    "--services",
}
SERVICE_ALIASES = {"wf": "workflow", "reports": "admin-reports"}
# Introspection / auth locale — pas des APIs données ; hors modèle policy.
PASSTHROUGH_SERVICES = frozenset({"auth", "schema"})

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


def norm(method):
    return method.lstrip("+").replace("-", "").replace("_", "").lower()


def deny(profile_dir, args, service, msg):
    alias = os.path.basename(os.path.abspath(profile_dir))
    log_usage(profile_dir, "refus", args, msg)
    sys.stderr.write(
        "gwsa : ✗ policy %s — %s\n"
        "       Élicitation : demander à l'utilisateur d'élargir la policy\n"
        "       (« gwsa policy %s show » pour voir, interface admin pour modifier).\n"
        % (service, msg, alias)
    )
    sys.exit(4)


def gws_json(profile_dir, args):
    """Interroge gws en lecture. Toute défaillance (binaire absent, timeout,
    sortie illisible) renvoie {} : l'appelant conclut alors « parent inconnu »,
    donc refus — fail closed, jamais de crash ni d'autorisation par accident."""
    env = dict(os.environ, GOOGLE_WORKSPACE_CLI_CONFIG_DIR=profile_dir)
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
    """Zones temporaires accordées par l'utilisateur (gwsa grant), non expirées."""
    try:
        with open(os.path.join(profile_dir, "session-grants.json")) as f:
            g = json.load(f)
    except Exception:
        return set()
    now = time.time()
    return {e["id"] for e in g.get("drive", []) if e.get("expiresAt", 0) > now and e.get("id")}


def zone_hint(alias):
    return ("aucune zone d'écriture active — demander à l'utilisateur une autorisation "
            "temporaire (« gwsa grant %s \"<dossier>\" [heures] ») ou permanente "
            "(« gwsa policy %s allow <dossier> » / interface admin)" % (alias, alias))


def check_drive(profile_dir, drive_raw, args, pos):
    drive = normalize_drive(drive_raw)
    if drive is None:
        return
    alias = os.path.basename(os.path.abspath(profile_dir))
    resource, method = pos[0], norm(pos[-1])

    if resource == "files" and method in DRIVE_READ_FILES:
        return
    if resource in SHARE_RESOURCES and method in ("list", "get"):
        return
    if resource not in ("files",) and resource not in SHARE_RESOURCES \
            and method in READ_METHODS:
        return

    if method == "emptytrash":
        deny(profile_dir, args, "drive", "emptyTrash interdit (suppression définitive)")

    if resource in SHARE_RESOURCES:
        if not drive.get("share"):
            deny(profile_dir, args, "drive",
                 "partage refusé par la policy (« %s %s »)" % (resource, pos[-1]))
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
    if not drive.get(cat, False):
        deny(profile_dir, args, "drive",
             "%s refusé·e par la policy (« files %s »)" % (LABELS_FR.get(cat, cat), pos[-1]))

    if not drive.get("zonesOnly"):
        return

    zones = set(drive.get("writeFolders") or []) | active_grants(profile_dir)
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
                 "[<dossier autorisé>] (zones actives : gwsa grants %s)" % (pos[-1], alias))
        for p in parents:
            if not under_allowed(profile_dir, p, zones):
                deny(profile_dir, args, "drive",
                     "parent/destination %s hors zone d'écriture autorisée" % p)
        return

    fid = params.get("fileId")
    if not fid:
        deny(profile_dir, args, "drive",
             "files %s sans fileId identifiable — refusé par prudence" % pos[-1])
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


def categorize(service, resources, raw_method):
    """Catégorie d'action, ou None si inconnue (→ fail closed)."""
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


LABELS_FR = {
    "read": "lecture", "create": "création", "update": "modification",
    "delete": "suppression", "send": "envoi", "drafts": "brouillons",
    "labels": "libellés", "share": "partage", "settings": "réglages",
}


def main():
    if len(sys.argv) < 3:
        return
    profile_dir, args = sys.argv[1], sys.argv[2:]
    policy_path = os.path.join(profile_dir, "policy.json")
    # Absence de policy = le checker n'est pas appelé par gwsa (profil legacy).
    # Les profils créés via `gwsa add` reçoivent une policy prudente automatiquement.
    # Un policy.json PRÉSENT et illisible doit refuser — fail closed.
    if not os.path.exists(policy_path):
        return
    try:
        with open(policy_path) as f:
            pol = json.load(f)
    except Exception:
        log_usage(profile_dir, "refus", args, "policy.json illisible/corrompu")
        sys.stderr.write(
            "gwsa : ✗ policy — policy.json présent mais illisible (corrompu) : "
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


if __name__ == "__main__":
    main()
