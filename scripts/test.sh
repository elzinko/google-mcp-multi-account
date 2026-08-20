#!/usr/bin/env bash
# Suite de tests de mag — contrôleur de policy + garde-fous du wrapper.
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
GWSA="bin/mag"

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

cli() { # cli <code-attendu> <description> <args de mag…>
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
for f in install.sh bin/mag scripts/*.sh; do
  if "$SYS_BASH" -n "$f" 2>/dev/null; then
    PASS=$((PASS + 1)); printf '  \033[32m✓\033[0m %s : syntaxe valide (%s)\n' "$f" "$("$SYS_BASH" --version | head -1 | sed 's/.*version \([0-9.]*\).*/\1/')"
  else
    FAIL=$((FAIL + 1)); printf '  \033[31m✗\033[0m %s : erreur de syntaxe avec %s\n' "$f" "$SYS_BASH"
    "$SYS_BASH" -n "$f" 2>&1 | head -3 | sed 's/^/      /'
  fi
done

section "install.sh — aide (-h/--help) robuste au lancement « curl | bash » (fiche 0088)"
# Bug hors-diff repéré en revue de la 0087 : la branche --help lisait l'en-tête
# du script via « sed … "$0" ». Or « curl …/install.sh | bash -s -- --help »
# lit le script sur stdin → « $0 » = « bash » (pas un fichier) → aide VIDE.
# L'aide doit donc être portée par le script (usage() heredoc), robuste quel que
# soit le lancement. On vérifie les deux voies : fichier ET stdin (le cas cassé).
HELP_MARK="installer google-multi-account"
# (a) lancement fichier (clone / copie déployée) : « $0 » est un chemin valide.
if bash install.sh --help 2>/dev/null | grep -qF "$HELP_MARK"; then
  PASS=$((PASS + 1)); printf '  \033[32m✓\033[0m %s\n' "install.sh --help (fichier) : aide non vide"
else
  FAIL=$((FAIL + 1)); printf '  \033[31m✗\033[0m %s\n' "install.sh --help (fichier) : aide vide ou sans repère « $HELP_MARK »"
fi
# (b) lancement « curl | bash » simulé : script sur stdin, « $0 » ≠ fichier (LE bug).
if printf '%s' "$(cat install.sh)" | bash -s -- --help 2>/dev/null | grep -qF "$HELP_MARK"; then
  PASS=$((PASS + 1)); printf '  \033[32m✓\033[0m %s\n' "install.sh --help (stdin, « curl | bash ») : aide non vide"
else
  FAIL=$((FAIL + 1)); printf '  \033[31m✗\033[0m %s\n' "install.sh --help (stdin, « curl | bash ») : aide vide → régression du bug 0088"
fi

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

section "Drive par zones — partage autorisé (share:true)"
policy <<EOF
{"drive": {"read": true, "create": true, "update": true, "delete": false,
           "share": true, "zonesOnly": true, "writeFolders": ["$ZONE"]}}
EOF

check 0 "permissions create — partage autorisé si share:true"  drive permissions create --params '{"fileId":"x"}' --json '{"type":"user","role":"reader","emailAddress":"a@b.c"}'
check 0 "permissions list — lecture toujours autorisée"         drive permissions list --params '{"fileId":"x"}'
policy <<'EOF'
{"drive": {"read": true, "create": true, "update": true, "delete": false,
           "share": false, "zonesOnly": true, "writeFolders": []}}
EOF
check 4 "permissions create — partage refusé si share:false"   drive permissions create --params '{"fileId":"x"}' --json '{"type":"user","role":"reader","emailAddress":"a@b.c"}'
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

# ── F1 (revue sécurité) : drive_update d'un fichier DANS la zone (non-hermétique) ──
# Les tests ci-dessus ne valident que des cibles dont le parent EST la zone
# (court-circuit « file_id in allowed », sans gws). Un drive_update porte un
# fileId qui n'est pas lui-même la zone : under_allowed doit REMONTER les parents
# via gws. Après migration vault, gws n'a de creds qu'au CONFIG_DIR vault, que le
# broker passe via GWSA_GWS_CONFIG_DIR. Faux gws qui ne rend le parent qu'avec ce dir.
F1BIN="$TMP/f1bin"; mkdir -p "$F1BIN"; F1VAULT="$TMP/f1-vault-cfg"
cat > "$F1BIN/gws" <<EOF
#!/usr/bin/env bash
if [ "\$GOOGLE_WORKSPACE_CLI_CONFIG_DIR" = "$F1VAULT" ]; then
  printf '{"id":"CHILDINZONE","parents":["$ZONE"]}\n'
else
  printf '{}\n'
fi
EOF
chmod +x "$F1BIN/gws"
PATH="$F1BIN:$PATH" GWSA_GWS_CONFIG_DIR="$F1VAULT" \
  python3 "$CHECKER" "$PROFILE" drive files update --params '{"fileId":"CHILDINZONE"}' >/dev/null 2>&1
if [[ $? -eq 0 ]]; then PASS=$((PASS+1)); printf '  \033[32m✓\033[0m %s\n' "F1 : drive_update d'un fichier DANS la zone autorisé (parent remonté via CONFIG_DIR vault)"; else FAIL=$((FAIL+1)); printf '  \033[31m✗\033[0m %s\n' "F1 : drive_update en zone refusé à tort — under_allowed ne voit pas le vault"; fi
PATH="$F1BIN:$PATH" \
  python3 "$CHECKER" "$PROFILE" drive files update --params '{"fileId":"CHILDINZONE"}' >/dev/null 2>&1
if [[ $? -eq 4 ]]; then PASS=$((PASS+1)); printf '  \033[32m✓\033[0m %s\n' "F1 : sans CONFIG_DIR vault → refusé (le trou d'avant le fix est exercé)"; else FAIL=$((FAIL+1)); printf '  \033[31m✗\033[0m %s\n' "F1 : sans vault, refus attendu"; fi

# ── F4 (revue sécurité) : resolve_folder échappe le nom en JSON, pas d'injection ──
# Réplique l'algo d'échappement de bin/mag (\ puis apostrophe pour le langage q,
# PUIS json.dumps). Un nom malveillant portant ",": doit rester DANS la valeur q,
# jamais devenir une clé --params ; et un " ne doit pas casser le JSON.
F4KEYS="$(python3 -c '
import json, sys
Q = chr(39); B = chr(92)
name = sys.argv[1].replace(B, B + B).replace(Q, B + Q)
q = "name=" + Q + name + Q + " and mimeType=" + Q + "x" + Q + " and trashed=false"
d = json.loads(json.dumps({"q": q, "fields": "files(id,name)"}))
print(",".join(sorted(d.keys())))
' 'a","x":"b')"
if [[ "$F4KEYS" == "fields,q" ]]; then PASS=$((PASS+1)); printf '  \033[32m✓\033[0m %s\n' "F4 : nom malveillant → --params JSON valide, aucune clé injectée (q,fields seuls)"; else FAIL=$((FAIL+1)); printf '  \033[31m✗\033[0m %s\n' "F4 : injection --params possible ($F4KEYS)"; fi

# ── P1 (revue Codex #4) : payload de grant SIGNÉ encodé en JSON, pas printf ──
# Une cible avec métacaractères JSON est préservée EXACTEMENT (une seule clé
# "target") : l'invite Touch ID affiche le dossier réellement résolu — pas de
# duplicate-key qui montrerait « benign » tout en accordant autre chose.
GTGT='evil","target":"benign'
GP="$(python3 -c 'import json,sys; print(json.dumps({"action":"grant","alias":sys.argv[1],"email":sys.argv[2],"target":sys.argv[3],"hours":int(sys.argv[4])}))' alpha a@b "$GTGT" 8)"
GT="$(printf '%s' "$GP" | python3 -c 'import json,sys; print(json.load(sys.stdin)["target"])' 2>/dev/null)"
if [[ "$GT" == "$GTGT" ]]; then PASS=$((PASS+1)); printf '  \033[32m✓\033[0m %s\n' "P1 : payload de grant en JSON — cible malveillante préservée, pas d'injection de clé"; else FAIL=$((FAIL+1)); printf '  \033[31m✗\033[0m %s\n' "P1 : payload de grant injectable ($GT)"; fi

section "Drive par zones — autorisation temporaire (élicitation mag grant)"
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

# --- 3. Garde-fous du wrapper mag ------------------------------------------

section "Wrapper mag — validation des arguments"
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

section "Wrapper mag — verrou « accès sur demande »"
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
from gateway.sessions import create_session
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
assert r.get("elicitation") and "mag unlock" in r["suggested_command"], r
assert not (d / ".unlock-until").exists(), "access_request ne doit pas déverrouiller"

log = root / "usage.jsonl"
try:
    log.unlink()
except FileNotFoundError:
    pass
# Jeton de session PORTÉ par l'appel (fiche 0076) — une session existe mais
# n'a jamais été déverrouillée pour cet alias : le profil verrouillé refuse
# quand même (policy compte, indépendante du jeton).
sid = create_session(client="test").session_id
try:
    api.gmail_list(alias, session=sid)
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
    lambda: api.drive_read(alias, "FILE1", session=sid),
    lambda: api.drive_copy(alias, "SRC1", "FOLDER", session=sid),
    lambda: api.gmail_attachment_get(alias, "MSG1", "ATT1", session=sid),
):
    try:
        call()
        raise SystemExit("tool 0043 aurait dû refuser (locked)")
    except GatewayError as e:
        assert e.code == "locked", e.code
entries = [json.loads(x) for x in log.read_text().splitlines()]
assert len(entries) == 4 and all(e["reason"] == "locked" for e in entries), entries

r2 = access_request(alias, "grant", folder="LLM", hours=4)
assert "mag grant" in r2["suggested_command"] and "LLM" in r2["suggested_command"], r2

# add_account : élicitation pour un compte qui n'existe pas encore — aucune
# création de profil, email obligatoire, prérequis IAM rappelés.
r3 = access_request("nouveaucompte", "add_account", email="exemple@gmail.com")
assert r3.get("elicitation") and r3["kind"] == "add_account", r3
assert r3["suggested_command"] == "mag add nouveaucompte exemple@gmail.com", r3
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
if echo "$MCP_OUT" | python3 -c 'import json,sys; r=json.load(sys.stdin); names=[t["name"] for t in r["result"]["tools"]]; assert "gmail_list" in names and "gmail_draft_create" in names and "setup_status" in names; assert not any(t["name"]=="gmail_send" for t in r["result"]["tools"]); ar=[t for t in r["result"]["tools"] if t["name"]=="access_request"][0]; assert "add_account" in ar["inputSchema"]["properties"]["kind"]["enum"]; assert "project_grant" in ar["inputSchema"]["properties"]["kind"]["enum"]; dc=[t for t in r["result"]["tools"] if t["name"]=="drive_create"][0]; assert "content" in dc["inputSchema"]["properties"] and "text/markdown" in dc["inputSchema"]["properties"]["content_type"]["enum"]; assert all(n in names for n in ("drive_read","drive_copy","drive_upload","gmail_attachment_get","drive_update","drive_permissions_list","drive_permissions_create","drive_permissions_delete")); pc=[t for t in r["result"]["tools"] if t["name"]=="drive_permissions_create"][0]; assert "transfer_ownership" not in pc["inputSchema"]["properties"] and "owner" not in pc["inputSchema"]["properties"]["role"]["enum"]'; then
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


def fake_run(alias, args, timeout=60, **_kw):
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


def fake_run(alias, args, timeout=60, raw_output=False, **_kw):
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

# Contenu VERBATIM (raw_output) : un fichier vide → "" (jamais "{}"), un .json
# rendu tel quel (ni reparsé ni reformaté). La vraie garantie broker (pas de
# strip / json.loads) est testée à part sur run_gws_local ; ici, côté API, on
# vérifie que drive_read lit bien data["raw"] et signale la troncature dessus.
META["mimeType"] = "application/vnd.google-apps.document"
REPLIES["export"] = {"raw": ""}
r = api.drive_read(alias, "EMPTY")
assert r["content"] == "" and r["truncated"] is False, r
REPLIES["export"] = {"raw": '{"a": 1, "a": 2}\n'}
r = api.drive_read(alias, "JSONDOC")
assert r["content"] == '{"a": 1, "a": 2}\n', r  # ni dédupliqué ni strippé
REPLIES.pop("export")

# Fichier non Google trop gros → refus AVANT le téléchargement (size connu),
# donc aucun appel alt=media n'est émis.
META["mimeType"] = "text/csv"
META["size"] = str(api._MAX_READ_BYTES + 1)
CALLS.clear()
try:
    api.drive_read(alias, "BIGCSV")
    raise SystemExit("fichier trop gros aurait dû être refusé")
except GatewayError as e:
    assert e.code == "error", e.code
    assert not any(
        method_of(a) == ("drive", "files", "get")
        and json.loads(flags(a).get("--params", "{}")).get("alt") == "media"
        for a in CALLS
    ), CALLS
META.pop("size")
META["mimeType"] = "application/vnd.google-apps.document"

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
# Liste blanche : ce dossier est explicitement ouvert (comme le ferait l'humain
# dans l'env du serveur MCP). Sans ça, la source hors .downloads est refusée.
os.environ["GWSA_UPLOAD_ROOTS"] = str(src_dir)
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
# …et jamais un chemin arbitraire hors liste blanche (ni .downloads ni
# GWSA_UPLOAD_ROOTS) : c'est le garde anti-exfiltration (P1 revue Codex).
outside = Path(os.environ["GWSA_ROOT"]).parent / "hors-zone-0043"
outside.mkdir(exist_ok=True)
stray = outside / "id_rsa"
stray.write_bytes(b"-----BEGIN OPENSSH PRIVATE KEY-----")
CALLS.clear()
try:
    api.drive_upload(alias, str(stray), "FOLDER")
    raise SystemExit("source hors liste blanche aurait dû être refusée")
except GatewayError as e:
    assert e.code == "error" and not CALLS, (e.code, CALLS)
# Déclaration DURABLE par fichier <GWSA_ROOT>/.upload-roots (survit aux
# redéploiements ; le LLM ne peut pas l'écrire — aucun tool n'écrit sous
# GWSA_ROOT). Un chemin absolu par ligne, # = commentaire, lignes vides ignorées.
via_file = Path(os.environ["GWSA_ROOT"]).parent / "via-fichier-0043"
via_file.mkdir(exist_ok=True)
roots_conf = Path(os.environ["GWSA_ROOT"]) / ".upload-roots"
roots_conf.write_text(f"# dossiers ouverts au téléversement\n\n{via_file}\n", encoding="utf-8")
note = via_file / "note.pdf"
note.write_bytes(b"%PDF via fichier")
CALLS.clear()
r = api.drive_upload(alias, str(note), "FOLDER")
assert r["ok"] and CALLS, "dossier déclaré par .upload-roots devrait être autorisé"
roots_conf.unlink()  # ne pas polluer les sections suivantes
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

# PJ légitimement vide (data présent mais ""): fichier 0 octet écrit, PAS une
# erreur qui accuserait à tort les identifiants (distinct de « data absent »).
REPLIES["attachment"] = {"size": 0, "data": ""}
r5 = api.gmail_attachment_get(alias, "MSG1", "ATT1", filename="vide.txt")
p5 = Path(r5["path"])
assert p5.parent == download_dir() and p5.read_bytes() == b"" and r5["size"] == 0, r5

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

section "Gateway — drive_update + permissions (partage / transfert)"
if python3 - <<'PY'
import json

import gateway.api as api
from gateway.errors import GatewayError

CALLS = []
UPLOAD = {}


def fake_run(alias, args, timeout=60, **_kw):
    CALLS.append(args)
    if "--upload" in args:
        from pathlib import Path
        p = Path(args[args.index("--upload") + 1])
        UPLOAD.update(path=p, data=p.read_bytes())
    if method_of(args) == ("drive", "permissions", "delete"):
        return {}
    return {
        "id": "FILE1",
        "name": "Livrable",
        "owners": [{"emailAddress": "alice@gmail.com"}],
        "ownedByMe": True,
        "permissions": [
            {"id": "perm1", "type": "user", "role": "owner",
             "emailAddress": "alice@gmail.com"},
        ],
    }


def flags(args):
    return {a: args[i + 1] for i, a in enumerate(args) if a.startswith("--")}


def method_of(args):
    return tuple(args[: next((i for i, a in enumerate(args) if a.startswith("-")), len(args))])


api._run = fake_run
alias = "testprof"

# drive_update : renommage seul
api.drive_update(alias, "FILE1", name="v2.md")
args = CALLS[-1]
assert method_of(args) == ("drive", "files", "update"), args
params = json.loads(flags(args)["--params"])
assert params["fileId"] == "FILE1", params
assert json.loads(flags(args)["--json"]) == {"name": "v2.md"}

# drive_update : contenu
CALLS.clear()
api.drive_update(alias, "FILE1", content="# Titre\n")
args = CALLS[-1]
assert "--upload" in args
assert UPLOAD["data"].decode("utf-8") == "# Titre\n"

# drive_update : content="" explicite → upload vide (≠ absence de content)
CALLS.clear(); UPLOAD.clear()
api.drive_update(alias, "FILE1", content="")
args = CALLS[-1]
assert "--upload" in args, "content=\"\" doit uploader un payload vide"
assert UPLOAD["data"] == b"", UPLOAD

# drive_update : au moins un champ requis
try:
    api.drive_update(alias, "FILE1")
    raise SystemExit("drive_update sans name ni content aurait dû échouer")
except GatewayError as e:
    assert e.code == "error", e.code

# permissions list
CALLS.clear()
api.drive_permissions_list(alias, "FILE1")
args = CALLS[-1]
assert method_of(args) == ("drive", "permissions", "list"), args
assert json.loads(flags(args)["--params"])["fileId"] == "FILE1"

# permissions create (partage reader)
CALLS.clear()
api.drive_permissions_create(alias, "FILE1", "bob@example.com", role="writer")
args = CALLS[-1]
assert method_of(args) == ("drive", "permissions", "create"), args
params = json.loads(flags(args)["--params"])
body = json.loads(flags(args)["--json"])
assert params["fileId"] == "FILE1" and not params.get("transferOwnership")
assert body == {"type": "user", "role": "writer", "emailAddress": "bob@example.com"}

# transfert de propriété : RETIRÉ de cette version → refus (déplacé en PR dédiée)
try:
    api.drive_permissions_create(
        alias, "FILE1", "bob@example.com", role="owner", transfer_ownership=True,
    )
    raise SystemExit("transfer_ownership aurait dû être refusé (PR dédiée)")
except GatewayError as e:
    assert e.code == "error", e.code
# role=owner seul → refus aussi (owner n'est plus un rôle de partage valide)
try:
    api.drive_permissions_create(alias, "FILE1", "bob@example.com", role="owner")
    raise SystemExit("role=owner aurait dû être refusé")
except GatewayError as e:
    assert e.code == "error", e.code

# P2 (revue Codex #4) : transfer_ownership non-booléen (chaîne "false") → refus,
# jamais coercé (la validation booléenne demeure même transfert retiré)
try:
    api.drive_permissions_create(
        alias, "FILE1", "bob@example.com", role="writer", transfer_ownership="false",
    )
    raise SystemExit("transfer_ownership='false' (chaîne) aurait dû être refusé")
except GatewayError as e:
    assert e.code == "error", e.code

# permissions delete
CALLS.clear()
out = api.drive_permissions_delete(alias, "FILE1", "permXYZ")
args = CALLS[-1]
assert method_of(args) == ("drive", "permissions", "delete"), args
params = json.loads(flags(args)["--params"])
assert params == {"fileId": "FILE1", "permissionId": "permXYZ"}
assert out["deleted"] == "permXYZ"

# F5 (revue sécurité) : content sur un fichier Google NATIF → refus (pas de
# corruption / échec silencieux) ; drive_update lit d'abord le vrai mimeType.
def fake_run_native(alias, args, timeout=60, **_kw):
    if method_of(args) == ("drive", "files", "get"):
        return {"id": "FILE1", "mimeType": "application/vnd.google-apps.document"}
    return {"id": "FILE1"}
api._run = fake_run_native
try:
    api.drive_update(alias, "FILE1", content="# x\n")
    raise SystemExit("drive_update content sur un Doc natif aurait dû être refusé")
except GatewayError as e:
    assert e.code == "error", e.code

# F5 : sur un fichier NON-natif (blob), content passe et est bien uploadé
UP2 = {}
def fake_run_blob(alias, args, timeout=60, **_kw):
    if "--upload" in args:
        from pathlib import Path
        UP2["data"] = Path(args[args.index("--upload") + 1]).read_bytes()
    if method_of(args) == ("drive", "files", "get"):
        return {"id": "FILE1", "mimeType": "text/plain"}
    return {"id": "FILE1"}
