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

section "Syntaxe des scripts — avec le bash DU SYSTÈME (macOS = 3.2)"
# La CI valide la syntaxe avec le bash de son runner (Linux, bash 5). Or macOS
# embarque bash 3.2, qui compte les apostrophes ASCII à l'intérieur d'un heredoc
# ouvert dans une substitution de commande : un nombre impair casse le parsing.
# Un script vert en CI peut donc être cassé chez l'utilisateur — d'où ce contrôle
# local, avec /bin/bash et pas le bash du PATH.
SYS_BASH="/bin/bash"
[[ -x "$SYS_BASH" ]] || SYS_BASH="$(command -v bash)"
for f in bin/gwsa scripts/*.sh; do
  if "$SYS_BASH" -n "$f" 2>/dev/null; then
    PASS=$((PASS + 1)); printf '  \033[32m✓\033[0m %s : syntaxe valide (%s)\n' "$f" "$("$SYS_BASH" --version | head -1 | sed 's/.*version \([0-9.]*\).*/\1/')"
  else
    FAIL=$((FAIL + 1)); printf '  \033[31m✗\033[0m %s : erreur de syntaxe avec %s\n' "$f" "$SYS_BASH"
    "$SYS_BASH" -n "$f" 2>&1 | head -3 | sed 's/^/      /'
  fi
done

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
check 0 "gmail attachments get — lecture autorisée"          gmail users messages attachments get --params '{"userId":"me","messageId":"m","id":"a"}'
check 0 "drive files export — lecture de contenu autorisée"  drive files export --params '{"fileId":"x","mimeType":"text/plain"}'
check 0 "drive files get alt=media — lecture autorisée"      drive files get --params '{"fileId":"x","alt":"media"}'
check 4 "drive files copy — création refusée en lecture seule" drive files copy --params '{"fileId":"x"}' --json '{"parents":["z"]}'
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
# fiche 0043 : copy = création zonée (destination), upload = create multipart
check 0 "files copy vers la zone — autorisé"                 drive files copy --params '{"fileId":"SRC"}' --json "{\"parents\":[\"$ZONE\"]}"
check 4 "files copy sans parent — refusé"                    drive files copy --params '{"fileId":"SRC"}' --json '{"name":"x"}'
check 4 "files copy hors zone — refusé (parent inconnu)"     drive files copy --params '{"fileId":"SRC"}' --json '{"parents":["AUTREDOSSIER98765432"]}'
check 0 "files create --upload (binaire) dans la zone — autorisé" drive files create --json "{\"name\":\"x.pdf\",\"parents\":[\"$ZONE\"]}" --upload ./x.pdf --upload-content-type application/pdf
check 4 "files create --upload sans parent — refusé"         drive files create --json '{"name":"x.pdf"}' --upload ./x.pdf --upload-content-type application/pdf

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

section "Corbeille = suppression + racine de zone immuable (fiche 0037)"
# A — corbeiller via « files update {trashed:true} » est une SUPPRESSION, refusée
#     sous delete:false même si update:true (le trou : classé « update » avant).
policy <<EOF
{"drive": {"read": true, "create": true, "update": true, "delete": false,
           "share": false, "zonesOnly": true, "writeFolders": ["$ZONE"]}}
EOF
no_grants
check 4 "corbeille via update {trashed:true} refusée sous delete:false"   drive files update --params "{\"fileId\":\"$ZONE\"}" --json '{"trashed":true}'
check 4 "corbeille via patch {trashed:true} refusée sous delete:false"    drive files patch  --params "{\"fileId\":\"$ZONE\"}" --json '{"trashed":true}'
# …et libre quand delete:true est explicitement accordé (hors zones)
policy <<'EOF'
{"drive": {"read": true, "create": true, "update": true, "delete": true,
           "share": false, "zonesOnly": false, "writeFolders": []}}
EOF
check 0 "corbeille via update {trashed:true} autorisée sous delete:true"  drive files update --json '{"trashed":true}'
# untrash (restauration, trashed:false) reste une modification, pas une suppression
policy <<'EOF'
{"drive": {"read": true, "create": true, "update": true, "delete": false,
           "share": false, "zonesOnly": false, "writeFolders": []}}
EOF
check 0 "restauration update {trashed:false} reste autorisée (update)"    drive files update --json '{"trashed":false}'
# B — la racine d'une zone est une frontière immuable, MÊME sous delete:true
policy <<EOF
{"drive": {"read": true, "create": true, "update": true, "delete": true,
           "share": false, "zonesOnly": true, "writeFolders": ["$ZONE"]}}
EOF
check 4 "racine de zone : suppression refusée même sous delete:true"      drive files delete --params "{\"fileId\":\"$ZONE\"}"
check 4 "racine de zone : corbeille refusée même sous delete:true"        drive files update --params "{\"fileId\":\"$ZONE\"}" --json '{"trashed":true}'
check 4 "racine de zone : renommage refusé (update sur la racine)"        drive files update --params "{\"fileId\":\"$ZONE\"}" --json '{"name":"x"}'

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
reserved() { # reserved <mot> — le refus doit CITER « mot réservé »
  local word="$1" out rc
  out="$("$GWSA" add "$word" 2>&1)"; rc=$?
  if [[ "$rc" -eq 3 && "$out" == *"mot réservé"* ]]; then
    PASS=$((PASS + 1)); printf '  \033[32m✓\033[0m « %s » refusé comme alias (mot réservé)\n' "$word"
  else
    FAIL=$((FAIL + 1)); printf '  \033[31m✗\033[0m « %s » devrait être refusé comme mot réservé (rc=%s)\n' "$word" "$rc"
  fi
}
reserved list
reserved admin
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

# fiche 0043 : les nouveaux tools restent derrière le verrou, refus journalisé.
for call in (
    lambda: api.drive_read(alias, "FILE1"),
    lambda: api.drive_copy(alias, "SRC1", "FOLDER"),
    lambda: api.gmail_attachment_get(alias, "MSG1", "ATT1"),
):
    try:
        call()
        raise SystemExit("tool 0043 aurait dû refuser (locked)")
    except GatewayError as e:
        assert e.code == "locked", e.code
entries = [json.loads(x) for x in log.read_text().splitlines()]
assert len(entries) == 4 and all(e["reason"] == "locked" for e in entries), entries

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
if echo "$MCP_OUT" | python3 -c 'import json,sys; r=json.load(sys.stdin); names=[t["name"] for t in r["result"]["tools"]]; assert "gmail_list" in names and "gmail_draft_create" in names and "setup_status" in names; assert not any(t["name"]=="gmail_send" for t in r["result"]["tools"]); ar=[t for t in r["result"]["tools"] if t["name"]=="access_request"][0]; assert "add_account" in ar["inputSchema"]["properties"]["kind"]["enum"]; assert "project_grant" in ar["inputSchema"]["properties"]["kind"]["enum"]; dc=[t for t in r["result"]["tools"] if t["name"]=="drive_create"][0]; assert "content" in dc["inputSchema"]["properties"] and "text/markdown" in dc["inputSchema"]["properties"]["content_type"]["enum"]; assert all(n in names for n in ("drive_read","drive_copy","drive_upload","gmail_attachment_get"))'; then
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

section "Gateway — lire / copier / téléverser / pièces jointes (fiche 0043)"
if python3 - <<'PY'
import base64
import hashlib
import json
import os
from pathlib import Path

import gateway.api as api
from gateway.config import download_dir, upload_spool
from gateway.errors import GatewayError

# Même famille de bug que la fiche 0024 : chaque méthode gws appelée doit
# porter TOUS ses paramètres de chemin (« gws schema <méthode> » → path).
PATH_PARAMS = {
    ("drive", "files", "get"): {"fileId"},
    ("drive", "files", "export"): {"fileId", "mimeType"},
    ("drive", "files", "copy"): {"fileId"},
    ("drive", "files", "create"): set(),
    ("gmail", "users", "messages", "attachments", "get"): {"userId", "messageId", "id"},
}

CALLS = []
ALL = []
UPLOAD = {}
META = {"id": "DOC1", "name": "Devis", "mimeType": "application/vnd.google-apps.document"}
REPLIES = {}


def flags(args):
    return {a: args[i + 1] for i, a in enumerate(args) if a.startswith("--")}


def method_of(args):
    return tuple(a for a in args[: next((i for i, a in enumerate(args)
                                          if a.startswith("-")), len(args))])


def fake_run(alias, args, timeout=60):
    CALLS.append(args)
    ALL.append(args)
    if "--upload" in args:  # capturer le média AVANT que la gateway ne l'efface
        p = Path(args[args.index("--upload") + 1])
        UPLOAD.update(path=p, data=p.read_bytes(), mode=p.stat().st_mode & 0o777)
    if REPLIES.get("boom"):
        raise GatewayError("échec simulé côté gws", code="exec")
    m = method_of(args)
    if m == ("drive", "files", "get"):
        if json.loads(flags(args)["--params"]).get("alt") == "media":
            return dict(REPLIES.get("media", {"raw": "contenu brut"}))
        return dict(META)
    if m == ("drive", "files", "export"):
        return dict(REPLIES.get("export", {"raw": "# Devis\n\nTexte."}))
    if m == ("gmail", "users", "messages", "attachments", "get"):
        return dict(REPLIES["attachment"])
    return {"id": "NEW1", "name": "x",
            "owners": [{"emailAddress": "alice@gmail.com"}], "ownedByMe": True}


api._run = fake_run
alias = "testprof"

# 1. drive_read : Google Doc → export markdown par défaut, métadonnées lues avant.
r = api.drive_read(alias, "DOC1")
assert r["content"] == "# Devis\n\nTexte." and r["truncated"] is False, r
assert r["export_mime_type"] == "text/markdown" and r["name"] == "Devis", r
exp = next(a for a in CALLS if method_of(a) == ("drive", "files", "export"))
assert json.loads(flags(exp)["--params"])["mimeType"] == "text/markdown", exp

# Sheet → CSV par défaut ; format explicite honoré.
META["mimeType"] = "application/vnd.google-apps.spreadsheet"
api.drive_read(alias, "SHEET1")
assert json.loads(flags(CALLS[-1])["--params"])["mimeType"] == "text/csv", CALLS[-1]
api.drive_read(alias, "SHEET1", format="text/plain")
assert json.loads(flags(CALLS[-1])["--params"])["mimeType"] == "text/plain", CALLS[-1]

# Fichier texte ordinaire → files get alt=media (pas d'export).
META["mimeType"] = "text/markdown"
r = api.drive_read(alias, "TXT1")
assert r["content"] == "contenu brut", r
last = CALLS[-1]
assert method_of(last) == ("drive", "files", "get"), last
assert json.loads(flags(last)["--params"])["alt"] == "media", last

# Binaire → refus explicite (drive_read est un tool TEXTE).
META["mimeType"] = "application/pdf"
try:
    api.drive_read(alias, "PDF1")
    raise SystemExit("un PDF aurait dû être refusé en lecture texte")
except GatewayError as e:
    assert e.code == "error", e.code

# Troncature : max_chars respecté ET signalé.
META["mimeType"] = "application/vnd.google-apps.document"
REPLIES["export"] = {"raw": "x" * 5000}
r = api.drive_read(alias, "DOC1", max_chars=1000)
assert len(r["content"]) == 1000 and r["truncated"] is True, (len(r["content"]), r)
REPLIES.pop("export")

# Format non textuel : refusé AVANT tout appel gws.
CALLS.clear()
try:
    api.drive_read(alias, "DOC1", format="application/pdf")
    raise SystemExit("format binaire aurait dû être refusé")
except GatewayError as e:
    assert e.code == "error" and not CALLS, (e.code, CALLS)

# 2. drive_copy : fileId dans --params, destination dans --json (zone vérifiable).
CALLS.clear()
r = api.drive_copy(alias, "SRC1", "FOLDER", name="Copie devis")
f = flags(CALLS[-1])
assert method_of(CALLS[-1]) == ("drive", "files", "copy"), CALLS[-1]
assert json.loads(f["--params"])["fileId"] == "SRC1", f
assert "owners(emailAddress)" in json.loads(f["--params"])["fields"], f
body = json.loads(f["--json"])
assert body["parents"] == ["FOLDER"] and body["name"] == "Copie devis", body
assert r["owner"] == "alice@gmail.com" and r["owned_by_me"] is True, r
api.drive_copy(alias, "SRC1", "FOLDER")
assert "name" not in json.loads(flags(CALLS[-1])["--json"]), CALLS[-1]

# 3. drive_upload : binaire local → dépôt broker (ADR-0003) → multipart, sans conversion.
src_dir = Path(os.environ["GWSA_ROOT"]).parent / "sources-0043"
src_dir.mkdir(exist_ok=True)
pdf = src_dir / "devis.pdf"
payload = b"%PDF-1.4 faux binaire \x00\x01\xff"
pdf.write_bytes(payload)
CALLS.clear()
r = api.drive_upload(alias, str(pdf), "FOLDER")
f = flags(CALLS[-1])
assert f["--upload-content-type"] == "application/pdf", f
assert UPLOAD["data"] == payload and UPLOAD["mode"] == 0o600, UPLOAD
assert UPLOAD["path"].parent == upload_spool(), UPLOAD["path"]
assert not UPLOAD["path"].exists(), "média non effacé après upload"
body = json.loads(f["--json"])
assert body["parents"] == ["FOLDER"] and body["name"] == "devis.pdf", body
assert "mimeType" not in body, body  # pas de conversion : le PDF reste un PDF
assert r["owner"] == "alice@gmail.com" and r["size"] == len(payload), r

