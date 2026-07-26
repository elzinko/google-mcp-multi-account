#!/usr/bin/env bash
# Suite de tests de gwsa — contrôleur de policy + garde-fous du wrapper.
#
# Hermétique : aucun compte réel, aucun appel réseau, aucun binaire `gws` requis
# (le contrôleur fail closed quand gws est absent). Tout se passe dans un
# GWSA_ROOT temporaire — tes vrais profils ~/.config/gws-accounts/ ne sont
# jamais lus ni écrits.
#
# Usage : ./scripts/test.sh          (exit 0 = tout vert, 1 = au moins un échec)
set -uo pipefail

cd "$(dirname "$0")/.."
CHECKER="scripts/policy-check.py"
GWSA="bin/gwsa"

TMP="$(mktemp -d)"
export GWSA_ROOT="$TMP/root"
PROFILE="$GWSA_ROOT/testprof"
mkdir -p "$PROFILE"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0

# --- Assertions -------------------------------------------------------------

policy() { cat > "$PROFILE/policy.json"; }        # policy.json depuis stdin
grants()  { cat > "$PROFILE/session-grants.json"; }
no_grants() { rm -f "$PROFILE/session-grants.json"; }

check() { # check <code-attendu> <description> <args du checker…>
  local want="$1" desc="$2"; shift 2
  python3 "$CHECKER" "$PROFILE" "$@" >/dev/null 2>&1
  local got=$?
  if [[ "$got" == "$want" ]]; then
    PASS=$((PASS + 1)); printf '  \033[32m✓\033[0m %s\n' "$desc"
  else
    FAIL=$((FAIL + 1)); printf '  \033[31m✗\033[0m %s (attendu %s, obtenu %s)\n' "$desc" "$want" "$got"
  fi
}

cli() { # cli <code-attendu> <description> <args de gwsa…>
  local want="$1" desc="$2"; shift 2
  "$GWSA" "$@" >/dev/null 2>&1
  local got=$?
  if [[ "$got" == "$want" ]]; then
    PASS=$((PASS + 1)); printf '  \033[32m✓\033[0m %s\n' "$desc"
  else
    FAIL=$((FAIL + 1)); printf '  \033[31m✗\033[0m %s (attendu %s, obtenu %s)\n' "$desc" "$want" "$got"
  fi
}

section() { printf '\n\033[1m%s\033[0m\n' "$1"; }

ZONE="ZONEFOLDER12345678901"
GRANT="GRANTFOLDER1234567890"

# --- 1. Policy par service (fail closed) ------------------------------------

section "Policy par service — préréglage prudent (Gmail sans envoi, Drive lecture seule)"
policy <<'EOF'
{
  "drive":    {"mode": "readonly"},
  "gmail":    {"read": true, "drafts": true, "send": false, "labels": true,
               "update": false, "delete": false, "settings": false},
  "calendar": {"read": true, "create": false, "update": false, "delete": false},
  "keep":     {"read": true, "create": true, "update": false, "delete": false}
}
EOF

check 0 "gmail messages list — lecture autorisée"            gmail users messages list --params '{}'
check 0 "gmail drafts create — brouillon autorisé"           gmail users drafts create --json '{}'
check 0 "gmail +triage — assistant de lecture autorisé"      gmail users messages +triage
check 0 "drive files list — lecture autorisée"               drive files list --params '{}'
check 0 "keep notes create — création autorisée"             keep notes create --json '{}'
check 0 "calendar events list — lecture autorisée"           calendar events list
check 4 "tasks insert — service hors policy → default-deny"  tasks tasklists insert --json '{}'
# Default-deny sur TOUTE la classe des services non modélisés (fiche 0002 point 1).
# Le préréglage prudent ne déclare que drive/gmail/calendar/keep : tout le reste
# (chat, meet, people, slides, forms, script…) est refusé, lecture comprise.
check 4 "chat send — service non modélisé → default-deny"    chat spaces messages create --json '{"text":"hi"}'
check 4 "meet create — service non modélisé → default-deny"  meet spaces create --json '{}'
check 4 "people create — service non modélisé → default-deny" people people createContact --json '{}'
check 4 "slides create — service non modélisé → default-deny" slides presentations create --json '{}'
check 4 "forms create — service non modélisé → default-deny"  forms forms create --json '{}'
check 4 "people GET — service non modélisé refusé même en lecture" people people get --params '{"resourceName":"people/me"}'
check 4 "gmail messages send — ENVOI refusé"                 gmail users messages send --json '{}'
check 4 "gmail drafts send — envoi d'un brouillon refusé"    gmail users drafts send --json '{}'
check 4 "gmail messages delete — suppression refusée"        gmail users messages delete --params '{}'
check 4 "gmail messages trash — mise à la corbeille refusée" gmail users messages trash --params '{}'
check 4 "gmail +reply — assistant d'envoi refusé"            gmail users messages +reply
check 4 "gmail settings update — réglages refusés"           gmail users settings updateVacation --json '{}'
check 4 "gmail méthode inconnue — refus par défaut"          gmail users messages frobnicate
check 4 "drive files update — lecture seule"                 drive files update --params '{"fileId":"x"}'
check 4 "drive files delete — lecture seule"                 drive files delete --params '{"fileId":"x"}'
check 4 "calendar events insert — création refusée"          calendar events insert --json '{}'
check 4 "keep notes delete — suppression refusée"            keep notes delete --params '{}'

# --- 2. Drive par zones (schéma v2) -----------------------------------------

section "Drive par zones — aucune zone autorisée (défaut : le LLM n'écrit nulle part)"
policy <<'EOF'
{"drive": {"read": true, "create": true, "update": true, "delete": false,
           "share": false, "zonesOnly": true, "writeFolders": []}}
EOF
no_grants

check 0 "files list — la lecture reste possible partout"     drive files list
check 4 "files create — aucune zone active"                  drive files create --json "{\"name\":\"x\",\"parents\":[\"$ZONE\"]}"
check 4 "files delete — suppression interdite par la policy" drive files delete --params '{"fileId":"x"}'
check 4 "permissions create — partage interdit"              drive permissions create --params '{"fileId":"x"}'

section "Drive par zones — une zone permanente"
policy <<EOF
{"drive": {"read": true, "create": true, "update": true, "delete": false,
           "share": false, "zonesOnly": true, "writeFolders": ["$ZONE"]}}
EOF

check 0 "files create dans la zone — autorisé"               drive files create --json "{\"name\":\"x\",\"parents\":[\"$ZONE\"]}"
check 4 "files create sans parent — refusé"                  drive files create --json '{"name":"x"}'
check 4 "files create hors zone — refusé (parent inconnu)"   drive files create --json '{"name":"x","parents":["AUTREDOSSIER98765432"]}'