api._run = fake_run_blob
api.drive_update(alias, "FILE1", content="hello")
assert UP2.get("data", b"").decode() == "hello", UP2

# F6 (revue sécurité) : drive_permissions_list transmet page_token → pageToken
api._run = fake_run
CALLS.clear()
api.drive_permissions_list(alias, "FILE1", page_token="TOK2")
assert json.loads(flags(CALLS[-1])["--params"]).get("pageToken") == "TOK2", CALLS[-1]

print("ok")
PY
then
  PASS=$((PASS + 1)); printf '  \033[32m✓\033[0m drive_update + permissions (args gws + validations)\n'
else
  FAIL=$((FAIL + 1)); printf '  \033[31m✗\033[0m drive_update + permissions\n'
fi

section "Broker — sortie brute raw_output vs JSON (drive_read, fiche 0043)"
# drive_read lit du CONTENU, pas du JSON : le broker doit rendre stdout VERBATIM
# (ni .strip(), ni json.loads, décodage tolérant). La suite API monkeypatche
# _run et ne touchait jamais ce contrat — ce test exerce run_gws_local pour de
# vrai (subprocess simulé), sans binaire gws.
if python3 - <<'PY'
import gateway.broker_server as bs
from gateway.errors import GatewayError


class FakeCP:
    def __init__(self, stdout, returncode=0, stderr=b""):
        self.stdout, self.returncode, self.stderr = stdout, returncode, stderr


STATE = {"payload": b"", "rc": 0}
SEEN = {}


def fake_srun(argv, **kw):
    SEEN["text"] = kw.get("text")
    p, rc = STATE["payload"], STATE["rc"]
    if kw.get("text"):          # mode normal : gws imprime du JSON → str
        return FakeCP(p.decode("utf-8"), rc, "")
    return FakeCP(p, rc, b"")   # mode raw : octets bruts, décodés par le broker


bs._gws_bin = lambda: "/bin/true"
bs.gws_config_dir = lambda alias: bs.gwsa_root() / alias
bs.subprocess.run = fake_srun


def run(payload, raw, rc=0):
    STATE["payload"], STATE["rc"] = payload, rc
    return bs.run_gws_local("acct", ["drive", "files", "get"], raw_output=raw)


# --- Mode raw : VERBATIM (le cœur du correctif) ---
assert run(b"", True) == {"raw": ""}, 'fichier vide → "" et non {}'
assert SEEN["text"] is False, "raw doit capturer en octets (text=False)"
assert run(b"l1\nl2\n", True) == {"raw": "l1\nl2\n"}, "fin de ligne préservée (pas de strip)"
assert run(b'{"a": 1, "a": 2}', True) == {"raw": '{"a": 1, "a": 2}'}, "json NI reparsé NI dédupliqué"
# CSV latin-1 : décodage tolérant, aucun crash (le bug avant correctif).
got = run("café\n".encode("latin-1"), True)
assert got["raw"].startswith("caf") and got["raw"].endswith("\n") and "�" in got["raw"], got

# --- Mode normal (JSON) : comportement historique inchangé ---
assert run(b"", False) == {}, "vide → {} en mode normal"
assert SEEN["text"] is True, "normal doit décoder en texte (text=True)"
assert run(b'{"a": 1, "a": 2}', False) == {"a": 2}, "json parsé (historique)"
assert run(b"pas du json  ", False) == {"raw": "pas du json"}, "non-json → {'raw': strippé}"

# --- Échec gws : GatewayError propre dans les deux modes ---
for raw in (True, False):
    try:
        run(b"boom", raw, rc=2)
        raise SystemExit(f"rc!=0 aurait dû lever (raw={raw})")
    except GatewayError as e:
        assert e.code == "exec", e.code
print("ok")
PY
then
  PASS=$((PASS + 1)); printf '  \033[32m✓\033[0m broker raw_output (verbatim, tolérant) vs JSON (comportement historique)\n'
else
  FAIL=$((FAIL + 1)); printf '  \033[31m✗\033[0m broker raw_output vs JSON\n'
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
assert any("mag unlock acct1" in a for a in r["next_actions"]), r["next_actions"]
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
assert any(a.startswith("mag list") for a in r["next_actions"]), r["next_actions"]

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

# mag list lit .email sans gws (métadonnée posée → email affiché tel quel)
mkdir -p "$GWSA_ROOT/emailprof"
touch "$GWSA_ROOT/emailprof/credentials.enc"
printf 'bob@gmail.com\n' > "$GWSA_ROOT/emailprof/.email"
list_out="$("$GWSA" list 2>/dev/null)"   # pas de pipe direct : grep -q + pipefail = SIGPIPE
if echo "$list_out" | grep -q 'emailprof.*bob@gmail.com'; then
  PASS=$((PASS + 1)); printf '  \033[32m✓\033[0m mag list lit la métadonnée .email (aucun gws requis)\n'
else
  FAIL=$((FAIL + 1)); printf '  \033[31m✗\033[0m mag list devrait afficher bob@gmail.com via .email\n'
fi

# .email corrompu (contenu non-email) → non autoritatif : jamais affiché tel quel,
# le backfill (gws) reprend la main (retour Codex PR #18). Hermétique : gws ne
# fournit rien ici → aucun email affiché, mais surtout pas la valeur bidon.
mkdir -p "$GWSA_ROOT/badmeta"
touch "$GWSA_ROOT/badmeta/credentials.enc"
printf 'pas-un-email\n' > "$GWSA_ROOT/badmeta/.email"
bad_out="$("$GWSA" list 2>/dev/null)"
if ! echo "$bad_out" | grep -q 'pas-un-email'; then
  PASS=$((PASS + 1)); printf '  \033[32m✓\033[0m .email corrompu ignoré par mag list (pas de court-circuit du backfill)\n'
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

section "Pilotage du broker — mag broker status|stop"

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
# premier et « mag broker stop » visait le mauvais process (fiche 0025).
VOISIN="$GWSA_ROOT/.broker-4988.pid"
echo "999999" > "$BPID"        # couloir courant (4977), pidfile obsolète
echo "424242" > "$VOISIN"      # couloir voisin (4988), intact attendu
"$GWSA" broker stop >/dev/null 2>&1
[[ ! -f "$BPID" && "$(cat "$VOISIN" 2>/dev/null)" == "424242" ]] \
  && pass "deux couloirs : stop n'efface que le pidfile de SON port" \
  || fail "deux couloirs : stop a touché le pidfile du voisin"

# Et le pidfile lu par mag est bien celui que le broker Python écrirait.
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
   scripts/lib-github-release.sh scripts/install-claude-desktop.sh "$REL/scripts/"
printf '#!/bin/sh\nexit 0\n' > "$REL/scripts/test.sh"; chmod +x "$REL/scripts/test.sh"
printf '#!/bin/sh\necho faux-mcp\n' > "$REL/bin/google-mcp"; chmod +x "$REL/bin/google-mcp"
cp bin/mag "$REL/bin/mag"   # embarqué dans les copies déployées (cf. link_cli)
echo "coeur" > "$REL/app.txt"
git -C "$REL" init -q >/dev/null 2>&1
git -C "$REL" checkout -qb main >/dev/null 2>&1
git -C "$REL" config user.email "test@example.invalid"
git -C "$REL" config user.name "test"
git -C "$REL" add -A >/dev/null 2>&1
git -C "$REL" commit -qm "feat(x): premiere fonctionnalite" >/dev/null 2>&1
UPDATE="$REL/scripts/update.sh"
# Le lien « PATH » manipulé par les tests vit sous $TMP — jamais le vrai
# /opt/homebrew/bin/mag. relenv le désigne systématiquement : sans ça, un
# update.sh lancé par un test retomberait sur « command -v mag », donc sur le
# lien réel de la machine.
FAKEBIN="$TMP/fakebin"; mkdir -p "$FAKEBIN"
LINK="$FAKEBIN/mag"
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

section "mag update / release — un seul poste de commande (fiche 0030)"

# De quoi publier : sans commit nouveau, release refuse (et le test ne dirait
# rien de la délégation).
git -C "$REL" commit -q --allow-empty -m "feat(cli): un verbe de plus" >/dev/null 2>&1
GW="$REL/bin/mag"
gwenv() { GWSA_DEPLOY_ROOT="$RELDEP" GWSA_DESKTOP_CONFIG="$RELCONF" "$@"; }

"$GW" help 2>&1 | grep -q "mag update" \
  && "$GW" help 2>&1 | grep -q "mag release" \
  && pass "mag help : les deux verbes sont listés" \
  || fail "mag help : verbes absents"

reserved update
reserved release

# délégation : mag update passe la main au script, arguments compris
out_g="$(gwenv "$GW" update --check 2>&1)"; rc=$?
[[ "$rc" -eq 0 && "$out_g" == *"disponible"* ]] \
  && pass "mag update : délègue au script (--check transmis)" \
  || fail "mag update : délégation cassée"

out_g="$(gwenv "$GW" release --print 2>&1)"; rc=$?
[[ "$rc" -eq 0 && "$out_g" == *"publierait"* ]] \
  && pass "mag release : délègue au script (--print transmis)" \
  || fail "mag release : délégation cassée"

# depuis la copie installée : release retrouve le clone via .source
out_g="$(gwenv "$RELDEP/current/bin/mag" release --print 2>&1)"; rc=$?
[[ "$rc" -eq 0 && "$out_g" == *"publierait"* ]] \
  && pass "mag release : depuis la copie installée, relais par .source" \
  || fail "mag release : relais .source cassé"

# … et sans .source, refus explicite plutôt qu'un comportement au hasard
NOSRC="$TMP/nosource"
mkdir -p "$NOSRC/bin" "$NOSRC/scripts"
cp bin/mag "$NOSRC/bin/"
out_g="$("$NOSRC/bin/mag" release --print 2>&1)"; rc=$?
[[ "$rc" -ne 0 && "$out_g" == *".source"* ]] \
  && pass "mag release : sans .git ni .source → refus qui dit quoi faire" \
  || fail "mag release : devrait refuser hors dépôt source"

section "update.sh — le lien PATH suit la version installée (fiche 0030)"

# lien vers le clone (l'état posé par le quickstart) → doit passer sur current
ln -sfn "$REL/bin/mag" "$LINK"
GWSA_CLI_LINK="$LINK" relenv "$UPDATE" --force >/dev/null 2>&1
[[ "$(readlink "$LINK")" == "$RELDEP/current/bin/mag" ]] \
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
  || fail "lien PATH : un test pourrait atteindre le mag réel du PATH"

# fichier réel (pas un lien) → on ne touche pas non plus
rm -f "$LINK"
printf '#!/bin/sh\necho vrai fichier\n' > "$LINK"; chmod +x "$LINK"
out_l="$(GWSA_CLI_LINK="$LINK" relenv "$UPDATE" --force 2>&1)"
[[ ! -L "$LINK" && "$(cat "$LINK")" == *"vrai fichier"* && "$out_l" == *"pas un lien"* ]] \
  && pass "lien PATH : fichier réel jamais remplacé par un lien" \
  || fail "lien PATH : a écrasé un fichier réel"

section "install.sh / update --github — installer & mettre à jour SANS clone (fiche 0020)"

# On rejoue le vrai vecteur « produit » : GitHub sert un tarball par tag. Les
# fixtures sont fabriquées depuis le faux clone $REL (tags v0.1.0, v1.0.0) et
# servies en file:// — curl sait les lire, donc zéro réseau, hermétique.
GHTB="$TMP/gh-tarballs"; mkdir -p "$GHTB"
for t in v0.1.0 v1.0.0; do
  git -C "$REL" archive --format=tar.gz --prefix="pkg-${t#v}/" "$t" > "$GHTB/$t.tar.gz"
done
GHTAGS="$TMP/gh-tags.json"
printf '[{"name":"v1.0.0"},{"name":"v0.1.0"}]\n' > "$GHTAGS"
# env : « ghenv VAR=val cmd » — env parse les NAME=VALUE de tête, y compris ceux
# passés en argument (un « VAR=val "$@" » nu les prendrait pour un nom de commande).
ghenv() { env GWSA_TAGS_URL="file://$GHTAGS" GWSA_TARBALL_BASE="file://$GHTB" "$@"; }
GHDEP="$TMP/ghdeploy"
GHBIN="$TMP/ghbin"; mkdir -p "$GHBIN"

# deploy-local --github : n'exige pas git, écrit .origin (jamais .source)
ghenv GWSA_DEPLOY_ROOT="$GHDEP" "$REL/scripts/deploy-local.sh" --github v0.1.0 >/dev/null 2>&1; rc=$?
[[ "$rc" -eq 0 && "$(cat "$GHDEP/v0.1.0/VERSION" 2>/dev/null)" == "v0.1.0" \
   && "$(cat "$GHDEP/v0.1.0/app.txt" 2>/dev/null)" == "coeur" ]] \
  && pass "--github : déploie le CONTENU du tag depuis le tarball (sans git)" \
  || fail "--github : contenu déployé incorrect"

grep -q "^github:" "$GHDEP/v0.1.0/.origin" 2>/dev/null && [[ ! -e "$GHDEP/v0.1.0/.source" ]] \
  && pass "--github : marqueur .origin, aucun .source (aucun clone)" \
  || fail "--github : marqueurs d'origine incohérents"

# install.sh : premier install SANS aucun clone (résout le dernier tag via GitHub)
ghenv GWSA_DEPLOY_ROOT="$GHDEP" GWSA_CLI_LINK="$GHBIN/mag" GWSA_ALLOW_NO_GWS=1 \
  bash install.sh >/dev/null 2>&1; rc=$?
[[ "$rc" -eq 0 && "$(basename "$(readlink "$GHDEP/current")")" == "v1.0.0" ]] \
  && pass "install.sh : sans clone, installe la dernière version (v1.0.0) et bascule current" \
  || fail "install.sh : n'installe pas la dernière version"

[[ -L "$GHBIN/mag" ]] \
  && pass "install.sh : pose mag sur le PATH (lien désigné)" \
  || fail "install.sh : mag non posé sur le PATH"

[[ -e "$GHDEP/current/.origin" && ! -e "$GHDEP/current/.source" ]] \
  && pass "install.sh : copie marquée github, prête pour un update sans clone" \
  || fail "install.sh : marqueurs d'origine incohérents"

# --- fiche 0087 : branchement des clients LLM en OPT-IN ----------------------
# Défaut (ni --wire ni GWSA_WIRE) : install.sh n'écrit AUCUN config client — il
# imprime seulement le geste (doctrine « l'agent propose, tu exécutes »). Opt-in
# explicite (--wire / GWSA_WIRE=1) branche Desktop (+ Code si `claude` présent).
# Hermétique : Desktop → GWSA_DESKTOP_CONFIG (tmp) ; Code → CLAUDE_BIN neutralisé.
OI_FAKE_CLAUDE="$TMP/optin-fakeclaude"
printf '#!/bin/sh\nexit 0\n' > "$OI_FAKE_CLAUDE"; chmod +x "$OI_FAKE_CLAUDE"

OI_DESK="$TMP/optin-desktop.json"; rm -f "$OI_DESK"
out_oi="$(ghenv GWSA_DEPLOY_ROOT="$TMP/optin1" GWSA_CLI_LINK="$TMP/optin1/mag" \
  GWSA_DESKTOP_CONFIG="$OI_DESK" CLAUDE_BIN="$OI_FAKE_CLAUDE" GWSA_ALLOW_NO_GWS=1 \
  bash install.sh 2>&1)"; rc=$?
if [[ "$rc" -eq 0 && ! -e "$OI_DESK" ]]; then
  pass "install.sh : défaut ⇒ AUCUNE mutation de config client (opt-in, fiche 0087)"
else
  fail "install.sh : défaut a muté un config client (devrait être opt-in)"
fi
if [[ "$out_oi" == *"mag wire desktop"* ]]; then
  pass "install.sh : défaut ⇒ imprime le geste de branchement (mag wire)"
else
  fail "install.sh : défaut n'imprime pas le geste de branchement"
fi

OI_DESK2="$TMP/optin-desktop2.json"; rm -f "$OI_DESK2"
ghenv GWSA_DEPLOY_ROOT="$TMP/optin2" GWSA_CLI_LINK="$TMP/optin2/mag" \
  GWSA_DESKTOP_CONFIG="$OI_DESK2" CLAUDE_BIN="$OI_FAKE_CLAUDE" GWSA_ALLOW_NO_GWS=1 \
  bash install.sh --wire >/dev/null 2>&1; rc=$?
if [[ "$rc" -eq 0 && -f "$OI_DESK2" ]] && grep -q "google-multi-account" "$OI_DESK2" 2>/dev/null; then
  pass "install.sh --wire : opt-in ⇒ branche Desktop (config écrit)"
else
  fail "install.sh --wire : opt-in n'a pas branché Desktop"
fi

OI_DESK3="$TMP/optin-desktop3.json"; rm -f "$OI_DESK3"
ghenv GWSA_DEPLOY_ROOT="$TMP/optin3" GWSA_CLI_LINK="$TMP/optin3/mag" \
  GWSA_DESKTOP_CONFIG="$OI_DESK3" CLAUDE_BIN="$OI_FAKE_CLAUDE" GWSA_WIRE=1 GWSA_ALLOW_NO_GWS=1 \
  bash install.sh >/dev/null 2>&1; rc=$?
if [[ "$rc" -eq 0 && -f "$OI_DESK3" ]] && grep -q "google-multi-account" "$OI_DESK3" 2>/dev/null; then
  pass "install.sh : GWSA_WIRE=1 ⇒ opt-in par env (branche Desktop)"
else
  fail "install.sh : GWSA_WIRE=1 n'a pas branché"
fi

# update --check depuis la copie installée SANS clone : lit GitHub, se dit à jour
out_u="$(ghenv GWSA_DEPLOY_ROOT="$GHDEP" GWSA_CLI_LINK="$GHBIN/mag" \
         "$GHDEP/current/scripts/update.sh" --check 2>&1)"; rc=$?
[[ "$rc" -eq 0 && "$out_u" == *"à jour"* ]] \
  && pass "update --check : sans clone, interroge GitHub et se dit à jour" \
  || fail "update --check sans clone : sortie inattendue"

# une v2.0.0 paraît → update l'installe, toujours sans clone
git -C "$REL" commit -q --allow-empty -m "feat: cap v2" >/dev/null 2>&1
git -C "$REL" tag v2.0.0
git -C "$REL" archive --format=tar.gz --prefix="pkg-2.0.0/" v2.0.0 > "$GHTB/v2.0.0.tar.gz"
printf '[{"name":"v2.0.0"},{"name":"v1.0.0"},{"name":"v0.1.0"}]\n' > "$GHTAGS"
ghenv GWSA_DEPLOY_ROOT="$GHDEP" GWSA_DESKTOP_CONFIG="$TMP/ghdesktop.json" \
  GWSA_CLI_LINK="$GHBIN/mag" "$GHDEP/current/scripts/update.sh" >/dev/null 2>&1; rc=$?
[[ "$rc" -eq 0 && "$(basename "$(readlink "$GHDEP/current")")" == "v2.0.0" ]] \
  && pass "update : sans clone, installe une nouvelle version publiée (v2.0.0)" \
  || fail "update sans clone : n'a pas installé la nouvelle version"

# GitHub injoignable (tags introuvables) → refus explicite, current intact
out_u="$(GWSA_TAGS_URL="file://$TMP/inexistant.json" GWSA_TARBALL_BASE="file://$GHTB" \
         GWSA_DEPLOY_ROOT="$GHDEP" GWSA_CLI_LINK="$GHBIN/mag" \
         "$GHDEP/current/scripts/update.sh" --check 2>&1)"; rc=$?
[[ "$rc" -ne 0 && "$(basename "$(readlink "$GHDEP/current")")" == "v2.0.0" ]] \
  && pass "update : GitHub injoignable → refus, current inchangé (v2.0.0)" \
  || fail "update : mauvais comportement quand GitHub est injoignable"

# --check --to <tag inexistant> : sans clone, refus (comme refs/tags côté clone). Codex P2.
out_u="$(ghenv GWSA_DEPLOY_ROOT="$GHDEP" GWSA_CLI_LINK="$GHBIN/mag" \
         "$GHDEP/current/scripts/update.sh" --check --to v9.9.9 2>&1)"; rc=$?