# Nom et type explicites honorés.
api.drive_upload(alias, str(pdf), "FOLDER", name="Devis client.pdf",
                 mime_type="application/x-pdf")
f = flags(CALLS[-1])
assert json.loads(f["--json"])["name"] == "Devis client.pdf", f
assert f["--upload-content-type"] == "application/x-pdf", f

# Fichier introuvable → refus net, aucun appel.
CALLS.clear()
try:
    api.drive_upload(alias, str(src_dir / "absent.bin"), "FOLDER")
    raise SystemExit("fichier absent aurait dû être refusé")
except GatewayError as e:
    assert e.code == "error" and not CALLS, (e.code, CALLS)

# Jamais lire sous GWSA_ROOT (tokens/credentials)…
secret = Path(os.environ["GWSA_ROOT"]) / "testprof" / "credentials.enc"
secret.parent.mkdir(parents=True, exist_ok=True)
secret.write_bytes(b"secret")
try:
    api.drive_upload(alias, str(secret), "FOLDER")
    raise SystemExit("un fichier du répertoire des comptes aurait dû être refusé")
except GatewayError as e:
    assert e.code == "error" and not CALLS, (e.code, CALLS)
# …sauf .downloads : re-téléverser une pièce jointe reçue est légitime.
dl_file = download_dir() / "logo.png"
dl_file.write_bytes(b"\x89PNG faux")
api.drive_upload(alias, str(dl_file), "FOLDER")
assert UPLOAD["data"] == b"\x89PNG faux", UPLOAD
dl_file.unlink()

# Taille plafonnée.
old_max = api._MAX_UPLOAD_BYTES
api._MAX_UPLOAD_BYTES = 4
try:
    api.drive_upload(alias, str(pdf), "FOLDER")
    raise SystemExit("fichier trop gros aurait dû être refusé")
except GatewayError as e:
    assert e.code == "error", e.code
finally:
    api._MAX_UPLOAD_BYTES = old_max

# Échec côté gws : le média est nettoyé quand même (finally).
REPLIES["boom"] = True
try:
    api.drive_upload(alias, str(pdf), "FOLDER")
    raise SystemExit("l'échec gws aurait dû remonter")
except GatewayError as e:
    assert e.code == "exec", e.code
REPLIES.pop("boom")
assert not UPLOAD["path"].exists(), "média laissé derrière après un échec"

# 4. gmail_attachment_get : PJ décodée dans .downloads, jamais d'écrasement.
blob = b"\x00\x01logo-binaire\xff"
REPLIES["attachment"] = {
    "size": len(blob),
    "data": base64.urlsafe_b64encode(blob).decode().rstrip("="),
}
CALLS.clear()
r = api.gmail_attachment_get(alias, "MSG1", "ATT1", filename="logo.png")
p = Path(r["path"])
assert p.parent == download_dir() and p.name == "logo.png", r
assert p.read_bytes() == blob and r["size"] == len(blob), r
assert r["sha256"] == hashlib.sha256(blob).hexdigest(), r
assert (p.stat().st_mode & 0o777) == 0o600, oct(p.stat().st_mode)
att = next(a for a in CALLS
           if method_of(a) == ("gmail", "users", "messages", "attachments", "get"))
assert json.loads(flags(att)["--params"]) == \
    {"userId": "me", "messageId": "MSG1", "id": "ATT1"}, att

# Même nom une 2e fois → NOUVEAU fichier (unifié), pas d'écrasement.
r2 = api.gmail_attachment_get(alias, "MSG1", "ATT1", filename="logo.png")
assert r2["path"] != r["path"] and Path(r2["path"]).read_bytes() == blob, r2

# Nom hostile → réduit à un nom de base inoffensif, toujours dans .downloads.
r3 = api.gmail_attachment_get(alias, "MSG1", "ATT1",
                              filename="../../../../etc/passwd")
p3 = Path(r3["path"])
assert p3.parent == download_dir() and ".." not in p3.name and p3.name, r3
# Nom qui MASQUE un point de tête (« :.env », « \x00.bashrc ») → jamais un
# fichier caché : le filtre de caractères court AVANT le retrait des points.
for hostile in (":.env", "\x00.bashrc", ":.:", "../.ssh/authorized_keys"):
    rh = api.gmail_attachment_get(alias, "MSG1", "ATT1", filename=hostile)
    ph = Path(rh["path"])
    assert ph.parent == download_dir() and ph.name and not ph.name.startswith("."), (hostile, rh)
r4 = api.gmail_attachment_get(alias, "MSG1", "ATT1")  # sans nom → défaut sain
assert Path(r4["path"]).parent == download_dir(), r4

# Réponse sans data → erreur claire, rien d'écrit sur le disque.
before = set(download_dir().iterdir())
REPLIES["attachment"] = {"size": 0}
try:
    api.gmail_attachment_get(alias, "MSG1", "ATT1")
    raise SystemExit("réponse vide aurait dû échouer")
except GatewayError as e:
    assert e.code == "exec", e.code
assert set(download_dir().iterdir()) == before, "fichier créé malgré l'échec"

# 5. Aucun appel de la fiche n'oublie un paramètre de chemin (famille 0024).
for args in ALL:
    m = method_of(args)
    assert m in PATH_PARAMS, f"méthode {m} inconnue du test — compléter PATH_PARAMS"
    params = json.loads(flags(args).get("--params", "{}"))
    missing = PATH_PARAMS[m] - set(params)
    assert not missing, f"{m} : paramètre(s) de chemin manquant(s) {missing}"
print("ok")
PY
then
  PASS=$((PASS + 1)); printf '  \033[32m✓\033[0m drive_read / drive_copy / drive_upload / gmail_attachment_get (fiche 0043)\n'
else
  FAIL=$((FAIL + 1)); printf '  \033[31m✗\033[0m tools fiche 0043 (lire / copier / téléverser / pièces jointes)\n'
fi

# Les répertoires de dépôt (.uploads) et de téléchargement (.downloads) vivent
# dans GWSA_ROOT : ils ne doivent jamais passer pour des profils (les trois
# énumérateurs filtrent sur ALIAS_RE).
if python3 -c '
from gateway.api import profiles_list
from gateway.config import download_dir, upload_spool
upload_spool()
download_dir()
profs = profiles_list()["profiles"]
assert profs and not any(p["alias"].startswith(".") for p in profs), profs
' && ! "$GWSA" list 2>/dev/null | grep -qE 'uploads|downloads'; then
  PASS=$((PASS + 1)); printf '  \033[32m✓\033[0m .uploads / .downloads invisibles des listes de profils\n'
else
  FAIL=$((FAIL + 1)); printf '  \033[31m✗\033[0m .uploads / .downloads ne doivent pas apparaître comme des profils\n'
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

# Port éphémère : évite les collisions avec un broker local (4878/4879).
_s = socket.socket()
_s.bind(("127.0.0.1", 0))
os.environ["GWSA_BROKER_PORT"] = str(_s.getsockname()[1])
_s.close()
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
import os
import subprocess
from pathlib import Path

import gateway.broker_server as bs
from gateway.config import upload_spool
from gateway.vault import gws_config_dir

captured = {}


class Done:
    returncode, stdout, stderr = 0, '{"ok": true}', ""


def fake(cmd, **kw):
    captured.update(kw, cmd=cmd)
    return Done()


alias = "brokercwd"
prof = Path(os.environ["GWSA_ROOT"]) / alias
prof.mkdir(parents=True, exist_ok=True)
expected_cfg = str(gws_config_dir(alias))

bs._gws_bin = lambda: "/usr/bin/true"   # suite hermétique : gws peut être absent
real_run, subprocess.run = subprocess.run, fake
try:
    bs.run_gws_local(alias, ["drive", "files", "list"])
finally:
    subprocess.run = real_run

spool = upload_spool()
assert captured["cwd"] == str(spool), captured.get("cwd")
assert spool.is_dir() and spool.stat().st_mode & 0o777 == 0o700, oct(spool.stat().st_mode)
assert captured["env"]["GOOGLE_WORKSPACE_CLI_CONFIG_DIR"] == expected_cfg, captured["env"]
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

# --- Couloirs étanches (fiche 0025) -----------------------------------------
#
# Le serveur MCP parle au broker qui écoute sur GWSA_BROKER_PORT. Deux versions
# branchées sur le même port se partagent le premier broker démarré : le nom de
# l'entrée mentirait alors sur la version qui répond.

# le port part dans l'entrée, même quand c'est celui par défaut
f="$CD/port-default.json"
"$INSTALL" --config "$f" >/dev/null 2>&1
[[ "$(jget "$f" mcpServers.google-multi-account.env.GWSA_BROKER_PORT)" == "4878" ]] \
  && pass "couloir : le port du broker est écrit dans l'entrée (4878 par défaut)" \
  || fail "couloir : port par défaut absent de l'entrée"

# --port choisit le couloir
f="$CD/port-custom.json"
"$INSTALL" --config "$f" --name google-multi-account-v0 --port 4881 >/dev/null 2>&1
[[ "$(jget "$f" mcpServers.google-multi-account-v0.env.GWSA_BROKER_PORT)" == "4881" ]] \
  && pass "couloir : --port 4881 écrit dans l'entrée nommée" \
  || fail "couloir : --port ignoré"

# deux binaires différents sur le même port → refus (le cœur de la fiche)
f="$CD/port-collision.json"
cat > "$f" <<'JSON'
{ "mcpServers": {
    "google-multi-account": { "command": "/ailleurs/google-mcp",
                              "env": { "GWSA_BROKER_PORT": "4878" } } } }
JSON
out_c="$("$INSTALL" --config "$f" --name google-multi-account-dev 2>&1)"; rc_c=$?
[[ "$rc_c" -ne 0 && "$out_c" == *"port 4878"* && "$out_c" == *"--port"* \
   && -z "$(jget "$f" mcpServers.google-multi-account-dev.command)" ]] \
  && pass "couloir : deux binaires sur un même port → refus + rien écrit" \
  || fail "couloir : collision de port non détectée"

# … mais un port libre passe, et l'entrée existante n'est pas touchée
"$INSTALL" --config "$f" --name google-multi-account-dev --port 4880 >/dev/null 2>&1
[[ "$(jget "$f" mcpServers.google-multi-account-dev.env.GWSA_BROKER_PORT)" == "4880" \
   && "$(jget "$f" mcpServers.google-multi-account.command)" == "/ailleurs/google-mcp" ]] \
  && pass "couloir : port libre accepté, entrée voisine intacte" \
  || fail "couloir : port libre refusé ou voisin modifié"

# un serveur MCP tiers n'est jamais un concurrent de port (il n'a pas de broker)
f="$CD/port-tiers.json"
cat > "$f" <<'JSON'
{ "mcpServers": { "filesystem": { "command": "/usr/local/bin/mcp-filesystem" } } }
JSON
"$INSTALL" --config "$f" >/dev/null 2>&1
[[ -n "$(jget "$f" mcpServers.google-multi-account.command)" ]] \
  && pass "couloir : serveur MCP tiers non compté comme concurrent de port" \
  || fail "couloir : serveur tiers pris pour un concurrent"

# port hors bornes → refus argumenté
for bad in 80 abc 99999; do
  "$INSTALL" --config "$CD/bad-port.json" --port "$bad" >/dev/null 2>&1 \
    && { fail "couloir : --port $bad aurait dû être refusé"; break; }
done
[[ ! -f "$CD/bad-port.json" ]] \
  && pass "couloir : --port invalide (80, abc, 99999) refusé, rien écrit" \
  || fail "couloir : --port invalide a quand même écrit"

# la version branchée est affichée (dev ici : pas de VERSION dans un clone)
# Pas de pipe direct : grep -q + pipefail = SIGPIPE sur le script amont.
out_v="$("$INSTALL" --config "$CD/version-shown.json" --print 2>&1)"
[[ "$out_v" == *"version  : dev"* ]] \
  && pass "couloir : le script annonce la version qu'il branche" \
  || fail "couloir : version non affichée"

# --- Branchement Claude Code — install-claude-code.sh (fiche 0040) -----------
#
# Hermétique : Claude Code se branche via le CLI `claude` (pas un fichier de
# config qu'on éditerait). On surcharge le CLI par un MOCK via CLAUDE_BIN — le
# vrai ~/.claude.json n'est JAMAIS touché (le script ne fait que déléguer).

section "Branchement Claude Code — install-claude-code.sh (délègue au CLI, hermétique)"
INSTALL_CC="scripts/install-claude-code.sh"
CCDIR="$TMP/cc"; mkdir -p "$CCDIR/home"
CCMOCK="$CCDIR/claude"; export CCREG="$CCDIR/registry"; export CCENV="$CCDIR/registry.env"; export CCLOG="$CCDIR/calls.log"
# Le mock imite `claude mcp get` de façon RÉALISTE : sa sortie cite le binaire ET
# les variables d'environnement (comme le vrai CLI), pour que le contrôle
# d'idempotence puisse comparer le port de broker et le client, pas juste le chemin.
cat > "$CCMOCK" <<'MOCK'
#!/usr/bin/env bash
echo "$*" >> "$CCLOG"
[[ "$1" == mcp ]] || exit 0
case "$2" in
  get)    [[ -s "$CCREG" ]] || exit 1
          echo "  Scope: User"; echo "  Command: $(cat "$CCREG")"; echo "  Environment:"
          [[ -s "$CCENV" ]] && cat "$CCENV"
          exit 0 ;;
  add)    printf '%s\n' "${@: -1}" > "$CCREG"
          : > "$CCENV"; prev=""
          for a in "$@"; do [[ "$prev" == "--env" ]] && echo "    $a" >> "$CCENV"; prev="$a"; done
          exit 0 ;;
  remove) rm -f "$CCREG" "$CCENV"; exit 0 ;;