section "Drive par zones — autorisation temporaire (élicitation gwsa grant)"
policy <<'EOF'
{"drive": {"read": true, "create": true, "update": true, "delete": false,
           "share": false, "zonesOnly": true, "writeFolders": []}}
EOF
python3 - "$PROFILE/session-grants.json" "$GRANT" <<'PYEOF'
import json, sys, time
json.dump({"drive": [{"id": sys.argv[2], "name": "Test", "grantedAt": int(time.time()),
                      "expiresAt": int(time.time()) + 3600}]}, open(sys.argv[1], "w"))
PYEOF
check 0 "grant actif — écriture autorisée dans la zone"      drive files create --json "{\"name\":\"x\",\"parents\":[\"$GRANT\"]}"

python3 - "$PROFILE/session-grants.json" "$GRANT" <<'PYEOF'
import json, sys, time
json.dump({"drive": [{"id": sys.argv[2], "name": "Test", "grantedAt": 0,
                      "expiresAt": int(time.time()) - 10}]}, open(sys.argv[1], "w"))
PYEOF
check 4 "grant EXPIRÉ — écriture refusée (redemander)"       drive files create --json "{\"name\":\"x\",\"parents\":[\"$GRANT\"]}"
no_grants

section "Rétrocompatibilité — ancien schéma {\"mode\": …}"
policy <<'EOF'
{"drive": {"mode": "readonly"}}
EOF
check 0 "legacy readonly — list autorisé"                    drive files list
check 4 "legacy readonly — update refusé"                    drive files update --params '{"fileId":"x"}'

policy <<'EOF'
{"drive": {"mode": "open"}}
EOF
check 0 "legacy open — écriture libre"                       drive files create --json '{"name":"x"}'

# --- 2b. Non-régression sécurité (bypass trouvés par l'audit 2026-07-20) -----

section "Bypass corrigés — le contrôleur ne doit plus se laisser contourner"
policy <<'EOF'
{"gmail":   {"read": true, "drafts": false, "send": false, "labels": false,
             "update": false, "delete": false, "settings": false},
 "drive":   {"read": true, "create": true, "update": true, "delete": false,
             "share": false, "zonesOnly": true, "writeFolders": ["ZONEFOLDER12345678901"]},
 "calendar":{"read": true, "create": false, "update": false, "delete": false, "share": false}}
EOF
no_grants

check 4 "préfixe de version service (gmail:v1) ne contourne pas la policy" gmail:v1 users messages send --json '{"raw":"x"}'
check 4 "casse du service (GMAIL) ne contourne pas la policy"             GMAIL users messages send --json '{"raw":"x"}'
check 4 "flag inconnu + positionnel piège (send … --x list) → envoi refusé" gmail users messages send --json '{"raw":"x"}' --sanitize list
check 4 "create : parent dans --params (ignoré par l'API) → refusé"       drive files create --params "{\"parents\":[\"$ZONE\"],\"name\":\"x\"}"
check 4 "move addParents hors zone refusé"                                drive files update --params "{\"fileId\":\"$ZONE\",\"addParents\":\"HORS9999999999999999\"}"
check 4 "removeParents sans réancrage en zone refusé"                     drive files update --params "{\"fileId\":\"$ZONE\",\"removeParents\":\"$ZONE\"}"

section "Policy corrompue → fail closed (le docstring le promet)"
printf '{ ceci nest pas du json valide' > "$PROFILE/policy.json"
check 4 "policy.json illisible → refus (jamais fail open)"                gmail users messages send --json '{"raw":"x"}'

section "Garde-fous de catégorie jamais exercés (régression = autorisation indue)"
policy <<'EOF'
{"drive":   {"read": true, "create": true, "update": true, "delete": true,
             "share": false, "zonesOnly": false, "writeFolders": []},
 "gmail":   {"read": true, "drafts": true, "send": false, "labels": false,
             "update": false, "delete": false, "settings": false},
 "calendar":{"read": true, "create": false, "update": false, "delete": false, "share": false}}
EOF
check 4 "emptyTrash refusé même avec delete:true (irréversible)"          drive files empty-trash --params '{}'
check 4 "gmail labels create refusé si labels:false"                     gmail users labels create --json '{}'
check 4 "gmail messages modify refusé si update:false"                   gmail users messages modify --params '{"id":"x"}'
check 4 "calendar acl insert (partage d'agenda) refusé si share:false"   calendar acl insert --json '{}'
policy <<'EOF'
{"gmail": {"read": true, "drafts": false, "send": false, "labels": true,
           "update": false, "delete": false, "settings": false}}
EOF
check 0 "gmail labels create autorisé si labels:true"                    gmail users labels create --json '{}'

# --- 3. Garde-fous du wrapper gwsa ------------------------------------------

section "Wrapper gwsa — validation des arguments"
rm -f "$PROFILE/policy.json"

cli 3 "alias invalide (slash) rejeté"                        "bad/alias" auth status
cli 3 "mot réservé comme alias rejeté (add list)"            add list
cli 3 "mot réservé comme alias rejeté (add admin)"           add admin
cli 3 "admin : arguments superflus rejetés"                  admin stop extra
cli 0 "admin stop sans serveur → no-op sain"                 admin stop
cli 3 "arguments superflus rejetés (list)"                   list auth status
cli 3 "add sans argument → usage"                            add
cli 3 "profil inconnu → erreur explicite"                    inexistant auth status
cli 3 "unlock avec durée non numérique rejeté"               unlock testprof abc
cli 3 "unlock durée 0 rejetée"                               unlock testprof 0
cli 0 "unlock d'un profil non verrouillé → no-op sain"       unlock testprof 30
cli 3 "lock avec arguments superflus rejeté"                 lock testprof extra
cli 3 "grant durée 0 rejetée"                                grant testprof UnDossier 0
cli 3 "grant durée > 168 h rejetée"                          grant testprof UnDossier 999
cli 3 "grant durée non numérique rejetée"                    grant testprof UnDossier abc
cli 3 "policy mode invalide rejeté"                          policy testprof mode badmode
cli 3 "policy action inconnue rejetée"                       policy testprof zzz
cli 3 "policy allow sans dossier rejeté"                     policy testprof allow
cli 3 "alias '..' (path-traversal) rejeté"                   ".." auth status
cli 3 "alias avec espace rejeté"                             "a b" auth status

