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
check 4 "chat send — service non modélisé → default-deny"    chat spaces messages create --json '{"text":"hi"}'
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

try:
    api.gmail_list(alias)
    raise SystemExit("gmail_list aurait dû refuser (locked)")
except GatewayError as e:
    assert e.code == "locked", e.code

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
  PASS=$((PASS + 1)); printf '  \033[32m✓\033[0m gateway lock + access_request\n'
else
  FAIL=$((FAIL + 1)); printf '  \033[31m✗\033[0m gateway lock + access_request\n'
fi

# MCP tools/list smoke (stdio JSON-RPC, une requête)
MCP_OUT="$(printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' | python3 -m gateway 2>/dev/null | head -1)"
if echo "$MCP_OUT" | python3 -c 'import json,sys; r=json.load(sys.stdin); names=[t["name"] for t in r["result"]["tools"]]; assert "gmail_list" in names and "gmail_draft_create" in names and "setup_status" in names; assert not any(t["name"]=="gmail_send" for t in r["result"]["tools"]); ar=[t for t in r["result"]["tools"] if t["name"]=="access_request"][0]; assert "add_account" in ar["inputSchema"]["properties"]["kind"]["enum"]'; then
  PASS=$((PASS + 1)); printf '  \033[32m✓\033[0m MCP tools/list (Gmail+Drive+setup_status, pas de send)\n'
else
  FAIL=$((FAIL + 1)); printf '  \033[31m✗\033[0m MCP tools/list\n'
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

srv.shutdown()
print("ok")
PY
then
  PASS=$((PASS + 1)); printf '  \033[32m✓\033[0m broker ping + locked + token\n'
else
  FAIL=$((FAIL + 1)); printf '  \033[31m✗\033[0m broker ping + locked + token\n'
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

# --- Bilan ------------------------------------------------------------------

printf '\n\033[1mBilan : %d réussis, %d échoués\033[0m\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