esac
MOCK
chmod +x "$CCMOCK"
MCP_ABS="$(pwd)/bin/google-mcp"
ccrun() { CLAUDE_BIN="$CCMOCK" HOME="$CCDIR/home" "$INSTALL_CC" "$@"; }

# 1. première fois → mcp add, scope user, bon binaire
: > "$CCLOG"; rm -f "$CCREG"
ccrun >/dev/null 2>&1
[[ "$(cat "$CCREG" 2>/dev/null)" == "$MCP_ABS" ]] \
  && grep -q "mcp add google-multi-account --scope user" "$CCLOG" \
  && pass "claude-code : première fois → mcp add scope user sur le bon binaire" \
  || fail "claude-code : enregistrement initial"

# les --env attendus sont transmis
grep -q "GWSA_CLIENT=claude-code" "$CCLOG" && grep -q "GWSA_BROKER_PORT=4878" "$CCLOG" \
  && pass "claude-code : --env GWSA_CLIENT=claude-code + port 4878 transmis" \
  || fail "claude-code : env manquants"

# 2. relance → idempotent, aucun nouvel add
: > "$CCLOG"
out_cc="$(ccrun 2>&1)"
[[ "$(grep -c "mcp add" "$CCLOG")" == "0" && "$out_cc" == *"rien à faire"* ]] \
  && pass "claude-code : relance idempotente (aucun mcp add)" \
  || fail "claude-code : devrait être idempotent"

# 3. pointe ailleurs → remove + re-add sur current
printf '/ancienne/cible/google-mcp\n' > "$CCREG"; : > "$CCLOG"
ccrun >/dev/null 2>&1
[[ "$(grep -c "mcp remove" "$CCLOG")" -ge 1 && "$(cat "$CCREG")" == "$MCP_ABS" ]] \
  && pass "claude-code : entrée périmée → remove + re-add sur current" \
  || fail "claude-code : re-pointage"

# 3b. bon binaire mais MAUVAIS port de broker → re-branchement (revue Codex #43 :
#     ne pas conclure « à jour » sur la seule sous-chaîne du binaire).
printf '%s\n' "$MCP_ABS" > "$CCREG"
printf '    GWSA_CLIENT=claude-code\n    GWSA_BROKER_PORT=9999\n' > "$CCENV"; : > "$CCLOG"
ccrun >/dev/null 2>&1
[[ "$(grep -c "mcp remove" "$CCLOG")" -ge 1 && "$(grep -c "mcp add" "$CCLOG")" -ge 1 ]] \
  && grep -q "GWSA_BROKER_PORT=4878" "$CCLOG" \
  && pass "claude-code : bon binaire mais mauvais port → re-branché sur le bon couloir" \
  || fail "claude-code : devrait re-brancher quand le port de broker diffère"

# 3c. bon binaire + bon port, mais SANS GWSA_CLIENT → re-branchement (attribution).
printf '%s\n' "$MCP_ABS" > "$CCREG"
printf '    GWSA_BROKER_PORT=4878\n' > "$CCENV"; : > "$CCLOG"
ccrun >/dev/null 2>&1
[[ "$(grep -c "mcp add" "$CCLOG")" -ge 1 ]] \
  && pass "claude-code : entrée sans GWSA_CLIENT → re-branchée (attribution du journal)" \
  || fail "claude-code : devrait re-brancher quand GWSA_CLIENT manque"

# 4. --print : montre la commande, n'invoque JAMAIS le CLI
: > "$CCLOG"
out_cc="$(ccrun --print 2>&1)"
[[ "$out_cc" == *"mcp add google-multi-account --scope user"* && ! -s "$CCLOG" ]] \
  && pass "claude-code : --print affiche la commande sans invoquer le CLI" \
  || fail "claude-code : --print a invoqué le CLI ou n'affiche rien"

# 5. claude absent → exit 0 + avertissement (déploiement non cassé)
out_cc="$(CLAUDE_BIN="$CCDIR/nexistepas" HOME="$CCDIR/home" "$INSTALL_CC" 2>&1)"; rc=$?
[[ "$rc" -eq 0 && "$out_cc" == *"introuvable"* ]] \
  && pass "claude-code : CLI absent → exit 0 + avertissement (déploiement non cassé)" \
  || fail "claude-code : devrait dégrader gracieusement"

# invariant : délégation PURE au CLI — le script ne redirige aucune écriture vers
# un fichier de config (pas de « > …claude.json », pas de tempfile/os.replace).
# Le vrai ~/.claude.json est déjà protégé par le mock ci-dessus ; ici on vérifie
# qu'aucun chemin de code n'écrit un fichier de config en dur.
if ! grep -E "(>|>>|tee|os\.replace|mkstemp)[^\"']*claude" "$INSTALL_CC" >/dev/null 2>&1; then
  pass "claude-code : délégation pure au CLI (aucune écriture directe de config)"
else
  fail "claude-code : le script écrit un fichier de config en dur (devrait déléguer)"
fi
unset CCREG CCLOG

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

# Port dédié : sans ça, un vrai broker écoutant sur 4878 rendrait le test
# « status sans pidfile » instable selon la machine.
export GWSA_BROKER_PORT=4977
# Le pidfile est nommé d'après le port (fiche 0025) : un couloir ne pilote que
# son propre broker.
BPID="$GWSA_ROOT/.broker-4977.pid"
rm -f "$BPID"

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
reserved broker

# Deux couloirs, deux brokers : arrêter l'un ne doit pas toucher l'autre.
# Sans le port dans le nom du pidfile, le second broker écrasait le fichier du
# premier et « gwsa broker stop » visait le mauvais process (fiche 0025).
VOISIN="$GWSA_ROOT/.broker-4988.pid"
echo "999999" > "$BPID"        # couloir courant (4977), pidfile obsolète
echo "424242" > "$VOISIN"      # couloir voisin (4988), intact attendu
"$GWSA" broker stop >/dev/null 2>&1
[[ ! -f "$BPID" && "$(cat "$VOISIN" 2>/dev/null)" == "424242" ]] \
  && pass "deux couloirs : stop n'efface que le pidfile de SON port" \
  || fail "deux couloirs : stop a touché le pidfile du voisin"

# Et le pidfile lu par gwsa est bien celui que le broker Python écrirait.
if python3 -c '
import os, sys
os.environ["GWSA_BROKER_PORT"] = "4988"
from gateway.broker_server import pid_path, token_path
assert pid_path().name == ".broker-4988.pid", pid_path()
assert token_path().name == ".broker-4988-token", token_path()
os.environ["GWSA_BROKER_PORT"] = "4977"
assert pid_path().name == ".broker-4977.pid", pid_path()
assert pid_path(4988).name == ".broker-4988.pid", "port explicite prioritaire"
'; then
  pass "broker Python : jeton et pidfile nommés d'après le port"
else
  fail "broker Python : jeton/pidfile pas indexés par port"
fi
rm -f "$VOISIN"

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

# --- Publication et mise à jour (fiche 0029) --------------------------------
#
# Hermétique : dépôt git jouet sous $TMP, aucun remote, aucun réseau, suite de
# tests remplacée par un stub. Le vrai dépôt n'est jamais tagué ni poussé.

section "release.sh — semver déduit des commits, CHANGELOG, tag annoté"

REL="$TMP/relrepo"
RELDEP="$TMP/reldeploy"
RELCONF="$TMP/reldesktop.json"
mkdir -p "$REL/scripts" "$REL/bin"
cp scripts/release.sh scripts/update.sh scripts/deploy-local.sh \
   scripts/install-claude-desktop.sh "$REL/scripts/"
printf '#!/bin/sh\nexit 0\n' > "$REL/scripts/test.sh"; chmod +x "$REL/scripts/test.sh"
printf '#!/bin/sh\necho faux-mcp\n' > "$REL/bin/google-mcp"; chmod +x "$REL/bin/google-mcp"
cp bin/gwsa "$REL/bin/gwsa"   # embarqué dans les copies déployées (cf. link_cli)
echo "coeur" > "$REL/app.txt"
git -C "$REL" init -q >/dev/null 2>&1
git -C "$REL" checkout -qb main >/dev/null 2>&1
git -C "$REL" config user.email "test@example.invalid"
git -C "$REL" config user.name "test"
git -C "$REL" add -A >/dev/null 2>&1
git -C "$REL" commit -qm "feat(x): premiere fonctionnalite" >/dev/null 2>&1
UPDATE="$REL/scripts/update.sh"
# Le lien « PATH » manipulé par les tests vit sous $TMP — jamais le vrai
# /opt/homebrew/bin/gwsa. relenv le désigne systématiquement : sans ça, un
# update.sh lancé par un test retomberait sur « command -v gwsa », donc sur le
# lien réel de la machine.
FAKEBIN="$TMP/fakebin"; mkdir -p "$FAKEBIN"
LINK="$FAKEBIN/gwsa"
relenv() {
  GWSA_DEPLOY_ROOT="$RELDEP" GWSA_DESKTOP_CONFIG="$RELCONF" \
  GWSA_CLI_LINK="${GWSA_CLI_LINK:-$LINK}" "$@"
}
release() { (cd "$REL" && GWSA_DEPLOY_ROOT="$RELDEP" ./scripts/release.sh "$@"); }
ntags() { git -C "$REL" tag --list | grep -c . | tr -d ' '; }

# dry-run : annonce la version, n'écrit ni tag ni CHANGELOG
out_r="$(release --print 2>&1)"; rc=$?
[[ "$rc" -eq 0 && "$out_r" == *"v0.1.0"* && "$(ntags)" == "0" && ! -f "$REL/CHANGELOG.md" ]] \
  && pass "release --print : annonce la version, ne tague rien, n'écrit rien" \
  || fail "release --print : dry-run non étanche"

# un feat sans tag existant → première minor
release >/dev/null 2>&1; rc=$?
[[ "$rc" -eq 0 && "$(git -C "$REL" tag --list)" == "v0.1.0" ]] \
  && pass "release : feat → v0.1.0, tag posé" \
  || fail "release : feat → v0.1.0"

grep -q "## v0.1.0" "$REL/CHANGELOG.md" 2>/dev/null \
  && grep -q "premiere fonctionnalite" "$REL/CHANGELOG.md" \
  && pass "release : CHANGELOG.md créé, commits groupés sous la version" \
  || fail "release : CHANGELOG.md incomplet"

# tag annoté (il porte les notes), pas un tag léger
[[ "$(git -C "$REL" cat-file -t v0.1.0 2>/dev/null)" == "tag" ]] \
  && pass "release : tag annoté (porte les notes de version)" \
  || fail "release : tag léger au lieu d'annoté"

# rien de nouveau depuis le tag → refus
release >/dev/null 2>&1; rc=$?
[[ "$rc" -ne 0 ]] \
  && pass "release : aucun commit depuis le dernier tag → refus" \
  || fail "release : devrait refuser sans commit nouveau"

# fix → patch. Contenu modifié pour de vrai : sans divergence entre v0.1.0 et
# la suite, le test de « --tag » plus bas ne pourrait pas distinguer la version
# demandée de celle de HEAD.
echo "coeur v2" > "$REL/app.txt"
git -C "$REL" commit -qam "fix(y): repare un souci" >/dev/null 2>&1
out_r="$(release --print 2>&1)"
[[ "$out_r" == *"v0.1.1"* && "$out_r" == *"patch"* ]] \
  && pass "release : fix → patch (v0.1.1)" \
  || fail "release : fix devrait donner un patch"

# breaking → major
git -C "$REL" commit -q --allow-empty -m "feat(z)!: signature changee" >/dev/null 2>&1
out_r="$(release --print 2>&1)"
[[ "$out_r" == *"v1.0.0"* && "$out_r" == *"major"* ]] \
  && pass "release : « type!: » (breaking) → major (v1.0.0)" \
  || fail "release : breaking devrait donner un major"

# niveau imposé en argument
out_r="$(release minor --print 2>&1)"
[[ "$out_r" == *"v0.2.0"* ]] \
  && pass "release : niveau imposé en argument (minor → v0.2.0)" \
  || fail "release : argument de niveau ignoré"

# arbre sale → refus
echo "brouillon" > "$REL/sale.txt"
release >/dev/null 2>&1; rc=$?
[[ "$rc" -ne 0 && "$(ntags)" == "1" ]] \
  && pass "release : arbre sale → refus, aucun tag posé" \
  || fail "release : arbre sale devrait refuser"
rm -f "$REL/sale.txt"

# hors branche principale → refus
git -C "$REL" checkout -qb chantier >/dev/null 2>&1
release >/dev/null 2>&1; rc=$?
[[ "$rc" -ne 0 ]] \
  && pass "release : hors branche principale → refus" \
  || fail "release : devrait refuser hors main"
git -C "$REL" checkout -q main >/dev/null 2>&1

# tests rouges → refus, rien n'est tagué
# Le stub rouge est COMMITÉ : sinon l'arbre est sale et c'est cette garde-là
# qui refuse — le test ne prouverait rien sur les tests rouges.
printf '#!/bin/sh\nexit 1\n' > "$REL/scripts/test.sh"
git -C "$REL" commit -qam "chore(test): suite rouge" >/dev/null 2>&1
release >/dev/null 2>&1; rc=$?
[[ "$rc" -ne 0 && "$(ntags)" == "1" ]] \
  && pass "release : tests rouges → refus, aucun tag posé (arbre propre)" \
  || fail "release : tests rouges devraient bloquer la publication"