section "Wrapper gwsa — verrou « accès sur demande »"
"$GWSA" lock testprof >/dev/null 2>&1
cli 3 "profil verrouillé → toute commande refusée"           testprof gmail users messages list
rm -f "$GWSA_ROOT/usage.jsonl"
GWSA_CLIENT=test-cli "$GWSA" testprof gmail users messages list >/dev/null 2>&1
if python3 - <<'PY'
import json, os
lines = open(os.path.join(os.environ["GWSA_ROOT"], "usage.jsonl")).read().splitlines()
assert len(lines) == 1, lines
e = json.loads(lines[0])
assert e["decision"] == "refus" and e["reason"] == "locked", e
assert e["client"] == "test-cli" and e["alias"] == "testprof", e
assert e["cmd"] == "gmail users messages list", e
PY
then
  PASS=$((PASS + 1)); printf '  \033[32m✓\033[0m refus de verrou journalisé (decision:refus, reason:locked, client)\n'
else
  FAIL=$((FAIL + 1)); printf '  \033[31m✗\033[0m refus de verrou journalisé dans usage.jsonl\n'
fi
"$GWSA" unlock testprof 5 >/dev/null 2>&1
if "$GWSA" list 2>/dev/null | grep -q "🔓"; then
  PASS=$((PASS + 1)); printf '  \033[32m✓\033[0m unlock temporaire visible dans list\n'
else
  FAIL=$((FAIL + 1)); printf '  \033[31m✗\033[0m unlock temporaire absent de list\n'
fi
"$GWSA" unlock testprof off >/dev/null 2>&1
if "$GWSA" list 2>/dev/null | grep -q "🔒"; then
  FAIL=$((FAIL + 1)); printf '  \033[31m✗\033[0m verrou toujours présent après « unlock off »\n'
else
  PASS=$((PASS + 1)); printf '  \033[32m✓\033[0m « unlock off » retire bien le verrou\n'
fi

# --- 4. Gateway MCP (API locale, sans réseau / sans gws) --------------------

section "Gateway — verrou + access_request (élicitation sans exécution)"
export PYTHONPATH="$(pwd)${PYTHONPATH:+:$PYTHONPATH}"
if python3 - <<'PY'
import json
import os
from pathlib import Path
from gateway.api import access_request, profiles_list
from gateway.errors import GatewayError
from gateway import api

root = Path(os.environ["GWSA_ROOT"])
alias = "testprof"
d = root / alias
d.mkdir(parents=True, exist_ok=True)
(d / ".locked").write_text("")
try:
    (d / ".unlock-until").unlink()
except FileNotFoundError:
    pass
os.environ.setdefault("GWSA_CLIENT", "test")

pl = profiles_list()
assert pl["ok"] and any(p["alias"] == alias for p in pl["profiles"]), pl

r = access_request(alias, "unlock", minutes=30)
assert r.get("elicitation") and "gwsa unlock" in r["suggested_command"], r
assert not (d / ".unlock-until").exists(), "access_request ne doit pas déverrouiller"

log = root / "usage.jsonl"
try:
    log.unlink()
except FileNotFoundError:
    pass
try:
    api.gmail_list(alias)
    raise SystemExit("gmail_list aurait dû refuser (locked)")
except GatewayError as e:
    assert e.code == "locked", e.code
# Le refus fail-fast (api._run) doit laisser une trace dans usage.jsonl.
entries = [json.loads(x) for x in log.read_text().splitlines()]
assert len(entries) == 1, entries
assert entries[0]["decision"] == "refus" and entries[0]["reason"] == "locked", entries
assert entries[0]["alias"] == alias, entries
assert entries[0]["client"] == os.environ["GWSA_CLIENT"], entries

r2 = access_request(alias, "grant", folder="LLM", hours=4)
assert "gwsa grant" in r2["suggested_command"] and "LLM" in r2["suggested_command"], r2

# add_account : élicitation pour un compte qui n'existe pas encore — aucune
# création de profil, email obligatoire, prérequis IAM rappelés.
r3 = access_request("nouveaucompte", "add_account", email="exemple@gmail.com")
assert r3.get("elicitation") and r3["kind"] == "add_account", r3
assert r3["suggested_command"] == "gwsa add nouveaucompte exemple@gmail.com", r3
assert "sync-iam" in r3["message"], r3
assert not (root / "nouveaucompte").exists(), "add_account ne doit rien créer"
try:
    access_request("nouveaucompte", "add_account")
    raise SystemExit("add_account sans email aurait dû refuser")
except GatewayError as e:
    assert e.code == "error", e.code
print("ok")
PY
then
  PASS=$((PASS + 1)); printf '  \033[32m✓\033[0m gateway lock (refus journalisé) + access_request\n'
else
  FAIL=$((FAIL + 1)); printf '  \033[31m✗\033[0m gateway lock (refus journalisé) + access_request\n'
fi

# MCP tools/list smoke (stdio JSON-RPC, une requête)
MCP_OUT="$(printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' | python3 -m gateway 2>/dev/null | head -1)"
if echo "$MCP_OUT" | python3 -c 'import json,sys; r=json.load(sys.stdin); names=[t["name"] for t in r["result"]["tools"]]; assert "gmail_list" in names and "gmail_draft_create" in names and "setup_status" in names; assert not any(t["name"]=="gmail_send" for t in r["result"]["tools"]); ar=[t for t in r["result"]["tools"] if t["name"]=="access_request"][0]; assert "add_account" in ar["inputSchema"]["properties"]["kind"]["enum"]; dc=[t for t in r["result"]["tools"] if t["name"]=="drive_create"][0]; assert "content" in dc["inputSchema"]["properties"] and "text/markdown" in dc["inputSchema"]["properties"]["content_type"]["enum"]'; then
  PASS=$((PASS + 1)); printf '  \033[32m✓\033[0m MCP tools/list (Gmail+Drive+setup_status, pas de send)\n'
else
  FAIL=$((FAIL + 1)); printf '  \033[31m✗\033[0m MCP tools/list\n'
fi

section "Gateway — arguments gws construits (fiche 0024 : paramètres de chemin, contenu, propriétaire)"
if python3 - <<'PY'
import base64
import json
import os
from pathlib import Path

import gateway.api as api
from gateway.config import upload_spool
from gateway.errors import GatewayError

# Paramètres de CHEMIN exigés par gws pour chaque méthode appelée par la
# gateway (« gws schema <méthode> » → path). Les oublier = refus avant tout
# appel : « Required path parameter userId is missing » (le bug de la fiche).
PATH_PARAMS = {
    ("gmail", "users", "messages", "list"): {"userId"},
    ("gmail", "users", "messages", "get"): {"userId", "id"},
    ("gmail", "users", "drafts", "create"): {"userId"},
    ("drive", "files", "list"): set(),
    ("drive", "files", "get"): {"fileId"},
    ("drive", "files", "create"): set(),
}

CALLS = []
UPLOAD = {}
REPLY = {
    "id": "FILE1",
    "name": "Livrable",
    "owners": [{"emailAddress": "alice@gmail.com"}],
    "ownedByMe": True,
}