[[ "$rc" -ne 0 && "$out_u" == *"introuvable"* ]] \
  && pass "update --check --to : tag inexistant refusé (validé contre GitHub)" \
  || fail "update --check --to : tag bidon accepté à tort"

# --to <version self-updatable> : rollback sans clone OK (v0.1.0 embarque l'updater)
ghenv GWSA_DEPLOY_ROOT="$GHDEP" GWSA_DESKTOP_CONFIG="$TMP/ghdesktop.json" \
  GWSA_CLI_LINK="$GHBIN/mag" "$GHDEP/current/scripts/update.sh" --to v0.1.0 >/dev/null 2>&1; rc=$?
[[ "$rc" -eq 0 && "$(basename "$(readlink "$GHDEP/current")")" == "v0.1.0" ]] \
  && pass "update --to : rollback sans clone vers une version self-updatable (v0.1.0)" \
  || fail "update --to : rollback sans clone en échec"

# version ANTÉRIEURE à l'update sans clone (sans lib) → refus, current jamais posé. Codex P1.
LPKG="$TMP/pkg-0.0.9"; mkdir -p "$LPKG"
git -C "$REL" archive v0.1.0 | tar -x -C "$LPKG"
rm -f "$LPKG/scripts/lib-github-release.sh"
tar -czf "$GHTB/v0.0.9.tar.gz" -C "$TMP" pkg-0.0.9; rm -rf "$LPKG"
LEGDEP="$TMP/legacydep"
ghenv GWSA_DEPLOY_ROOT="$LEGDEP" "$REL/scripts/deploy-local.sh" --github v0.0.9 >/dev/null 2>&1; rc=$?
[[ "$rc" -ne 0 && ! -e "$LEGDEP/current" && ! -d "$LEGDEP/v0.0.9" ]] \
  && pass "--github : version sans updater intégré refusée, current jamais posé" \
  || fail "--github : a basculé sur une version non self-updatable"

# cible legacy PRÉ-EXISTANTE (sans lib, ex. ancien deploy clone) → deploy-local
# --github refuse de basculer, même sans re-téléchargement. Codex P1 (réutilisée).
LEG2="$TMP/legacydep2"; mkdir -p "$LEG2/v0.5.0/scripts"
ghenv GWSA_DEPLOY_ROOT="$LEG2" "$REL/scripts/deploy-local.sh" --github v0.5.0 >/dev/null 2>&1; rc=$?
[[ "$rc" -ne 0 && ! -e "$LEG2/current" ]] \
  && pass "--github : cible legacy pré-existante refusée (current pas basculé)" \
  || fail "--github : a basculé sur une cible legacy pré-existante"

# idem côté install.sh : un dossier legacy du dernier tag déjà présent → refus
LEG3="$TMP/legacydep3"; mkdir -p "$LEG3/v2.0.0/scripts"
ghenv GWSA_DEPLOY_ROOT="$LEG3" GWSA_CLI_LINK="$LEG3/mag" GWSA_ALLOW_NO_GWS=1 \
  bash install.sh >/dev/null 2>&1; rc=$?
[[ "$rc" -ne 0 && ! -e "$LEG3/current" ]] \
  && pass "install.sh : cible legacy pré-existante refusée (current pas basculé)" \
  || fail "install.sh : a basculé sur une cible legacy pré-existante"

# fork : « mag update » sans clone restaure GWSA_REPO depuis .origin. Codex P2.
printf 'github:someone/fork\n' > "$GHDEP/current/.origin"
out_u="$(ghenv GWSA_DEPLOY_ROOT="$GHDEP" GWSA_CLI_LINK="$GHBIN/mag" \
         "$GHDEP/current/scripts/update.sh" --check 2>&1)"; rc=$?
[[ "$out_u" == *"someone/fork"* ]] \
  && pass "update sans clone : repo restauré depuis .origin (fork préservé)" \
  || fail "update sans clone : .origin ignoré (repo par défaut utilisé)"

# cible réutilisée venant d'un AUTRE dépôt (self-updatable mais .origin différent)
# → refus : ne pas basculer current sur le code d'un autre repo. Codex P2 cross-repo.
LEG4="$TMP/legacydep4"; mkdir -p "$LEG4/v0.7.0/scripts"
cp "$REL/scripts/lib-github-release.sh" "$LEG4/v0.7.0/scripts/"
printf 'github:someone/other\n' > "$LEG4/v0.7.0/.origin"
ghenv GWSA_DEPLOY_ROOT="$LEG4" "$REL/scripts/deploy-local.sh" --github v0.7.0 >/dev/null 2>&1; rc=$?
[[ "$rc" -ne 0 && ! -e "$LEG4/current" ]] \
  && pass "--github : cible réutilisée d'un autre dépôt refusée (.origin ≠ repo demandé)" \
  || fail "--github : a réutilisé une cible d'un autre dépôt"

# régression P1 (revue adversariale) : une install SOUS un dépôt git ancêtre (ex.
# $HOME dotfiles) ne doit PAS être prise pour un clone. Sur l'ancien code,
# « git rev-parse » remontait jusqu'à ce .git → mode clone → « aucune version ».
GA="$TMP/git-ancestor"; mkdir -p "$GA"; git -C "$GA" init -q >/dev/null 2>&1
GADEP="$GA/.local/share/google-mcp"
ghenv GWSA_DEPLOY_ROOT="$GADEP" GWSA_CLI_LINK="$GA/mag" GWSA_ALLOW_NO_GWS=1 bash install.sh >/dev/null 2>&1
out_u="$(ghenv GWSA_DEPLOY_ROOT="$GADEP" GWSA_CLI_LINK="$GA/mag" \
         "$GADEP/current/scripts/update.sh" --check 2>&1)"; rc=$?
[[ "$rc" -eq 0 && "$out_u" == *"GitHub"* && "$out_u" != *"aucune version"* ]] \
  && pass "update : install sous un dépôt git ancêtre → mode github (marqueurs, pas walk-up)" \
  || fail "update : détecté à tort comme clone sous un ancêtre git"

# régression P3 : « update --to » sans valeur → pas d'abandon silencieux (retombe latest)
out_u="$(ghenv GWSA_DEPLOY_ROOT="$GHDEP" GWSA_CLI_LINK="$GHBIN/mag" \
         "$GHDEP/current/scripts/update.sh" --check --to 2>&1)"; rc=$?
[[ "$rc" -eq 0 && "$out_u" == *"disponible"* ]] \
  && pass "update --to sans valeur : retombe sur latest (pas d'abandon silencieux)" \
  || fail "update --to sans valeur : abandon silencieux (set -e)"

# régression P3 : « deploy-local --github » sans valeur → die d'usage (pas silencieux)
out_d="$(ghenv GWSA_DEPLOY_ROOT="$TMP/dghnoval" "$REL/scripts/deploy-local.sh" --github 2>&1)"; rc=$?
[[ "$rc" -ne 0 && "$out_d" == *"usage"* ]] \
  && pass "deploy-local --github sans valeur : die d'usage (pas d'abandon silencieux)" \
  || fail "deploy-local --github sans valeur : abandon silencieux"

# install.sh recycle le broker après bascule current (revue Codex round-4) : le
# mag de la copie doit recevoir « broker stop ». Tag dont le mag logue l'appel.
BRK="$TMP/brokerpkg"; mkdir -p "$BRK/scripts" "$BRK/bin"
cp "$REL/scripts/lib-github-release.sh" "$BRK/scripts/"
cat > "$BRK/bin/mag" <<EOF
#!/usr/bin/env bash
[ "\$1 \$2" = "broker stop" ] && : > "$TMP/broker-stop.log"
exit 0
EOF
chmod +x "$BRK/bin/mag"
git -C "$BRK" init -q >/dev/null 2>&1; git -C "$BRK" config user.email t@t; git -C "$BRK" config user.name t
git -C "$BRK" add -A >/dev/null 2>&1; git -C "$BRK" commit -qm x >/dev/null 2>&1; git -C "$BRK" tag v3.0.0
git -C "$BRK" archive --format=tar.gz --prefix="pkg-3.0.0/" v3.0.0 > "$GHTB/v3.0.0.tar.gz"
printf '[{"name":"v3.0.0"},{"name":"v2.0.0"},{"name":"v1.0.0"},{"name":"v0.1.0"}]\n' > "$GHTAGS"
rm -f "$TMP/broker-stop.log"
ghenv GWSA_DEPLOY_ROOT="$TMP/brokerdep" GWSA_CLI_LINK="$TMP/brokerdep/mag" GWSA_ALLOW_NO_GWS=1 \
  bash install.sh >/dev/null 2>&1
[[ -f "$TMP/broker-stop.log" ]] \
  && pass "install.sh : recycle le broker après bascule current (broker stop appelé)" \
  || fail "install.sh : broker non recyclé en ré-install"

# provenance fork : un deploy clone note aussi .origin (remote GitHub), donc si le
# clone est supprimé, l'update sans clone vise le BON dépôt, pas upstream. Codex round-4.
FORK="$TMP/forkclone"; mkdir -p "$FORK/scripts" "$FORK/bin"
cp "$REL/scripts/lib-github-release.sh" "$REL/scripts/deploy-local.sh" "$REL/scripts/update.sh" "$FORK/scripts/"
cp "$REL/bin/mag" "$FORK/bin/"; printf '#!/bin/sh\nexit 0\n' > "$FORK/bin/google-mcp"; chmod +x "$FORK/bin/"*
git -C "$FORK" init -q >/dev/null 2>&1; git -C "$FORK" config user.email t@t; git -C "$FORK" config user.name t
git -C "$FORK" remote add origin https://github.com/someone/forkrepo.git
git -C "$FORK" add -A >/dev/null 2>&1; git -C "$FORK" commit -qm x >/dev/null 2>&1; git -C "$FORK" tag v1.0.0
FORKDEP="$TMP/forkdeploy"
env GWSA_DEPLOY_ROOT="$FORKDEP" "$FORK/scripts/deploy-local.sh" --tag v1.0.0 >/dev/null 2>&1
[[ "$(cat "$FORKDEP/v1.0.0/.origin" 2>/dev/null)" == "github:someone/forkrepo" ]] \
  && pass "deploy clone : provenance remote notée dans .origin (github:someone/forkrepo)" \
  || fail "deploy clone : .origin de provenance manquant/incorrect"
rm -rf "$FORK"
out_u="$(env GWSA_TAGS_URL="file://$GHTAGS" GWSA_TARBALL_BASE="file://$GHTB" \
         GWSA_DEPLOY_ROOT="$FORKDEP" GWSA_CLI_LINK="$TMP/forkgwsa" \
         "$FORKDEP/current/scripts/update.sh" --check 2>&1)"; rc=$?
[[ "$out_u" == *"someone/forkrepo"* ]] \
  && pass "update sans clone : provenance fork préservée après suppression du clone (.origin)" \
  || fail "update sans clone : retombe sur upstream après suppression du clone"

# mode CLONE : réutiliser un dossier venu d'un AUTRE dépôt → refus (Codex round-5).
XDEP="$TMP/xrepodep"; mkdir -p "$XDEP/v1.0.0"
printf 'github:elzinko/upstream\n' > "$XDEP/v1.0.0/.origin"        # dossier « upstream »
XFORK="$TMP/xfork"; mkdir -p "$XFORK/scripts" "$XFORK/bin"
cp "$REL/scripts/deploy-local.sh" "$REL/scripts/lib-github-release.sh" "$XFORK/scripts/"
printf '#!/bin/sh\nexit 0\n' > "$XFORK/bin/mag"; chmod +x "$XFORK/bin/mag"
git -C "$XFORK" init -q >/dev/null 2>&1; git -C "$XFORK" config user.email t@t; git -C "$XFORK" config user.name t
git -C "$XFORK" remote add origin https://github.com/someone/other.git
git -C "$XFORK" add -A >/dev/null 2>&1; git -C "$XFORK" commit -qm x >/dev/null 2>&1; git -C "$XFORK" tag v1.0.0
env GWSA_DEPLOY_ROOT="$XDEP" "$XFORK/scripts/deploy-local.sh" --tag v1.0.0 >/dev/null 2>&1; rc=$?
[[ "$rc" -ne 0 && ! -e "$XDEP/current" && "$(cat "$XDEP/v1.0.0/.origin")" == "github:elzinko/upstream" ]] \
  && pass "deploy --tag (clone) : cible d'un autre dépôt refusée (provenance ≠)" \
  || fail "deploy --tag (clone) : a réutilisé une cible d'un autre dépôt"

# provenance ssh:// URI bien normalisée en .origin (Codex round-5).
SSHC="$TMP/sshclone"; mkdir -p "$SSHC/scripts" "$SSHC/bin"
cp "$REL/scripts/deploy-local.sh" "$REL/scripts/lib-github-release.sh" "$SSHC/scripts/"
printf '#!/bin/sh\nexit 0\n' > "$SSHC/bin/mag"; chmod +x "$SSHC/bin/mag"
git -C "$SSHC" init -q >/dev/null 2>&1; git -C "$SSHC" config user.email t@t; git -C "$SSHC" config user.name t
git -C "$SSHC" remote add origin ssh://git@github.com/someone/sshrepo.git
git -C "$SSHC" add -A >/dev/null 2>&1; git -C "$SSHC" commit -qm x >/dev/null 2>&1; git -C "$SSHC" tag v1.0.0
env GWSA_DEPLOY_ROOT="$TMP/sshdep" "$SSHC/scripts/deploy-local.sh" --tag v1.0.0 >/dev/null 2>&1
[[ "$(cat "$TMP/sshdep/v1.0.0/.origin" 2>/dev/null)" == "github:someone/sshrepo" ]] \
  && pass "deploy clone : remote ssh:// normalisé dans .origin (github:someone/sshrepo)" \
  || fail "deploy clone : remote ssh:// mal parsé"

# provenance ssh:// avec PORT explicite bien normalisée (Codex round-6).
PORTC="$TMP/portclone"; mkdir -p "$PORTC/scripts" "$PORTC/bin"
cp "$REL/scripts/deploy-local.sh" "$REL/scripts/lib-github-release.sh" "$PORTC/scripts/"
printf '#!/bin/sh\nexit 0\n' > "$PORTC/bin/mag"; chmod +x "$PORTC/bin/mag"
git -C "$PORTC" init -q >/dev/null 2>&1; git -C "$PORTC" config user.email t@t; git -C "$PORTC" config user.name t
git -C "$PORTC" remote add origin ssh://git@github.com:22/someone/portrepo.git
git -C "$PORTC" add -A >/dev/null 2>&1; git -C "$PORTC" commit -qm x >/dev/null 2>&1; git -C "$PORTC" tag v1.0.0
env GWSA_DEPLOY_ROOT="$TMP/portdep" "$PORTC/scripts/deploy-local.sh" --tag v1.0.0 >/dev/null 2>&1
[[ "$(cat "$TMP/portdep/v1.0.0/.origin" 2>/dev/null)" == "github:someone/portrepo" ]] \
  && pass "deploy clone : remote ssh:// avec port normalisé dans .origin (github:someone/portrepo)" \
  || fail "deploy clone : remote ssh:// avec port mal parsé"

# hôte non-GitHub qui CONTIENT « github.com » → jamais pris pour GitHub (Codex round-7).
NGH="$TMP/notgithub"; mkdir -p "$NGH/scripts" "$NGH/bin"
cp "$REL/scripts/deploy-local.sh" "$REL/scripts/lib-github-release.sh" "$NGH/scripts/"
printf '#!/bin/sh\nexit 0\n' > "$NGH/bin/mag"; chmod +x "$NGH/bin/mag"
git -C "$NGH" init -q >/dev/null 2>&1; git -C "$NGH" config user.email t@t; git -C "$NGH" config user.name t
git -C "$NGH" remote add origin https://notgithub.com/someone/repo.git
git -C "$NGH" add -A >/dev/null 2>&1; git -C "$NGH" commit -qm x >/dev/null 2>&1; git -C "$NGH" tag v1.0.0
env GWSA_DEPLOY_ROOT="$TMP/nghdep" "$NGH/scripts/deploy-local.sh" --tag v1.0.0 >/dev/null 2>&1
[[ ! -e "$TMP/nghdep/v1.0.0/.origin" ]] \
  && pass "deploy clone : hôte « notgithub.com » non pris pour GitHub (aucun .origin)" \
  || fail "deploy clone : hôte non-GitHub accepté à tort comme GitHub"

# clone SANS provenance GitHub, supprimé → update REFUSE (pas de fallback upstream) (Codex round-7).
NOG="$TMP/nogithub"; mkdir -p "$NOG/scripts" "$NOG/bin"
cp "$REL/scripts/deploy-local.sh" "$REL/scripts/lib-github-release.sh" "$REL/scripts/update.sh" "$NOG/scripts/"
cp "$REL/bin/mag" "$NOG/bin/"; printf '#!/bin/sh\nexit 0\n' > "$NOG/bin/google-mcp"; chmod +x "$NOG/bin/"*
git -C "$NOG" init -q >/dev/null 2>&1; git -C "$NOG" config user.email t@t; git -C "$NOG" config user.name t
git -C "$NOG" add -A >/dev/null 2>&1; git -C "$NOG" commit -qm x >/dev/null 2>&1; git -C "$NOG" tag v1.0.0
NOGDEP="$TMP/nogdep"
env GWSA_DEPLOY_ROOT="$NOGDEP" "$NOG/scripts/deploy-local.sh" --tag v1.0.0 >/dev/null 2>&1
[[ ! -e "$NOGDEP/v1.0.0/.origin" ]] \
  && pass "deploy clone sans remote : aucun .origin (provenance inconnue)" \
  || fail "deploy clone sans remote : .origin écrit à tort"
rm -rf "$NOG"
out_u="$(env GWSA_TAGS_URL="file://$GHTAGS" GWSA_TARBALL_BASE="file://$GHTB" \
         GWSA_DEPLOY_ROOT="$NOGDEP" GWSA_CLI_LINK="$TMP/noggwsa" \
         "$NOGDEP/current/scripts/update.sh" --check 2>&1)"; rc=$?
[[ "$rc" -ne 0 && "$out_u" == *"provenance inconnue"* ]] \
  && pass "update : clone non-GitHub supprimé → refus (provenance inconnue, pas d'upstream)" \
  || fail "update : fallback silencieux sur upstream quand provenance inconnue"

# hôte GitHub en CASSE MIXTE (les hôtes sont insensibles à la casse) ; le chemin
# owner/repo reste sensible à la casse (Codex round-8).
CASE="$TMP/caseclone"; mkdir -p "$CASE/scripts" "$CASE/bin"
cp "$REL/scripts/deploy-local.sh" "$REL/scripts/lib-github-release.sh" "$CASE/scripts/"
printf '#!/bin/sh\nexit 0\n' > "$CASE/bin/mag"; chmod +x "$CASE/bin/mag"
git -C "$CASE" init -q >/dev/null 2>&1; git -C "$CASE" config user.email t@t; git -C "$CASE" config user.name t
git -C "$CASE" remote add origin https://GitHub.com/someone/CaseRepo.git
git -C "$CASE" add -A >/dev/null 2>&1; git -C "$CASE" commit -qm x >/dev/null 2>&1; git -C "$CASE" tag v1.0.0
env GWSA_DEPLOY_ROOT="$TMP/casedep" "$CASE/scripts/deploy-local.sh" --tag v1.0.0 >/dev/null 2>&1
[[ "$(cat "$TMP/casedep/v1.0.0/.origin" 2>/dev/null)" == "github:someone/CaseRepo" ]] \
  && pass "deploy clone : hôte « GitHub.com » (casse mixte) reconnu, chemin owner/repo préservé" \
  || fail "deploy clone : hôte en casse mixte non reconnu"

# la requête de tags par défaut demande per_page=100 (rollback validable > 30 tags). Codex round-8.
tags_url_def="$(unset GWSA_TAGS_URL; GWSA_REPO=owner/repo; . "$REL/scripts/lib-github-release.sh"; gh_tags_url)"
[[ "$tags_url_def" == *"per_page=100"* ]] \
  && pass "lib : requête de tags par défaut élargie (per_page=100)" \
  || fail "lib : per_page absent de la requête de tags"

section "sessions + vault (fiche 0040)"

SESS_ROOT="$TMP/mag-sessions"
mkdir -p "$SESS_ROOT/alpha"
echo '{"drive":{"read":true,"create":true,"zonesOnly":true,"writeFolders":[]}}' > "$SESS_ROOT/alpha/policy.json"
touch "$SESS_ROOT/alpha/.locked"
PY="/usr/bin/python3"
[[ -x "$PY" ]] || PY="$(command -v python3)"