printf '#!/bin/sh\nexit 0\n' > "$REL/scripts/test.sh"
git -C "$REL" commit -qam "chore(test): suite verte" >/dev/null 2>&1

# seconde version, pour avoir de quoi tester update
release >/dev/null 2>&1
[[ -n "$(git -C "$REL" tag --list v1.0.0)" ]] \
  && pass "release : seconde publication (v1.0.0) enchaînée sans friction" \
  || fail "release : seconde publication en échec"

section "deploy-local.sh --tag — déployer une version autre que celle de HEAD"

# HEAD porte « coeur v2 » ; la copie de v0.1.0 doit porter « coeur ».
relenv "$REL/scripts/deploy-local.sh" --tag v0.1.0 >/dev/null 2>&1; rc=$?
[[ "$rc" -eq 0 && "$(cat "$RELDEP/v0.1.0/VERSION" 2>/dev/null)" == "v0.1.0" \
   && "$(cat "$RELDEP/v0.1.0/app.txt" 2>/dev/null)" == "coeur" ]] \
  && pass "--tag : déploie le CONTENU de la version demandée, pas celui de HEAD" \
  || fail "--tag : contenu déployé = celui de HEAD"

[[ "$(cat "$RELDEP/v0.1.0/.source" 2>/dev/null)" == "$REL" ]] \
  && pass "--tag : clone source noté dans .source (update depuis la copie)" \
  || fail "--tag : .source manquant dans la copie déployée"

relenv "$REL/scripts/deploy-local.sh" --tag v9.9.9 >/dev/null 2>&1; rc=$?
[[ "$rc" -ne 0 ]] \
  && pass "--tag : tag inconnu → refus" \
  || fail "--tag : tag inconnu devrait refuser"

# un arbre sale ne bloque PAS --tag : on archive une référence, pas le chantier
echo "brouillon" > "$REL/sale.txt"
relenv "$REL/scripts/deploy-local.sh" --tag v1.0.0 >/dev/null 2>&1; rc=$?
[[ "$rc" -eq 0 && -d "$RELDEP/v1.0.0" && ! -f "$RELDEP/v1.0.0/sale.txt" ]] \
  && pass "--tag : arbre sale toléré, mais jamais embarqué dans la copie" \
  || fail "--tag : arbre sale mal géré"
rm -f "$REL/sale.txt"

section "update.sh — mettre à jour le poste en une commande"

rm -rf "$RELDEP" "$RELCONF"
out_u="$(relenv "$UPDATE" --check 2>&1)"; rc=$?
[[ "$rc" -eq 0 && "$out_u" == *"aucune"* && "$out_u" == *"v1.0.0"* && ! -d "$RELDEP" ]] \
  && pass "update --check : dit installé/disponible, n'écrit rien" \
  || fail "update --check : écrit ou n'informe pas"

relenv "$UPDATE" >/dev/null 2>&1; rc=$?
[[ "$rc" -eq 0 && "$(basename "$(readlink "$RELDEP/current")")" == "v1.0.0" ]] \
  && pass "update : installe la dernière version et bascule current" \
  || fail "update : n'installe pas la dernière version"

[[ "$(jget "$RELCONF" mcpServers.google-multi-account.command)" == "$RELDEP/current/bin/google-mcp" ]] \
  && pass "update : branche le client sur current (jamais sur un dossier de version)" \
  || fail "update : entrée client absente ou figée sur une version"

out_u="$(relenv "$UPDATE" 2>&1)"; rc=$?
[[ "$rc" -eq 0 && "$out_u" == *"déjà à jour"* ]] \
  && pass "update : relancé sans rien à faire → « déjà à jour » (idempotent)" \
  || fail "update : devrait être idempotent"

relenv "$UPDATE" --to v0.1.0 >/dev/null 2>&1; rc=$?
[[ "$rc" -eq 0 && "$(basename "$(readlink "$RELDEP/current")")" == "v0.1.0" ]] \
  && pass "update --to : installe une version précise (retour arrière)" \
  || fail "update --to : version précise non installée"

relenv "$UPDATE" --to v9.9.9 >/dev/null 2>&1; rc=$?
[[ "$rc" -ne 0 && "$(basename "$(readlink "$RELDEP/current")")" == "v0.1.0" ]] \
  && pass "update --to : version inconnue → refus, current inchangé" \
  || fail "update --to : version inconnue mal gérée"

# depuis la COPIE INSTALLÉE (sans .git) : le relais par .source doit marcher
out_u="$(relenv "$RELDEP/current/scripts/update.sh" --check 2>&1)"; rc=$?
[[ "$rc" -eq 0 && "$out_u" == *"clone source"* && "$out_u" == *"v1.0.0"* ]] \
  && pass "update : lancé depuis la copie installée, retrouve le clone via .source" \
  || fail "update : ne retrouve pas le clone depuis la copie installée"

section "gwsa update / release — un seul poste de commande (fiche 0030)"

# De quoi publier : sans commit nouveau, release refuse (et le test ne dirait
# rien de la délégation).
git -C "$REL" commit -q --allow-empty -m "feat(cli): un verbe de plus" >/dev/null 2>&1
GW="$REL/bin/gwsa"
gwenv() { GWSA_DEPLOY_ROOT="$RELDEP" GWSA_DESKTOP_CONFIG="$RELCONF" "$@"; }

"$GW" help 2>&1 | grep -q "gwsa update" \
  && "$GW" help 2>&1 | grep -q "gwsa release" \
  && pass "gwsa help : les deux verbes sont listés" \
  || fail "gwsa help : verbes absents"

reserved update
reserved release

# délégation : gwsa update passe la main au script, arguments compris
out_g="$(gwenv "$GW" update --check 2>&1)"; rc=$?
[[ "$rc" -eq 0 && "$out_g" == *"disponible"* ]] \
  && pass "gwsa update : délègue au script (--check transmis)" \
  || fail "gwsa update : délégation cassée"

out_g="$(gwenv "$GW" release --print 2>&1)"; rc=$?
[[ "$rc" -eq 0 && "$out_g" == *"publierait"* ]] \
  && pass "gwsa release : délègue au script (--print transmis)" \
  || fail "gwsa release : délégation cassée"

# depuis la copie installée : release retrouve le clone via .source
out_g="$(gwenv "$RELDEP/current/bin/gwsa" release --print 2>&1)"; rc=$?
[[ "$rc" -eq 0 && "$out_g" == *"publierait"* ]] \
  && pass "gwsa release : depuis la copie installée, relais par .source" \
  || fail "gwsa release : relais .source cassé"

# … et sans .source, refus explicite plutôt qu'un comportement au hasard
NOSRC="$TMP/nosource"
mkdir -p "$NOSRC/bin" "$NOSRC/scripts"
cp bin/gwsa "$NOSRC/bin/"
out_g="$("$NOSRC/bin/gwsa" release --print 2>&1)"; rc=$?
[[ "$rc" -ne 0 && "$out_g" == *".source"* ]] \
  && pass "gwsa release : sans .git ni .source → refus qui dit quoi faire" \
  || fail "gwsa release : devrait refuser hors dépôt source"

section "update.sh — le lien PATH suit la version installée (fiche 0030)"

# lien vers le clone (l'état posé par le quickstart) → doit passer sur current
ln -sfn "$REL/bin/gwsa" "$LINK"
GWSA_CLI_LINK="$LINK" relenv "$UPDATE" --force >/dev/null 2>&1
[[ "$(readlink "$LINK")" == "$RELDEP/current/bin/gwsa" ]] \
  && pass "lien PATH : le lien vers le clone passe sur la copie installée" \
  || fail "lien PATH : pas rebranché sur current"

# déjà correct → idempotent
out_l="$(GWSA_CLI_LINK="$LINK" relenv "$UPDATE" --force 2>&1)"
[[ "$out_l" == *"déjà sur la copie installée"* ]] \
  && pass "lien PATH : déjà correct → rien à faire (idempotent)" \
  || fail "lien PATH : devrait se dire déjà correct"

# cible étrangère au projet → on ne touche pas
ln -sfn "/usr/bin/true" "$LINK"
out_l="$(GWSA_CLI_LINK="$LINK" relenv "$UPDATE" --force 2>&1)"
[[ "$(readlink "$LINK")" == "/usr/bin/true" && "$out_l" == *"hors projet"* ]] \
  && pass "lien PATH : cible étrangère laissée intacte (avertissement)" \
  || fail "lien PATH : a écrasé une cible étrangère"

# bac à sable sans lien désigné → on ne touche à rien (le PATH réel est sacré)
out_l="$(GWSA_DEPLOY_ROOT="$RELDEP" GWSA_DESKTOP_CONFIG="$RELCONF" "$UPDATE" --force 2>&1)"
[[ "$out_l" == *"sans GWSA_CLI_LINK"* ]] \
  && pass "lien PATH : dépôt surchargé sans GWSA_CLI_LINK → aucun lien touché" \
  || fail "lien PATH : un test pourrait atteindre le gwsa réel du PATH"

# fichier réel (pas un lien) → on ne touche pas non plus
rm -f "$LINK"
printf '#!/bin/sh\necho vrai fichier\n' > "$LINK"; chmod +x "$LINK"
out_l="$(GWSA_CLI_LINK="$LINK" relenv "$UPDATE" --force 2>&1)"
[[ ! -L "$LINK" && "$(cat "$LINK")" == *"vrai fichier"* && "$out_l" == *"pas un lien"* ]] \
  && pass "lien PATH : fichier réel jamais remplacé par un lien" \
  || fail "lien PATH : a écrasé un fichier réel"

section "sessions + vault (fiche 0040)"

SESS_ROOT="$TMP/gwsa-sessions"
mkdir -p "$SESS_ROOT/alpha"
echo '{"drive":{"read":true,"create":true,"zonesOnly":true,"writeFolders":[]}}' > "$SESS_ROOT/alpha/policy.json"
touch "$SESS_ROOT/alpha/.locked"
PY="/usr/bin/python3"
[[ -x "$PY" ]] || PY="$(command -v python3)"

export GWSA_ROOT="$SESS_ROOT" PYTHONPATH="$(pwd)"
out_s="$("$PY" -c "
from gateway.sessions import create_session, session_unlock, session_grant_drive, active_drive_zones, create_child_session, revoke_descendants
s1 = create_session(client='test')
s2 = create_session(client='test')
session_unlock(s1.session_id, 'alpha', 30)
session_grant_drive(s1.session_id, 'alpha', 'folderAAA', 'ZoneA', 2)
z1 = active_drive_zones(s1.session_id, 'alpha')
z2 = active_drive_zones(s2.session_id, 'alpha')
child = create_child_session(s1.session_id)
zc = active_drive_zones(child.session_id, 'alpha')
print('z1', len(z1), 'z2', len(z2), 'zc', len(zc))
")"
[[ "$out_s" == *"z1 1"* && "$out_s" == *"z2 0"* && "$out_s" == *"zc 1"* ]] \
  && pass "sessions : grants isolés par session, héritage enfant" \
  || fail "sessions : isolation ou héritage incorrect ($out_s)"

n_rev="$("$PY" -c "
from gateway.sessions import create_session, create_child_session, revoke_descendants
p = create_session(client='t')
c = create_child_session(p.session_id)
print(revoke_descendants(p.session_id))
")"
[[ "$n_rev" == "1" ]] \
  && pass "sessions : revoke_descendants purge les enfants" \
  || fail "sessions : revoke_descendants ($n_rev)"

GRANT_FID="GRANTFOLDER1234567890"
rm -f "$SESS_ROOT/alpha/session-grants.json"
out_g="$(GWSA_ROOT="$SESS_ROOT" "$GWSA" grant alpha "$GRANT_FID" 8 2>&1)"
[[ "$out_g" == *"legacy"* && -f "$SESS_ROOT/alpha/session-grants.json" ]] \
  && pass "grant global : avertissement dépréciation + session-grants.json legacy" \
  || fail "grant global : dépréciation ou legacy ($out_g)"

sid="$("$PY" -c 'from gateway.sessions import create_session; print(create_session(client="t").session_id)')"
rm -f "$SESS_ROOT/alpha/session-grants.json"
GWSA_ROOT="$SESS_ROOT" GWSA_SESSION_ID="$sid" "$GWSA" grant alpha "$GRANT_FID" 8 >/dev/null 2>&1
z_sess="$("$PY" -c "from gateway.sessions import active_drive_zones; print(len(active_drive_zones('$sid', 'alpha')))")"
[[ ! -f "$SESS_ROOT/alpha/session-grants.json" && "$z_sess" == "1" ]] \
  && pass "grant + GWSA_SESSION_ID : registre session seulement" \
  || fail "grant + GWSA_SESSION_ID : registre session ($z_sess)"

rm -f "$SESS_ROOT/alpha/.unlock-until"
out_u="$(GWSA_ROOT="$SESS_ROOT" "$GWSA" unlock alpha 30 2>&1)"
[[ "$out_u" == *"legacy"* && -f "$SESS_ROOT/alpha/.unlock-until" ]] \
  && pass "unlock global : avertissement dépréciation + .unlock-until legacy" \
  || fail "unlock global : dépréciation ou legacy ($out_u)"

sid_u="$("$PY" -c 'from gateway.sessions import create_session; print(create_session(client="t").session_id)')"
rm -f "$SESS_ROOT/alpha/.unlock-until"
GWSA_ROOT="$SESS_ROOT" GWSA_SESSION_ID="$sid_u" "$GWSA" unlock alpha 30 >/dev/null 2>&1
u_ok="$("$PY" -c "from gateway.sessions import is_session_unlocked; print(is_session_unlocked('$sid_u', 'alpha'))")"
[[ ! -f "$SESS_ROOT/alpha/.unlock-until" && "$u_ok" == "True" ]] \
  && pass "unlock + GWSA_SESSION_ID : registre session seulement" \
  || fail "unlock + GWSA_SESSION_ID : registre session (unlock=$u_ok)"