def fake_run(alias, args, timeout=60):
    """Remplace l'aller-retour broker : on inspecte la commande gws construite."""
    CALLS.append(args)
    if "--upload" in args:  # capturer le média AVANT que la gateway ne l'efface
        p = Path(args[args.index("--upload") + 1])
        UPLOAD.update(path=p, data=p.read_bytes(), mode=p.stat().st_mode & 0o777)
    if REPLY.get("boom"):
        raise GatewayError("échec simulé côté gws", code="exec")
    return dict(REPLY)


api._run = fake_run


def flags(args):
    return {a: args[i + 1] for i, a in enumerate(args) if a.startswith("--")}


def method_of(args):
    return tuple(a for a in args[: next((i for i, a in enumerate(args)
                                          if a.startswith("-")), len(args))])


alias = "testprof"
api.gmail_list(alias, query="is:unread")
api.gmail_get(alias, "MSGID")
api.gmail_create_draft(alias, to="bob@example.com", subject="Sujet",
                       body="Corps", cc="carol@example.com")
api.drive_list(alias, parent="FOLDER")
api.drive_get(alias, "FILE1")

# 1. Aucun appel n'oublie un paramètre de chemin — le bug initial et sa famille.
for args in CALLS:
    m = method_of(args)
    assert m in PATH_PARAMS, f"méthode {m} inconnue du test — compléter PATH_PARAMS"
    params = json.loads(flags(args).get("--params", "{}"))
    missing = PATH_PARAMS[m] - set(params)
    assert not missing, f"{m} : paramètre(s) de chemin manquant(s) {missing}"

# 2. Le brouillon garde son corps RFC 2822 en plus du userId.
draft = next(a for a in CALLS if method_of(a) == ("gmail", "users", "drafts", "create"))
f = flags(draft)
assert json.loads(f["--params"]) == {"userId": "me"}, f["--params"]
raw = json.loads(f["--json"])["message"]["raw"]
msg = base64.urlsafe_b64decode(raw + "=" * (-len(raw) % 4)).decode("utf-8")
assert "To: bob@example.com" in msg and "Subject: Sujet" in msg, msg
assert "Cc: carol@example.com" in msg and msg.endswith("Corps"), msg

# 3. Propriétaire demandé ET exposé (drive_get / drive_list).
get_args = next(a for a in CALLS if method_of(a) == ("drive", "files", "get"))
list_args = next(a for a in CALLS if method_of(a) == ("drive", "files", "list"))
for args in (get_args, list_args):
    fields = json.loads(flags(args)["--params"])["fields"]
    assert "owners(emailAddress)" in fields and "ownedByMe" in fields, fields

got = api.drive_get(alias, "FILE1")
assert got["owner"] == "alice@gmail.com" and got["owned_by_me"] is True, got
REPLY_LIST = {"files": [dict(REPLY), {"id": "F2", "name": "Autre"}]}
api._run = lambda *a, **k: dict(REPLY_LIST)
listed = api.drive_list(alias)
assert listed["ownership"] == [
    {"id": "FILE1", "name": "Livrable", "owner": "alice@gmail.com", "owned_by_me": True},
    {"id": "F2", "name": "Autre", "owner": "", "owned_by_me": None},
], listed["ownership"]
api._run = fake_run

# 4. drive_create sans contenu : comportement historique (aucun --upload).
CALLS.clear()
created = api.drive_create(alias, "Vide", "FOLDER")
args = CALLS[-1]
assert "--upload" not in args, args
assert json.loads(flags(args)["--json"])["parents"] == ["FOLDER"], args
assert created["owner"] == "alice@gmail.com", created

# 5. drive_create avec contenu : upload multipart, texte exact, fichier effacé.
CALLS.clear()
texte = "# Livrable\n\nUn **paragraphe** accentué : éàü.\n"
api.drive_create(alias, "Livrable", "FOLDER", content=texte)
args = CALLS[-1]
f = flags(args)
assert f["--upload-content-type"] == "text/markdown", f
assert UPLOAD["data"].decode("utf-8") == texte, UPLOAD["data"]
assert UPLOAD["mode"] == 0o600, oct(UPLOAD["mode"])
# Le média doit vivre dans le répertoire de dépôt = cwd de gws (ADR-0003),
# sinon gws refuse « outside the current directory ».
assert UPLOAD["path"].parent == upload_spool(), UPLOAD["path"]
assert not UPLOAD["path"].exists(), "le média doit être effacé après l'appel"
# Les zones Drive restent vérifiables : parents dans --json, propriétaire demandé.
assert json.loads(f["--json"])["parents"] == ["FOLDER"], f["--json"]
assert "owners(emailAddress)" in json.loads(f["--params"])["fields"], f["--params"]

# 6. content_type explicite honoré ; format non textuel refusé.
api.drive_create(alias, "Brut", "FOLDER", content="texte", content_type="text/plain")
assert flags(CALLS[-1])["--upload-content-type"] == "text/plain", CALLS[-1]
assert UPLOAD["path"].suffix == ".txt", UPLOAD["path"]
# Cible non-Google : le fichier est déposé tel quel, pas converti.
api.drive_create(alias, "notes.txt", "FOLDER", mime_type="text/plain", content="brut")
assert flags(CALLS[-1])["--upload-content-type"] == "text/plain", CALLS[-1]
for bad in ("application/pdf", "image/png"):
    try:
        api.drive_create(alias, "X", "FOLDER", content="x", content_type=bad)
        raise SystemExit(f"content_type {bad} aurait dû être refusé")
    except GatewayError as e:
        assert e.code == "error", e.code

# 7. Contenu démesuré : refus net, rien n'est envoyé ni laissé sur le disque.
before = set(upload_spool().iterdir())
try:
    api.drive_create(alias, "Gros", "FOLDER", content="x" * 2_000_000)
    raise SystemExit("un contenu de 2 Mo aurait dû être refusé")
except GatewayError as e:
    assert e.code == "error", e.code

# 8. Échec côté gws : le média est effacé quand même (nettoyage en finally).
REPLY["boom"] = True
try:
    api.drive_create(alias, "Livrable", "FOLDER", content="perdu")
    raise SystemExit("l'échec gws aurait dû remonter")
except GatewayError as e:
    assert e.code == "exec", e.code
REPLY.pop("boom")
assert not UPLOAD["path"].exists(), "média laissé derrière après un échec"
assert set(upload_spool().iterdir()) == before, "résidus dans le répertoire de dépôt"
print("ok")
PY
then
  PASS=$((PASS + 1)); printf '  \033[32m✓\033[0m paramètres de chemin + brouillon + propriétaire + contenu Drive\n'