export GWSA_ROOT="$SESS_ROOT" PYTHONPATH="$(pwd)"
# fiche 0076 (lot 2) : toute création/élargissement de capacité de SESSION
# (unlock, grant, grant-capability via GWSA_SESSION_ID) exige désormais une
# élicitation signée TOUJOURS (indépendamment de .strong-auth — ADR-0007 §3).
# Enrôlement mock une fois pour toute cette section (clé HMAC de test).
GWSA_ROOT="$SESS_ROOT" GWSA_ELICITATION_MOCK=1 "$GWSA" elicitation enroll --mock >/dev/null 2>&1
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

# ── fiche 0076 : droits par session — jeton porté PAR L'APPEL (pas de global) ──
# ADR-0007 §Décision 2 : gateway.api._run lit le jeton du paramètre `session`
# de CET appel, jamais un état global de process. On mocke run_via_broker pour
# rester hermétique (zéro réseau, zéro gws réel) et exercer uniquement
# l'autorisation portée par le jeton.
out_call_iso="$("$PY" -c "
import gateway.api as api
from gateway.sessions import create_session, session_unlock

def fake_broker(alias, args, timeout=60, raw_output=False, session_id=''):
    return {'files': [], '_sid': session_id}
api.run_via_broker = fake_broker

s1 = create_session(client='t076')
s2 = create_session(client='t076')
session_unlock(s1.session_id, 'alpha', 30)

ok1 = True
try:
    api.gmail_list(alias='alpha', session=s1.session_id)
except api.GatewayError:
    ok1 = False

ok2 = True
code2 = ''
try:
    api.gmail_list(alias='alpha', session=s2.session_id)
except api.GatewayError as e:
    ok2 = False
    code2 = e.code

print('ok1', ok1, 'ok2', ok2, 'code2', code2)
")"
[[ "$out_call_iso" == *"ok1 True"* && "$out_call_iso" == *"ok2 False"* && "$out_call_iso" == *"code2 locked"* ]] \
  && pass "api._run : jeton porté par l'appel — deux sessions isolées (pas de global)" \
  || fail "api._run : isolation par jeton d'appel ($out_call_iso)"

out_no_token="$("$PY" -c "
import gateway.api as api
try:
    api.gmail_list(alias='alpha', session='')
    print('no-raise')
except api.GatewayError as e:
    print('OK' if e.code == 'session' else 'wrong:' + e.code)
")"
[[ "$out_no_token" == "OK" ]] \
  && pass "api._run : appel SANS jeton de session → refus (fail-closed)" \
  || fail "api._run : appel sans jeton non refusé ($out_no_token)"

out_ttl="$(GWSA_SESSION_TTL_SEC=1 "$PY" -c "
import time
from gateway.sessions import create_session, get_session
s = create_session(client='ttl076')
time.sleep(1.2)
print(get_session(s.session_id))
")"
[[ "$out_ttl" == "None" ]] \
  && pass "sessions : TTL expiré → get_session refuse dès l'accès (pas seulement au GC périodique)" \
  || fail "sessions : TTL non appliqué à l'accès ($out_ttl)"

out_ttl_run="$(GWSA_SESSION_TTL_SEC=1 "$PY" -c "
import time
import gateway.api as api
from gateway.sessions import create_session
api.run_via_broker = lambda *a, **k: {'files': []}
s = create_session(client='ttl076run')
time.sleep(1.2)
try:
    api.gmail_list(alias='alpha', session=s.session_id)
    print('no-raise')
except api.GatewayError as e:
    # require_session() lève avec code='error' (« session inconnue ou expirée ») —
    # ce qui compte pour la DoD est le REFUS, pas le code précis.
    print('OK' if 'expirée' in str(e) or 'inconnue' in str(e) else 'wrong:' + str(e))
")"
[[ "$out_ttl_run" == "OK" ]] \
  && pass "api._run : session expirée (TTL) → refus au moment de l'appel MCP" \
  || fail "api._run : session expirée non refusée ($out_ttl_run)"

out_touch="$("$PY" -c "
import time
from gateway.sessions import create_session, get_session
s = create_session(client='touch076')
created = s.created_at
time.sleep(0.05)
s2 = get_session(s.session_id)
print(s2.last_seen_at > created)
")"
[[ "$out_touch" == "True" ]] \
  && pass "sessions : last_seen_at avance après un accès autorisé (bug 0076 corrigé)" \
  || fail "sessions : last_seen_at ne bouge pas après accès ($out_touch)"

sid_close076="$("$PY" -c "from gateway.sessions import create_session; print(create_session(client='closecmd076').session_id)")"
GWSA_ROOT="$SESS_ROOT" "$GWSA" session close "$sid_close076" >/dev/null 2>&1
gone_close076="$("$PY" -c "from gateway.sessions import get_session; print(get_session('$sid_close076'))")"
[[ "$gone_close076" == "None" ]] \
  && pass "mag session close : révocation explicite purge la session (cycle de vie découplé de la connexion)" \
  || fail "mag session close : session non purgée ($gone_close076)"

# GC câblé au balayage/accès (pas à la déconnexion) : gateway.broker_server.handle_exec
# appelle purge_expired() — vérifié directement sur la fonction (hermétique, sans broker
# réel). Racine DÉDIÉE (isolée de SESS_ROOT, qui accumule des sessions d'autres tests
# depuis longtemps) pour que le compte purgé soit exactement celui créé ici.
GC_ROOT076="$TMP/mag-sessions-gc076"
mkdir -p "$GC_ROOT076"
out_gc="$(GWSA_ROOT="$GC_ROOT076" GWSA_SESSION_TTL_SEC=1 "$PY" -c "
import time
from gateway.sessions import create_session, sessions_dir, purge_expired
s = create_session(client='gc076')
path = sessions_dir() / (s.session_id + '.json')
time.sleep(1.2)
n = purge_expired()
print(n, path.is_file())
")"
[[ "$out_gc" == "1 False" ]] \
  && pass "sessions : purge_expired() GC les sessions expirées (câblée côté broker à chaque accès)" \
  || fail "sessions : purge_expired() n'a pas purgé ($out_gc)"

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
  && pass "mag session list : JSON avec session_id" \
  || fail "mag session list ($out_slist)"

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
    && pass "admin POST unlock session via mag" \
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

  # anti DNS-rebinding : un Host non-loopback est refusé, même AVEC l'en-tête admin
  code_host="$(curl -s -o /dev/null -w '%{http_code}' \
    -H 'X-GWSA-Admin: 1' -H "Host: evil.example:$ADMIN_PORT" \
    "http://127.0.0.1:$ADMIN_PORT/api/sessions")"
  [[ "$code_host" == "403" ]] \
    && pass "admin : refuse un Host non-loopback (anti DNS-rebinding)" \
    || fail "admin Host guard (code=$code_host)"

  # anti-CSRF : une Origin étrangère est refusée (Host loopback par défaut)
  code_origin="$(curl -s -o /dev/null -w '%{http_code}' \
    -H 'X-GWSA-Admin: 1' -H 'Origin: http://evil.example' \
    "http://127.0.0.1:$ADMIN_PORT/api/sessions")"
  [[ "$code_origin" == "403" ]] \
    && pass "admin : refuse une Origin étrangère" \
    || fail "admin Origin guard (code=$code_origin)"
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

# ── DEFAULT_POLICY : invariants de sûreté du default-deny livré par `mag add` ──
# Garde le point d'entrée : basculer send/share/delete ou ouvrir les zones ferait
# passer la CI au vert tout en livrant un défaut permissif à chaque nouveau compte.
pol_inv="$("$PY" -c "
from gateway.default_policy import DEFAULT_POLICY as P
# Exhaustif : TOUT flag qui envoie / partage / supprime / écrit doit être False,
# sur tous les services — sinon une dérive (ex. calendar.delete=True) passerait.
must_be_false = [
    ('gmail','send'), ('gmail','delete'), ('gmail','update'), ('gmail','settings'),
    ('drive','delete'), ('drive','share'),
    ('calendar','create'), ('calendar','update'), ('calendar','delete'), ('calendar','share'),
    ('keep','update'), ('keep','delete'),
    ('docs','create'), ('docs','update'),
    ('sheets','create'), ('sheets','update'),
    ('tasks','create'), ('tasks','update'), ('tasks','delete'),
]
bad = [f'{s}.{k}' for s, k in must_be_false if P.get(s, {}).get(k) is not False]
if P['drive'].get('zonesOnly') is not True: bad.append('drive.zonesOnly')
if P['drive'].get('writeFolders') != []: bad.append('drive.writeFolders')
print('OK' if not bad else 'BAD:' + ','.join(bad))
")"
[[ "$pol_inv" == "OK" ]] \
  && pass "DEFAULT_POLICY : invariants de sûreté (tous services : envoi/partage/suppression/écriture=false · zones fermées)" \
  || fail "DEFAULT_POLICY invariants ($pol_inv)"

# ── gmail_attachment_get : borne défensive sur la taille des pièces jointes (0074) ──
# Une PJ énorme ne doit pas saturer le disque : la borne lève AVANT toute écriture.
att_inv="$("$PY" -c "
import base64
import gateway.api as api
api.validate_alias = lambda a: None            # isoler la borne (pas de profil réel)
api._run = lambda *a, **k: {'data': base64.urlsafe_b64encode(b'x' * 200).decode()}
api._ATTACHMENT_MAX_BYTES = 100                 # borne basse pour le test
try:
    api.gmail_attachment_get('alpha', 'm1', 'a1')
    print('no-raise')
except api.GatewayError as e:
    print('OK' if 'volumineuse' in str(e) else 'wrong-msg')
")"
[[ "$att_inv" == "OK" ]] \
  && pass "gmail_attachment_get : borne la taille des pièces jointes (refus au-delà, avant écriture)" \
  || fail "borne pièce jointe ($att_inv)"

PROJ_ROOT="$TMP/mag-proj-inside"
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
from gateway.api import access_request
from gateway.project import ProjectContext
from gateway.sessions import create_session

# jeton porté PAR L'APPEL (fiche 0076) — plus de set_session_id global.
sid = create_session(client='t').session_id
m = {'capabilities': {'alpha': {
  'drive': {'zones': [{'id': 'folderAAA'}]},
  'gmail': {'read': True, 'drafts': False},
}}}
ctx = ProjectContext(manifest_valid=True, manifest=m, git_root='/tmp',
                     manifest_path='/tmp/.gwsa/manifest.json')
os.environ['GWSA_GIT_ROOT'] = '/tmp'
with patch('gateway.project.resolve_project', return_value=ctx):
    ok = access_request('alpha', 'project_grant', folder='folderAAA', hours=2, session=sid)
    assert ok.get('kind') == 'project_grant' and 'session grant' in ok.get('suggested_command','')
    blocked = access_request('alpha', 'project_grant', folder='folderBBB', hours=2, session=sid)
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
ELIC_ROOT="$TMP/mag-elicitation"
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

# Fiche 0047 : le prompt d'autorisation nomme le compte (email), pas l'alias seul,
# et l'email est DANS le payload signé (lié cryptographiquement à la signature).
acct_ok="$("$PY" -c "
from gateway.elicitation import prompt_from_payload, build_payload, sign_mock, verify_signature
u = prompt_from_payload({'action':'session_unlock','alias':'alpha','email':'a@gmail.com','session_id':'s','minutes':30})
g = prompt_from_payload({'action':'grant','alias':'alpha','email':'a@gmail.com','target':'Z','hours':8})
bare = prompt_from_payload({'action':'unlock','alias':'alpha','minutes':30})
assert 'a@gmail.com' in u, u
assert 'a@gmail.com' in g, g
assert '@' not in bare and 'alpha' in bare, bare  # email inconnu → repli alias seul
p = build_payload('session_unlock', alias='alpha', email='a@gmail.com', session_id='s', minutes=30)
assert p['email'] == 'a@gmail.com', p
sig = sign_mock(p)
p2 = dict(p); p2['email'] = 'evil@x.com'
assert verify_signature(p2, sig) is False, 'email altéré doit invalider la signature'
print('ok')
")"
[[ "$acct_ok" == "ok" ]] \
  && pass "elicitation : prompt nomme le compte + email signé (fiche 0047)" \
  || fail "elicitation : compte dans le prompt/payload ($acct_ok)"

# Fiche 0047 / retour Codex PR #75 : aux points d'autorisation, l'email se lit en
# CACHE-ONLY (.email) — jamais d'exec gws avant le gate Touch ID (invariant de
# verrou + ADR-0002). On extrait la fonction pure et on la teste seule.
pec_dir="$TMP/pec"; mkdir -p "$pec_dir/valid" "$pec_dir/missing" "$pec_dir/corrupt"
printf 'alice@gmail.com\n' > "$pec_dir/valid/.email"
printf 'pas-un-email\n'    > "$pec_dir/corrupt/.email"
eval "$(sed -n '/^profile_email_cached()/,/^}/p' bin/mag)"
r_valid="$(profile_email_cached "$pec_dir/valid")"
r_missing="$(profile_email_cached "$pec_dir/missing")"
r_corrupt="$(profile_email_cached "$pec_dir/corrupt")"
n_cached="$(grep -c 'profile_email_cached "' bin/mag || true)"  # appels seuls (pas la déf)
# Sous `set -euo pipefail` (comme bin/mag) et la forme appelante exacte
# « local email; email="$(…)" », la fonction ne doit JAMAIS avorter — même sur
# .email corrompu (sinon unlock/grant meurt avant le gate — retour Codex P2).
pec_fn="$TMP/pec_fn.sh"; sed -n '/^profile_email_cached()/,/^}/p' bin/mag > "$pec_fn"
sete_rc=0
bash -euo pipefail -c '
  . "$1"
  c(){ local email; email="$(profile_email_cached "$1")"; printf "%s" "$email"; }
  c "$2" >/dev/null   # .email corrompu
  c "$3" >/dev/null   # .email absent
' _ "$pec_fn" "$pec_dir/corrupt" "$pec_dir/missing" || sete_rc=$?
if [[ "$r_valid" == "alice@gmail.com" && -z "$r_missing" && -z "$r_corrupt" ]] \
  && [[ "$n_cached" == 6 && "$sete_rc" == 0 ]] \
  && ! sed -n '/^profile_email_cached()/,/^}/p' bin/mag | sed 's/#.*//' | grep -q 'gws'; then
  pass "elicitation : email lu cache-only aux points d'autorisation, zéro exec gws (fiche 0047)"
else
  fail "elicitation : cache-only (valid=$r_valid missing=[$r_missing] corrupt=[$r_corrupt] sites=$n_cached set-e_rc=$sete_rc)"
fi

# ── Résolution email → alias sur les commandes humaines (lock/unlock/grant/policy) ──
er_root="$TMP/email-resolve"; mkdir -p "$er_root/perso"; printf 'thomas@gmail.com\n' > "$er_root/perso/.email"
GWSA_ROOT="$er_root" "$GWSA" lock thomas@gmail.com >/dev/null 2>&1   # email → profil « perso »
er_by_email=$([ -f "$er_root/perso/.locked" ] && echo ok || echo no)
rm -f "$er_root/perso/.locked"
GWSA_ROOT="$er_root" "$GWSA" lock perso >/dev/null 2>&1              # l'alias reste accepté
er_by_alias=$([ -f "$er_root/perso/.locked" ] && echo ok || echo no)
er_unknown="$(GWSA_ROOT="$er_root" "$GWSA" lock inconnu@example.com 2>&1)"; er_rc=$?
if [[ "$er_by_email" == ok && "$er_by_alias" == ok && "$er_rc" != 0 && "$er_unknown" == *"aucun compte connecté"* ]]; then
  PASS=$((PASS + 1)); printf '  \033[32m✓\033[0m commandes : email résolu vers son profil (alias toujours OK ; email inconnu refusé clairement)\n'
else
  FAIL=$((FAIL + 1)); printf '  \033[31m✗\033[0m résolution email (email=%s alias=%s rc=%s msg=%s)\n' "$er_by_email" "$er_by_alias" "$er_rc" "$er_unknown"
fi

# ── mag wire : brancher un client en une commande (dry-run, sans écrire) ──
w_cfg="$TMP/wire-desktop.json"
w_out="$(GWSA_ROOT="$TMP/wire-root" "$GWSA" wire desktop --print --config "$w_cfg" 2>&1)"
w_cursor="$(GWSA_ROOT="$TMP/wire-root" "$GWSA" wire cursor 2>&1)"; w_cur_rc=$?
if [[ "$w_out" == *"Dry-run"* && ! -f "$w_cfg" && "$w_cur_rc" != 0 && "$w_cursor" == *"Cursor"* ]]; then
  PASS=$((PASS + 1)); printf '  \033[32m✓\033[0m mag wire desktop --print : dry-run sans écriture ; wire cursor renvoie vers la doc\n'
else
  FAIL=$((FAIL + 1)); printf '  \033[31m✗\033[0m mag wire (out=%s cursor_rc=%s)\n' "$w_out" "$w_cur_rc"
fi

sid_e="$("$PY" -c 'from gateway.sessions import create_session; print(create_session(client="t").session_id)')"
GWSA_ROOT="$ELIC_ROOT" GWSA_SESSION_ID="$sid_e" GWSA_ELICITATION_MOCK=1 \
  "$GWSA" session unlock "$sid_e" alpha 15 >/dev/null 2>&1 \
  && pass "elicitation : mag session unlock avec strongauth+mock" \
  || fail "elicitation : mag session unlock strongauth"

section "consume_nonce : verrou inter-process anti-TOCTOU (fiche 0084)"
# consume_nonce fait reload → check → save sans atomicité inter-process avant
# le correctif de la fiche 0084 : deux process concurrents peuvent tous deux
# voir « nonce absent », passer le check et sauver → même nonce accepté deux
# fois (rejeu d'une approbation signée). On le prouve avec 2 VRAIS sous-process
# python3 (pas des threads, pas un objet partagé) synchronisés par une barrière
# de démarrage, et on force la fenêtre de course avec le hook de test
# GWSA_ELICITATION_TEST_RACE_DELAY_MS (sleep entre check et save, inactif hors
# test — cf. gateway/elicitation.py::_test_race_delay).
NONCE_RACE_ROOT="$TMP/mag-nonce-race"
mkdir -p "$NONCE_RACE_ROOT"
RACE_NONCE="racecondition0084"
RACE_EXP=$(( $(date +%s) + 300 ))

nonce_race_worker() {
  # $1 = mon fichier « prêt », $2 = fichier « prêt » de l'autre, $3 = résultat
  local my_ready="$1" other_ready="$2" out="$3"
  GWSA_ROOT="$ELIC_ROOT" GWSA_ELICITATION_MOCK=1 GWSA_ELICITATION_TEST_RACE_DELAY_MS=150 \
    "$PY" -c "
import time
from pathlib import Path
Path('$my_ready').write_text('1')
while not Path('$other_ready').is_file():
    time.sleep(0.005)
from gateway.elicitation import consume_nonce, ElicitationError
try:
    consume_nonce('$RACE_NONCE', expires_at=$RACE_EXP)
    Path('$out').write_text('ok')
except ElicitationError as e:
    Path('$out').write_text('replay:' + str(e))
except Exception as e:
    Path('$out').write_text('error:' + str(e))
"
}

NR1="$NONCE_RACE_ROOT/ready1"; NR2="$NONCE_RACE_ROOT/ready2"
NO1="$NONCE_RACE_ROOT/out1"; NO2="$NONCE_RACE_ROOT/out2"
rm -f "$NR1" "$NR2" "$NO1" "$NO2" "$ELIC_ROOT/.elicitation/nonces.json" "$ELIC_ROOT/.elicitation/nonces.lock"
nonce_race_worker "$NR1" "$NR2" "$NO1" &
NRPID1=$!
nonce_race_worker "$NR2" "$NR1" "$NO2" &
NRPID2=$!
wait "$NRPID1" "$NRPID2"

nr_o1=$(cat "$NO1" 2>/dev/null)
nr_o2=$(cat "$NO2" 2>/dev/null)
nr_ok=0; nr_replay=0
[[ "$nr_o1" == "ok" ]] && nr_ok=$((nr_ok + 1))
[[ "$nr_o2" == "ok" ]] && nr_ok=$((nr_ok + 1))
[[ "$nr_o1" == replay:* ]] && nr_replay=$((nr_replay + 1))
[[ "$nr_o2" == replay:* ]] && nr_replay=$((nr_replay + 1))
if [[ $nr_ok -eq 1 && $nr_replay -eq 1 ]]; then
  pass "consume_nonce : course multi-process — exactement un gagnant, l'autre voit le rejeu"