sid_u2="$("$PY" -c 'from gateway.sessions import create_session; print(create_session(client="t").session_id)')"
u2_ok="$("$PY" -c "from gateway.sessions import is_session_unlocked; print(is_session_unlocked('$sid_u2', 'alpha'))")"
[[ "$u2_ok" == "False" ]] \
  && pass "unlock session : isolation entre sessions parallèles" \
  || fail "unlock session : autre session hérite ($u2_ok)"

# list_sessions + admin API sessions (fiche 0040 phase C)
sid_list="$("$PY" -c "
from gateway.sessions import create_session, session_unlock, list_sessions
s = create_session(client='admin-test')
session_unlock(s.session_id, 'alpha', 20)
n = len(list_sessions())
print(s.session_id, n)
")"
sid_list_id="${sid_list%% *}"
n_list="${sid_list##* }"
[[ -n "$sid_list_id" && "$n_list" -ge 1 ]] \
  && pass "sessions : list_sessions retourne au moins une session" \
  || fail "sessions : list_sessions ($sid_list)"

out_slist="$(GWSA_ROOT="$SESS_ROOT" "$GWSA" session list 2>/dev/null)"
[[ "$out_slist" == *"$sid_list_id"* && "$out_slist" == *'"sessions"'* ]] \
  && pass "gwsa session list : JSON avec session_id" \
  || fail "gwsa session list ($out_slist)"

ADMIN_PORT=$((49000 + RANDOM % 1000))
GWSA_ROOT="$SESS_ROOT" GWSA_ADMIN_PORT="$ADMIN_PORT" node "$(pwd)/admin/server.js" >/dev/null 2>&1 &
ADMIN_PID=$!
admin_ready=0
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if curl -sf -H 'X-GWSA-Admin: 1' "http://127.0.0.1:$ADMIN_PORT/api/sessions" >/dev/null 2>&1; then
    admin_ready=1; break
  fi
  sleep 0.2
done
if [[ "$admin_ready" -eq 1 ]]; then
  admin_get="$(curl -sf -H 'X-GWSA-Admin: 1' "http://127.0.0.1:$ADMIN_PORT/api/sessions")"
  [[ "$admin_get" == *"$sid_list_id"* ]] \
    && pass "admin GET /api/sessions : liste la session" \
    || fail "admin GET /api/sessions ($admin_get)"

  sid_admin="$("$PY" -c 'from gateway.sessions import create_session; print(create_session(client="admin-api").session_id)')"
  admin_un="$(curl -sf -H 'X-GWSA-Admin: 1' -H 'Content-Type: application/json' \
    -X POST -d '{"alias":"alpha","minutes":25}' \
    "http://127.0.0.1:$ADMIN_PORT/api/sessions/$sid_admin/unlock")"
  u_admin="$("$PY" -c "from gateway.sessions import is_session_unlocked; print(is_session_unlocked('$sid_admin', 'alpha'))")"
  [[ "$admin_un" == *'"ok":true'* && "$u_admin" == "True" ]] \
    && pass "admin POST unlock session via gwsa" \
    || fail "admin POST unlock ($admin_un unlock=$u_admin)"

  admin_close="$(curl -sf -H 'X-GWSA-Admin: 1' -H 'Content-Type: application/json' \
    -X POST -d '{}' "http://127.0.0.1:$ADMIN_PORT/api/sessions/$sid_admin/close")"
  gone="$("$PY" -c "from gateway.sessions import get_session; print(get_session('$sid_admin'))")"
  [[ "$admin_close" == *'"ok":true'* && "$gone" == "None" ]] \
    && pass "admin POST close session" \
    || fail "admin POST close ($admin_close gone=$gone)"

  # anti-CSRF : sans en-tête → 403
  code_csrf="$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$ADMIN_PORT/api/sessions")"
  [[ "$code_csrf" == "403" ]] \
    && pass "admin /api/sessions : refuse sans X-GWSA-Admin" \
    || fail "admin CSRF sessions (code=$code_csrf)"
else
  fail "admin server sessions : démarrage timeout port $ADMIN_PORT"
fi
kill "$ADMIN_PID" 2>/dev/null || true
wait "$ADMIN_PID" 2>/dev/null || true

out_close="$("$PY" -c "
from gateway.sessions import create_session, create_child_session, close_session, get_session, sessions_dir
p = create_session(client='t')
c = create_child_session(p.session_id)
pid, cid = p.session_id, c.session_id
close_session(pid)
print('parent', get_session(pid), 'child', get_session(cid))
")"
[[ "$out_close" == *"parent None"* && "$out_close" == *"child None"* ]] \
  && pass "close_session : purge parent + descendants" \
  || fail "close_session : purge incomplète ($out_close)"

PROJ_ROOT="$TMP/gwsa-proj-inside"
rm -rf "$PROJ_ROOT"
git_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
rm -rf "$git_root/.gwsa"
GWSA_ROOT="$SESS_ROOT" "$GWSA" project init >/dev/null 2>&1
GWSA_ROOT="$SESS_ROOT" "$GWSA" project sign >/dev/null 2>&1
out_p="$(GWSA_ROOT="$SESS_ROOT" "$GWSA" project show 2>/dev/null)"
[[ -n "$git_root" && -f "$git_root/.gwsa/manifest.json" && -f "$git_root/.gwsa/manifest.sig" \
   && "$out_p" == *'"manifest_valid": true'* ]] \
  && pass "project : init + sign local + show" \
  || fail "project : init/sign/show (root=$git_root out=$out_p)"
rm -rf "$git_root/.gwsa" 2>/dev/null || true

cap_out="$("$PY" -c "
import os
from gateway.project import grant_allowed_by_manifest, ProjectContext
from gateway.sessions import create_session, session_grant_drive, active_drive_zones
from gateway.errors import GatewayError
from unittest.mock import patch

m = {'capabilities': {'alpha': {'drive': {'zones': [{'id': 'folderAAA'}]}}}}
assert not grant_allowed_by_manifest(m, 'alpha', 'folderBBB')
assert grant_allowed_by_manifest(m, 'alpha', 'folderAAA')
# zones: [] explicite = plafond vide (deny), ≠ absence de clé zones
m_empty = {'capabilities': {'alpha': {'drive': {'zones': []}}}}
assert not grant_allowed_by_manifest(m_empty, 'alpha', 'folderAAA')
m_no_zones = {'capabilities': {'alpha': {'drive': {'read': True}}}}
assert grant_allowed_by_manifest(m_no_zones, 'alpha', 'anyFolder')
sid = create_session(client='t').session_id
ctx = ProjectContext(manifest_valid=True, manifest=m, git_root='/tmp')
os.environ['GWSA_GIT_ROOT'] = '/tmp'
with patch('gateway.project.resolve_project', return_value=ctx):
    try:
        session_grant_drive(sid, 'alpha', 'folderBBB', 'Bad', 1)
        raise SystemExit('no reject')
    except GatewayError:
        pass
    session_grant_drive(sid, 'alpha', 'folderAAA', 'ZoneA', 1)
print(len(active_drive_zones(sid, 'alpha')))
")"
[[ "$cap_out" == "1" ]] \
  && pass "project manifest : grant session ⊆ zones manifeste" \
  || fail "project manifest : intersection grant ($cap_out)"

# access_request project_grant + plafond services manifeste
pg_out="$("$PY" -c "
import os
from unittest.mock import patch
from gateway.context import set_session_id
from gateway.api import access_request
from gateway.project import ProjectContext
from gateway.sessions import create_session

sid = create_session(client='t').session_id
set_session_id(sid)
m = {'capabilities': {'alpha': {
  'drive': {'zones': [{'id': 'folderAAA'}]},
  'gmail': {'read': True, 'drafts': False},
}}}
ctx = ProjectContext(manifest_valid=True, manifest=m, git_root='/tmp',
                     manifest_path='/tmp/.gwsa/manifest.json')
os.environ['GWSA_GIT_ROOT'] = '/tmp'
with patch('gateway.project.resolve_project', return_value=ctx):
    ok = access_request('alpha', 'project_grant', folder='folderAAA', hours=2)
    assert ok.get('kind') == 'project_grant' and 'session grant' in ok.get('suggested_command','')
    blocked = access_request('alpha', 'project_grant', folder='folderBBB', hours=2)
    assert blocked.get('blocked_by_manifest') is True
from gateway.project import manifest_allows_service
assert manifest_allows_service(m, 'alpha', 'gmail', 'read') is True
assert manifest_allows_service(m, 'alpha', 'gmail', 'drafts') is False
print('ok')
")"
[[ "$pg_out" == "ok" ]] \
  && pass "project_grant : plafond manifeste + services" \
  || fail "project_grant ($pg_out)"

# policy-check : plafond services via _manifest_service_cap
svc_cap="$("$PY" -c "
import importlib.util, os, sys
from unittest.mock import patch
from gateway.project import ProjectContext

spec = importlib.util.spec_from_file_location('pc', 'scripts/policy-check.py')
pc = importlib.util.module_from_spec(spec)
sys.argv = ['pc']
spec.loader.exec_module(pc)
m = {'capabilities': {'alpha': {'gmail': {'read': True, 'drafts': False}}}}
ctx = ProjectContext(manifest_valid=True, manifest=m, git_root='/tmp')
os.environ['GWSA_GIT_ROOT'] = '/tmp'
with patch('gateway.project.resolve_project', return_value=ctx):
    assert pc._manifest_service_cap('alpha', 'gmail', 'read') is True
    assert pc._manifest_service_cap('alpha', 'gmail', 'drafts') is False
print('ok')
")"
[[ "$svc_cap" == "ok" ]] \
  && pass "policy-check : plafond services manifeste" \
  || fail "policy-check services manifeste ($svc_cap)"

policy <<'EOF'
{"drive": {"read": true, "create": true, "update": true, "delete": false,
           "share": false, "zonesOnly": true, "writeFolders": []}}
EOF
no_grants
OLD_PROFILE="$PROFILE"
PROFILE="$SESS_ROOT/alpha"
export GWSA_USE_SESSION_GRANTS=1 GWSA_SESSION_DRIVE_ZONES="$GRANT_FID"
check 0 "policy : zones session MCP (GWSA_SESSION_DRIVE_ZONES)" \
  drive files create --json "{\"name\":\"x\",\"parents\":[\"$GRANT_FID\"]}"
unset GWSA_USE_SESSION_GRANTS GWSA_SESSION_DRIVE_ZONES
PROFILE="$OLD_PROFILE"

mkdir -p "$SESS_ROOT/beta"
echo 'secret' > "$SESS_ROOT/beta/credentials.enc"
GWSA_ROOT="$SESS_ROOT" "$PY" -c "
from gateway.vault import migrate_alias, is_migrated, gws_config_dir, has_credentials, remove_vault_alias
from gateway.profiles import list_profiles
from pathlib import Path
assert migrate_alias('beta')
assert is_migrated('beta')
assert not Path('$SESS_ROOT/beta/credentials.enc').exists()
assert gws_config_dir('beta').name == 'beta'
assert has_credentials('beta')
# re-auth : nouveau credentials.enc profil remplace le vault
Path('$SESS_ROOT/beta/credentials.enc').write_text('fresh')
assert migrate_alias('beta')
assert Path('$SESS_ROOT/.vault/beta/credentials.enc').read_text() == 'fresh'
assert not Path('$SESS_ROOT/beta/credentials.enc').exists()
# list_profiles voit le vault
profs = {p['alias']: p for p in list_profiles()}
assert profs['beta']['connected'] is True
remove_vault_alias('beta')
assert not has_credentials('beta')
" 2>/dev/null \
  && pass "vault : migration credentials.enc vers .vault/" \
  || fail "vault : migration"

section "élicitation signée (fiche 0001)"
ELIC_ROOT="$TMP/gwsa-elicitation"
mkdir -p "$ELIC_ROOT/alpha"
touch "$ELIC_ROOT/.strong-auth"
export GWSA_ROOT="$ELIC_ROOT" GWSA_ELICITATION_MOCK=1 PYTHONPATH="$(pwd)"
"$PY" "$(pwd)/scripts/elicitation-cli.py" enroll --mock >/dev/null 2>&1 \
  && pass "elicitation : enroll mock" \
  || fail "elicitation : enroll mock"

gate_ok="$("$PY" -c "
from gateway.elicitation import run_elicitation_gate, build_payload, sign_mock, consume_nonce, ElicitationError
run_elicitation_gate({'action': 'session_unlock', 'alias': 'alpha', 'session_id': 'abc', 'minutes': 30})
p = build_payload('session_unlock', alias='alpha', session_id='abc', minutes=30)
consume_nonce(p['nonce'], expires_at=p['expires_at'])
try:
    consume_nonce(p['nonce'], expires_at=p['expires_at'])
    raise SystemExit('replay allowed')
except ElicitationError:
    pass
print('ok')
")"
[[ "$gate_ok" == "ok" ]] \
  && pass "elicitation : gate mock + anti-rejeu nonce" \
  || fail "elicitation : gate mock ($gate_ok)"