else
  FAIL=$((FAIL + 1)); printf '  \033[31m✗\033[0m arguments gws construits (fiche 0024)\n'
fi

# Le répertoire de dépôt vit dans GWSA_ROOT : il ne doit jamais passer pour un
# profil (les trois énumérateurs filtrent sur ALIAS_RE).
if python3 -c '
from gateway.api import profiles_list
from gateway.config import upload_spool
upload_spool()
profs = profiles_list()["profiles"]
assert profs and not any(p["alias"].startswith(".") for p in profs), profs
' && ! "$GWSA" list 2>/dev/null | grep -q 'uploads'; then
  PASS=$((PASS + 1)); printf '  \033[32m✓\033[0m répertoire de dépôt .uploads invisible des listes de profils\n'
else
  FAIL=$((FAIL + 1)); printf '  \033[31m✗\033[0m .uploads ne doit pas apparaître comme un profil\n'
fi

section "Gateway — setup_status (lecture seule, dégradation gracieuse)"
if python3 - <<'PY'
import os
from pathlib import Path
from gateway.setup_status import setup_status

root = Path(os.environ["GWSA_ROOT"])
# Profil connecté + verrouillé factice (pas de provision.env ni gcloud dans le tmp).
d = root / "acct1"
d.mkdir(parents=True, exist_ok=True)
(d / "credentials.enc").write_text("x")   # marque « connecté »
(d / ".locked").write_text("")
try:
    (d / ".unlock-until").unlink()
except FileNotFoundError:
    pass

r = setup_status()
assert r["ok"] and "accounts" in r and "next_actions" in r, r
# Sans provision.env : projet inconnu → IAM non vérifiable, jamais d'erreur.
assert r["project_id"] is None and r["iam_checked"] is False, r
assert all(a["iam"] == "unknown" for a in r["accounts"]), r
# Profil verrouillé → commande unlock proposée ; rien n'est exécuté.
assert any("gwsa unlock acct1" in a for a in r["next_actions"]), r["next_actions"]
assert (d / ".locked").exists() and not (d / ".unlock-until").exists(), "setup_status ne doit rien muter"
print("ok")
PY
then
  PASS=$((PASS + 1)); printf '  \033[32m✓\033[0m setup_status (dégradation gracieuse + next_actions)\n'
else
  FAIL=$((FAIL + 1)); printf '  \033[31m✗\033[0m setup_status\n'
fi

section "Email = métadonnée .email (ADR-0002) — lisible verrouillé, sans exécuter gws"
if python3 - <<'PY'
import os
from pathlib import Path
from gateway.api import profiles_list
from gateway.setup_status import setup_status

root = Path(os.environ["GWSA_ROOT"])
# acct1 (connecté + verrouillé, cf. section précédente) reçoit sa métadonnée.
(root / "acct1" / ".email").write_text("alice@gmail.com\n")
# acct2 : connecté, sans .email (profil d'avant la fiche 0014).
d2 = root / "acct2"
d2.mkdir(parents=True, exist_ok=True)
(d2 / "credentials.enc").write_text("x")

profs = {p["alias"]: p for p in profiles_list()["profiles"]}
assert profs["acct1"]["locked"] and profs["acct1"]["email"] == "alice@gmail.com", profs
assert profs["acct2"]["email"] == "", profs  # pas de fichier → vide (zéro exec gws)

r = setup_status()
accs = {a["alias"]: a for a in r["accounts"]}
assert accs["acct1"]["email"] == "alice@gmail.com", accs  # cohérent avec profiles_list
assert accs["acct2"]["email"] == "", accs
# Profil sans .email → suggérer le geste humain qui la renseigne.
assert any(a.startswith("gwsa list") for a in r["next_actions"]), r["next_actions"]

# Contenu non-email → ignoré (pas de confiance aveugle dans le fichier).
(d2 / ".email").write_text("pas-un-email\n")
profs2 = {p["alias"]: p for p in profiles_list()["profiles"]}
assert profs2["acct2"]["email"] == "", profs2
print("ok")
PY
then
  PASS=$((PASS + 1)); printf '  \033[32m✓\033[0m email lisible verrouillé + backfill suggéré + contenu validé\n'
else
  FAIL=$((FAIL + 1)); printf '  \033[31m✗\033[0m email métadonnée .email\n'
fi

# Invariant ADR-0002 : la gateway n'exécute jamais gws elle-même — le seul
# GOOGLE_WORKSPACE_CLI_CONFIG_DIR autorisé est celui du broker.
if ! grep -rn "GOOGLE_WORKSPACE_CLI_CONFIG_DIR" gateway/ --include='*.py' | grep -v "broker_server.py" | grep -q .; then
  PASS=$((PASS + 1)); printf '  \033[32m✓\033[0m invariant : aucun GOOGLE_WORKSPACE_CLI_CONFIG_DIR dans gateway/ hors broker\n'
else
  FAIL=$((FAIL + 1)); printf '  \033[31m✗\033[0m gateway/ contient un GOOGLE_WORKSPACE_CLI_CONFIG_DIR hors broker_server.py\n'
fi

# gwsa list lit .email sans gws (métadonnée posée → email affiché tel quel)
mkdir -p "$GWSA_ROOT/emailprof"
touch "$GWSA_ROOT/emailprof/credentials.enc"
printf 'bob@gmail.com\n' > "$GWSA_ROOT/emailprof/.email"
list_out="$("$GWSA" list 2>/dev/null)"   # pas de pipe direct : grep -q + pipefail = SIGPIPE
if echo "$list_out" | grep -q 'emailprof.*bob@gmail.com'; then
  PASS=$((PASS + 1)); printf '  \033[32m✓\033[0m gwsa list lit la métadonnée .email (aucun gws requis)\n'
else
  FAIL=$((FAIL + 1)); printf '  \033[31m✗\033[0m gwsa list devrait afficher bob@gmail.com via .email\n'
fi

# .email corrompu (contenu non-email) → non autoritatif : jamais affiché tel quel,
# le backfill (gws) reprend la main (retour Codex PR #18). Hermétique : gws ne
# fournit rien ici → aucun email affiché, mais surtout pas la valeur bidon.
mkdir -p "$GWSA_ROOT/badmeta"
touch "$GWSA_ROOT/badmeta/credentials.enc"
printf 'pas-un-email\n' > "$GWSA_ROOT/badmeta/.email"
bad_out="$("$GWSA" list 2>/dev/null)"
if ! echo "$bad_out" | grep -q 'pas-un-email'; then
  PASS=$((PASS + 1)); printf '  \033[32m✓\033[0m .email corrompu ignoré par gwsa list (pas de court-circuit du backfill)\n'