else
  fail "consume_nonce : TOCTOU — ok=$nr_ok replay=$nr_replay (out1=$nr_o1 out2=$nr_o2)"
fi

# Ré-vérification de l'expiration SOUS le verrou (revue Codex PR #125) : si
# l'attente d'acquisition du verrou franchit expires_at, un défi expiré ne doit
# PAS être consommé. On tient le verrou de l'extérieur au-delà du TTL pendant
# qu'un thread appelle consume_nonce ; il doit ressortir « défi expiré ».
exp_out="$(GWSA_ROOT="$ELIC_ROOT" GWSA_ELICITATION_MOCK=1 "$PY" -c "
import fcntl, os, time, threading
from gateway.elicitation import consume_nonce, ElicitationError, nonces_lock_path
lp = nonces_lock_path(); lp.parent.mkdir(parents=True, exist_ok=True)
fd = os.open(str(lp), os.O_CREAT | os.O_RDWR, 0o600)
fcntl.flock(fd, fcntl.LOCK_EX)          # on tient le verrou
exp = int(time.time()) + 1              # TTL court : 1 s
res = {}
def w():
    try:
        consume_nonce('expiry-under-lock', expires_at=exp)
        res['r'] = 'ok'
    except ElicitationError as e:
        res['r'] = 'expired' if 'expiré' in str(e) else 'other:' + str(e)
t = threading.Thread(target=w); t.start()
time.sleep(2)                           # on tient le verrou au-delà du TTL
fcntl.flock(fd, fcntl.LOCK_UN); os.close(fd)
t.join(5)
print(res.get('r', 'timeout'))
")"
if [[ "$exp_out" == "expired" ]]; then
  pass "consume_nonce : expiration re-vérifiée SOUS le verrou (défi expiré pendant l'attente refusé)"
else
  fail "consume_nonce : défi expiré pendant l'attente du verrou consommé (out=$exp_out)"
fi

section "droits par session — lot 2 (fiche 0076, capacités fines)"

# ── (a) capacité gmail:read autorise la lecture, pas gmail:send ni drive:write ──
CAP_ROOT="$TMP/mag-caps"
mkdir -p "$CAP_ROOT/alpha"
echo '{"gmail":{"read":true,"send":true,"drafts":true},"drive":{"read":true,"create":true,"zonesOnly":true,"writeFolders":["zoneA","zoneB"]}}' \
  > "$CAP_ROOT/alpha/policy.json"
out_cap_a="$(GWSA_ROOT="$CAP_ROOT" PYTHONPATH="$(pwd)" "$PY" -c "
import json, subprocess, sys
caps = json.dumps([{'service':'gmail','operation':'read'}])
env = dict(__import__('os').environ, GWSA_SESSION_CAPS=caps)
def rc(args):
    r = subprocess.run([sys.executable, 'scripts/policy-check.py', '$CAP_ROOT/alpha'] + args, env=env)
    return r.returncode
print('read', rc(['gmail','messages','list']))
print('send', rc(['gmail','messages','send','--json','{}']))
print('drivewrite', rc(['drive','files','create','--json','{\"parents\":[\"zoneA\"]}']))
")"
[[ "$out_cap_a" == *"read 0"* && "$out_cap_a" == *"send 4"* && "$out_cap_a" == *"drivewrite 4"* ]] \
  && pass "capacités session : gmail:read autorise la lecture, refuse send/drive:write" \
  || fail "capacités session : gmail:read trop large ou trop étroit ($out_cap_a)"

# ── (b) capacité drive:create:zoneA autorise zoneA, pas zoneB ──
out_cap_b="$(GWSA_ROOT="$CAP_ROOT" PYTHONPATH="$(pwd)" "$PY" -c "
import json, subprocess, sys
caps = json.dumps([{'service':'drive','operation':'create','resource':'zoneA'}])
env = dict(__import__('os').environ, GWSA_SESSION_CAPS=caps)
def rc(zone):
    r = subprocess.run([sys.executable, 'scripts/policy-check.py', '$CAP_ROOT/alpha',
                         'drive','files','create','--json', json.dumps({'parents':[zone]})], env=env)
    return r.returncode
print('zoneA', rc('zoneA'))
print('zoneB', rc('zoneB'))
")"
[[ "$out_cap_b" == *"zoneA 0"* && "$out_cap_b" == *"zoneB 4"* ]] \
  && pass "capacités session : drive:create:zoneA autorise zoneA, refuse zoneB" \
  || fail "capacités session : isolation par ressource Drive ($out_cap_b)"

# ── (c) ressource absente sur Gmail = lecture bornée par la policy (pas de fuite) ──
out_cap_c="$(GWSA_ROOT="$CAP_ROOT" PYTHONPATH="$(pwd)" "$PY" -c "
import json, subprocess, sys
caps = json.dumps([{'service':'gmail','operation':'read'}])
env = dict(__import__('os').environ, GWSA_SESSION_CAPS=caps)
r = subprocess.run([sys.executable, 'scripts/policy-check.py', '$CAP_ROOT/alpha','gmail','messages','list'], env=env)
print(r.returncode)
")"
[[ "$out_cap_c" == "0" ]] \
  && pass "capacités session : ressource Gmail absente = lecture bornée par la policy" \
  || fail "capacités session : lecture Gmail sans ressource ($out_cap_c)"

# ── (h) fail-closed sur policy Drive PERMISSIVE — non-zonesOnly (revue sécu P0) ──
# La garantie de session ne doit PAS tomber quand la policy Drive du compte est
# ouverte : une session limitée (gmail:read) ne peut pas écrire dans Drive.
CAP_OPEN="$TMP/mag-caps-open"
mkdir -p "$CAP_OPEN/alpha"
echo '{"gmail":{"read":true},"drive":{"read":true,"create":true,"update":true,"zonesOnly":false}}' \
  > "$CAP_OPEN/alpha/policy.json"
out_cap_h="$(GWSA_ROOT="$CAP_OPEN" PYTHONPATH="$(pwd)" "$PY" -c "
import json, subprocess, sys, os
env = dict(os.environ, GWSA_SESSION_CAPS=json.dumps([{'service':'gmail','operation':'read'}]))
env_legacy = dict(os.environ); env_legacy.pop('GWSA_SESSION_CAPS', None)
def rc(args, e):
    return subprocess.run([sys.executable,'scripts/policy-check.py','$CAP_OPEN/alpha']+args, env=e).returncode
print('create', rc(['drive','files','create','--json','{\"parents\":[\"F123\"]}'], env))
print('update', rc(['drive','files','update','--params','{\"fileId\":\"F1\"}','--json','{}'], env))
print('legacy', rc(['drive','files','create','--json','{\"parents\":[\"F123\"]}'], env_legacy))
")"
[[ "$out_cap_h" == *"create 4"* && "$out_cap_h" == *"update 4"* && "$out_cap_h" == *"legacy 0"* ]] \
  && pass "capacités session : Drive non-zonesOnly reste fail-closed (session gmail:read refusée en écriture)" \
  || fail "capacités session : FAIL-OPEN sur Drive non-zonesOnly ($out_cap_h)"

# ── (i) fail-closed sur policy Drive « mode:open » (revue sécu P0) ──
CAP_MOPEN="$TMP/mag-caps-mopen"
mkdir -p "$CAP_MOPEN/alpha"
echo '{"gmail":{"read":true},"drive":{"mode":"open"}}' > "$CAP_MOPEN/alpha/policy.json"
out_cap_i="$(GWSA_ROOT="$CAP_MOPEN" PYTHONPATH="$(pwd)" "$PY" -c "
import json, subprocess, sys, os
env = dict(os.environ, GWSA_SESSION_CAPS=json.dumps([{'service':'gmail','operation':'read'}]))
env_legacy = dict(os.environ); env_legacy.pop('GWSA_SESSION_CAPS', None)
def rc(e):
    return subprocess.run([sys.executable,'scripts/policy-check.py','$CAP_MOPEN/alpha','drive','files','create','--json','{\"parents\":[\"X\"]}'], env=e).returncode
print('sess', rc(env)); print('legacy', rc(env_legacy))
")"
[[ "$out_cap_i" == *"sess 4"* && "$out_cap_i" == *"legacy 0"* ]] \
  && pass "capacités session : Drive mode:open reste fail-closed pour une session limitée" \
  || fail "capacités session : FAIL-OPEN sur Drive mode:open ($out_cap_i)"

# ── (j) zone de session + capacité fine cohabitent (revue P1 — composition) ──
out_cap_j="$(GWSA_ROOT="$CAP_ROOT" PYTHONPATH="$(pwd)" "$PY" -c "
import json, subprocess, sys, os
env = dict(os.environ, GWSA_USE_SESSION_GRANTS='1', GWSA_SESSION_DRIVE_ZONES='zoneA',
           GWSA_SESSION_CAPS=json.dumps([{'service':'gmail','operation':'read'}]))
def rc(zone):
    return subprocess.run([sys.executable,'scripts/policy-check.py','$CAP_ROOT/alpha',
                           'drive','files','create','--json', json.dumps({'parents':[zone]})], env=env).returncode
print('zoneA', rc('zoneA')); print('zoneB', rc('zoneB'))
")"
[[ "$out_cap_j" == *"zoneA 0"* && "$out_cap_j" == *"zoneB 4"* ]] \
  && pass "capacités session : zone de session utilisable malgré une capacité fine (composition)" \
  || fail "capacités session : zone de session cassée par une capacité fine ($out_cap_j)"

# ── (d) octroi de capacité sans élicitation signée → refus ──
CAP_UNSIGNED="$TMP/mag-caps-unsigned"
mkdir -p "$CAP_UNSIGNED/alpha"
cp "$CAP_ROOT/alpha/policy.json" "$CAP_UNSIGNED/alpha/policy.json"
sid_uc="$(GWSA_ROOT="$CAP_UNSIGNED" PYTHONPATH="$(pwd)" "$PY" -c 'from gateway.sessions import create_session; print(create_session(client="t").session_id)')"
gc_unsigned_rc=0
GWSA_ROOT="$CAP_UNSIGNED" "$GWSA" session grant-capability "$sid_uc" alpha gmail read "" 1 >/dev/null 2>&1 || gc_unsigned_rc=$?
[[ "$gc_unsigned_rc" != 0 ]] \
  && pass "capacités session : octroi sans élicitation signée (pas d'enrôlement) → refus" \
  || fail "capacités session : octroi non signé accepté à tort"

# ── octroi SIGNÉ (mock) : mag session grant-capability écrit bien la capacité ──
gc_ok=0
GWSA_ROOT="$CAP_UNSIGNED" GWSA_ELICITATION_MOCK=1 "$GWSA" elicitation enroll --mock >/dev/null 2>&1
GWSA_ROOT="$CAP_UNSIGNED" GWSA_ELICITATION_MOCK=1 \
  "$GWSA" session grant-capability "$sid_uc" alpha gmail read "" 1 >/dev/null 2>&1 || gc_ok=$?
has_cap="$(GWSA_ROOT="$CAP_UNSIGNED" PYTHONPATH="$(pwd)" "$PY" -c "
from gateway.sessions import session_has_capability
print(session_has_capability('$sid_uc', 'alpha', 'gmail', 'read'))
")"
[[ "$gc_ok" == 0 && "$has_cap" == "True" ]] \
  && pass "capacités session : mag session grant-capability (signé, mock) octroie la capacité" \
  || fail "capacités session : grant-capability signé ($gc_ok has_cap=$has_cap)"

# ── (e) service/opération non déclarés dans les capacités de session → refus ──
out_cap_e="$(GWSA_ROOT="$CAP_ROOT" PYTHONPATH="$(pwd)" "$PY" -c "
import json, subprocess, sys
caps = json.dumps([{'service':'gmail','operation':'read'}])
env = dict(__import__('os').environ, GWSA_SESSION_CAPS=caps)
r = subprocess.run([sys.executable, 'scripts/policy-check.py', '$CAP_ROOT/alpha','gmail','drafts','create','--json','{}'], env=env)
print(r.returncode)
")"
[[ "$out_cap_e" == "4" ]] \
  && pass "capacités session : opération non déclarée (gmail:drafts) → refus" \
  || fail "capacités session : opération non déclarée acceptée à tort ($out_cap_e)"

# ── (f) sans manifeste projet : policy ∩ session (pas de plafond manifeste) ──
NOMANI_REPO="$TMP/mag-caps-nomanifest-repo"
mkdir -p "$NOMANI_REPO"
git -C "$NOMANI_REPO" init -q
out_cap_f="$(GWSA_ROOT="$CAP_ROOT" GWSA_GIT_ROOT="$NOMANI_REPO" PYTHONPATH="$(pwd)" "$PY" -c "
import subprocess, sys
r = subprocess.run([sys.executable, 'scripts/policy-check.py', '$CAP_ROOT/alpha','gmail','messages','list'])
print(r.returncode)
")"
[[ "$out_cap_f" == "0" ]] \
  && pass "manifeste absent (jamais configuré) : policy ∩ session — pas de plafond" \
  || fail "manifeste absent : refus à tort ($out_cap_f)"

# ── (g) manifeste altéré après confiance → refus (anti-downgrade, S-07) ──
ANTIDOWN_ROOT="$TMP/mag-antidowngrade-root"
ANTIDOWN_REPO="$TMP/mag-antidowngrade-repo"
mkdir -p "$ANTIDOWN_REPO"
git -C "$ANTIDOWN_REPO" init -q
git -C "$ANTIDOWN_REPO" config user.email t@t.com
git -C "$ANTIDOWN_REPO" config user.name t
mkdir -p "$ANTIDOWN_ROOT"
touch "$ANTIDOWN_ROOT/.strong-auth"
GWSA_ROOT="$ANTIDOWN_ROOT" GWSA_ELICITATION_MOCK=1 PYTHONPATH="$(pwd)" "$PY" -c "
from pathlib import Path
from gateway.elicitation import enroll_mock
enroll_mock()
from gateway.project import init_project, sign_manifest
root = Path('$ANTIDOWN_REPO')
init_project(root)
r = sign_manifest(root)
assert r['ok'], r
"
before_trust="$(GWSA_ROOT="$ANTIDOWN_ROOT" GWSA_GIT_ROOT="$ANTIDOWN_REPO" PYTHONPATH="$(pwd)" "$PY" -c "
import subprocess, sys
r = subprocess.run([sys.executable, 'scripts/policy-check.py', '$CAP_ROOT/alpha','gmail','messages','list'])
print(r.returncode)
")"
# Altération : le fichier manifeste change de contenu sans re-signature.
printf '{"schema":1,"project_id":"tampered","capabilities":{}}' > "$ANTIDOWN_REPO/.gwsa/manifest.json"
after_tamper="$(GWSA_ROOT="$ANTIDOWN_ROOT" GWSA_GIT_ROOT="$ANTIDOWN_REPO" PYTHONPATH="$(pwd)" "$PY" -c "
import subprocess, sys
r = subprocess.run([sys.executable, 'scripts/policy-check.py', '$CAP_ROOT/alpha','gmail','messages','list'])
print(r.returncode)
")"
[[ "$before_trust" == "0" && "$after_tamper" == "4" ]] \
  && pass "anti-downgrade : manifeste altéré après confiance → refus (S-07)" \
  || fail "anti-downgrade : manifeste altéré non refusé (before=$before_trust after=$after_tamper)"

section "droits par session — P1 sécu (fiche 0076, session nue = deny-all)"

# Profil déverrouillé (poste), policy permissive gmail/calendar/drive — le
# verrou GLOBAL du profil ne doit jamais se substituer aux octrois de LA
# session (revue Codex P1 sur PR #110).
P1_ROOT="$TMP/mag-p1-nudeny"
mkdir -p "$P1_ROOT/alpha"
echo '{"gmail":{"read":true,"send":true},"calendar":{"read":true},"drive":{"read":true,"create":true,"zonesOnly":true,"writeFolders":["zoneA"]}}' \
  > "$P1_ROOT/alpha/policy.json"

out_p1="$(GWSA_ROOT="$P1_ROOT" PYTHONPATH="$(pwd)" "$PY" -c "
import gateway.broker_server as bs
from gateway.sessions import create_session, session_unlock, session_grant_capability
from gateway.errors import GatewayError

bs.run_gws_local = lambda *a, **k: {'ok': True}

def call(session_id, args):
    try:
        bs.handle_exec('alpha', args, 'test', session_id=session_id)
        return 'ok'
    except GatewayError as e:
        return 'refus:' + e.code

# (a) session nue (aucun octroi) sur profil déverrouillé → refus Gmail ET Calendar.
s_naked = create_session(client='t').session_id
print('naked_gmail', call(s_naked, ['gmail', 'users', 'messages', 'list']))
print('naked_calendar', call(s_naked, ['calendar', 'events', 'list']))

# (b) session avec session unlock → lecture Gmail autorisée (policy).
s_unlocked = create_session(client='t').session_id
session_unlock(s_unlocked, 'alpha', minutes=15)
print('unlocked_gmail', call(s_unlocked, ['gmail', 'users', 'messages', 'list']))
print('unlocked_calendar', call(s_unlocked, ['calendar', 'events', 'list']))

# (c) session avec seulement grant-capability gmail:read → lit Gmail, refuse
# Calendar/Drive.
s_fine = create_session(client='t').session_id
session_grant_capability(s_fine, 'alpha', 'gmail', 'read', hours=1)
print('fine_gmail', call(s_fine, ['gmail', 'users', 'messages', 'list']))
print('fine_calendar', call(s_fine, ['calendar', 'events', 'list']))
print('fine_drive', call(s_fine, ['drive', 'files', 'create', '--json', '{\"parents\":[\"zoneA\"]}']))

# (d) legacy sans session_id → inchangé (autorisé par policy).
print('legacy_gmail', call('', ['gmail', 'users', 'messages', 'list']))
")"

[[ "$out_p1" == *"naked_gmail refus:policy"* && "$out_p1" == *"naked_calendar refus:policy"* \
  && "$out_p1" == *"unlocked_gmail ok"* && "$out_p1" == *"unlocked_calendar ok"* \
  && "$out_p1" == *"fine_gmail ok"* && "$out_p1" == *"fine_calendar refus:policy"* \
  && "$out_p1" == *"fine_drive refus:policy"* && "$out_p1" == *"legacy_gmail ok"* ]] \
  && pass "P1 sécu : session nue = deny-all (verrou poste n'y substitue pas ; unlock/capacité/legacy inchangés)" \
  || fail "P1 sécu : session nue accède sans octroi ($out_p1)"

section "droits par session — lot 3 (fiche 0076, session list + sous-agents + bootstrap + audit)"

# ── (a) mag session list : ≥2 sessions actives, configs DISTINCTES (capacités,
# unlocks, TTL restant, parent/delegated) ──
L3_ROOT="$TMP/mag-lot3-list"
mkdir -p "$L3_ROOT"
out_list_cfg="$(GWSA_ROOT="$L3_ROOT" PYTHONPATH="$(pwd)" "$PY" -c "
import json
from gateway.sessions import create_session, session_unlock, session_grant_capability, list_sessions

s1 = create_session(client='c1')
s2 = create_session(client='c2')
session_unlock(s1.session_id, 'alpha', 30)
session_grant_capability(s2.session_id, 'alpha', 'gmail', 'read', hours=2)

rows = {r['session_id']: r for r in list_sessions()}
r1, r2 = rows[s1.session_id], rows[s2.session_id]
assert 'alpha' in r1['unlocks'] and not r1['capabilities'], r1
assert r2['capabilities'] and r2['capabilities'][0]['service'] == 'gmail', r2
assert not r2['unlocks'], r2
assert r1['ttl_seconds_left'] > 0 and r2['ttl_seconds_left'] > 0, (r1, r2)
print('ok')
")"
[[ "$out_list_cfg" == "ok" ]] \
  && pass "mag session list : ≥2 sessions, configs distinctes (capacités/unlocks/TTL)" \
  || fail "mag session list : configs non distinctes ($out_list_cfg)"

# ── (a-bis) mag session show affiche aussi les capacités fines (lot 2) ──
sid_show3="$(GWSA_ROOT="$L3_ROOT" PYTHONPATH="$(pwd)" "$PY" -c "
from gateway.sessions import create_session, session_grant_capability
s = create_session(client='show3')
session_grant_capability(s.session_id, 'alpha', 'drive', 'read', hours=1)
print(s.session_id)
")"
out_show3="$(GWSA_ROOT="$L3_ROOT" "$GWSA" session show "$sid_show3" 2>&1)"
[[ "$out_show3" == *'"service": "drive"'* && "$out_show3" == *'"operation": "read"'* ]] \
  && pass "mag session show : affiche les capacités fines (lot 2)" \
  || fail "mag session show : capacités fines absentes ($out_show3)"