tamper="$("$PY" -c "
from gateway.elicitation import build_payload, sign_mock, verify_signature
p = build_payload('grant', alias='alpha', target='Z', hours=8)
sig = sign_mock(p)
p['hours'] = 99
print(verify_signature(p, sig))
")"
[[ "$tamper" == "False" ]] \
  && pass "elicitation : payload altéré → signature invalide" \
  || fail "elicitation : tamper détecté ($tamper)"

sid_e="$("$PY" -c 'from gateway.sessions import create_session; print(create_session(client="t").session_id)')"
GWSA_ROOT="$ELIC_ROOT" GWSA_SESSION_ID="$sid_e" GWSA_ELICITATION_MOCK=1 \
  "$GWSA" session unlock "$sid_e" alpha 15 >/dev/null 2>&1 \
  && pass "elicitation : gwsa session unlock avec strongauth+mock" \
  || fail "elicitation : gwsa session unlock strongauth"

section "sandbox remove (fiche 0041)"
SB_DEP="$TMP/sandbox-remove"
mkdir -p "$SB_DEP/test-sb"
printf '%s\n' '{"id":"test-sb","broker_port":4899,"admin_port":4898,"version":"dev@abc (dev)"}' \
  > "$SB_DEP/test-sb/.sandbox.json"
echo "dev" > "$SB_DEP/test-sb/VERSION"
GWSA_DEPLOY_ROOT="$SB_DEP" ./scripts/sandbox.sh remove test-sb >/dev/null 2>&1; rc=$?
[[ "$rc" -eq 0 && ! -d "$SB_DEP/test-sb" ]] \
  && pass "sandbox remove : supprime le répertoire jetable" \
  || fail "sandbox remove : répertoire encore présent (rc=$rc)"

GWSA_DEPLOY_ROOT="$SB_DEP" ./scripts/sandbox.sh remove current >/dev/null 2>&1; rc=$?
[[ "$rc" -ne 0 ]] \
  && pass "sandbox remove current → refus" \
  || fail "sandbox remove current devrait refuser"

mkdir -p "$SB_DEP/v1.0.0"
GWSA_DEPLOY_ROOT="$SB_DEP" ./scripts/sandbox.sh remove v1.0.0 >/dev/null 2>&1; rc=$?
[[ "$rc" -ne 0 ]] \
  && pass "sandbox remove sans manifeste sandbox → refus" \
  || fail "sandbox remove archive stable devrait refuser"

# remove sans id → branche courante (préfixe / manifest.branch)
SB_BR="$TMP/sandbox-branch-rm"
mkdir -p "$SB_BR"
# Fabrique un faux « repo » : on utilise le vrai REPO via script, donc on pose
# deux sandboxes dont le manifeste.branch = branche courante du worktree.
CUR_BR="$(git rev-parse --abbrev-ref HEAD)"
CUR_SLUG="$(printf '%s' "$CUR_BR" | tr '[:upper:]' '[:lower:]' | tr '/ ' '--' | tr -cd 'a-z0-9._-' | cut -c1-40)"
# Nouveau format <slug>-<sha> (sans préfixe dev-)
SB1="${CUR_SLUG}-aaa1111"
SB2="${CUR_SLUG}-bbb2222"
mkdir -p "$SB_BR/$SB1" "$SB_BR/$SB2"
printf '%s\n' "{\"id\":\"$SB1\",\"broker_port\":4891,\"admin_port\":4890,\"branch\":\"$CUR_BR\",\"version\":\"x\"}" \
  > "$SB_BR/$SB1/.sandbox.json"
printf '%s\n' "{\"id\":\"$SB2\",\"broker_port\":4893,\"admin_port\":4892,\"branch\":\"$CUR_BR\",\"version\":\"y\"}" \
  > "$SB_BR/$SB2/.sandbox.json"
# Une seule → remove sans id
rm -rf "$SB_BR/$SB2"
GWSA_DEPLOY_ROOT="$SB_BR" ./scripts/sandbox.sh remove >/dev/null 2>&1; rc=$?
[[ "$rc" -eq 0 && ! -d "$SB_BR/$SB1" ]] \
  && pass "sandbox remove sans id : cible la branche courante" \
  || fail "sandbox remove sans id (rc=$rc)"

# Plusieurs → --all
mkdir -p "$SB_BR/$SB1" "$SB_BR/$SB2"
printf '%s\n' "{\"id\":\"$SB1\",\"broker_port\":4891,\"admin_port\":4890,\"branch\":\"$CUR_BR\",\"version\":\"x\"}" \
  > "$SB_BR/$SB1/.sandbox.json"
printf '%s\n' "{\"id\":\"$SB2\",\"broker_port\":4893,\"admin_port\":4892,\"branch\":\"$CUR_BR\",\"version\":\"y\"}" \
  > "$SB_BR/$SB2/.sandbox.json"
GWSA_DEPLOY_ROOT="$SB_BR" ./scripts/sandbox.sh remove --all >/dev/null 2>&1; rc=$?
[[ "$rc" -eq 0 && ! -d "$SB_BR/$SB1" && ! -d "$SB_BR/$SB2" ]] \
  && pass "sandbox remove --all : toutes les sandboxes de la branche" \
  || fail "sandbox remove --all (rc=$rc)"

# Compat : ancien id dev-<slug>-… toujours trouvé sans id (préfixe)
SB_OLD="dev-${CUR_SLUG}-oldc0de"
mkdir -p "$SB_BR/$SB_OLD"
printf '%s\n' "{\"id\":\"$SB_OLD\",\"broker_port\":4895,\"admin_port\":4894,\"branch\":\"$CUR_BR\",\"version\":\"legacy\"}" \
  > "$SB_BR/$SB_OLD/.sandbox.json"
GWSA_DEPLOY_ROOT="$SB_BR" ./scripts/sandbox.sh remove >/dev/null 2>&1; rc=$?
[[ "$rc" -eq 0 && ! -d "$SB_BR/$SB_OLD" ]] \
  && pass "sandbox remove sans id : compat ancien id dev-<slug>-…" \
  || fail "sandbox remove compat dev-* (rc=$rc)"

section "sandbox deploy --wire (fiche 0041)"
SB_WIRE_ROOT="$TMP/sandbox-wire-deploy"
SB_DESK="$TMP/sandbox-wire-desktop.json"
SB_CUR="$TMP/sandbox-wire-cursor.json"
# Entrée stable préexistante — ne doit jamais être écrasée
cat > "$SB_DESK" <<'EOF'
{
  "mcpServers": {
    "google-multi-account": {
      "command": "/opt/stable/bin/google-mcp",
      "env": { "GWSA_CLIENT": "claude-desktop", "GWSA_BROKER_PORT": "4878" }
    }
  }
}
EOF
cat > "$SB_CUR" <<'EOF'
{
  "mcpServers": {
    "google-multi-account": {
      "command": "/opt/stable/bin/google-mcp",
      "env": { "GWSA_CLIENT": "cursor", "GWSA_BROKER_PORT": "4878" }
    }
  }
}
EOF
mkdir -p "$SB_WIRE_ROOT"
# Ports hauts peu susceptibles d'être occupés ; skip code (claude absent OK)
WIRE_OUT="$(
  GWSA_DEPLOY_ROOT="$SB_WIRE_ROOT" \
  GWSA_DESKTOP_CONFIG="$SB_DESK" \
  GWSA_CURSOR_CONFIG="$SB_CUR" \
  ./scripts/sandbox.sh deploy --wire desktop,cursor --port 4921 --admin-port 4920 2>&1
)" || true
WIRE_ID="$(printf '%s\n' "$WIRE_OUT" | sed -n 's/^[[:space:]]*id[[:space:]]*:[[:space:]]*//p' | head -1)"
CUR_SHA="$(git rev-parse --short HEAD)"
EXPECTED_ID_PREFIX="${CUR_SLUG}-${CUR_SHA}"
[[ -n "$WIRE_ID" && -d "$SB_WIRE_ROOT/$WIRE_ID" ]] \
  && pass "sandbox deploy --wire : déploiement créé ($WIRE_ID)" \
  || fail "sandbox deploy --wire : id/déploiement manquant"
# Id = <slug>-<sha>[-dirty], sans préfixe dev-
case "$WIRE_ID" in
  dev-*) fail "sandbox id ne doit plus commencer par dev- (got $WIRE_ID)" ;;
  "${EXPECTED_ID_PREFIX}"|"${EXPECTED_ID_PREFIX}-dirty")
    pass "sandbox id format : <slug>-<sha> (pas de préfixe dev-)" ;;
  *) fail "sandbox id inattendu : $WIRE_ID (attendu ${EXPECTED_ID_PREFIX}[-dirty])" ;;
esac
ENTRY="google-multi-account-${WIRE_ID}"
python3 - "$SB_DESK" "$ENTRY" "$SB_WIRE_ROOT/$WIRE_ID/bin/google-mcp" <<'PY' >/dev/null 2>&1
import json, sys
cfg, name, bin_path = sys.argv[1], sys.argv[2], sys.argv[3]
d = json.load(open(cfg, encoding="utf-8"))
servers = d["mcpServers"]
assert "google-multi-account" in servers
stable = servers["google-multi-account"]
assert stable["env"]["GWSA_BROKER_PORT"] == "4878"
assert stable["command"] == "/opt/stable/bin/google-mcp"
assert name in servers
e = servers[name]
assert e["command"] == bin_path
assert e["env"]["GWSA_BROKER_PORT"] == "4921"
assert e["env"]["GWSA_CLIENT"] == "claude-desktop"
assert name != "google-multi-account"
PY
[[ $? -eq 0 ]] \
  && pass "sandbox --wire desktop : entrée suffixée + stable intact" \
  || fail "sandbox --wire desktop : config Desktop incorrecte"

python3 - "$SB_CUR" "$ENTRY" "$SB_WIRE_ROOT/$WIRE_ID/bin/google-mcp" <<'PY' >/dev/null 2>&1
import json, sys
cfg, name, bin_path = sys.argv[1], sys.argv[2], sys.argv[3]
d = json.load(open(cfg, encoding="utf-8"))
servers = d["mcpServers"]
assert servers["google-multi-account"]["env"]["GWSA_BROKER_PORT"] == "4878"
e = servers[name]
assert e["command"] == bin_path
assert e["env"]["GWSA_BROKER_PORT"] == "4921"
assert e["env"]["GWSA_CLIENT"] == "cursor"
PY
[[ $? -eq 0 ]] \
  && pass "sandbox --wire cursor : entrée suffixée + stable intact" \
  || fail "sandbox --wire cursor : config Cursor incorrecte"

python3 - "$SB_WIRE_ROOT/$WIRE_ID/.sandbox.json" "$ENTRY" <<'PY' >/dev/null 2>&1
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
assert d.get("mcp_entry") == sys.argv[2]
assert d["broker_port"] == 4921
PY
[[ $? -eq 0 ]] \
  && pass "sandbox --wire : mcp_entry dans .sandbox.json" \
  || fail "sandbox --wire : mcp_entry absent du manifeste"

printf '%s\n' "$WIRE_OUT" | grep -q "checklist post-wire\|Suite — checklist\|Redémarrer les clients" \
  && pass "sandbox deploy --wire : checklist courte (pas le bloc manuel long)" \
  || fail "sandbox deploy --wire : checklist post-wire absente"

# wire --remove desktop : retire Desktop seulement, conserve Cursor + répertoire
GWSA_DEPLOY_ROOT="$SB_WIRE_ROOT" \
GWSA_DESKTOP_CONFIG="$SB_DESK" \
GWSA_CURSOR_CONFIG="$SB_CUR" \
  ./scripts/sandbox.sh wire "$WIRE_ID" --remove desktop >/dev/null 2>&1; rc=$?
python3 - "$SB_DESK" "$SB_CUR" "$ENTRY" <<'PY' >/dev/null 2>&1
import json, sys
desk, cur, name = sys.argv[1], sys.argv[2], sys.argv[3]
d = json.load(open(desk, encoding="utf-8"))
assert name not in d["mcpServers"]
assert "google-multi-account" in d["mcpServers"]
c = json.load(open(cur, encoding="utf-8"))
assert name in c["mcpServers"], "cursor doit rester branché"
assert "google-multi-account" in c["mcpServers"]
PY
[[ "$rc" -eq 0 && $? -eq 0 && -d "$SB_WIRE_ROOT/$WIRE_ID" ]] \
  && pass "sandbox wire --remove desktop : Desktop only, dir conservé" \
  || fail "sandbox wire --remove desktop (rc=$rc)"

# wire --remove (all) : retire aussi Cursor ; dir toujours là
GWSA_DEPLOY_ROOT="$SB_WIRE_ROOT" \
GWSA_DESKTOP_CONFIG="$SB_DESK" \
GWSA_CURSOR_CONFIG="$SB_CUR" \
  ./scripts/sandbox.sh wire "$WIRE_ID" --remove >/dev/null 2>&1; rc=$?
python3 - "$SB_CUR" "$ENTRY" <<'PY' >/dev/null 2>&1
import json, sys
c = json.load(open(sys.argv[1], encoding="utf-8"))
assert sys.argv[2] not in c["mcpServers"]
assert "google-multi-account" in c["mcpServers"]
PY
[[ "$rc" -eq 0 && $? -eq 0 && -d "$SB_WIRE_ROOT/$WIRE_ID" ]] \
  && pass "sandbox wire --remove : tous clients, dir conservé" \
  || fail "sandbox wire --remove all (rc=$rc)"

# Re-wire pour tester remove nucléaire ensuite
GWSA_DEPLOY_ROOT="$SB_WIRE_ROOT" \
GWSA_DESKTOP_CONFIG="$SB_DESK" \
GWSA_CURSOR_CONFIG="$SB_CUR" \
  ./scripts/sandbox.sh wire "$WIRE_ID" --wire desktop,cursor >/dev/null 2>&1