else
  FAIL=$((FAIL + 1)); printf '  \033[31m✗\033[0m .email corrompu ne doit pas être affiché tel quel\n'
fi

section "Broker Phase 2 A — ping + refus locked via RPC"
if python3 - <<'PY'
import json, os, socket, threading, time
from pathlib import Path

os.environ["GWSA_BROKER_PORT"] = "4879"  # port de test isolé
from gateway.broker_server import (
    BrokerHandler, ThreadedTCPServer, ensure_token, handle_exec, broker_port,
)
from gateway.errors import GatewayError

root = Path(os.environ["GWSA_ROOT"])
alias = "testprof"
d = root / alias
d.mkdir(parents=True, exist_ok=True)
(d / ".locked").write_text("")
try:
    (d / ".unlock-until").unlink()
except FileNotFoundError:
    pass

tok = ensure_token()
BrokerHandler.expected_token = tok
srv = ThreadedTCPServer(("127.0.0.1", broker_port()), BrokerHandler)
t = threading.Thread(target=srv.serve_forever, daemon=True)
t.start()
time.sleep(0.05)

def rpc(obj):
    data = (json.dumps(obj) + "\n").encode()
    with socket.create_connection(("127.0.0.1", broker_port()), timeout=2) as s:
        s.sendall(data)
        buf = b""
        while b"\n" not in buf:
            buf += s.recv(65536)
    return json.loads(buf.split(b"\n", 1)[0])

log = root / "usage.jsonl"
try:
    log.unlink()
except FileNotFoundError:
    pass

r = rpc({"token": tok, "cmd": "ping"})
assert r.get("ok"), r
r2 = rpc({"token": tok, "cmd": "exec", "alias": alias, "args": ["gmail", "users", "messages", "list"], "client": "test"})
assert r2.get("ok") is False and r2.get("code") == "locked", r2
r3 = rpc({"token": "bad", "cmd": "ping"})
assert r3.get("ok") is False and r3.get("code") == "auth", r3

# handle_exec direct aussi
try:
    handle_exec(alias, ["gmail", "users", "messages", "list"], "test")
    raise SystemExit("attendu locked")
except GatewayError as e:
    assert e.code == "locked", e.code

# Les deux refus (RPC + direct) doivent être dans usage.jsonl, avec le client.
entries = [json.loads(x) for x in log.read_text().splitlines()]
assert len(entries) == 2, entries
for e in entries:
    assert e["decision"] == "refus" and e["reason"] == "locked", e
    assert e["client"] == "test" and e["alias"] == alias, e

srv.shutdown()
print("ok")
PY
then
  PASS=$((PASS + 1)); printf '  \033[32m✓\033[0m broker ping + locked (refus journalisé) + token\n'
else
  FAIL=$((FAIL + 1)); printf '  \033[31m✗\033[0m broker ping + locked (refus journalisé) + token\n'
fi

# Le broker exécute gws depuis le répertoire de dépôt (ADR-0003) : c'est le bac
# à sable fichiers de gws, qui refuse tout --upload en dehors de son cwd.
if python3 - <<'PY'
import subprocess
from pathlib import Path

import gateway.broker_server as bs
from gateway.config import upload_spool

captured = {}


class Done:
    returncode, stdout, stderr = 0, '{"ok": true}', ""


def fake(cmd, **kw):
    captured.update(kw, cmd=cmd)
    return Done()


bs._gws_bin = lambda: "/usr/bin/true"   # suite hermétique : gws peut être absent
real_run, subprocess.run = subprocess.run, fake
try:
    bs.run_gws_local(Path("/nowhere/profile"), ["drive", "files", "list"])
finally:
    subprocess.run = real_run

spool = upload_spool()
assert captured["cwd"] == str(spool), captured.get("cwd")
assert spool.is_dir() and spool.stat().st_mode & 0o777 == 0o700, oct(spool.stat().st_mode)
assert captured["env"]["GOOGLE_WORKSPACE_CLI_CONFIG_DIR"] == "/nowhere/profile", captured["env"]
print("ok")
PY
then
  PASS=$((PASS + 1)); printf '  \033[32m✓\033[0m broker : gws exécuté depuis le répertoire de dépôt (cwd, 0700)\n'
else
  FAIL=$((FAIL + 1)); printf '  \033[31m✗\033[0m broker : cwd de gws = répertoire de dépôt (ADR-0003)\n'
fi

# --- 5. Onboarding IAM — détecteur du 403 « quota project » (hermétique) -----

section "Onboarding IAM — scripts/iam-check.py (détection 403 + remédiation)"
IAM="scripts/iam-check.py"
GWS_403='error[api]: Caller does not have required permission to use project gws-multi-802ec6. Grant the caller the roles/serviceusage.serviceUsageConsumer role, or a custom role with the serviceusage.services.use permission, by visiting https://console...'

iam_out="$(printf '%s' "$GWS_403" | python3 "$IAM" detect alice@gmail.com 2>/dev/null)"; iam_rc=$?
if [[ "$iam_rc" == 0 ]] \
   && echo "$iam_out" | grep -q 'add-iam-policy-binding gws-multi-802ec6' \
   && echo "$iam_out" | grep -q -- '--member=user:alice@gmail.com' \
   && echo "$iam_out" | grep -q 'serviceUsageConsumer'; then
  PASS=$((PASS + 1)); printf '  \033[32m✓\033[0m 403 détecté → commande gcloud exacte (projet + email de l'\''appelant)\n'
else
  FAIL=$((FAIL + 1)); printf '  \033[31m✗\033[0m 403 détecté → remédiation (rc=%s)\n' "$iam_rc"
fi

# Sortie normale de gws (pas de 403) → aucune remédiation, rc=1
printf '%s' '{"files":[{"id":"x","name":"y"}]}' | python3 "$IAM" detect bob@gmail.com >/dev/null 2>&1
if [[ $? == 1 ]]; then
  PASS=$((PASS + 1)); printf '  \033[32m✓\033[0m sortie saine → aucune remédiation (rc=1, silencieux)\n'
else
  FAIL=$((FAIL + 1)); printf '  \033[31m✗\033[0m sortie saine devrait être silencieuse (rc=1)\n'
fi

# Usage invalide (pas d'email / mauvais verbe) → rc=2
printf 'x' | python3 "$IAM" detect >/dev/null 2>&1
if [[ $? == 2 ]]; then
  PASS=$((PASS + 1)); printf '  \033[32m✓\033[0m usage invalide → rc=2\n'
else
  FAIL=$((FAIL + 1)); printf '  \033[31m✗\033[0m usage invalide devrait donner rc=2\n'
fi

# --- 6. Branchement Claude Desktop — scripts/install-claude-desktop.sh -------
#
# Hermétique : jamais le vrai ~/Library/.../claude_desktop_config.json — tout se
# passe sur des fichiers de config sous $TMP, via --config. Aucune install de
# Claude Desktop requise.