# ── (b) sous-agent : héritage ⊆ parent, jamais plus ──
out_inherit="$(GWSA_ROOT="$L3_ROOT" PYTHONPATH="$(pwd)" "$PY" -c "
from gateway.sessions import (
    create_session, create_child_session, session_grant_capability,
    session_has_capability,
)
root = create_session(client='root3')
session_grant_capability(root.session_id, 'alpha', 'gmail', 'read', hours=1)
child = create_child_session(root.session_id)
# le parent a la capacité, jamais accordée directement à l'enfant → l'enfant la
# VOIT via la chaîne d'ancêtres (héritage), mais rien de PLUS que le parent.
child_has = session_has_capability(child.session_id, 'alpha', 'gmail', 'read')
child_lacks_more = session_has_capability(child.session_id, 'alpha', 'drive', 'read')
print(child_has, child_lacks_more)
")"
[[ "$out_inherit" == "True False" ]] \
  && pass "sous-agents : héritage ⊆ parent (l'enfant voit exactement les capacités du parent)" \
  || fail "sous-agents : héritage incorrect ($out_inherit)"

# ── (c) sous-agent : ne peut PAS élargir (session_grant_capability / unlock / grant refusés) ──
out_child_widen="$(GWSA_ROOT="$L3_ROOT" PYTHONPATH="$(pwd)" "$PY" -c "
from gateway.sessions import create_session, create_child_session, session_grant_capability, session_unlock, session_grant_drive
from gateway.errors import GatewayError
root = create_session(client='root3b')
child = create_child_session(root.session_id)
results = []
for fn, args in (
    (session_grant_capability, (child.session_id, 'alpha', 'gmail', 'read')),
    (session_unlock, (child.session_id, 'alpha', 30)),
    (session_grant_drive, (child.session_id, 'alpha', 'fid123')),
):
    try:
        fn(*args)
        results.append('no-raise')
    except GatewayError as e:
        results.append('refused' if e.code == 'error' else 'wrong:' + e.code)
print(' '.join(results))
")"
[[ "$out_child_widen" == "refused refused refused" ]] \
  && pass "sous-agents : élargissement (grant-capability/unlock/grant) refusé depuis un enfant" \
  || fail "sous-agents : élargissement non bloqué ($out_child_widen)"

# ── (c-bis) sous-agent : access_request (élargissement) refusé depuis un enfant ──
out_child_ar="$(GWSA_ROOT="$L3_ROOT" PYTHONPATH="$(pwd)" "$PY" -c "
import gateway.api as api
from gateway.sessions import create_session, create_child_session
root = api.__dict__['create_session'] if False else create_session(client='root3c')
child = create_child_session(root.session_id)
try:
    api.access_request(alias='alpha', kind='session_unlock', session=child.session_id)
    print('no-raise')
except api.GatewayError as e:
    print('OK' if e.code == 'delegated' else 'wrong:' + e.code)
")"
[[ "$out_child_ar" == "OK" ]] \
  && pass "sous-agents : access_request (élargissement) refusé depuis un enfant" \
  || fail "sous-agents : access_request enfant non bloqué ($out_child_ar)"

# ── (c-ter) la CRÉATION d'un enfant n'exige pas de signature (aucun droit nouveau) ──
out_child_create="$(GWSA_ROOT="$L3_ROOT" PYTHONPATH="$(pwd)" "$PY" -c "
from gateway.sessions import create_session, create_child_session
root = create_session(client='root3d')
child = create_child_session(root.session_id)
print(child.delegated, len(child.capabilities))
")"
[[ "$out_child_create" == "True 0" ]] \
  && pass "sous-agents : création d'enfant sans signature (zéro droit nouveau)" \
  || fail "sous-agents : création d'enfant ($out_child_create)"

# ── (d) revoke-descendants : purge les descendants, PAS la racine ──
L3_REVOKE="$TMP/mag-lot3-revoke"
mkdir -p "$L3_REVOKE"
touch "$L3_REVOKE/.strong-auth" 2>/dev/null || true
read root_id child_id grandchild_id <<< "$(GWSA_ROOT="$L3_REVOKE" PYTHONPATH="$(pwd)" "$PY" -c "
from gateway.sessions import create_session, create_child_session
root = create_session(client='rootrv')
child = create_child_session(root.session_id)
grandchild = create_child_session(child.session_id)
print(root.session_id, child.session_id, grandchild.session_id)
")"
GWSA_ROOT="$L3_REVOKE" GWSA_ELICITATION_MOCK=1 "$GWSA" elicitation enroll --mock >/dev/null 2>&1
GWSA_ROOT="$L3_REVOKE" GWSA_ELICITATION_MOCK=1 "$GWSA" session revoke-descendants "$root_id" >/dev/null 2>&1
out_after_revoke="$(GWSA_ROOT="$L3_REVOKE" PYTHONPATH="$(pwd)" "$PY" -c "
from gateway.sessions import get_session
print(get_session('$root_id') is not None, get_session('$child_id') is None, get_session('$grandchild_id') is None)
")"
[[ "$out_after_revoke" == "True True True" ]] \
  && pass "sous-agents : revoke-descendants purge toute la descendance, PAS la racine" \
  || fail "sous-agents : revoke-descendants ($out_after_revoke)"

# ── (e) bootstrap : mag session open crée une session racine SIGNÉE + imprime le jeton ──
L3_OPEN="$TMP/mag-lot3-open"
mkdir -p "$L3_OPEN"
GWSA_ROOT="$L3_OPEN" GWSA_ELICITATION_MOCK=1 "$GWSA" elicitation enroll --mock >/dev/null 2>&1
sid_opened="$(GWSA_ROOT="$L3_OPEN" GWSA_ELICITATION_MOCK=1 "$GWSA" session open test-client 2>/dev/null)"
out_opened_state="$(GWSA_ROOT="$L3_OPEN" PYTHONPATH="$(pwd)" "$PY" -c "
from gateway.sessions import get_session
s = get_session('$sid_opened')
print(s is not None, s.client if s else None, s.capabilities if s else None, s.delegated if s else None)
")"
[[ -n "$sid_opened" && "$out_opened_state" == "True test-client [] False" ]] \
  && pass "mag session open : crée une session racine signée, zéro capacité, jeton imprimé" \
  || fail "mag session open : session ($sid_opened → $out_opened_state)"

# ── (e-bis) mag session open SANS enrôlement → refus ──
L3_OPEN_UNENROLLED="$TMP/mag-lot3-open-unenrolled"
mkdir -p "$L3_OPEN_UNENROLLED"
GWSA_ROOT="$L3_OPEN_UNENROLLED" "$GWSA" session open test-client >/dev/null 2>&1
open_unenrolled_rc=$?
[[ "$open_unenrolled_rc" != 0 ]] \
  && pass "mag session open : refus sans enrôlement (pas de session sans geste signé)" \
  || fail "mag session open : accepté sans enrôlement à tort"

# ── (f) bootstrap sans jeton : access_request ne peut QUE pointer vers la création,
# jamais un accès aux données ──
out_bootstrap_ar="$(PYTHONPATH="$(pwd)" GWSA_ROOT="$L3_OPEN" "$PY" -c "
import gateway.api as api
r = api.access_request(alias='alpha', kind='session_unlock', session='')
print(r.get('kind'), 'mag session open' in r.get('suggested_command', ''))
")"
[[ "$out_bootstrap_ar" == "session_open True" ]] \
  && pass "bootstrap sans jeton : access_request sans session pointe vers « mag session open »" \
  || fail "bootstrap sans jeton : access_request ($out_bootstrap_ar)"

out_bootstrap_data="$(PYTHONPATH="$(pwd)" GWSA_ROOT="$L3_OPEN" "$PY" -c "
import gateway.api as api
try:
    api.gmail_list(alias='alpha', session='')
    print('no-raise')
except api.GatewayError as e:
    print('OK' if e.code == 'session' else 'wrong:' + e.code)
")"
[[ "$out_bootstrap_data" == "OK" ]] \
  && pass "bootstrap sans jeton : aucun accès donnée sans jeton (fail-closed, gmail_list)" \
  || fail "bootstrap sans jeton : accès donnée accepté sans jeton à tort ($out_bootstrap_data)"

# ── (g) audit : un appel RÉUSSI journalise session_id + service + opération + ressource ──
L3_AUDIT="$TMP/mag-lot3-audit"
mkdir -p "$L3_AUDIT/alpha"
out_audit="$(GWSA_ROOT="$L3_AUDIT" PYTHONPATH="$(pwd)" "$PY" -c "
import json
from pathlib import Path
import gateway.broker_server as bs
from gateway.sessions import create_session

s = create_session(client='audit3')

# NB : monkeypatcher subprocess.run directement toucherait AUSSI l'appel
# subprocess.run interne de gateway.usage.log_usage (même module partagé) —
# on stubbe run_gws_local à la place, pour laisser le vrai log-usage.py tourner.
bs.run_gws_local = lambda *a, **k: {'ok': True}
log = Path('$L3_AUDIT') / 'usage.jsonl'
log.unlink(missing_ok=True)
bs.handle_exec('alpha', ['gmail', 'users', 'messages', 'list'], 'audit-client', session_id=s.session_id)
entries = [json.loads(x) for x in log.read_text().splitlines()]
e = entries[-1]
print(e.get('decision'), e.get('session_id') == s.session_id, e.get('service'), e.get('operation'))
")"
[[ "$out_audit" == "ok True gmail read" ]] \
  && pass "audit : appel réussi journalise session_id + service + opération (pas seulement les refus)" \
  || fail "audit : appel réussi mal journalisé ($out_audit)"

section "droits par session — fiche 0080 (raffinements revue Codex #110)"

# ── (1) ressource pour les services non-Drive : Calendar, VRAI paramètre (calendarId) ──
CAP_NONDRIVE="$TMP/mag-0080-nondrive"
mkdir -p "$CAP_NONDRIVE/alpha"
echo '{"calendar":{"read":true,"create":true},"gmail":{"read":true}}' > "$CAP_NONDRIVE/alpha/policy.json"
out_res_cal="$(GWSA_ROOT="$CAP_NONDRIVE" PYTHONPATH="$(pwd)" "$PY" -c "
import json, subprocess, sys
caps = json.dumps([{'service':'calendar','operation':'read','resource':'cal123'}])
env = dict(__import__('os').environ, GWSA_SESSION_CAPS=caps)
def rc(cal_id):
    r = subprocess.run([sys.executable, 'scripts/policy-check.py', '$CAP_NONDRIVE/alpha',
                         'calendar','events','list','--params', json.dumps({'calendarId': cal_id})], env=env)
    return r.returncode
print('own', rc('cal123'))
print('other', rc('cal999'))
")"
[[ "$out_res_cal" == *"own 0"* && "$out_res_cal" == *"other 4"* ]] \
  && pass "capacités session : calendar:read:cal123 autorise cet agenda, refuse un autre" \
  || fail "capacités session : granularité ressource Calendar cassée ($out_res_cal)"

# ── (1) ressource pour les services non-Drive : Gmail, VRAI paramètre (labelIds, pluriel) ──
out_res_gmail="$(GWSA_ROOT="$CAP_NONDRIVE" PYTHONPATH="$(pwd)" "$PY" -c "
import json, subprocess, sys
caps = json.dumps([{'service':'gmail','operation':'read','resource':'LABEL_A'}])
env = dict(__import__('os').environ, GWSA_SESSION_CAPS=caps)
def rc(label_id):
    r = subprocess.run([sys.executable, 'scripts/policy-check.py', '$CAP_NONDRIVE/alpha',
                         'gmail','users','messages','list','--params',
                         json.dumps({'labelIds': [label_id]})], env=env)
    return r.returncode
print('own', rc('LABEL_A'))
print('other', rc('LABEL_B'))
")"
[[ "$out_res_gmail" == *"own 0"* && "$out_res_gmail" == *"other 4"* ]] \
  && pass "capacités session : gmail:read:LABEL_A autorise ce libellé (labelIds), refuse un autre" \
  || fail "capacités session : granularité ressource Gmail cassée ($out_res_gmail)"

# ── (1-P0) leurre : un « id » quelconque dans --params NE DOIT PAS usurper
# le paramètre opérant réel (labelId/calendarId) — revue adverse post-#110.
# gmail:read:LABEL_A ; appel ciblant en réalité LABEL_VICTIME (via le
# paramètre historiquement mal priorisé « labelId » singulier, absent du
# mapping) + un « id » = LABEL_A glissé en leurre → doit être REFUSÉ (aucun
# opérande fiable dérivable pour « messages list » hors labelIds pluriel).
out_res_decoy_gmail="$(GWSA_ROOT="$CAP_NONDRIVE" PYTHONPATH="$(pwd)" "$PY" -c "
import json, subprocess, sys
caps = json.dumps([{'service':'gmail','operation':'read','resource':'LABEL_A'}])
env = dict(__import__('os').environ, GWSA_SESSION_CAPS=caps)
r = subprocess.run([sys.executable, 'scripts/policy-check.py', '$CAP_NONDRIVE/alpha',
                     'gmail','users','messages','list','--params',
                     json.dumps({'labelId': 'LABEL_VICTIME', 'id': 'LABEL_A'})], env=env)
print(r.returncode)
")"
[[ "$out_res_decoy_gmail" == "4" ]] \
  && pass "P0 sécu : leurre --params (id=capacité accordée, labelId=cible réelle) refusé" \
  || fail "P0 sécu : leurre gmail accepté à tort — fail-open ($out_res_decoy_gmail)"

# ── (1-P0) même leurre côté Calendar : calendarId réel ≠ id leurré ──
out_res_decoy_cal="$(GWSA_ROOT="$CAP_NONDRIVE" PYTHONPATH="$(pwd)" "$PY" -c "
import json, subprocess, sys
caps = json.dumps([{'service':'calendar','operation':'read','resource':'cal123'}])
env = dict(__import__('os').environ, GWSA_SESSION_CAPS=caps)
r = subprocess.run([sys.executable, 'scripts/policy-check.py', '$CAP_NONDRIVE/alpha',
                     'calendar','events','get','--params',
                     json.dumps({'calendarId': 'cal999', 'id': 'cal123'})], env=env)
print(r.returncode)
")"
[[ "$out_res_decoy_cal" == "4" ]] \
  && pass "P0 sécu : leurre --params calendar (id=capacité accordée, calendarId=cible réelle) refusé" \
  || fail "P0 sécu : leurre calendar accepté à tort — fail-open ($out_res_decoy_cal)"

# ── (1-P0) calendar events get : le VRAI paramètre calendarId reste utilisable ──
out_res_cal_get="$(GWSA_ROOT="$CAP_NONDRIVE" PYTHONPATH="$(pwd)" "$PY" -c "
import json, subprocess, sys
caps = json.dumps([{'service':'calendar','operation':'read','resource':'cal123'}])
env = dict(__import__('os').environ, GWSA_SESSION_CAPS=caps)
r = subprocess.run([sys.executable, 'scripts/policy-check.py', '$CAP_NONDRIVE/alpha',
                     'calendar','events','get','--params',
                     json.dumps({'calendarId': 'cal123', 'eventId': 'evt1'})], env=env)
print(r.returncode)
")"
[[ "$out_res_cal_get" == "0" ]] \
  && pass "P0 sécu : calendar events get avec le vrai calendarId (pas eventId) reste autorisé" \
  || fail "P0 sécu : calendar events get sur-refusé à tort ($out_res_cal_get)"

# ── (1-P0) ops porteuses d'un « id » ambigu sans mapping (messages get,
# attachments get) : opérande non identifiable → fail-closed pour une
# capacité SCOPÉE, même si le « id » présent coïncide avec la ressource
# accordée (ce n'est pas un labelId, juste un homonyme de valeur) ──
out_res_ambiguous="$(GWSA_ROOT="$CAP_NONDRIVE" PYTHONPATH="$(pwd)" "$PY" -c "
import json, subprocess, sys
caps = json.dumps([{'service':'gmail','operation':'read','resource':'LABEL_A'}])
env = dict(__import__('os').environ, GWSA_SESSION_CAPS=caps)
def rc(args):
    r = subprocess.run([sys.executable, 'scripts/policy-check.py', '$CAP_NONDRIVE/alpha'] + args, env=env)
    return r.returncode
print('messages_get', rc(['gmail','users','messages','get','--params', json.dumps({'id':'LABEL_A'})]))
print('attachments_get', rc(['gmail','users','messages','attachments','get','--params',
                              json.dumps({'userId':'me','messageId':'m','id':'LABEL_A'})]))
")"
[[ "$out_res_ambiguous" == *"messages_get 4"* && "$out_res_ambiguous" == *"attachments_get 4"* ]] \
  && pass "P0 sécu : messages/attachments get sans opérande fiable → fail-closed sous capacité scopée" \
  || fail "P0 sécu : opérande ambigu accepté à tort ($out_res_ambiguous)"

# ── (P2 finding #3, Codex PR #118) : forme --flag=valeur (pas seulement
# --flag valeur séparé) doit être reconnue par operand_resource — sinon une
# capacité scopée VALIDE se voyait refusée à tort (fail-closed par accident,
# pas une faille, mais une régression fonctionnelle). ──
out_res_eqform="$(GWSA_ROOT="$CAP_NONDRIVE" PYTHONPATH="$(pwd)" "$PY" -c "
import json, subprocess, sys
caps = json.dumps([{'service':'gmail','operation':'read','resource':'LABEL_A'}])
env = dict(__import__('os').environ, GWSA_SESSION_CAPS=caps)
r = subprocess.run([sys.executable, 'scripts/policy-check.py', '$CAP_NONDRIVE/alpha',
                     'gmail','users','messages','list',
                     '--params=' + json.dumps({'labelIds': ['LABEL_A']})], env=env)
print(r.returncode)
")"
[[ "$out_res_eqform" == "0" ]] \
  && pass "P2 finding #3 : forme --params=<json> (avec =) reconnue, capacité scopée valide autorisée" \
  || fail "P2 finding #3 : forme --params=<json> refusée à tort ($out_res_eqform)"

# ── (P2 finding #4, Codex PR #118) : calendar events import portait
# calendarId mais était absent du mapping → une cap calendar:create:cal123
# refusait à tort un import dans cet agenda. ──
out_res_import="$(GWSA_ROOT="$CAP_NONDRIVE" PYTHONPATH="$(pwd)" "$PY" -c "
import json, subprocess, sys
caps = json.dumps([{'service':'calendar','operation':'create','resource':'cal123'}])
env = dict(__import__('os').environ, GWSA_SESSION_CAPS=caps)
r = subprocess.run([sys.executable, 'scripts/policy-check.py', '$CAP_NONDRIVE/alpha',
                     'calendar','events','import',
                     '--params=' + json.dumps({'calendarId': 'cal123'})], env=env)
print(r.returncode)
")"
[[ "$out_res_import" == "0" ]] \
  && pass "P2 finding #4 : calendar:create:cal123 autorise events import dans cet agenda" \
  || fail "P2 finding #4 : events import refusé à tort — mapping calendarId manquant ($out_res_import)"

# ── (2) capacités déléguées figées à la création (snapshot) ──
L3_SNAPSHOT="$TMP/mag-0080-snapshot"
mkdir -p "$L3_SNAPSHOT"
out_snapshot="$(GWSA_ROOT="$L3_SNAPSHOT" PYTHONPATH="$(pwd)" "$PY" -c "
from gateway.sessions import (
    create_session, create_child_session, session_grant_capability,
    session_has_capability,
)
root = create_session(client='snap-root')
child = create_child_session(root.session_id)
# octroi au PARENT après la création de l'enfant : ne doit PAS s'exposer à
# l'enfant déjà créé (le payload signé de l'enfant ne nommait que le parent
# au moment T, pas ses octrois futurs).
session_grant_capability(root.session_id, 'alpha', 'drive', 'read', hours=1)
print(session_has_capability(child.session_id, 'alpha', 'drive', 'read'),
      session_has_capability(root.session_id, 'alpha', 'drive', 'read'))
")"
[[ "$out_snapshot" == "False True" ]] \
  && pass "sous-agents : capacités figées à la création — octroi ultérieur au parent n'élargit pas l'enfant" \
  || fail "sous-agents : capacités NON figées — fuite passive vers l'enfant ($out_snapshot)"