# remove doit unwire avant suppression
GWSA_DEPLOY_ROOT="$SB_WIRE_ROOT" \
GWSA_DESKTOP_CONFIG="$SB_DESK" \
GWSA_CURSOR_CONFIG="$SB_CUR" \
  ./scripts/sandbox.sh remove "$WIRE_ID" >/dev/null 2>&1; rc=$?
[[ "$rc" -eq 0 && ! -d "$SB_WIRE_ROOT/$WIRE_ID" ]] \
  && pass "sandbox remove après wire : répertoire supprimé" \
  || fail "sandbox remove après wire : échec (rc=$rc)"

python3 - "$SB_DESK" "$SB_CUR" "$ENTRY" <<'PY' >/dev/null 2>&1
import json, sys
desk, cur, name = sys.argv[1], sys.argv[2], sys.argv[3]
for path in (desk, cur):
    d = json.load(open(path, encoding="utf-8"))
    servers = d["mcpServers"]
    assert name not in servers, path
    assert "google-multi-account" in servers
    assert servers["google-multi-account"]["env"]["GWSA_BROKER_PORT"] == "4878"
PY
[[ $? -eq 0 ]] \
  && pass "sandbox remove : unwire suffixé, stable intact" \
  || fail "sandbox remove : unwire incomplet ou stable touché"

# wire sur sandbox déjà déployée (sans --wire au deploy)
SB_WIRE2="$TMP/sandbox-wire-later"
mkdir -p "$SB_WIRE2"
# Réutiliser ports libres différents
LATER_OUT="$(
  GWSA_DEPLOY_ROOT="$SB_WIRE2" \
  ./scripts/sandbox.sh deploy --port 4923 --admin-port 4922 2>&1
)" || true
LATER_ID="$(printf '%s\n' "$LATER_OUT" | sed -n 's/^[[:space:]]*id[[:space:]]*:[[:space:]]*//p' | head -1)"
printf '%s\n' "$LATER_OUT" | grep -q "sandbox wire\|install-claude-desktop" \
  && pass "sandbox deploy sans --wire : consignes manuelles / wire" \
  || fail "sandbox deploy sans --wire : consignes manuelles absentes"
cat > "$SB_DESK" <<'EOF'
{"mcpServers": {"google-multi-account": {"command": "/opt/stable/bin/google-mcp", "env": {"GWSA_CLIENT": "claude-desktop", "GWSA_BROKER_PORT": "4878"}}}}
EOF
GWSA_DEPLOY_ROOT="$SB_WIRE2" \
GWSA_DESKTOP_CONFIG="$SB_DESK" \
GWSA_CURSOR_CONFIG="$SB_CUR" \
  ./scripts/sandbox.sh wire "$LATER_ID" --wire desktop >/dev/null 2>&1; rc=$?
python3 - "$SB_DESK" "google-multi-account-${LATER_ID}" <<'PY' >/dev/null 2>&1
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
assert sys.argv[2] in d["mcpServers"]
assert "google-multi-account" in d["mcpServers"]
PY
[[ "$rc" -eq 0 && $? -eq 0 ]] \
  && pass "sandbox wire : branche Desktop sur sandbox existante" \
  || fail "sandbox wire sur sandbox existante (rc=$rc)"
# nettoyage
GWSA_DEPLOY_ROOT="$SB_WIRE2" \
GWSA_DESKTOP_CONFIG="$SB_DESK" \
GWSA_CURSOR_CONFIG="$SB_CUR" \
  ./scripts/sandbox.sh remove "$LATER_ID" >/dev/null 2>&1 || true

section "admin : retirer entrée MCP (dev panel)"
MCP_CFG="$TMP/claude-desktop-mcp.json"
cat > "$MCP_CFG" <<EOF
{
  "mcpServers": {
    "google-multi-account": {
      "command": "$HOME/.local/share/google-mcp/current/bin/google-mcp",
      "env": { "GWSA_CLIENT": "claude-desktop", "GWSA_BROKER_PORT": "4878" }
    },
    "google-mcp-dev-temp-xyz": {
      "command": "$HOME/.local/share/google-mcp/dev-temp/bin/google-mcp",
      "env": { "GWSA_CLIENT": "claude-desktop", "GWSA_BROKER_PORT": "4889" }
    }
  }
}
EOF
MCP_ADMIN_PORT=4971
GWSA_ROOT="$TMP/admin-mcp-root" GWSA_ADMIN_PORT="$MCP_ADMIN_PORT" \
  GWSA_DESKTOP_CONFIG="$MCP_CFG" GWSA_CURSOR_CONFIG="" \
  node "$(pwd)/admin/server.js" >/dev/null 2>&1 &
MCP_ADMIN_PID=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if curl -sf -H 'X-GWSA-Admin: 1' "http://127.0.0.1:$MCP_ADMIN_PORT/api/dev" >/dev/null 2>&1; then break; fi
  sleep 0.2
done
prot="$(curl -s -o /tmp/mcp-rm-prot.json -w '%{http_code}' -H 'X-GWSA-Admin: 1' -H 'Content-Type: application/json' \
  -d "{\"name\":\"google-multi-account\",\"config\":\"$MCP_CFG\"}" \
  "http://127.0.0.1:$MCP_ADMIN_PORT/api/dev/mcp-client/remove")"
[[ "$prot" == "403" ]] \
  && pass "admin MCP remove : refuse google-multi-account (protégée)" \
  || fail "admin MCP remove : stable devrait être 403 (got $prot)"

ok_rm="$(curl -s -o /tmp/mcp-rm-ok.json -w '%{http_code}' -H 'X-GWSA-Admin: 1' -H 'Content-Type: application/json' \
  -d "{\"name\":\"google-mcp-dev-temp-xyz\",\"config\":\"$MCP_CFG\"}" \
  "http://127.0.0.1:$MCP_ADMIN_PORT/api/dev/mcp-client/remove")"
"$PY" -c "
import json
d=json.load(open('$MCP_CFG'))
assert 'google-mcp-dev-temp-xyz' not in d['mcpServers']
assert 'google-multi-account' in d['mcpServers']
" \
  && [[ "$ok_rm" == "200" ]] \
  && pass "admin MCP remove : retire l'entrée jetable, garde le stable" \
  || fail "admin MCP remove : retrait jetable (http=$ok_rm)"

grep -q 'removeMcpClient' admin/index.html \
  && grep -q 'removeSandbox' admin/index.html \
  && grep -q '/api/dev/mcp-client/remove' admin/index.html \
  && pass "admin UI : boutons Retirer MCP + Supprimer sandbox" \
  || fail "admin UI : marqueurs remove absents"

kill "$MCP_ADMIN_PID" 2>/dev/null || true
wait "$MCP_ADMIN_PID" 2>/dev/null || true

section "Admin zones — flux authorize (wiring + logique + API)"

AF_HTML=admin/index.html
AF_LOGIC=scripts/af-selection-logic.js

# Markers UI / handlers : auraient attrapé « Sélectionner → Zones vides »
if grep -q 'data-af-action="select"' "$AF_HTML" \
  && grep -q 'afOpenAuthorize()' "$AF_HTML" \
  && grep -q 'onclick="afConfirm()"' "$AF_HTML" \
  && grep -q 'id="dAuthorizeFolder"' "$AF_HTML" \
  && grep -q '/drive-folder"' "$AF_HTML" \
  && grep -q '"/grant"' "$AF_HTML"; then
  pass "wiring : Sélectionner → durée → Valider appelle drive-folder/grant"
else
  fail "wiring : marqueurs authorize manquants dans admin/index.html"
fi

# Pas de ligne « Sélectionné : » / bouton footer Autoriser… (UI simplifiée)
if ! grep -q 'id="afChosen"' "$AF_HTML" \
  && ! grep -q 'id="afConfirmBtn"' "$AF_HTML" \
  && ! grep -q 'Sélectionné :' "$AF_HTML"; then
  pass "UI : pas de afChosen / Autoriser… en footer (Sélectionner suffit)"
else
  fail "UI : afChosen ou Autoriser… encore présents"
fi

# Loading UX sur Valider (Touch ID / grant) — marqueurs cheap
if grep -q 'id="afValidateBtn"' "$AF_HTML" \
  && grep -q 'function afSetAuthorizeLoading' "$AF_HTML" \
  && grep -q 'is-loading' "$AF_HTML" \
  && grep -q 'afSetAuthorizeLoading(true)' "$AF_HTML" \
  && grep -q 'finally { afSetAuthorizeLoading(false); }' "$AF_HTML"; then
  pass "wiring : Valider loading UX (is-loading + finally)"
else
  fail "wiring : marqueurs loading Valider manquants"
fi

# Footer picker = Annuler seul (entre dAddFolder et dAuthorizeFolder)
picker_footer="$(awk '/id="dAddFolder"/,/id="dAuthorizeFolder"/' "$AF_HTML")"
if echo "$picker_footer" | grep -q 'dAddFolder.close()' \
  && ! echo "$picker_footer" | grep -q 'Autoriser'; then
  pass "UI : footer picker = Annuler uniquement"
else
  fail "UI : footer picker encore trop chargé"
fi

# Régression critique : afOpenAuthorize ne doit PAS fermer le picker
if node -e '
const fs = require("fs");
const html = fs.readFileSync("admin/index.html", "utf8");
const m = html.match(/function afOpenAuthorize\(\) \{([\s\S]*?)\n\}/);
if (!m) { console.error("afOpenAuthorize introuvable"); process.exit(2); }
const body = m[1];
if (body.includes("dAddFolder.close")) {
  console.error("afOpenAuthorize ferme encore dAddFolder (reprise Zones prématurée)");
  process.exit(1);
}
if (!body.includes("dAuthorizeFolder.showModal")) {
  console.error("afOpenAuthorize n'\''ouvre pas dAuthorizeFolder");
  process.exit(1);
}
' ; then
  pass "régression : afOpenAuthorize garde le picker ouvert sous le dialog durée"
else
  fail "régression : afOpenAuthorize referme le picker (bug zones vides)"
fi

# Navigation efface la sélection (afClearSelection dans afOpen / afJump / afEnterFolder)
if grep -q 'function afClearSelection' "$AF_HTML" \
  && grep -q 'function afOpen(id, name) { afClearSelection()' "$AF_HTML" \
  && grep -q 'function afJump(i) { afClearSelection()' "$AF_HTML" \
  && grep -q 'afClearSelection();' "$AF_HTML"; then
  pass "sélection : clear sur navigate (open / jump / enter)"
else
  fail "sélection : afClearSelection absent des navigateurs"
fi

# Logique pure (Node) — sélection + machine à états du bug
if node "$AF_LOGIC" >/dev/null; then
  pass "logique : sélection clear + flux authorize (picker reste ouvert)"
else
  fail "logique : scripts/af-selection-logic.js en échec"
fi

# Padlock / unlock UX — chip unifié (cadenas + timer), modal relock, pas de confirm() natif
if grep -q 'id="dRelock"' "$AF_HTML" \
  && grep -q 'function openRelock' "$AF_HTML" \
  && grep -q 'function doRelock' "$AF_HTML" \
  && grep -q 'function lockSetLoading' "$AF_HTML" \
  && grep -q 'function shorten' "$AF_HTML" \
  && grep -q 'class="lockchip' "$AF_HTML" \
  && grep -q 'cd-prolong' "$AF_HTML" \
  && grep -q 'cd-shorten' "$AF_HTML" \
  && grep -q 'Verrouiller l' "$AF_HTML" \
  && grep -q 'id="relockAccount"' "$AF_HTML" \
  && ! grep -q 'encore ' "$AF_HTML" \
  && ! grep -q 'confirm("Verrouiller' "$AF_HTML" \
  && ! grep -q "confirm('Verrouiller" "$AF_HTML" \
  && ! grep -q 'confirm("Reverrouiller' "$AF_HTML" \
  && ! grep -q "confirm('Reverrouiller" "$AF_HTML"; then
  pass "padlock : lockchip unifié + −/+ + modal dRelock (sans confirm())"
else
  fail "padlock : marqueurs lockchip / shorten / dRelock manquants"
fi

if grep -q 'TOUCHID_BIN=' bin/gwsa \
  && grep -q 'strong_auth_reason' bin/gwsa \
  && grep -q 'mcp-google-mcp-multi-account' bin/gwsa; then
  pass "touchid : binaire nommé + raison avec email (gwsa)"
else
  fail "touchid : strong_auth_reason ou binaire manquant dans gwsa"
fi

# Sous strongauth, add sans email doit refuser avant Touch ID (fiche 0032 / review #50)
printf '{"installed":{"client_id":"hermetic-test","client_secret":"not-a-real-secret"}}\n' \
  > "$GWSA_ROOT/client_secret.json"
touch "$GWSA_ROOT/.strong-auth"
out_add="$("$GWSA" add newacct 2>&1)"; rc_add=$?
rm -f "$GWSA_ROOT/.strong-auth"
if [[ "$rc_add" -eq 3 ]] \
  && echo "$out_add" | grep -q 'email requis quand strongauth'; then
  pass "touchid : gwsa add sans email refusé sous strongauth (exit 3)"
else
  fail "touchid : add sans email sous strongauth — rc=$rc_add out=$(echo "$out_add" | head -c 160)"
fi