section "Branchement Claude Desktop — install-claude-desktop.sh (merge idempotent, hermétique)"
INSTALL="scripts/install-claude-desktop.sh"
CD="$TMP/desktop"; mkdir -p "$CD"

pass() { PASS=$((PASS + 1)); printf '  \033[32m✓\033[0m %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  \033[31m✗\033[0m %s\n' "$1"; }
jget() { # jget <fichier> <chemin.pointé> → imprime la valeur (vide/rc≠0 si absente)
  python3 -c 'import json,sys
d = json.load(open(sys.argv[1]))
for k in sys.argv[2].split("."): d = d[k]
print(d)' "$1" "$2" 2>/dev/null
}

# existe et exécutable
[[ -x "$INSTALL" ]] \
  && pass "le script existe et est exécutable" \
  || fail "le script existe et est exécutable"

# création : config absente → entrée ajoutée (command absolu + GWSA_CLIENT)
f="$CD/create.json"
"$INSTALL" --config "$f" >/dev/null 2>&1
cmd="$(jget "$f" mcpServers.google-multi-account.command)"
env_client="$(jget "$f" mcpServers.google-multi-account.env.GWSA_CLIENT)"
[[ "$cmd" == */bin/google-mcp && "$env_client" == "claude-desktop" ]] \
  && pass "création : fichier absent → entrée (command absolu + GWSA_CLIENT=claude-desktop)" \
  || fail "création : fichier absent → entrée (command absolu + GWSA_CLIENT)"

# préservation : autres serveurs MCP + clés annexes intacts
f="$CD/preserve.json"
cat > "$f" <<'JSON'
{ "mcpServers": { "autre": { "command": "/usr/bin/foo", "args": ["--x"] } }, "globalShortcut": "Cmd+Shift+Space" }
JSON
"$INSTALL" --config "$f" >/dev/null 2>&1
[[ "$(jget "$f" mcpServers.autre.command)" == "/usr/bin/foo" \
   && "$(jget "$f" globalShortcut)" == "Cmd+Shift+Space" \
   && -n "$(jget "$f" mcpServers.google-multi-account.command)" ]] \
  && pass "préservation : serveur tiers + clés annexes intacts, entrée ajoutée" \
  || fail "préservation : serveur tiers + clés annexes intacts"

# idempotence : relance → aucune écriture (exit 0, contenu identique)
before="$(cat "$f")"
"$INSTALL" --config "$f" >/dev/null 2>&1; rc=$?
[[ "$rc" -eq 0 && "$before" == "$(cat "$f")" ]] \
  && pass "idempotence : relance → aucune écriture (exit 0, contenu identique)" \
  || fail "idempotence : relance → aucune écriture"

# mise à jour de chemin + backup horodaté
f="$CD/update.json"
cat > "$f" <<'JSON'
{ "mcpServers": { "google-multi-account": { "command": "/vieux/chemin/bin/google-mcp", "env": { "GWSA_CLIENT": "claude-desktop" } } } }
JSON
"$INSTALL" --config "$f" >/dev/null 2>&1
newcmd="$(jget "$f" mcpServers.google-multi-account.command)"
[[ "$newcmd" == */bin/google-mcp && "$newcmd" != *vieux* ]] \
  && pass "mise à jour : ancien chemin remplacé par le chemin absolu courant" \
  || fail "mise à jour : ancien chemin remplacé"
ls "$f".bak-* >/dev/null 2>&1 \
  && pass "backup horodaté créé avant modification" \
  || fail "backup horodaté créé avant modification"

# JSON invalide → refus (exit ≠ 0), fichier intact
f="$CD/bad.json"
printf '{ pas du json ' > "$f"; orig="$(cat "$f")"
"$INSTALL" --config "$f" >/dev/null 2>&1; rc=$?
[[ "$rc" -ne 0 && "$orig" == "$(cat "$f")" ]] \
  && pass "JSON invalide → refus (exit≠0), fichier intact" \
  || fail "JSON invalide → refus, fichier intact"

# --print (dry-run) n'écrit rien
f="$CD/dry.json"
"$INSTALL" --print --config "$f" >/dev/null 2>&1; rc=$?
[[ "$rc" -eq 0 && ! -e "$f" ]] \
  && pass "--print : dry-run n'écrit rien" \
  || fail "--print : dry-run n'écrit rien"

# fail-closed : mcpServers non-objet → refus, fichier intact (esprit default-deny)
f="$CD/notobj.json"
printf '{ "mcpServers": [1, 2, 3] }' > "$f"; orig="$(cat "$f")"
"$INSTALL" --config "$f" >/dev/null 2>&1; rc=$?
[[ "$rc" -ne 0 && "$orig" == "$(cat "$f")" ]] \
  && pass "mcpServers non-objet → refus (fail-closed), fichier intact" \
  || fail "mcpServers non-objet → refus, fichier intact"

# --- Déploiement local figé (fiche 0023) ------------------------------------

section "Version du serveur — VERSION généré au déploiement, « dev » dans un clone"

python3 - >/dev/null 2>&1 <<'PY'
import sys, tempfile, pathlib
sys.path.insert(0, ".")
import gateway.version as v
d = pathlib.Path(tempfile.mkdtemp())
v.REPO_DIR = d                                   # racine bidon : rien n'est lu du vrai repo
assert v.server_version() == "dev", "sans VERSION → dev"
(d / "VERSION").write_text("v9.9.9\n", encoding="utf-8")
assert v.server_version() == "v9.9.9", "avec VERSION → son contenu"
(d / "VERSION").write_text("   \n", encoding="utf-8")
assert v.server_version() == "dev", "VERSION vide → dev"
PY
[[ $? -eq 0 ]] \
  && pass "version : « dev » sans VERSION, contenu du fichier sinon, « dev » si vide" \
  || fail "version : « dev » sans VERSION, contenu du fichier sinon"

section "Pilotage du broker — gwsa broker status|stop"

BPID="$GWSA_ROOT/.broker.pid"
rm -f "$BPID"
# Port dédié : sans ça, un vrai broker écoutant sur 4878 rendrait le test
# « status sans pidfile » instable selon la machine.
export GWSA_BROKER_PORT=4977

out="$("$GWSA" broker status 2>&1)"; rc=$?
[[ "$rc" -eq 0 && "$out" == *"arrêté"* ]] \
  && pass "broker status sans pidfile → « arrêté », exit 0" \
  || fail "broker status sans pidfile → « arrêté », exit 0"