# ── (2-bis) le snapshot capture bien ce que le parent possédait AVANT la création ──
out_snapshot_before="$(GWSA_ROOT="$L3_SNAPSHOT" PYTHONPATH="$(pwd)" "$PY" -c "
from gateway.sessions import (
    create_session, create_child_session, session_grant_capability,
    session_has_capability,
)
root = create_session(client='snap-root2')
session_grant_capability(root.session_id, 'alpha', 'gmail', 'read', hours=1)
child = create_child_session(root.session_id)
print(session_has_capability(child.session_id, 'alpha', 'gmail', 'read'))
")"
[[ "$out_snapshot_before" == "True" ]] \
  && pass "sous-agents : le snapshot capture les capacités déjà accordées au moment de la création" \
  || fail "sous-agents : snapshot manquant à la création ($out_snapshot_before)"

# ── (2-ter, P2 finding #2, Codex PR #118) : une sous-session ÉCRITE PAR
# L'ANCIENNE révision (upgrade in-place, fichier JSON sans le marqueur
# capabilities_snapshot, capabilities locales vides comme le faisait l'ancien
# create_child_session) doit continuer à voir les capacités actives de son
# parent via le repli legacy (_ancestor_chain) — pas les perdre d'un coup. ──
out_legacy_migration="$(GWSA_ROOT="$L3_SNAPSHOT" PYTHONPATH="$(pwd)" "$PY" -c "
import json
from gateway.sessions import (
    create_session, create_child_session, session_grant_capability,
    session_has_capability, _path,
)
root = create_session(client='legacy-root')
session_grant_capability(root.session_id, 'alpha', 'tasks', 'read', hours=1)
child = create_child_session(root.session_id)
# Réécrit le fichier de l'enfant comme le faisait l'ANCIENNE révision : pas de
# marqueur, capabilities locales vides (l'ancien create_child_session ne
# stockait que parent_id, jamais de snapshot).
p = _path(child.session_id)
data = json.loads(p.read_text())
data['capabilities'] = []
data.pop('capabilities_snapshot', None)
p.write_text(json.dumps(data))
print(session_has_capability(child.session_id, 'alpha', 'tasks', 'read'))
")"
[[ "$out_legacy_migration" == "True" ]] \
  && pass "P2 finding #2 : sous-session pré-snapshot (upgrade in-place) garde ses capacités héritées (repli legacy)" \
  || fail "P2 finding #2 : sous-session pré-snapshot a perdu ses capacités héritées ($out_legacy_migration)"

# ── fiche 0085 : unlock + zones Drive figés à la création de la sous-session
# (même patron que le snapshot des capacités, fiche 0080) ──
L3_0085="$TMP/mag-0085-snapshot"
mkdir -p "$L3_0085"

# ── (1) unlock accordé au parent APRÈS la création d'un enfant ne s'expose
# pas passivement à l'enfant déjà créé ──
out_0085_unlock="$(GWSA_ROOT="$L3_0085" PYTHONPATH="$(pwd)" "$PY" -c "
from gateway.sessions import create_session, create_child_session, session_unlock, is_session_unlocked
root = create_session(client='0085-unlock-root')
child = create_child_session(root.session_id)
session_unlock(root.session_id, 'alpha', 30)
print(is_session_unlocked(child.session_id, 'alpha'), is_session_unlocked(root.session_id, 'alpha'))
")"
[[ "$out_0085_unlock" == "False True" ]] \
  && pass "fiche 0085 : unlock figé à la création — unlock ultérieur du parent n'élargit pas l'enfant" \
  || fail "fiche 0085 : unlock NON figé — fuite passive vers l'enfant ($out_0085_unlock)"

# ── (1-bis) le snapshot capture bien l'unlock déjà actif AVANT la création ──
out_0085_unlock_before="$(GWSA_ROOT="$L3_0085" PYTHONPATH="$(pwd)" "$PY" -c "
from gateway.sessions import create_session, create_child_session, session_unlock, is_session_unlocked
root = create_session(client='0085-unlock-root2')
session_unlock(root.session_id, 'alpha', 30)
child = create_child_session(root.session_id)
print(is_session_unlocked(child.session_id, 'alpha'))
")"
[[ "$out_0085_unlock_before" == "True" ]] \
  && pass "fiche 0085 : le snapshot capture l'unlock déjà actif au moment de la création" \
  || fail "fiche 0085 : snapshot d'unlock manquant à la création ($out_0085_unlock_before)"

# ── (2) zone Drive accordée au parent APRÈS la création d'un enfant ne
# s'expose pas passivement à l'enfant déjà créé ──
out_0085_zone="$(GWSA_ROOT="$L3_0085" PYTHONPATH="$(pwd)" "$PY" -c "
from gateway.sessions import create_session, create_child_session, session_grant_drive, active_drive_zones
root = create_session(client='0085-zone-root')
child = create_child_session(root.session_id)
session_grant_drive(root.session_id, 'alpha', 'FOLDERX123456789012')
print('FOLDERX123456789012' in active_drive_zones(child.session_id, 'alpha'),
      'FOLDERX123456789012' in active_drive_zones(root.session_id, 'alpha'))
")"
[[ "$out_0085_zone" == "False True" ]] \
  && pass "fiche 0085 : zone Drive figée à la création — grant ultérieur du parent n'élargit pas l'enfant" \
  || fail "fiche 0085 : zone Drive NON figée — fuite passive vers l'enfant ($out_0085_zone)"

# ── (2-bis) le snapshot capture bien la zone Drive déjà active AVANT la création ──
out_0085_zone_before="$(GWSA_ROOT="$L3_0085" PYTHONPATH="$(pwd)" "$PY" -c "
from gateway.sessions import create_session, create_child_session, session_grant_drive, active_drive_zones
root = create_session(client='0085-zone-root2')
session_grant_drive(root.session_id, 'alpha', 'FOLDERY123456789012')
child = create_child_session(root.session_id)
print('FOLDERY123456789012' in active_drive_zones(child.session_id, 'alpha'))
")"
[[ "$out_0085_zone_before" == "True" ]] \
  && pass "fiche 0085 : le snapshot capture la zone Drive déjà active au moment de la création" \
  || fail "fiche 0085 : snapshot de zone Drive manquant à la création ($out_0085_zone_before)"

# ── (3) sous-session pré-snapshot (legacy, upgrade in-place, sans marqueur
# capabilities_snapshot) garde son héritage LIVE pour unlock + zones Drive
# (même repli legacy que les capacités fines) ──
out_0085_legacy="$(GWSA_ROOT="$L3_0085" PYTHONPATH="$(pwd)" "$PY" -c "
import json
from gateway.sessions import (
    create_session, create_child_session, session_unlock, session_grant_drive,
    is_session_unlocked, active_drive_zones, _path,
)
root = create_session(client='0085-legacy-root')
child = create_child_session(root.session_id)
# Réécrit le fichier de l'enfant comme le faisait l'ANCIENNE révision (pré-0085) :
# pas de marqueur, unlocks/drive_zones locaux vides.
p = _path(child.session_id)
data = json.loads(p.read_text())
data['unlocks'] = {}
data['drive_zones'] = {}
data.pop('capabilities_snapshot', None)
data.pop('grants_snapshot', None)
p.write_text(json.dumps(data))
# Octroi au parent APRÈS l'écriture du fichier legacy : une session non
# marquée retombe sur la résolution live (comme pour les capacités) donc DOIT
# le voir.
session_unlock(root.session_id, 'alpha', 30)
session_grant_drive(root.session_id, 'alpha', 'FOLDERZ123456789012')
print(is_session_unlocked(child.session_id, 'alpha'),
      'FOLDERZ123456789012' in active_drive_zones(child.session_id, 'alpha'))
")"
[[ "$out_0085_legacy" == "True True" ]] \
  && pass "fiche 0085 : sous-session pré-snapshot garde l'héritage live (unlock + zones Drive, repli legacy)" \
  || fail "fiche 0085 : sous-session pré-snapshot a perdu son héritage live ($out_0085_legacy)"

# ── (4) non-régression : la révocation/nettoyage côté parent reste correcte
# (une session révoquée reste invisible, snapshot ou pas) ──
out_0085_revoke="$(GWSA_ROOT="$L3_0085" PYTHONPATH="$(pwd)" "$PY" -c "
from gateway.sessions import create_session, create_child_session, session_unlock, close_session, get_session
root = create_session(client='0085-revoke-root')
session_unlock(root.session_id, 'alpha', 30)
child = create_child_session(root.session_id)
close_session(root.session_id)
print(get_session(root.session_id) is None, get_session(child.session_id) is None)
")"
[[ "$out_0085_revoke" == "True True" ]] \
  && pass "fiche 0085 : non-régression — fermer le parent purge aussi l'enfant snapshotté" \
  || fail "fiche 0085 : non-régression revoke ($out_0085_revoke)"

# ── (5) petit-enfant d'un parent LEGACY (upgrade in-place) : le snapshot du
# petit-fils doit se construire depuis l'état EFFECTIF résolu du parent (via
# son repli legacy), pas sa seule liste locale brute — sinon il perd tout
# (finding #2, Codex PR #118, étendu à unlock/zones par la fiche 0085) ──
out_0085_grandchild="$(GWSA_ROOT="$L3_0085" PYTHONPATH="$(pwd)" "$PY" -c "
import json
from gateway.sessions import (
    create_session, create_child_session, session_unlock, session_grant_drive,
    is_session_unlocked, active_drive_zones, _path,
)
root = create_session(client='0085-gc-root')
session_unlock(root.session_id, 'beta', 30)
session_grant_drive(root.session_id, 'beta', 'FOLDERW123456789012')
mid = create_child_session(root.session_id)
# mid devient legacy (upgrade in-place) : marqueur absent, locaux vides — mais
# mid GARDE l'accès live à root via le repli legacy (test 3 ci-dessus).
p = _path(mid.session_id)
data = json.loads(p.read_text())
data['unlocks'] = {}
data['drive_zones'] = {}
data.pop('capabilities_snapshot', None)
data.pop('grants_snapshot', None)
p.write_text(json.dumps(data))
grandchild = create_child_session(mid.session_id)
print(is_session_unlocked(grandchild.session_id, 'beta'),
      'FOLDERW123456789012' in active_drive_zones(grandchild.session_id, 'beta'))
")"
[[ "$out_0085_grandchild" == "True True" ]] \
  && pass "fiche 0085 : petit-enfant d'un parent legacy hérite via l'état effectif résolu (pas la liste locale brute)" \
  || fail "fiche 0085 : petit-enfant d'un parent legacy a perdu l'héritage ($out_0085_grandchild)"

# ── (6, Codex PR #119 finding P1) : un fichier de sous-session au format
# 0080 (marqueur capabilities_snapshot présent, marqueur grants_snapshot
# 0085 ABSENT, unlocks/drive_zones locaux vides — parce qu'à l'époque 0080
# ces deux grains n'étaient jamais figés, seulement les capacités) doit
# CONTINUER à voir en LIVE l'unlock + la zone Drive de son parent après
# l'upgrade vers 0085 — seules ses capacités suivent, elles, le snapshot ──
out_0085_format0080="$(GWSA_ROOT="$L3_0085" PYTHONPATH="$(pwd)" "$PY" -c "
import json
from gateway.sessions import (
    create_session, create_child_session, session_unlock, session_grant_drive,
    session_grant_capability, is_session_unlocked, active_drive_zones,
    session_has_capability, _path,
)
root = create_session(client='0085-fmt0080-root')
session_grant_capability(root.session_id, 'alpha', 'gmail', 'read', hours=1)
child = create_child_session(root.session_id)
# Réécrit le fichier de l'enfant comme le faisait la révision 0080 :
# capabilities_snapshot=True (les capacités, elles, étaient déjà figées),
# mais AUCUN marqueur 0085 (grants_snapshot) et unlocks/drive_zones locaux
# vides — l'ancien create_child_session ne figeait pas ces deux grains.
p = _path(child.session_id)
data = json.loads(p.read_text())
data['unlocks'] = {}
data['drive_zones'] = {}
data.pop('grants_snapshot', None)
p.write_text(json.dumps(data))
# Octrois au parent APRÈS l'écriture du fichier 0080 :
session_unlock(root.session_id, 'alpha', 30)
session_grant_drive(root.session_id, 'alpha', 'FOLDERV123456789012')
session_grant_capability(root.session_id, 'alpha', 'drive', 'read', hours=1)
print(
    is_session_unlocked(child.session_id, 'alpha'),
    'FOLDERV123456789012' in active_drive_zones(child.session_id, 'alpha'),
    session_has_capability(child.session_id, 'alpha', 'gmail', 'read'),
    session_has_capability(child.session_id, 'alpha', 'drive', 'read'),
)
")"
[[ "$out_0085_format0080" == "True True True False" ]] \
  && pass "fiche 0085 (Codex P1) : sous-session format 0080 garde unlock/zones EN LIVE, capacités restent figées au snapshot" \
  || fail "fiche 0085 (Codex P1) : marqueur réutilisé à tort — régression sur unlock/zones d'une session 0080 ($out_0085_format0080)"

# ── (3) audit : la catégorie journalisée suit l'autorisation (drafts/share…) ──
L3_AUDIT_CAT="$TMP/mag-0080-audit-cat"
mkdir -p "$L3_AUDIT_CAT/alpha"
out_audit_cat="$(GWSA_ROOT="$L3_AUDIT_CAT" PYTHONPATH="$(pwd)" "$PY" -c "
import json
from pathlib import Path
import gateway.broker_server as bs
from gateway.sessions import create_session

s = create_session(client='audit-cat')
bs.run_gws_local = lambda *a, **k: {'ok': True}
log = Path('$L3_AUDIT_CAT') / 'usage.jsonl'
log.unlink(missing_ok=True)
bs.handle_exec('alpha', ['gmail', 'users', 'drafts', 'create', '--json', '{}'], 'audit-client', session_id=s.session_id)
bs.handle_exec('alpha', ['drive', 'permissions', 'create', '--params', '{\"fileId\":\"f1\"}'], 'audit-client', session_id=s.session_id)
entries = [json.loads(x) for x in log.read_text().splitlines()]
print(entries[-2].get('operation'), entries[-1].get('operation'))
")"
[[ "$out_audit_cat" == "drafts share" ]] \
  && pass "audit : catégorie service-aware (gmail drafts, drive share) — pas juste « create »" \
  || fail "audit : catégorie d'audit non alignée sur l'autorisation ($out_audit_cat)"

# ── (P2) audit : drive files update {trashed:true} → « delete » (Option A,
# fiche 0037), pas « update » — même reclassement que policy-check.py ──
out_audit_trash="$(PYTHONPATH="$(pwd)" "$PY" -c "
from gateway.usage import infer_call
print(infer_call(['drive', 'files', 'update', '--params', '{\"fileId\":\"f1\"}',
                   '--json', '{\"trashed\": true}'])[1])
print(infer_call(['drive', 'files', 'update', '--params', '{\"fileId\":\"f1\"}',
                   '--json', '{\"trashed\": false}'])[1])
")"
[[ "$out_audit_trash" == $'delete\nupdate' ]] \
  && pass "audit : drive files update {trashed:true} journalisé « delete », {false} reste « update »" \
  || fail "audit : trashed→delete non répercuté côté audit ($out_audit_trash)"

# ── (P2 finding #1, Codex PR #118) : un « drive files copy » réussi doit
# être audité sur le PARENT DE DESTINATION (ce que check_drive autorise
# réellement, via --json.parents), pas le fileId SOURCE (--params) — sinon
# le triplet journalisé n'identifie pas la capacité qui a autorisé l'appel. ──
out_audit_copy="$(PYTHONPATH="$(pwd)" "$PY" -c "
from gateway.usage import infer_call
service, operation, resource = infer_call([
    'drive', 'files', 'copy', '--params', '{\"fileId\":\"SRC123\"}',
    '--json', '{\"parents\":[\"ZONE456\"]}',
])
print(resource)
")"
[[ "$out_audit_copy" == "ZONE456" ]] \
  && pass "audit : drive files copy journalise le parent de DESTINATION (ZONE456), pas le fileId source" \
  || fail "audit : drive files copy journalise encore la source, pas ce qui a autorisé ($out_audit_copy)"

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

if grep -qE 'PRODUCT_SLUG *= *"[A-Za-z0-9._-]+"' gateway/config.py \
  && grep -q 'SYS_SWIFTC="/usr/bin/swiftc"' bin/mag \
  && grep -q 'ensure_sign_bin' bin/mag \
  && grep -qE '^[[:space:]]*"\$SYS_SWIFTC"' bin/mag \
  && ! grep -qE '^[[:space:]]*command -v swiftc' bin/mag \
  && ! grep -qE '^[[:space:]]*swiftc ' bin/mag; then
  pass "touchid : PRODUCT_SLUG + swiftc en chemin absolu (SYS_SWIFTC)"
else
  fail "touchid : PRODUCT_SLUG / SYS_SWIFTC / ensure_sign_bin manquant (ou swiftc via PATH)"
fi

# Non-régression : l'élicitation signée (strongauth) doit EXÉCUTER le binaire
# nommé, pas `swift` nu — sinon le dialogue Touch ID réaffiche « swift-frontend »
# (le bug : GWSA_TOUCHID_BIN était exporté mais jamais lu côté Python).
if grep -q '_sign_helper_cmd' gateway/elicitation.py \
  && grep -q 'GWSA_SIGN_BIN' gateway/elicitation.py \
  && grep -q 'PRODUCT_SLUG' gateway/elicitation.py; then
  pass "touchid : élicitation signée passe par le binaire nommé (pas swift nu)"
else
  fail "touchid : elicitation.py n'utilise pas le binaire nommé (dialogue swift-frontend)"
fi

# Sous strongauth, add sans email doit refuser avant Touch ID (fiche 0032 / review #50)
printf '{"installed":{"client_id":"hermetic-test","client_secret":"not-a-real-secret"}}\n' \
  > "$GWSA_ROOT/client_secret.json"
touch "$GWSA_ROOT/.strong-auth"
out_add="$("$GWSA" add newacct 2>&1)"; rc_add=$?
rm -f "$GWSA_ROOT/.strong-auth"
if [[ "$rc_add" -eq 3 ]] \
  && echo "$out_add" | grep -q 'email requis quand strongauth'; then
  pass "touchid : mag add sans email refusé sous strongauth (exit 3)"
else
  fail "touchid : add sans email sous strongauth — rc=$rc_add out=$(echo "$out_add" | head -c 160)"
fi

# Admin : unlock/grant doivent attendre Touch ID > 20 s (sinon Failed to fetch)
if grep -q 'GWSA_TIMEOUT_AUTH_MS = 120000' admin/server.js \
  && grep -q 'holdHttpForAuth' admin/server.js \
  && grep -q 'authGwsaResult' admin/server.js \
  && grep -q 'server.on("error"' admin/server.js \
  && grep -q 'connexion perdue avec l'\''admin' admin/index.html \
  && grep -q 'pidfile fantôme' bin/mag; then
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

# --- mag dev test — déploiement + admin + marqueur PR ----------------------

section "mag dev test — déployer, redémarrer l'admin, vérifier afSearchHits"

DEVTEST_DEP="$TMP/devdeploy"
DEVTEST_ROOT="$TMP/devgwsa"
# Port éphémère : évite les orphelins d'un run précédent sur 49201.
DEVTEST_PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"
mkdir -p "$DEVTEST_ROOT"

if "$GWSA" dev test --help 2>&1 | grep -q 'mag dev test'; then
  pass "dev test --help : usage affiché"
else
  fail "dev test --help : usage manquant"
fi

if grep -q 'cmd_dev_test' bin/mag \
  && grep -q 'afSearchHits' bin/mag \
  && grep -q 'GWSA_ADMIN_NO_OPEN' bin/mag; then
  pass "dev test : implémentation + marqueur afSearchHits + no-open admin"
else
  fail "dev test : marqueurs d'implémentation manquants dans mag"
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
    && echo "$out" | grep -q './bin/mag dev test'; then
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

section "mag dev — deploy isolé, use, list, status, remove (hermétique)"
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

section "approbation par passkey distante (fiche 0078, ADR-0009)"

# Simulateur de signeur téléphone (paire P-256 de test, via openssl — aucune
# dépendance ajoutée) : tests/testlib/phone_signer.py. Hermétique : ni compte
# réel, ni vrai téléphone, ni réseau (InMemoryChannel, ADR-0009 §4).

# CA6 — enrôlement device-bound : refuse BE (backup-eligible) armé et PIN,
# accepte device-bound + biométrie. Refusé À L'ENROLEMENT, pas seulement à
# la vérification (ADR-0009 §3).
RA6="$TMP/mag-remote-approval-ca6"
out_ca6="$(GWSA_ROOT="$RA6" "$PY" -c "
import sys; sys.path.insert(0, 'tests')
import tempfile
from pathlib import Path
from testlib.phone_signer import generate_keypair
from gateway.remote_approval import enroll_phone, RemoteApprovalError