# Admin : unlock/grant doivent attendre Touch ID > 20 s (sinon Failed to fetch)
if grep -q 'GWSA_TIMEOUT_AUTH_MS = 120000' admin/server.js \
  && grep -q 'holdHttpForAuth' admin/server.js \
  && grep -q 'authGwsaResult' admin/server.js \
  && grep -q 'server.on("error"' admin/server.js \
  && grep -q 'connexion perdue avec l'\''admin' admin/index.html \
  && grep -q 'pidfile fantôme' bin/gwsa; then
  pass "admin : timeout Touch ID 120s + listen error + message Failed to fetch"
else
  fail "admin : garde-fous Touch ID / Failed to fetch manquants"
fi

# API admin hermétique : grant + drive-folder écrivent bien grants / policy
AF_ALIAS=zonesapi
AF_DIR="$GWSA_ROOT/$AF_ALIAS"
mkdir -p "$AF_DIR"
printf '%s\n' '{"drive":{"read":true,"create":true,"update":true,"delete":false,"share":false,"zonesOnly":true,"writeFolders":[]}}' \
  > "$AF_DIR/policy.json"
rm -f "$GWSA_ROOT/.strong-auth"   # pas de Touch ID en bac à sable
AF_PORT=0
# port libre 49152–49500
for AF_PORT in 49171 49172 49173 49174 49175; do
  if ! (echo >/dev/tcp/127.0.0.1/"$AF_PORT") 2>/dev/null; then break; fi
done
AF_FID="ZONEFOLDER12345678901"
AF_PID=""
GWSA_ADMIN_PORT="$AF_PORT" node admin/server.js >/dev/null 2>&1 &
AF_PID=$!
# attendre l'écoute (max ~3 s)
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if (echo >/dev/tcp/127.0.0.1/"$AF_PORT") 2>/dev/null; then break; fi
  sleep 0.3
done
af_api() { # af_api METHOD PATH [json-body]
  local method="$1" path="$2" body="${3:-}"
  if [[ -n "$body" ]]; then
    curl -sS -o "$TMP/af_api.json" -w "%{http_code}" \
      -X "$method" "http://127.0.0.1:${AF_PORT}${path}" \
      -H "X-GWSA-Admin: 1" -H "Content-Type: application/json" -d "$body"
  else
    curl -sS -o "$TMP/af_api.json" -w "%{http_code}" \
      -X "$method" "http://127.0.0.1:${AF_PORT}${path}" \
      -H "X-GWSA-Admin: 1"
  fi
}
AF_CODE="$(af_api POST "/api/profiles/${AF_ALIAS}/grant" "{\"target\":\"${AF_FID}\",\"hours\":2}")"
if [[ "$AF_CODE" == "200" ]] \
  && grep -q "$AF_FID" "$AF_DIR/session-grants.json" 2>/dev/null; then
  pass "API grant : écrit session-grants.json (temporaire)"
else
  fail "API grant : HTTP $AF_CODE — $(head -c 200 "$TMP/af_api.json" 2>/dev/null)"
fi
AF_CODE="$(af_api POST "/api/profiles/${AF_ALIAS}/drive-folder" "{\"target\":\"${AF_FID}\"}")"
if [[ "$AF_CODE" == "200" ]] \
  && grep -q "$AF_FID" "$AF_DIR/policy.json" 2>/dev/null; then
  pass "API drive-folder : ajoute writeFolders (permanent)"
else
  fail "API drive-folder : HTTP $AF_CODE — $(head -c 200 "$TMP/af_api.json" 2>/dev/null)"
fi
# profiles JSON expose grants + writeFolders pour le refresh UI
AF_CODE="$(af_api GET "/api/profiles")"
if [[ "$AF_CODE" == "200" ]] \
  && grep -q "$AF_ALIAS" "$TMP/af_api.json" \
  && grep -q "$AF_FID" "$TMP/af_api.json"; then
  pass "API profiles : refresh UI voit la zone après authorize"
else
  fail "API profiles : zone absente du payload refresh"
fi
if [[ -n "$AF_PID" ]]; then kill "$AF_PID" 2>/dev/null || true; wait "$AF_PID" 2>/dev/null || true; fi

# --- gwsa dev test — déploiement + admin + marqueur PR ----------------------

section "gwsa dev test — déployer, redémarrer l'admin, vérifier afSearchHits"

DEVTEST_DEP="$TMP/devdeploy"
DEVTEST_ROOT="$TMP/devgwsa"
# Port éphémère : évite les orphelins d'un run précédent sur 49201.
DEVTEST_PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"
mkdir -p "$DEVTEST_ROOT"

if "$GWSA" dev test --help 2>&1 | grep -q 'gwsa dev test'; then
  pass "dev test --help : usage affiché"
else
  fail "dev test --help : usage manquant"
fi

if grep -q 'cmd_dev_test' bin/gwsa \
  && grep -q 'afSearchHits' bin/gwsa \
  && grep -q 'GWSA_ADMIN_NO_OPEN' bin/gwsa; then
  pass "dev test : implémentation + marqueur afSearchHits + no-open admin"
else
  fail "dev test : marqueurs d'implémentation manquants dans gwsa"
fi

if command -v node >/dev/null 2>&1; then
  branch="$(git rev-parse --abbrev-ref HEAD)"
  sha="$(git rev-parse --short HEAD)"
  part="$(printf '%s' "$branch" | tr '/' '-' | tr -cd 'A-Za-z0-9-')"
  [[ -n "$part" ]] || part="branch"
  dev_id="dev-${part}-${sha}"
  out="$(GWSA_DEPLOY_ROOT="$DEVTEST_DEP" GWSA_ROOT="$DEVTEST_ROOT" \
    GWSA_ADMIN_PORT="$DEVTEST_PORT" \
    "$GWSA" dev test 2>&1)" || true
  if [[ -d "$DEVTEST_DEP/$dev_id" ]] \
    && echo "$out" | grep -q "Déploiement : $dev_id" \
    && echo "$out" | grep -q "http://127.0.0.1:$DEVTEST_PORT" \
    && echo "$out" | grep -q 'Marqueur PR  : oui' \
    && echo "$out" | grep -q 'afSearchHits' \
    && echo "$out" | grep -q './bin/gwsa dev test'; then
    pass "dev test : déploiement + admin + marqueur afSearchHits (hermétique)"
  else
    fail "dev test : résumé incomplet — $(echo "$out" | tail -20 | tr '\n' ' ')"
  fi
  # pidfile port-spécifique (GWSA_ADMIN_PORT) + legacy .admin.pid
  for pf in "$DEVTEST_ROOT/.admin-$DEVTEST_PORT.pid" "$DEVTEST_ROOT/.admin.pid"; do
    if [[ -f "$pf" ]]; then
      apid="$(cat "$pf" 2>/dev/null || true)"
      kill "$apid" 2>/dev/null || true
      rm -f "$pf"
    fi
  done
  lsof -ti "tcp:$DEVTEST_PORT" -sTCP:LISTEN 2>/dev/null | xargs kill 2>/dev/null || true
  rm -rf "$DEVTEST_DEP/$dev_id"
else
  printf '  \033[33m⊘\033[0m dev test hermétique : node absent — ignoré\n'
fi

section "gwsa dev — deploy isolé, use, list, status, remove (hermétique)"
# HOME factice : DEV_PROD_ROOT / DEV_ISOLATED_ROOT vivent sous ~/.config/…
# (jamais le vrai $HOME). client_secret.json = fixture OAuth, pas un secret réel.

DEVCORR_HOME="$TMP/devcorr-home"
DEVCORR_DEP="$TMP/devcorr-deploy"
DEVCORR_CFG="$TMP/devcorr-desktop.json"
DEVCORR_PROD="$DEVCORR_HOME/.config/gws-accounts"
DEVCORR_ISO="$DEVCORR_HOME/.config/gws-accounts-dev"
mkdir -p "$DEVCORR_PROD"
printf '{"installed":{"client_id":"hermetic-test","client_secret":"not-a-real-secret"}}\n' \
  > "$DEVCORR_PROD/client_secret.json"
chmod 600 "$DEVCORR_PROD/client_secret.json"

branch="$(git rev-parse --abbrev-ref HEAD)"
sha="$(git rev-parse --short HEAD)"
part="$(printf '%s' "$branch" | tr '/' '-' | tr -cd 'A-Za-z0-9-')"
[[ -n "$part" ]] || part="branch"
dev_corr_id="dev-${part}-${sha}"
dev_corr_target="$DEVCORR_DEP/$dev_corr_id"
server_name="google-mcp-$dev_corr_id"

out_iso="$(HOME="$DEVCORR_HOME" GWSA_DEPLOY_ROOT="$DEVCORR_DEP" \
  "$GWSA" dev deploy --isolated 2>&1)" || true
if [[ -d "$dev_corr_target" ]] \
  && echo "$out_iso" | grep -q '(isolé)' \
  && [[ -f "$DEVCORR_ISO/client_secret.json" ]] \
  && cmp -s "$DEVCORR_PROD/client_secret.json" "$DEVCORR_ISO/client_secret.json" \
  && DEVCORR_ISO="$DEVCORR_ISO" DEVCORR_TARGET="$dev_corr_target" python3 - <<'PY'
import json, os, stat
iso = os.environ["DEVCORR_ISO"]
target = os.environ["DEVCORR_TARGET"]
mode = os.stat(os.path.join(iso, "client_secret.json")).st_mode & 0o777
assert mode == 0o600, oct(mode)
meta = json.load(open(os.path.join(target, ".dev-meta.json"), encoding="utf-8"))
assert meta.get("isolated") is True, meta
assert meta.get("gwsa_root") == iso, meta
PY
then
  pass "dev deploy --isolated : meta isolated + client_secret.json copié (0600, sans lire le contenu)"
else
  fail "dev deploy --isolated : seed OAuth ou meta incorrect — $(echo "$out_iso" | tail -5 | tr '\n' ' ')"
fi

# Relance : secret déjà présent → pas d'écrasement ni d'erreur
touch -t 202001010000 "$DEVCORR_ISO/client_secret.json"
HOME="$DEVCORR_HOME" GWSA_DEPLOY_ROOT="$DEVCORR_DEP" \
  "$GWSA" dev deploy --isolated >/dev/null 2>&1 || true
if DEVCORR_ISO="$DEVCORR_ISO" python3 - <<'PY'
import os, time
path = os.path.join(os.environ["DEVCORR_ISO"], "client_secret.json")
assert time.localtime(os.path.getmtime(path)).tm_year == 2020
PY
then
  pass "dev deploy --isolated : client_secret existant non écrasé (idempotent)"
else
  fail "dev deploy --isolated : client_secret.json réécrit alors qu'il existait déjà"
fi

if HOME="$DEVCORR_HOME" GWSA_DEPLOY_ROOT="$DEVCORR_DEP" \
  GWSA_DESKTOP_CONFIG="$DEVCORR_CFG" \
  "$GWSA" dev use "$dev_corr_id" --claude-desktop --apply >/dev/null 2>&1 \
  && DEVCORR_CFG="$DEVCORR_CFG" DEVCORR_ISO="$DEVCORR_ISO" \
     DEVCORR_TARGET="$dev_corr_target" SERVER_NAME="$server_name" python3 - <<'PY'
import json, os
cfg = os.environ["DEVCORR_CFG"]
name = os.environ["SERVER_NAME"]
iso = os.environ["DEVCORR_ISO"]
target = os.environ["DEVCORR_TARGET"]
entry = json.load(open(cfg, encoding="utf-8"))["mcpServers"][name]
assert entry["command"] == os.path.join(target, "bin", "google-mcp"), entry
env = entry["env"]
assert env["GWSA_CLIENT"] == "claude-desktop", env
assert env["GWSA_ROOT"] == iso, env
assert env["GWSA_BROKER_PORT"].isdigit(), env
PY
then
  pass "dev use --claude-desktop --apply : JSON MCP correct (config temporaire)"
else
  fail "dev use --claude-desktop --apply : structure JSON incorrecte"
fi

list_out="$(HOME="$DEVCORR_HOME" GWSA_DEPLOY_ROOT="$DEVCORR_DEP" "$GWSA" dev list 2>&1)"
if echo "$list_out" | grep -q "$dev_corr_id" \
  && echo "$list_out" | grep -q "$DEVCORR_ISO"; then
  pass "dev list : version dev + GWSA_ROOT isolé visibles"
else
  fail "dev list : version ou root isolé absent"
fi

status_out="$(HOME="$DEVCORR_HOME" GWSA_DEPLOY_ROOT="$DEVCORR_DEP" \
  "$GWSA" dev status "$dev_corr_id" 2>&1)"
if echo "$status_out" | grep -q "Version $dev_corr_id"; then
  pass "dev status <id> : version dev affichée"
else
  fail "dev status <id> : version absente — $(echo "$status_out" | tr '\n' ' ')"
fi

if HOME="$DEVCORR_HOME" GWSA_DEPLOY_ROOT="$DEVCORR_DEP" \
  "$GWSA" dev remove "$dev_corr_id" >/dev/null 2>&1 \
  && [[ ! -d "$dev_corr_target" ]]; then
  pass "dev remove <id> : version dev supprimée"
else
  fail "dev remove <id> : répertoire encore présent"
fi

rm_stable_out="$(HOME="$DEVCORR_HOME" GWSA_DEPLOY_ROOT="$DEVCORR_DEP" \
  "$GWSA" dev remove v1.0.0 2>&1)" || true
if echo "$rm_stable_out" | grep -q "n'est pas une version dev"; then
  pass "dev remove : refuse une version stable (dev-* uniquement)"
else
  fail "dev remove : aurait dû refuser une version stable — $rm_stable_out"
fi

# --- Bilan ------------------------------------------------------------------

printf '\n\033[1mBilan : %d réussis, %d échoués\033[0m\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