echo "999999" > "$BPID"          # pid qui n'existe pas → pidfile obsolète
out="$("$GWSA" broker status 2>&1)"; rc=$?
[[ "$rc" -eq 0 && "$out" == *"obsolète"* ]] \
  && pass "broker status sur pidfile obsolète → le signale, exit 0" \
  || fail "broker status sur pidfile obsolète → le signale"

# Pid VIVANT mais qui n'est pas un broker (le shell de test lui-même) : les pids
# sont recyclés, un pidfile périmé ne doit pas condamner un process innocent.
echo "$$" > "$BPID"
out="$("$GWSA" broker status 2>&1)"; rc=$?
[[ "$rc" -eq 0 && "$out" == *"obsolète"* ]] \
  && pass "broker status : pid vivant mais non-broker → obsolète (pas de faux positif)" \
  || fail "broker status : pid vivant mais non-broker → obsolète"

out="$("$GWSA" broker stop 2>&1)"; rc=$?
[[ "$rc" -eq 0 ]] && kill -0 "$$" 2>/dev/null \
  && pass "broker stop : ne tue PAS un process innocent dont le pid traînait" \
  || fail "broker stop : ne tue pas un process innocent"

echo "999999" > "$BPID"
out="$("$GWSA" broker stop 2>&1)"; rc=$?
[[ "$rc" -eq 0 && ! -f "$BPID" ]] \
  && pass "broker stop sur pidfile obsolète → nettoie, exit 0 (idempotent)" \
  || fail "broker stop sur pidfile obsolète → nettoie, exit 0"

cli 3 "broker : sous-commande inconnue refusée" broker nawak
cli 3 "« broker » est un mot réservé (gwsa add broker)" add broker

section "deploy-local.sh — copie figée, refus d'un arbre sale ou non taggé"

DEP="$TMP/deploy"
SRC="$TMP/srcrepo"
mkdir -p "$SRC/scripts"
cp scripts/deploy-local.sh "$SRC/scripts/"
echo "coeur" > "$SRC/app.txt"
git -C "$SRC" init -q >/dev/null 2>&1
git -C "$SRC" config user.email "test@example.invalid"
git -C "$SRC" config user.name "test"
git -C "$SRC" add -A >/dev/null 2>&1
git -C "$SRC" commit -qm "init" >/dev/null 2>&1
DEPLOY="$SRC/scripts/deploy-local.sh"

GWSA_DEPLOY_ROOT="$DEP" "$DEPLOY" >/dev/null 2>&1; rc=$?
[[ "$rc" -ne 0 && ! -d "$DEP" ]] \
  && pass "HEAD non taggé → refus, rien de déployé" \
  || fail "HEAD non taggé → refus, rien de déployé"

git -C "$SRC" tag v1.0.0

echo "pas commité" > "$SRC/dirty.txt"
GWSA_DEPLOY_ROOT="$DEP" "$DEPLOY" >/dev/null 2>&1; rc=$?
[[ "$rc" -ne 0 && ! -d "$DEP" ]] \
  && pass "arbre de travail sale → refus, rien de déployé" \
  || fail "arbre de travail sale → refus, rien de déployé"
rm -f "$SRC/dirty.txt"

GWSA_DEPLOY_ROOT="$DEP" "$DEPLOY" --print >/dev/null 2>&1; rc=$?
[[ "$rc" -eq 0 && ! -d "$DEP" ]] \
  && pass "--print : dry-run n'écrit rien" \
  || fail "--print : dry-run n'écrit rien"

GWSA_DEPLOY_ROOT="$DEP" "$DEPLOY" >/dev/null 2>&1; rc=$?
[[ "$rc" -eq 0 && -f "$DEP/v1.0.0/app.txt" && "$(cat "$DEP/v1.0.0/VERSION" 2>/dev/null)" == "v1.0.0" ]] \
  && pass "déploiement : copie créée sous le nom du tag + VERSION écrit" \
  || fail "déploiement : copie créée + VERSION écrit"

[[ "$(basename "$(readlink "$DEP/current" 2>/dev/null)" 2>/dev/null)" == "v1.0.0" ]] \
  && pass "déploiement : current pointe la version déployée" \
  || fail "déploiement : current pointe la version déployée"

[[ ! -d "$DEP/v1.0.0/.git" ]] \
  && pass "copie figée : pas de .git embarqué (git archive, fichiers suivis seuls)" \
  || fail "copie figée : pas de .git embarqué"

# LE critère de la fiche : toucher la source ne doit rien changer au déployé.
echo "modifié pendant le développement" > "$SRC/app.txt"
[[ "$(cat "$DEP/v1.0.0/app.txt")" == "coeur" ]] \
  && pass "copie figée : modifier la source ne change PAS le code déployé" \
  || fail "copie figée : modifier la source ne change PAS le code déployé"
git -C "$SRC" checkout -q -- app.txt

GWSA_DEPLOY_ROOT="$DEP" "$DEPLOY" >/dev/null 2>&1; rc=$?
[[ "$rc" -eq 0 ]] \
  && pass "redéploiement du même tag → idempotent (exit 0)" \
  || fail "redéploiement du même tag → idempotent"

echo "v2" > "$SRC/app.txt"
git -C "$SRC" commit -qam "v2" >/dev/null 2>&1
git -C "$SRC" tag v1.1.0
GWSA_DEPLOY_ROOT="$DEP" "$DEPLOY" >/dev/null 2>&1
[[ "$(basename "$(readlink "$DEP/current" 2>/dev/null)" 2>/dev/null)" == "v1.1.0" ]] \
  && pass "seconde version déployée, current suit" \
  || fail "seconde version déployée, current suit"

GWSA_DEPLOY_ROOT="$DEP" "$DEPLOY" --rollback v1.0.0 >/dev/null 2>&1; rc=$?
[[ "$rc" -eq 0 && "$(basename "$(readlink "$DEP/current" 2>/dev/null)" 2>/dev/null)" == "v1.0.0" ]] \
  && pass "rollback : current revient sur la version précédente" \
  || fail "rollback : current revient sur la version précédente"

out="$(GWSA_DEPLOY_ROOT="$DEP" "$DEPLOY" --list 2>&1)"
[[ "$out" == *"* v1.0.0"* && "$out" == *"v1.1.0"* ]] \
  && pass "--list : les versions déployées, courante marquée d'une étoile" \
  || fail "--list : versions déployées, courante marquée"

GWSA_DEPLOY_ROOT="$DEP" "$DEPLOY" --rollback v9.9.9 >/dev/null 2>&1; rc=$?
[[ "$rc" -ne 0 ]] \
  && pass "rollback vers une version non déployée → refus" \
  || fail "rollback vers une version non déployée → refus"

# --- Bilan ------------------------------------------------------------------

printf '\n\033[1mBilan : %d réussis, %d échoués\033[0m\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