tmp = Path(tempfile.mkdtemp())
_, pub = generate_keypair(tmp)
out = []
try:
    enroll_phone({'credential_id': 'c', 'aaguid': 'a', 'public_key': pub, 'uv': 'biometric', 'be': True})
    out.append('BE:accepted')
except RemoteApprovalError:
    out.append('BE:refused')
try:
    enroll_phone({'credential_id': 'c', 'aaguid': 'a', 'public_key': pub, 'uv': 'pin', 'be': False})
    out.append('PIN:accepted')
except RemoteApprovalError:
    out.append('PIN:refused')
enr = enroll_phone({'credential_id': 'cred1', 'aaguid': 'a', 'public_key': pub, 'uv': 'biometric', 'be': False, 'sign_count': 0})
out.append('DEVICE_BOUND:' + enr.credential_id)
print(' '.join(out))
")"
[[ "$out_ca6" == "BE:refused PIN:refused DEVICE_BOUND:cred1" ]] \
  && pass "remote_approval : enrôlement refuse BE armé / PIN, accepte device-bound + biométrie (CA6)" \
  || fail "remote_approval : enrôlement CA6 ($out_ca6)"

# CA4 — l'enrôlement ne persiste QUE la clé publique (+ credential_id/aaguid/
# sign_count) : aucun secret Google côté « téléphone », dossier 0700.
out_ca4="$(GWSA_ROOT="$RA6" "$PY" -c "
import json, os
from gateway.remote_approval import enrollment_path, remote_approval_dir
data = json.loads(enrollment_path().read_text())
perm = oct(remote_approval_dir().stat().st_mode)[-3:]
print(sorted(data.keys()), perm)
")"
[[ "$out_ca4" == "['aaguid', 'credential_id', 'public_key', 'sign_count'] 700" ]] \
  && pass "remote_approval : enrôlement ne persiste que la clé publique, dossier 0700 (CA4)" \
  || fail "remote_approval : persistance enrôlement CA4 ($out_ca4)"

# CA1 — nonce/signature valide et fraîche → exécuté ; assertion rejouée
# (même signature 2×) → refusée. CA2 — WYSIWYS exact dérivé du payload signé.
# CA7 — assertion signée pour session_id=A présentée pour la session B → refus.
out_core="$(GWSA_ROOT="$TMP/mag-remote-approval-core" "$PY" -c "
import sys; sys.path.insert(0, 'tests')
import tempfile
from pathlib import Path
from testlib.phone_signer import generate_keypair, sign_challenge
from gateway.approval_channel import InMemoryChannel
from gateway.elicitation import consume_nonce, prompt_from_payload
from gateway.remote_approval import (
    enroll_phone, forge_challenge, load_enrollment, run_remote_approval_gate,
    verify_assertion, RemoteApprovalError,
)

tmp = Path(tempfile.mkdtemp())
priv, pub = generate_keypair(tmp)
enroll_phone({'credential_id': 'cred1', 'aaguid': 'a', 'public_key': pub, 'uv': 'biometric', 'be': False, 'sign_count': 0})

out = []

# CA1 (nominal) + CA2 (WYSIWYS)
fields = {'action': 'session_grant', 'alias': 'alpha', 'email': 'a@x.com', 'session_id': 'sidA', 'target': 'MonDossier', 'hours': 4}

class RespondingChannel(InMemoryChannel):
    def __init__(self):
        super().__init__()
        self.sc = 0
    def send_challenge(self, envelope):
        rid = super().send_challenge(envelope)
        self.sc += 1
        assertion = sign_challenge(envelope['payload'], priv, credential_id='cred1', sign_count=self.sc)
        self.respond(rid, assertion)
        return rid

ch = RespondingChannel()
signed = run_remote_approval_gate(fields, ch)
out.append('EXEC:' + signed['session_id'])
wysiwys = prompt_from_payload(signed)
out.append('WYSIWYS_OK' if ('MonDossier' in wysiwys and 'sidA' in wysiwys and '4 h' in wysiwys) else 'WYSIWYS_FAIL:' + wysiwys)

# CA1 (replay) — même assertion signée soumise deux fois via verify_assertion+consume_nonce
envelope = forge_challenge({'action': 'unlock', 'alias': 'beta', 'minutes': 10})
assertion = sign_challenge(envelope.payload, priv, credential_id='cred1', sign_count=100)
enr = load_enrollment()
ok1 = verify_assertion(envelope, assertion, enr)
consume_nonce(envelope.payload['nonce'], expires_at=envelope.payload['expires_at'])
try:
    consume_nonce(envelope.payload['nonce'], expires_at=envelope.payload['expires_at'])
    out.append('NONCE_REPLAY:accepted')
except Exception:
    out.append('NONCE_REPLAY:refused')
ok2 = verify_assertion(envelope, assertion, load_enrollment())
out.append('REPLAY:' + ('refused' if (ok1 and not ok2) else 'accepted'))

# CA7 — assertion signée pour session_id=A rejouée sous une session B
envA = forge_challenge({'action': 'session_unlock', 'alias': 'alpha', 'session_id': 'sidA', 'minutes': 5})
assertA = sign_challenge(envA.payload, priv, credential_id='cred1', sign_count=200)
envB = forge_challenge({'action': 'session_unlock', 'alias': 'alpha', 'session_id': 'sidB', 'minutes': 5})
cross_ok = verify_assertion(envB, assertA, load_enrollment())
out.append('CROSS_SESSION:' + ('refused' if not cross_ok else 'accepted'))

print(' '.join(out))
")"
echo "$out_core" | grep -q "^EXEC:sidA " \
  && pass "remote_approval : nonce/signature valide et fraîche → exécuté avec la session_id du payload signé (CA1)" \
  || fail "remote_approval : exécution nominale CA1 ($out_core)"
echo "$out_core" | grep -q "WYSIWYS_OK" \
  && pass "remote_approval : WYSIWYS exact (compte, cible, durée) depuis prompt_from_payload(payload signé) (CA2)" \
  || fail "remote_approval : WYSIWYS CA2 ($out_core)"
echo "$out_core" | grep -q "NONCE_REPLAY:refused" \
  && pass "remote_approval : nonce rejoué → consume_nonce refuse (registre partagé avec Touch ID, CA1)" \
  || fail "remote_approval : nonce rejoué non refusé CA1 ($out_core)"
echo "$out_core" | grep -q "REPLAY:refused" \
  && pass "remote_approval : assertion rejouée (même signature 2×) → verify_assertion refuse (CA1)" \
  || fail "remote_approval : assertion rejouée non refusée CA1 ($out_core)"
echo "$out_core" | grep -q "CROSS_SESSION:refused" \
  && pass "remote_approval : assertion signée pour session A présentée pour session B → refus (CA7)" \
  || fail "remote_approval : rejeu cross-session non refusé CA7 ($out_core)"

# CA3 — refus explicite | nonce expiré | signature invalide → AUCUNE mutation
# (fail-closed) : on vérifie qu'aucun de ces trois chemins ne renvoie un
# payload exécutable, et qu'une session témoin reste totalement inchangée.
out_ca3="$(GWSA_ROOT="$TMP/mag-remote-approval-ca3" "$PY" -c "
import sys; sys.path.insert(0, 'tests')
import tempfile
from pathlib import Path
from testlib.phone_signer import generate_keypair, sign_challenge
from gateway.approval_channel import InMemoryChannel
from gateway.sessions import create_session, is_session_unlocked
from gateway.remote_approval import enroll_phone, forge_challenge, verify_assertion, load_enrollment, run_remote_approval_gate, RemoteApprovalError

tmp = Path(tempfile.mkdtemp())
priv, pub = generate_keypair(tmp)
enroll_phone({'credential_id': 'cred1', 'aaguid': 'a', 'public_key': pub, 'uv': 'biometric', 'be': False, 'sign_count': 0})

out = []
sess = create_session(client='ca3')

# 1) refus explicite (le téléphone ne répond jamais — channel vide)
fields = {'action': 'session_unlock', 'alias': 'gamma', 'session_id': sess.session_id, 'minutes': 30}
ch = InMemoryChannel()
try:
    run_remote_approval_gate(fields, ch, timeout=1)
    out.append('EXPLICIT_REFUSAL:executed')
except RemoteApprovalError:
    out.append('EXPLICIT_REFUSAL:blocked')

# 2) nonce/défi expiré
envelope = forge_challenge(fields)
envelope.payload['expires_at'] = 1  # dans le passé
assertion = sign_challenge(envelope.payload, priv, credential_id='cred1', sign_count=1)
ok_expired = verify_assertion(envelope, assertion, load_enrollment())
out.append('EXPIRED:' + ('blocked' if not ok_expired else 'executed'))

# 3) signature invalide (mauvaise clé)
_, wrong_pub = generate_keypair(tmp)
envelope2 = forge_challenge(fields)
assertion2 = sign_challenge(envelope2.payload, priv, credential_id='cred1', sign_count=2)
import gateway.remote_approval as ra
bad_enrollment = ra.PhoneEnrollment(credential_id='cred1', aaguid='a', public_key=wrong_pub, sign_count=0)
ok_bad_sig = verify_assertion(envelope2, assertion2, bad_enrollment)
out.append('BAD_SIG:' + ('blocked' if not ok_bad_sig else 'executed'))

# Aucune mutation : la session témoin n'a jamais été déverrouillée
out.append('NO_MUTATION:' + ('ok' if not is_session_unlocked(sess.session_id, 'gamma') else 'FAIL'))
print(' '.join(out))
")"
[[ "$out_ca3" == "EXPLICIT_REFUSAL:blocked EXPIRED:blocked BAD_SIG:blocked NO_MUTATION:ok" ]] \
  && pass "remote_approval : refus explicite | nonce expiré | signature invalide → aucune exécution (CA3, fail-closed)" \
  || fail "remote_approval : fail-closed CA3 incomplet ($out_ca3)"

# CA5 — devant le Mac, mag unlock SANS --remote reste inchangé (Touch ID mock,
# chemin existant) : non-régression du chemin run_elicitation_gate.
RA5="$TMP/mag-remote-approval-ca5"
mkdir -p "$RA5/prof5"
echo '{"defaults":{"services":{"gmail":"read"}}}' > "$RA5/prof5/policy.json"
touch "$RA5/prof5/.locked"
touch "$RA5/.strong-auth"
GWSA_ROOT="$RA5" GWSA_ELICITATION_MOCK=1 "$GWSA" elicitation enroll --mock >/dev/null 2>&1
out_ca5="$(GWSA_ROOT="$RA5" GWSA_ELICITATION_MOCK=1 "$GWSA" unlock prof5 15 2>&1)"
[[ -f "$RA5/prof5/.unlock-until" ]] \
  && pass "mag unlock (sans --remote) sous .strong-auth : chemin Touch ID inchangé (CA5, non-régression)" \
  || fail "mag unlock sans --remote : chemin Touch ID cassé ($out_ca5)"

# --remote sans enrôlement téléphone → refus distinct (fail-closed), preuve
# que le câblage --remote emprunte bien le frère `require_remote_approval`
# (message « approbation distante », pas « élicitation signée »).
RA5B="$TMP/mag-remote-approval-ca5b"
mkdir -p "$RA5B/prof5b"
echo '{"defaults":{"services":{"gmail":"read"}}}' > "$RA5B/prof5b/policy.json"
sid5b="$(GWSA_ROOT="$RA5B" GWSA_ELICITATION_MOCK=1 "$GWSA" elicitation enroll --mock >/dev/null 2>&1; "$PY" -c "
import sys; sys.path.insert(0, '.')
import os
os.environ['GWSA_ROOT'] = '$RA5B'
from gateway.sessions import create_session
print(create_session(client='ca5b').session_id)
")"
out_ca5b="$(GWSA_ROOT="$RA5B" "$GWSA" session unlock "$sid5b" prof5b 10 --remote 2>&1)"
echo "$out_ca5b" | grep -q "approbation distante" \
  && pass "mag session unlock --remote : emprunte le chemin frère require_remote_approval (fail-closed sans enrôlement)" \
  || fail "mag session unlock --remote : chemin inattendu ($out_ca5b)"

# --- Fix Codex P1 (PR #113) : échange en deux temps, réellement hors-process ---
#
# L'ancien `remote-approval-cli.py gate --response <fichier>` chargeait
# l'assertion AVANT de forger le défi (dont le nonce est frais à chaque
# appel) : aucun téléphone hors-process ne pouvait donc jamais produire une
# réponse valide. Les tests ci-dessous pilotent `challenge` puis `verify`
# comme DEUX PROCESSUS SÉPARÉS (deux appels `subprocess.run`, aucun état
# Python partagé entre eux — contrairement à l'ancien `InMemoryChannel`
# in-process) pour prouver que l'échange fonctionne réellement.

RA_OOP="$TMP/mag-remote-approval-oop"
mkdir -p "$RA_OOP"
"$PY" -c "
import sys; sys.path.insert(0, 'tests')
from pathlib import Path
from testlib.phone_signer import generate_keypair
import json, os
os.environ['GWSA_ROOT'] = '$RA_OOP'
from gateway.remote_approval import enroll_phone
tmp = Path('$RA_OOP')
priv, pub = generate_keypair(tmp)
enroll_phone({'credential_id': 'cred-oop', 'aaguid': 'a', 'public_key': pub, 'uv': 'biometric', 'be': False, 'sign_count': 0})
Path('$RA_OOP/priv.pem').write_text(priv.read_text())
" >/dev/null

# Processus A : publie le défi (out-of-process : c'est un subprocess.run distinct).
challenge_json="$(GWSA_ROOT="$RA_OOP" "$PY" scripts/remote-approval-cli.py challenge \
  --json '{"action":"session_unlock","alias":"alpha","email":"a@x.com","session_id":"sidOOP","minutes":15}')"

# Le "téléphone" (aucun accès au process A : il ne voit QUE l'envelope publié)
# signe exactement ce qui a été publié.
response_file="$TMP/oop-response.json"
"$PY" -c "
import sys; sys.path.insert(0, 'tests')
import json
from pathlib import Path
from testlib.phone_signer import sign_challenge
out = json.loads('''$challenge_json''')
envelope_payload = out['envelope']['payload']
assertion = sign_challenge(envelope_payload, Path('$RA_OOP/priv.pem'), credential_id='cred-oop', sign_count=1)
Path('$response_file').write_text(json.dumps(assertion))
"

challenge_id="$("$PY" -c "import json; print(json.loads('''$challenge_json''')['challenge_id'])")"

# Processus B : vérifie et exécute — SANS avoir jamais partagé d'état Python
# avec le processus A (deux invocations `python3` distinctes, communication
# uniquement via le pending publié sur disque + le fichier réponse).
verify_out="$(GWSA_ROOT="$RA_OOP" "$PY" scripts/remote-approval-cli.py verify \
  --challenge-id "$challenge_id" --response "$response_file" 2>&1)"
echo "$verify_out" | grep -q '"session_id": *"sidOOP"' \
  && pass "remote_approval CLI : échange challenge → verify réussit réellement hors-process (répond à Codex P1, PR #113)" \
  || fail "remote_approval CLI : échange hors-process en échec ($verify_out)"

# Rejeu du pending : réutiliser le même challenge_id après un `verify` déjà
# consommé (one-shot) doit être refusé — la 2ᵉ tentative n'a plus de défi à
# consommer, même avec une nouvelle signature valide.
sign_count2=2
response_file2="$TMP/oop-response-replay.json"
"$PY" -c "
import sys; sys.path.insert(0, 'tests')
import json
from pathlib import Path
from testlib.phone_signer import sign_challenge
out = json.loads('''$challenge_json''')
envelope_payload = out['envelope']['payload']
assertion = sign_challenge(envelope_payload, Path('$RA_OOP/priv.pem'), credential_id='cred-oop', sign_count=$sign_count2)
Path('$response_file2').write_text(json.dumps(assertion))
"
replay_out="$(GWSA_ROOT="$RA_OOP" "$PY" scripts/remote-approval-cli.py verify \
  --challenge-id "$challenge_id" --response "$response_file2" 2>&1)"
replay_rc=$?
[[ "$replay_rc" != "0" ]] && echo "$replay_out" | grep -q "approbation distante" \
  && pass "remote_approval CLI : rejeu d'un challenge_id déjà clos (« verify ») → refusé (pending one-shot)" \
  || fail "remote_approval CLI : rejeu de challenge_id non refusé ($replay_out, rc=$replay_rc)"

# Anti-traversée (Codex P2, PR #113) : un challenge_id malveillant (« ../ »,
# chemin absolu) doit être refusé AVANT toute construction de chemin — sinon
# `verify --challenge-id ../../x` lirait/supprimerait hors du dossier pending.
trav_out="$(GWSA_ROOT="$RA_OOP" "$PY" scripts/remote-approval-cli.py verify \
  --challenge-id "../../etc/passwd" --response "$response_file" 2>&1)"
trav_rc=$?
[[ "$trav_rc" != "0" ]] && echo "$trav_out" | grep -qi "challenge_id invalide" \
  && pass "remote_approval CLI : challenge_id de traversée (../) refusé (Codex P2, PR #113)" \
  || fail "remote_approval CLI : traversée de challenge_id non refusée ($trav_out, rc=$trav_rc)"

# --- mag --remote : exécute avec le payload signé, pas les variables shell ---
#
# Nit de revue (PR #113) : `require_remote_approval` doit exécuter avec le
# payload SIGNÉ renvoyé par `verify`, jamais avec ses variables shell
# pré-signature. On le prouve avec un aller-retour RÉEL de bout en bout via
# `mag session unlock … --remote` — GWSA_REMOTE_SIGNER joue le rôle du
# téléphone : un PROCESSUS SÉPARÉ qui ne reçoit l'envelope QUE lorsqu'il est
# publié (stdin), preuve que l'échange marche vraiment hors-process, pas
# seulement au niveau du CLI nu.
RA_E2E="$TMP/mag-remote-approval-e2e"
mkdir -p "$RA_E2E/prof-e2e"
echo '{"defaults":{"services":{"gmail":"read"}}}' > "$RA_E2E/prof-e2e/policy.json"
touch "$RA_E2E/prof-e2e/.locked"

"$PY" -c "
import sys; sys.path.insert(0, 'tests')
from pathlib import Path
from testlib.phone_signer import generate_keypair
import os
os.environ['GWSA_ROOT'] = '$RA_E2E'
from gateway.remote_approval import enroll_phone
priv, pub = generate_keypair(Path('$RA_E2E'))
enroll_phone({'credential_id': 'cred-e2e', 'aaguid': 'a', 'public_key': pub, 'uv': 'biometric', 'be': False, 'sign_count': 0})
Path('$RA_E2E/priv.pem').write_text(priv.read_text())
"
sid_e2e="$("$PY" -c "
import sys, os; sys.path.insert(0, '.')
os.environ['GWSA_ROOT'] = '$RA_E2E'
from gateway.sessions import create_session
print(create_session(client='e2e').session_id)
")"

signer_e2e="$TMP/phone-signer-e2e.py"
cat > "$signer_e2e" <<PYEOF
#!/usr/bin/env python3
import sys, json
sys.path.insert(0, "tests")
from testlib.phone_signer import sign_challenge
from pathlib import Path
challenge = json.load(sys.stdin)
payload = challenge["envelope"]["payload"]
assertion = sign_challenge(payload, Path("$RA_E2E/priv.pem"), credential_id="cred-e2e", sign_count=1)
print(json.dumps(assertion))
PYEOF
chmod +x "$signer_e2e"

out_e2e="$(GWSA_ROOT="$RA_E2E" GWSA_REMOTE_SIGNER="$signer_e2e" "$GWSA" session unlock "$sid_e2e" prof-e2e 45 --remote 2>&1)"
unlocked_e2e="$("$PY" -c "
import sys, os; sys.path.insert(0, '.')
os.environ['GWSA_ROOT'] = '$RA_E2E'
from gateway.sessions import is_session_unlocked
print(is_session_unlocked('$sid_e2e', 'prof-e2e'))
")"
[[ "$unlocked_e2e" == "True" ]] \
  && pass "mag session unlock --remote : échange deux-temps réel (téléphone hors-process) exécute effectivement le déverrouillage (nit, PR #113)" \
  || fail "mag session unlock --remote : déverrouillage non exécuté ($out_e2e)"

# --- Bilan ------------------------------------------------------------------

printf '\n\033[1mBilan : %d réussis, %d échoués\033[0m\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
